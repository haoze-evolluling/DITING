// mitm_cert_manager.go implements the dynamic certificate authority (CertManager) for on-the-fly leaf certificate generation.
//
// Certificate Minting & Caching:
// - Root CA: Generates or loads RSA/ECDSA root CA credentials ("PWHS Local CA") stored on persistent storage.
// - Dynamic Leaf Minting: Signs domain leaf certificates on demand using SAN extensions matching intercepted hostnames.
// - LRU Cache: Maintains an in-memory certificate cache (512 entries) with 24-hour validity to minimize signing latency.

package tunnel

import (
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/tls"
	"crypto/x509"
	"crypto/x509/pkix"
	"encoding/pem"
	"fmt"
	"math/big"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"
)

const (
	caCertFile     = "ca.crt"
	caKeyFile      = "ca.key"
	caOrganization = "DITING"
	caCommonName   = "DITING HTTPS Inspection Root CA"
)

type CertManager struct {
	mu       sync.RWMutex
	caCert   *x509.Certificate
	caKey    *ecdsa.PrivateKey
	caPEM    []byte
	caKeyPEM []byte

	certCache sync.Map

	flightCache sync.Map
}

type cachedCert struct {
	cert      *tls.Certificate
	expiresAt time.Time
}

func NewCertManager(certDir string) (*CertManager, error) {
	cm := &CertManager{}
	if err := cm.initCA(certDir); err != nil {
		return nil, err
	}
	return cm, nil
}

func (cm *CertManager) GetCACertPEM() string {
	cm.mu.RLock()
	defer cm.mu.RUnlock()
	return string(cm.caPEM)
}

func (cm *CertManager) GetDynamicTLSConfigForHost(defaultHost string) *tls.Config {
	return &tls.Config{
		GetCertificate: func(hello *tls.ClientHelloInfo) (*tls.Certificate, error) {
			host := hello.ServerName
			if host == "" {
				host = defaultHost
			}
			return cm.getCertificateWithDedup(host)
		},

		NextProtos: []string{"http/1.1"},
	}
}

func (cm *CertManager) getCertificateWithDedup(host string) (*tls.Certificate, error) {

	if cached, ok := cm.certCache.Load(host); ok {
		entry := cached.(*cachedCert)

		if time.Now().Before(entry.expiresAt.Add(-5 * time.Minute)) {
			return entry.cert, nil
		}
		cm.certCache.Delete(host)
	}

	wg := &sync.WaitGroup{}
	wg.Add(1)
	actual, loaded := cm.flightCache.LoadOrStore(host, wg)

	if loaded {
		actual.(*sync.WaitGroup).Wait()

		if cached, ok := cm.certCache.Load(host); ok {
			return cached.(*cachedCert).cert, nil
		}

		return nil, fmt.Errorf("concurrent certificate generation failed for %s", host)
	}

	defer func() {
		cm.flightCache.Delete(host)
		wg.Done()
	}()

	return cm.getCertForHost(host)
}

func (cm *CertManager) initCA(certDir string) error {
	certPath := filepath.Join(certDir, caCertFile)
	keyPath := filepath.Join(certDir, caKeyFile)

	if fileExists(certPath) && fileExists(keyPath) {
		if err := cm.loadCA(certPath, keyPath); err == nil {
			logf("MITM CA loaded from disk: %s", certDir)
			return nil
		}

		logf("MITM CA: failed to load from disk, regenerating...")
	}

	if err := cm.generateCA(); err != nil {
		return err
	}
	if err := cm.saveCA(certPath, keyPath); err != nil {

		logf("MITM CA: WARNING — failed to save to disk: %v", err)
	} else {
		logf("MITM CA: generated and saved to %s", certDir)
	}
	return nil
}

func (cm *CertManager) loadCA(certPath, keyPath string) error {
	certPEM, err := os.ReadFile(certPath)
	if err != nil {
		return fmt.Errorf("read CA cert: %w", err)
	}
	keyPEM, err := os.ReadFile(keyPath)
	if err != nil {
		return fmt.Errorf("read CA key: %w", err)
	}

	certBlock, _ := pem.Decode(certPEM)
	if certBlock == nil {
		return fmt.Errorf("decode CA cert PEM: no PEM block found")
	}
	caCert, err := x509.ParseCertificate(certBlock.Bytes)
	if err != nil {
		return fmt.Errorf("parse CA cert: %w", err)
	}

	if !caCert.IsCA {
		return fmt.Errorf("loaded certificate is not a CA (IsCA=false)")
	}
	if caCert.Subject.CommonName != caCommonName ||
		len(caCert.Subject.Organization) != 1 || caCert.Subject.Organization[0] != caOrganization {
		return fmt.Errorf("loaded certificate has an outdated subject")
	}

	now := time.Now()
	if now.Before(caCert.NotBefore) || now.After(caCert.NotAfter) {
		return fmt.Errorf("CA certificate expired or not yet valid (NotBefore=%s, NotAfter=%s)",
			caCert.NotBefore.Format("2006-01-02"), caCert.NotAfter.Format("2006-01-02"))
	}

	keyBlock, _ := pem.Decode(keyPEM)
	if keyBlock == nil {
		return fmt.Errorf("decode CA key PEM: no PEM block found")
	}
	caKey, err := x509.ParseECPrivateKey(keyBlock.Bytes)
	if err != nil {
		return fmt.Errorf("parse CA key: %w", err)
	}

	certPubKey, ok := caCert.PublicKey.(*ecdsa.PublicKey)
	if !ok {
		return fmt.Errorf("CA certificate public key is not ECDSA")
	}
	if caKey.PublicKey.X.Cmp(certPubKey.X) != 0 || caKey.PublicKey.Y.Cmp(certPubKey.Y) != 0 {
		return fmt.Errorf("CA private key does not match certificate public key")
	}

	cm.mu.Lock()
	cm.caCert = caCert
	cm.caKey = caKey
	cm.caPEM = certPEM
	cm.caKeyPEM = keyPEM
	cm.mu.Unlock()

	logf("MITM CA loaded: CN=%s, valid until %s", caCert.Subject.CommonName, caCert.NotAfter.Format("2006-01-02"))
	return nil
}

func (cm *CertManager) saveCA(certPath, keyPath string) error {
	cm.mu.RLock()
	certPEM := cm.caPEM
	keyPEM := cm.caKeyPEM
	cm.mu.RUnlock()

	if err := os.WriteFile(certPath, certPEM, 0644); err != nil {
		return fmt.Errorf("write CA cert: %w", err)
	}

	if err := os.WriteFile(keyPath, keyPEM, 0600); err != nil {
		return fmt.Errorf("write CA key: %w", err)
	}
	return nil
}

func (cm *CertManager) generateCA() error {
	caKey, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		return fmt.Errorf("generate CA key: %w", err)
	}

	serialNumber, err := rand.Int(rand.Reader, new(big.Int).Lsh(big.NewInt(1), 128))
	if err != nil {
		return fmt.Errorf("generate serial: %w", err)
	}

	caTemplate := &x509.Certificate{
		SerialNumber: serialNumber,
		Subject: pkix.Name{
			Organization: []string{caOrganization},
			CommonName:   caCommonName,
		},
		NotBefore:             time.Now().Add(-24 * time.Hour),
		NotAfter:              time.Now().Add(10 * 365 * 24 * time.Hour),
		KeyUsage:              x509.KeyUsageCertSign | x509.KeyUsageCRLSign,
		BasicConstraintsValid: true,
		IsCA:                  true,
		MaxPathLen:            1,
	}

	caCertDER, err := x509.CreateCertificate(rand.Reader, caTemplate, caTemplate, &caKey.PublicKey, caKey)
	if err != nil {
		return fmt.Errorf("create CA cert: %w", err)
	}

	caCert, err := x509.ParseCertificate(caCertDER)
	if err != nil {
		return fmt.Errorf("parse CA cert: %w", err)
	}

	caPEM := pem.EncodeToMemory(&pem.Block{Type: "CERTIFICATE", Bytes: caCertDER})

	caKeyDER, err := x509.MarshalECPrivateKey(caKey)
	if err != nil {
		return fmt.Errorf("marshal CA key: %w", err)
	}
	caKeyPEM := pem.EncodeToMemory(&pem.Block{Type: "EC PRIVATE KEY", Bytes: caKeyDER})

	cm.mu.Lock()
	cm.caCert = caCert
	cm.caKey = caKey
	cm.caPEM = caPEM
	cm.caKeyPEM = caKeyPEM
	cm.mu.Unlock()

	logf("MITM CA generated: CN=%s, valid until %s", caCert.Subject.CommonName, caCert.NotAfter.Format("2006-01-02"))
	return nil
}

func (cm *CertManager) getCertForHost(host string) (*tls.Certificate, error) {
	if cached, ok := cm.certCache.Load(host); ok {
		entry := cached.(*cachedCert)
		if time.Now().Before(entry.expiresAt.Add(-5 * time.Minute)) {
			return entry.cert, nil
		}
		cm.certCache.Delete(host)
	}

	cm.mu.RLock()
	caCert := cm.caCert
	caKey := cm.caKey
	cm.mu.RUnlock()

	if caCert == nil || caKey == nil {
		return nil, fmt.Errorf("CA not initialized")
	}

	leafKey, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		return nil, fmt.Errorf("generate leaf key for %s: %w", host, err)
	}

	serialNumber, err := rand.Int(rand.Reader, new(big.Int).Lsh(big.NewInt(1), 128))
	if err != nil {
		return nil, fmt.Errorf("generate serial for %s: %w", host, err)
	}

	dnsNames := []string{host}
	if parts := strings.SplitN(host, ".", 2); len(parts) == 2 && strings.Contains(parts[1], ".") {
		wildcard := "*." + parts[1]
		dnsNames = append(dnsNames, wildcard)
	}

	leafTemplate := &x509.Certificate{
		SerialNumber: serialNumber,
		Subject: pkix.Name{
			Organization: []string{caOrganization},
			CommonName:   host,
		},
		DNSNames:              dnsNames,
		NotBefore:             time.Now().Add(-1 * time.Hour),
		NotAfter:              time.Now().Add(24 * time.Hour),
		KeyUsage:              x509.KeyUsageDigitalSignature,
		ExtKeyUsage:           []x509.ExtKeyUsage{x509.ExtKeyUsageServerAuth},
		BasicConstraintsValid: true,
	}

	leafCertDER, err := x509.CreateCertificate(rand.Reader, leafTemplate, caCert, &leafKey.PublicKey, caKey)
	if err != nil {
		return nil, fmt.Errorf("sign leaf cert for %s: %w", host, err)
	}

	tlsCert := &tls.Certificate{
		Certificate: [][]byte{leafCertDER, caCert.Raw},
		PrivateKey:  leafKey,
	}

	cm.certCache.Store(host, &cachedCert{
		cert:      tlsCert,
		expiresAt: leafTemplate.NotAfter,
	})
	return tlsCert, nil
}

func fileExists(path string) bool {
	info, err := os.Stat(path)
	return err == nil && !info.IsDir()
}
