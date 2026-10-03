// mitm_trust_test.go validates upstream TLS root certificate trust management,
// ensuring embedded ISRG root certificates parse correctly, remain valid, and properly integrate into the shared cert pool.

package tunnel

import (
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/x509"
	"crypto/x509/pkix"
	"encoding/asn1"
	"encoding/pem"
	"math/big"
	"testing"
	"time"
)

func TestBundledRootsParse(t *testing.T) {
	for name, pemStr := range map[string]string{
		"ISRG Root X1": isrgRootX1PEM,
		"ISRG Root X2": isrgRootX2PEM,
	} {
		block, _ := pem.Decode([]byte(pemStr))
		if block == nil {
			t.Fatalf("%s: no PEM block decoded", name)
		}
		cert, err := x509.ParseCertificate(block.Bytes)
		if err != nil {
			t.Fatalf("%s: parse: %v", name, err)
		}
		if !cert.IsCA {
			t.Errorf("%s: expected IsCA=true", name)
		}
		if time.Now().After(cert.NotAfter) {
			t.Errorf("%s: bundled root is expired (NotAfter=%s)", name, cert.NotAfter)
		}
	}
}

func TestUpstreamRootPoolIncludesBundled(t *testing.T) {
	pool, added := buildUpstreamRootPool()
	if pool == nil {
		t.Fatal("buildUpstreamRootPool returned nil pool")
	}
	if added != 2 {
		t.Errorf("expected both bundled ISRG roots appended to pool, got %d", added)
	}

	if upstreamRootPool() == nil {
		t.Error("upstreamRootPool returned nil")
	}
}

func TestIsExtendedValidation(t *testing.T) {
	mk := func(policies []asn1.ObjectIdentifier) *x509.Certificate {
		key, _ := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
		tmpl := &x509.Certificate{
			SerialNumber:      big.NewInt(1),
			Subject:           pkix.Name{CommonName: "example.com"},
			NotBefore:         time.Now().Add(-time.Hour),
			NotAfter:          time.Now().Add(time.Hour),
			PolicyIdentifiers: policies,
		}
		der, err := x509.CreateCertificate(rand.Reader, tmpl, tmpl, &key.PublicKey, key)
		if err != nil {
			t.Fatalf("create cert: %v", err)
		}
		c, err := x509.ParseCertificate(der)
		if err != nil {
			t.Fatalf("parse cert: %v", err)
		}
		return c
	}

	ev := mk([]asn1.ObjectIdentifier{{2, 23, 140, 1, 1}})
	if !isExtendedValidation(ev) {
		t.Error("expected EV cert to be detected")
	}

	dv := mk([]asn1.ObjectIdentifier{{2, 23, 140, 1, 2, 1}})
	if isExtendedValidation(dv) {
		t.Error("DV cert should not be flagged EV")
	}

	if isExtendedValidation(nil) {
		t.Error("nil cert should not be flagged EV")
	}
}
