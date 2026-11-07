//go:build cgo

// mitm_sniffer_native_test.go covers the flow sniffer through rust/diting-sniffer-core.
//
// These cases need the kernel: the TLS ClientHello walk and the plaintext HTTP sniff live there
// now, so `go test` on a machine without a C toolchain builds them out (see
// mitm_sniffer_native_stub.go). The corpus in rust/diting-sniffer-core/tests/fixtures pins the
// parser byte for byte; these are the pipeline assertions the Go call sites rely on.

package tunnel

import (
	"encoding/binary"
	"testing"
)

func snifferTestExtension(extensionType uint16, data []byte) []byte {
	out := make([]byte, 4+len(data))
	binary.BigEndian.PutUint16(out[0:2], extensionType)
	binary.BigEndian.PutUint16(out[2:4], uint16(len(data)))
	copy(out[4:], data)
	return out
}

func snifferTestSNI(host string) []byte {
	entry := make([]byte, 3+len(host))
	entry[0] = 0x00
	binary.BigEndian.PutUint16(entry[1:3], uint16(len(host)))
	copy(entry[3:], host)
	list := make([]byte, 2+len(entry))
	binary.BigEndian.PutUint16(list[0:2], uint16(len(entry)))
	copy(list[2:], entry)
	return snifferTestExtension(0x0000, list)
}

func snifferTestClientHello(host string) []byte {
	body := []byte{0x01, 0, 0, 0, 0x03, 0x03}
	body = append(body, make([]byte, 32)...)
	body = append(body, 0x00)
	body = append(body, 0x00, 0x02, 0x13, 0x01)
	body = append(body, 0x01, 0x00)
	extensions := snifferTestSNI(host)
	body = append(body, byte(len(extensions)>>8), byte(len(extensions)))
	body = append(body, extensions...)
	length := len(body) - 4
	body[1] = byte(length >> 16)
	body[2] = byte(length >> 8)
	body[3] = byte(length)
	record := []byte{0x16, 0x03, 0x01, byte(len(body) >> 8), byte(len(body))}
	return append(record, body...)
}

func TestSnifferKernelLoads(t *testing.T) {
	if err := ensureSnifferKernel(); err != nil {
		t.Fatalf("sniffer kernel: %v", err)
	}
}

func TestClassifyFlowHTTP(t *testing.T) {
	cases := map[string]struct {
		request string
		host    string
	}{
		"plain":       {"GET /index.html HTTP/1.1\r\nHost: Example.COM\r\n\r\n", "Example.COM"},
		"with port":   {"GET / HTTP/1.1\r\nHost: ads.example.com:8080\r\n\r\n", "ads.example.com"},
		"fold long s": {"GET / HTTP/1.1\r\nHo\u017ft: fold.example\r\n\r\n", "fold.example"},
		"no host":     {"GET / HTTP/1.1\r\nAccept: */*\r\n\r\n", ""},
		"truncated":   {"GET / HTTP/1.1\r\nHost: example.com", ""},
	}
	for name, c := range cases {
		classification, host := classifyFlow([]byte(c.request))
		if classification != classHTTP {
			t.Fatalf("%s: class %d, want HTTP", name, classification)
		}
		if host != c.host {
			t.Fatalf("%s: host %q, want %q", name, host, c.host)
		}
	}
}

func TestClassifyFlowTLS(t *testing.T) {
	record := snifferTestClientHello("Ads.Example.COM")
	classification, host := classifyFlow(record)
	if classification != classTLS {
		t.Fatalf("class %d, want TLS", classification)
	}
	if host != "Ads.Example.COM" {
		t.Fatalf("host %q", host)
	}

	// A TLS record too short to parse still classifies as TLS: the caller falls back to the IP
	// rather than relaying a flow that is about to be intercepted.
	classification, host = classifyFlow([]byte{0x16, 0x03, 0x01, 0x00, 0x00})
	if classification != classTLS || host != "" {
		t.Fatalf("short record: class=%d host=%q", classification, host)
	}
}

func TestClassifyFlowUnknown(t *testing.T) {
	for _, data := range [][]byte{nil, []byte("nope"), {0x16, 0x02}} {
		if classification, host := classifyFlow(data); classification != classUnknown || host != "" {
			t.Fatalf("%q: class=%d host=%q", data, classification, host)
		}
	}
}

func TestFlowClassifierMatchesTheOldPipeline(t *testing.T) {
	// The three-way decision the handler used to inline:
	//   TLS gate -> parse SNI; looksLikeHTTPRequest -> parse Host; otherwise passthrough.
	http := []byte("POST /a HTTP/1.1\r\nAccept: */*\r\nHost:  spaced.example  \r\n\r\n")
	if classification, host := classifyFlow(http); classification != classHTTP || host != "spaced.example" {
		t.Fatalf("http: class=%d host=%q", classification, host)
	}
}
