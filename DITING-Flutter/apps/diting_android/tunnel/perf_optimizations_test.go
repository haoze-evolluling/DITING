package tunnel

import (
	"bytes"
	"crypto/tls"
	"crypto/x509"
	"fmt"
	"net"
	"strings"
	"sync/atomic"
	"testing"
	"time"

	"github.com/miekg/dns"
)

func TestCacheKeyFormatUnchanged(t *testing.T) {
	got := cacheKey("Example.COM.", 28, 1)
	if want := fmt.Sprintf("%s:%d:%d", "example.com", 28, 1); got != want {
		t.Fatalf("cacheKey = %q, want %q", got, want)
	}
}

func TestConnLogKeyFormatUnchanged(t *testing.T) {
	if got, want := connLogKey("", "pkg", "1.2.3.4", 443, 6, ""), "pkg|1.2.3.4|443|6"; got != want {
		t.Fatalf("conn key = %q, want %q", got, want)
	}
	if got, want := connLogKey("blk|", "pkg", "::1", 53, 17, "uid_blocked"), "blk|pkg|::1|53|17|uid_blocked"; got != want {
		t.Fatalf("blocked key = %q, want %q", got, want)
	}
}

type countingUIDResolver struct {
	calls atomic.Int32
	uid   int
}

func (r *countingUIDResolver) ResolveUID(int, string, int, string, int) int {
	r.calls.Add(1)
	return r.uid
}

func TestCachingUIDResolverDedupesFlowLookups(t *testing.T) {
	inner := &countingUIDResolver{uid: 10123}
	r := newCachingUIDResolver(inner)
	flow := flowID{appIP: net.ParseIP("10.0.0.2"), appPort: 40000, serverIP: net.ParseIP("1.1.1.1"), serverPort: 443}

	for i := 0; i < 5; i++ {
		if uid := resolveFlowUID(r, ProtocolTCP, flow); uid != 10123 {
			t.Fatalf("uid = %d", uid)
		}
	}
	if n := inner.calls.Load(); n != 1 {
		t.Fatalf("inner lookups = %d, want 1", n)
	}

	// A different protocol or port is a different flow.
	resolveFlowUID(r, ProtocolUDP, flow)
	flow.appPort++
	resolveFlowUID(r, ProtocolTCP, flow)
	if n := inner.calls.Load(); n != 3 {
		t.Fatalf("inner lookups = %d, want 3", n)
	}

	if newCachingUIDResolver(r) != r {
		t.Fatal("re-wrapping must be idempotent")
	}
}

func TestCachingUIDResolverNegativeEntriesExpireQuickly(t *testing.T) {
	inner := &countingUIDResolver{uid: UIDUnknown}
	r := newCachingUIDResolver(inner).(*cachingUIDResolver)
	flow := flowID{appIP: net.ParseIP("10.0.0.2"), appPort: 1, serverIP: net.ParseIP("8.8.8.8"), serverPort: 53}

	resolveFlowUID(r, ProtocolUDP, flow)
	for k, v := range r.entries {
		v.expires = time.Now().Add(-time.Millisecond)
		r.entries[k] = v
	}
	resolveFlowUID(r, ProtocolUDP, flow)
	if n := inner.calls.Load(); n != 2 {
		t.Fatalf("inner lookups = %d, want 2 after expiry", n)
	}
}

type countingAppUidResolver struct {
	calls atomic.Int32
	name  string
}

func (r *countingAppUidResolver) PackageForUid(int) string {
	r.calls.Add(1)
	return r.name
}

func TestCachingAppUidResolver(t *testing.T) {
	inner := &countingAppUidResolver{name: "com.example"}
	r := newCachingAppUidResolver(inner)
	for i := 0; i < 3; i++ {
		if got := r.PackageForUid(10001); got != "com.example" {
			t.Fatalf("package = %q", got)
		}
	}
	if n := inner.calls.Load(); n != 1 {
		t.Fatalf("inner lookups = %d, want 1", n)
	}

	// Empty answers are not cached: the package may be installed later.
	empty := &countingAppUidResolver{}
	re := newCachingAppUidResolver(empty)
	re.PackageForUid(1)
	re.PackageForUid(1)
	if n := empty.calls.Load(); n != 2 {
		t.Fatalf("empty lookups = %d, want 2", n)
	}
}

func TestIsPrivateIP(t *testing.T) {
	cases := map[string]bool{
		"10.1.2.3": true, "172.16.0.1": true, "172.31.255.255": true, "172.32.0.1": false,
		"192.168.1.1": true, "8.8.8.8": false, "2001:db8::1": false,
	}
	for ip, want := range cases {
		if got := isPrivateIP(net.ParseIP(ip)); got != want {
			t.Fatalf("isPrivateIP(%s) = %t, want %t", ip, got, want)
		}
	}
}

func TestCopyPooledCopiesEverything(t *testing.T) {
	src := bytes.Repeat([]byte("diting"), 20000)
	var dst bytes.Buffer
	n, err := copyPooled(&dst, bytes.NewReader(src))
	if err != nil || n != int64(len(src)) || !bytes.Equal(dst.Bytes(), src) {
		t.Fatalf("copyPooled n=%d err=%v equal=%t", n, err, bytes.Equal(dst.Bytes(), src))
	}
}

type batchRecorder struct{ batches chan string }

func (b *batchRecorder) OnDNSQueryBatch(s string) { b.batches <- s }

// A partial batch must still be flushed by the lazily armed timer.
func TestLogAggregatorFlushesPartialBatch(t *testing.T) {
	a := newLogAggregator()
	rec := &batchRecorder{batches: make(chan string, 4)}
	a.setCallback(rec)
	a.start()
	defer a.stop()

	for round := 0; round < 2; round++ {
		a.push(logItem{Domain: fmt.Sprintf("r%d.example", round)})
		select {
		case got := <-rec.batches:
			if !strings.Contains(got, fmt.Sprintf("r%d.example", round)) {
				t.Fatalf("round %d batch = %s", round, got)
			}
		case <-time.After(2 * time.Second):
			t.Fatalf("round %d: partial batch never flushed", round)
		}
	}
}

// Leaf certificates share one key but must still chain to the CA and carry the
// right SAN per host.
func TestCertManagerSharedLeafKeyCertsVerify(t *testing.T) {
	cm, err := NewCertManager(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	a, err := cm.getCertificateWithDedup("a.example.com")
	if err != nil {
		t.Fatal(err)
	}
	b, err := cm.getCertificateWithDedup("b.example.org")
	if err != nil {
		t.Fatal(err)
	}
	if a.PrivateKey != b.PrivateKey {
		t.Fatal("expected a shared leaf key")
	}
	roots := x509.NewCertPool()
	roots.AddCert(cm.caCert)
	for host, c := range map[string]*tls.Certificate{"a.example.com": a, "b.example.org": b} {
		leaf, err := x509.ParseCertificate(c.Certificate[0])
		if err != nil {
			t.Fatal(err)
		}
		if _, err := leaf.Verify(x509.VerifyOptions{DNSName: host, Roots: roots}); err != nil {
			t.Fatalf("%s: %v", host, err)
		}
	}
}

// The configured-provider path must hand back the message validation already
// unpacked, and it must match the raw answer.
func TestValidateDNSResponseReturnsUnpackedMsg(t *testing.T) {
	q := new(dns.Msg)
	q.SetQuestion("reuse.example.com.", dns.TypeA)
	rawQ, _ := q.Pack()
	resp := new(dns.Msg)
	resp.SetReply(q)
	resp.Answer = append(resp.Answer, &dns.A{Hdr: dns.RR_Header{Name: "reuse.example.com.", Rrtype: dns.TypeA, Class: dns.ClassINET, Ttl: 60}, A: net.ParseIP("1.2.3.4")})
	rawR, _ := resp.Pack()

	parsed, _, _ := parseDNSQuery(rawQ)
	msg, err := validateDNSResponseParsed(parsed, rawQ, rawR)
	if err != nil || msg == nil || len(msg.Answer) != 1 || msg.Id != q.Id {
		t.Fatalf("msg=%v err=%v", msg, err)
	}
}
