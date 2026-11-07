//go:build cgo

// cert_native_test.go covers the Go half of the MITM CA (rust/diting-cert-core):
//
//   - the upgrade path: a CA written by the old pure-Go implementation must still load and still
//     sign leaves the standard library accepts (rust/diting-cert-core/tests/corpus.rs pins the
//     same fixture field by field on the Rust side);
//   - persistence: a generated CA is written to ca.crt/ca.key and reloaded unchanged next time;
//   - a broken pair is replaced rather than adopted;
//   - the LRU and the per-host single-flight still return one certificate per host;
//   - `isExtendedValidation` is answered by the kernel.

package tunnel

import (
	"bytes"
	"crypto/tls"
	"encoding/asn1"
	"crypto/x509"
	"encoding/pem"
	"os"
	"path/filepath"
	"runtime"
	"sync"
	"testing"
	"time"
)

const certFixtureDir = "../../rust/diting-cert-core/tests/fixtures"

func certFixture(t *testing.T, name string) []byte {
	t.Helper()
	path := filepath.Join(certFixtureDir, name)
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("read fixture %s: %v", path, err)
	}
	return data
}

// writeCAFiles installs a cert/key pair into certDir the way the old implementation left it.
func writeCAFiles(t *testing.T, certDir string, certPEM, keyPEM []byte) {
	t.Helper()
	if err := os.WriteFile(filepath.Join(certDir, caCertFile), certPEM, 0644); err != nil {
		t.Fatalf("write ca.crt: %v", err)
	}
	if err := os.WriteFile(filepath.Join(certDir, caKeyFile), keyPEM, 0600); err != nil {
		t.Fatalf("write ca.key: %v", err)
	}
}

func parseLeaf(t *testing.T, cert *tls.Certificate) *x509.Certificate {
	t.Helper()
	leaf, err := x509.ParseCertificate(cert.Certificate[0])
	if err != nil {
		t.Fatalf("parse leaf: %v", err)
	}
	return leaf
}

func TestCertManagerAdoptsTheLegacyCA(t *testing.T) {
	certDir := t.TempDir()
	legacyCert := certFixture(t, "legacy_ca.crt")
	legacyKey := certFixture(t, "legacy_ca.key")
	writeCAFiles(t, certDir, legacyCert, legacyKey)

	cm, err := NewCertManager(certDir)
	if err != nil {
		t.Fatalf("NewCertManager: %v", err)
	}
	defer cm.Release()

	if got := cm.GetCACertPEM(); got != string(legacyCert) {
		t.Fatalf("GetCACertPEM did not return the installed root back byte for byte")
	}
	// Loading must not have touched the files on disk.
	for name, expected := range map[string][]byte{caCertFile: legacyCert, caKeyFile: legacyKey} {
		data, readErr := os.ReadFile(filepath.Join(certDir, name))
		if readErr != nil {
			t.Fatalf("read %s: %v", name, readErr)
		}
		if string(data) != string(expected) {
			t.Fatalf("%s was rewritten while loading the CA", name)
		}
	}

	caCert := cm.caCertificate()
	if caCert == nil {
		t.Fatal("no CA certificate")
	}
	if caCert.Subject.CommonName != caCommonName {
		t.Fatalf("CA CN = %q", caCert.Subject.CommonName)
	}
	roots := x509.NewCertPool()
	roots.AddCert(caCert)

	minted, err := cm.getCertificateWithDedup("www.example.com")
	if err != nil {
		t.Fatalf("mint: %v", err)
	}
	if len(minted.Certificate) != 2 {
		t.Fatalf("chain length = %d, want leaf + CA", len(minted.Certificate))
	}
	leaf := parseLeaf(t, minted)
	if leaf.Subject.CommonName != "www.example.com" {
		t.Fatalf("leaf CN = %q", leaf.Subject.CommonName)
	}
	if len(leaf.DNSNames) != 2 || leaf.DNSNames[0] != "www.example.com" || leaf.DNSNames[1] != "*.example.com" {
		t.Fatalf("leaf DNS names = %v", leaf.DNSNames)
	}
	if string(leaf.AuthorityKeyId) != string(caCert.SubjectKeyId) {
		t.Fatal("leaf AKI does not match the CA SKI")
	}
	if leaf.KeyUsage != x509.KeyUsageDigitalSignature {
		t.Fatalf("leaf key usage = %v", leaf.KeyUsage)
	}
	if len(leaf.ExtKeyUsage) != 1 || leaf.ExtKeyUsage[0] != x509.ExtKeyUsageServerAuth {
		t.Fatalf("leaf EKU = %v", leaf.ExtKeyUsage)
	}
	if now := time.Now(); leaf.NotAfter.Before(now.Add(23*time.Hour)) || leaf.NotAfter.After(now.Add(25*time.Hour)) {
		t.Fatalf("leaf NotAfter = %v, want ~24h out", leaf.NotAfter)
	}
	// The signature must verify against the root that was loaded from disk, i.e. the kernel signed
	// with the persisted key and not with a freshly generated one.
	if _, err := leaf.Verify(x509.VerifyOptions{DNSName: "www.example.com", Roots: roots}); err != nil {
		t.Fatalf("verify leaf: %v", err)
	}
	if _, err := leaf.Verify(x509.VerifyOptions{DNSName: "other.example.net", Roots: roots}); err == nil {
		t.Fatal("the leaf verified for a host it does not cover")
	}

	// One shared leaf key per process, matching the old implementation.
	second, err := cm.getCertificateWithDedup("a.b.example.com")
	if err != nil {
		t.Fatalf("mint second host: %v", err)
	}
	if second.PrivateKey != minted.PrivateKey {
		t.Fatal("leaves do not share one key")
	}
	secondLeaf := parseLeaf(t, second)
	if len(secondLeaf.DNSNames) != 2 || secondLeaf.DNSNames[1] != "*.b.example.com" {
		t.Fatalf("second leaf DNS names = %v", secondLeaf.DNSNames)
	}
	if _, err := secondLeaf.Verify(x509.VerifyOptions{DNSName: "a.b.example.com", Roots: roots}); err != nil {
		t.Fatalf("verify second leaf: %v", err)
	}
}

func TestCertManagerGeneratesThenReloadsTheSameCA(t *testing.T) {
	certDir := t.TempDir()
	cm, err := NewCertManager(certDir)
	if err != nil {
		t.Fatalf("NewCertManager: %v", err)
	}
	generated := cm.GetCACertPEM()
	cm.Release()
	if generated == "" {
		t.Fatal("generated CA PEM is empty")
	}

	certPath := filepath.Join(certDir, caCertFile)
	keyPath := filepath.Join(certDir, caKeyFile)
	onDisk, err := os.ReadFile(certPath)
	if err != nil {
		t.Fatalf("read ca.crt: %v", err)
	}
	if string(onDisk) != generated {
		t.Fatal("ca.crt differs from GetCACertPEM")
	}
	info, err := os.Stat(keyPath)
	if err != nil {
		t.Fatalf("stat ca.key: %v", err)
	}
	if runtime.GOOS != "windows" && info.Mode().Perm() != 0600 {
		t.Fatalf("ca.key mode = %v, want 0600", info.Mode().Perm())
	}
	keyPEM, err := os.ReadFile(keyPath)
	if err != nil {
		t.Fatalf("read ca.key: %v", err)
	}
	block, _ := pem.Decode(keyPEM)
	if block == nil || block.Type != "EC PRIVATE KEY" {
		t.Fatalf("ca.key is not a SEC1 EC key")
	}
	if _, err := x509.ParseECPrivateKey(block.Bytes); err != nil {
		t.Fatalf("parse ca.key: %v", err)
	}

	reloaded, err := NewCertManager(certDir)
	if err != nil {
		t.Fatalf("reload: %v", err)
	}
	defer reloaded.Release()
	if got := reloaded.GetCACertPEM(); got != generated {
		t.Fatal("the second manager regenerated the CA instead of loading it")
	}
}

// A pair that does not match (or does not parse) must be replaced, exactly as before: the old code
// logged the failure and generated a new CA.
func TestCertManagerReplacesABrokenCA(t *testing.T) {
	certDir := t.TempDir()
	legacyCert := certFixture(t, "legacy_ca.crt")

	other, err := NewCertManager(t.TempDir())
	if err != nil {
		t.Fatalf("NewCertManager: %v", err)
	}
	foreignKey := other.caKeyPEM
	other.Release()

	writeCAFiles(t, certDir, legacyCert, foreignKey)
	cm, err := NewCertManager(certDir)
	if err != nil {
		t.Fatalf("NewCertManager: %v", err)
	}
	if cm.GetCACertPEM() == string(legacyCert) {
		cm.Release()
		t.Fatal("a mismatched key/cert pair was adopted")
	}
	cm.Release()

	saved, err := os.ReadFile(filepath.Join(certDir, caCertFile))
	if err != nil {
		t.Fatalf("read ca.crt: %v", err)
	}
	if string(saved) == string(legacyCert) {
		t.Fatal("the replacement CA was not written to disk")
	}

	writeCAFiles(t, certDir, legacyCert, []byte("not a pem"))
	again, err := NewCertManager(certDir)
	if err != nil {
		t.Fatalf("NewCertManager: %v", err)
	}
	defer again.Release()
	if again.GetCACertPEM() == string(legacyCert) {
		t.Fatal("an unparsable key was adopted")
	}
}

func TestCertManagerCacheAndSingleFlight(t *testing.T) {
	cm, err := NewCertManager(t.TempDir())
	if err != nil {
		t.Fatalf("NewCertManager: %v", err)
	}
	defer cm.Release()

	const workers = 8
	results := make([]*tls.Certificate, workers)
	var wg sync.WaitGroup
	for index := 0; index < workers; index++ {
		wg.Add(1)
		go func(slot int) {
			defer wg.Done()
			cert, mintErr := cm.getCertificateWithDedup("race.example.com")
			if mintErr != nil {
				t.Errorf("mint: %v", mintErr)
				return
			}
			results[slot] = cert
		}(index)
	}
	wg.Wait()

	for index, cert := range results {
		if cert == nil {
			t.Fatalf("worker %d got no certificate", index)
		}
		if !bytes.Equal(cert.Certificate[0], results[0].Certificate[0]) {
			t.Fatalf("worker %d got a different certificate for the same host", index)
		}
	}
	if got := cm.certCache.len(); got != 1 {
		t.Fatalf("cache holds %d certificates, want 1", got)
	}

	// A second lookup is a cache hit: no new flight is registered while it runs.
	if _, err := cm.getCertificateWithDedup("race.example.com"); err != nil {
		t.Fatalf("cached lookup: %v", err)
	}
	if _, busy := cm.flightCache.Load("race.example.com"); busy {
		t.Fatal("the single-flight entry was not cleaned up")
	}

	cm.Release()
	if got := cm.certCache.len(); got != 0 {
		t.Fatalf("Release left %d cached certificates", got)
	}
	if _, err := cm.getCertificateWithDedup("race.example.com"); err == nil {
		t.Fatal("a released manager still minted a certificate")
	}
}

func TestIsExtendedValidationUsesTheKernel(t *testing.T) {
	if isExtendedValidation(nil) {
		t.Fatal("a nil certificate must not be EV")
	}
	single := func(oids ...asn1.ObjectIdentifier) *x509.Certificate {
		return &x509.Certificate{PolicyIdentifiers: oids}
	}
	if !isExtendedValidation(single(asn1.ObjectIdentifier{2, 23, 140, 1, 1})) {
		t.Fatal("CA/Browser Forum EV policy not recognised")
	}
	if isExtendedValidation(single(asn1.ObjectIdentifier{2, 23, 140, 1, 2, 1})) {
		t.Fatal("DV policy reported as EV")
	}
	// One EV policy next to a DV one is enough.
	mixed := single(asn1.ObjectIdentifier{2, 23, 140, 1, 2, 1}, asn1.ObjectIdentifier{1, 3, 6, 1, 4, 1, 34697, 2, 1})
	if !isExtendedValidation(mixed) {
		t.Fatal("EV policy in a mixed list not recognised")
	}
}
