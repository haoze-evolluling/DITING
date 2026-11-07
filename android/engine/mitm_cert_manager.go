// mitm_cert_manager.go keeps the Go half of the dynamic certificate authority (CertManager).
//
// What is left here after the migration to rust/diting-cert-core:
// - Root CA persistence: the `ca.crt` / `ca.key` file names, the reads and writes, and the
//   "load from disk, otherwise generate and save" decision.
// - Minted leaf cache: a size-bounded LRU of `*tls.Certificate` (a Go type, so it cannot move) with
//   24-hour validity, plus the per-host single-flight that keeps one handshake storm to one mint.
// - tls.Config glue: `GetCertificate`, the SNI default and `NextProtos`.
//
// What moved to the kernel: the CA template (subject, validity window, key usage, serial, the SEC1
// `EC PRIVATE KEY` encoding), the load-time validation and its exact error texts, and leaf minting
// (SAN rule, shared leaf key, AKI/SKI chain, NotAfter). The kernel never reads a clock, so every
// call passes `time.Now()`'s unix seconds.
//
// Without the kernel `NewCertManager` fails, `StartStackMitm` reports it, and the tunnel runs
// unintercepted instead of asking the OS to trust a root nobody can sign with.

package tunnel

import (
	"container/list"
	"crypto/ecdsa"
	"crypto/tls"
	"crypto/x509"
	"encoding/pem"
	"fmt"
	"os"
	"path/filepath"
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
	// mu guards ca against Release; minting holds it for the whole kernel call so a teardown
	// cannot free the handle under a handshake in flight.
	mu sync.RWMutex
	// ca is the kernel's CA handle, nil once released or when loading failed.
	ca *nativeCertAuthority
	// caPEM is the CA certificate PEM. It is cached (not read back from the kernel every time)
	// and survives Release, because `GetMitmCACert` is still answered after MITM stops.
	caPEM string
	// caKeyPEM is only set when this process generated the CA: `initCA` needs it once, to write
	// `ca.key`. A loaded CA never exposes its key, so it stays empty.
	caKeyPEM []byte

	certCache certCacheStore

	flightCache sync.Map

	// leafKey is the one P-256 key every minted leaf shares, parsed from the kernel's key PEM once.
	// Generating a fresh key per host doubled the per-host minting cost and the key never leaves
	// this process, so per-host keys bought no isolation.
	leafKeyOnce sync.Once
	leafKey     *ecdsa.PrivateKey
	leafKeyErr  error
}

type cachedCert struct {
	cert      *tls.Certificate
	expiresAt time.Time
}

// certCacheMaxEntries caps the minted leaf certificate cache. The file header
// has always claimed an "LRU cache (512 entries)", but the implementation was a
// plain sync.Map that only ever deleted on an expired hit, so a long-lived
// session browsing many hosts grew it without bound.
const certCacheMaxEntries = 512

// certCacheStore is a size-bounded LRU for minted leaf certificates.
type certCacheStore struct {
	mu       sync.Mutex
	entries  map[string]*list.Element
	order    *list.List // front = most recently used
	maxItems int
}

type certCacheItem struct {
	host  string
	entry *cachedCert
}

func (c *certCacheStore) load(host string) (*cachedCert, bool) {
	c.mu.Lock()
	defer c.mu.Unlock()
	elem, ok := c.entries[host]
	if !ok {
		return nil, false
	}
	c.order.MoveToFront(elem)
	return elem.Value.(*certCacheItem).entry, true
}

func (c *certCacheStore) store(host string, entry *cachedCert) {
	c.mu.Lock()
	defer c.mu.Unlock()
	if c.entries == nil {
		c.entries = make(map[string]*list.Element, c.maxItems)
		c.order = list.New()
	}
	if elem, ok := c.entries[host]; ok {
		elem.Value.(*certCacheItem).entry = entry
		c.order.MoveToFront(elem)
		return
	}
	c.entries[host] = c.order.PushFront(&certCacheItem{host: host, entry: entry})
	for c.order.Len() > c.maxItems {
		back := c.order.Back()
		if back == nil {
			break
		}
		c.order.Remove(back)
		delete(c.entries, back.Value.(*certCacheItem).host)
	}
}

func (c *certCacheStore) delete(host string) {
	c.mu.Lock()
	defer c.mu.Unlock()
	if elem, ok := c.entries[host]; ok {
		c.order.Remove(elem)
		delete(c.entries, host)
	}
}

// purgeExpired drops every entry whose certificate is past (or within a minute
// of) its validity so a cache filled by a previous session cannot keep serving
// re-minted certificates from dead hosts.
func (c *certCacheStore) purgeExpired(now time.Time) {
	c.mu.Lock()
	defer c.mu.Unlock()
	for host, elem := range c.entries {
		entry := elem.Value.(*certCacheItem).entry
		if entry == nil || entry.cert == nil || !now.Before(entry.expiresAt.Add(-5*time.Minute)) {
			c.order.Remove(elem)
			delete(c.entries, host)
		}
	}
}

func (c *certCacheStore) reset(maxItems int) {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.entries = make(map[string]*list.Element, maxItems)
	c.order = list.New()
	c.maxItems = maxItems
}

// len reports the number of cached certificates.
func (c *certCacheStore) len() int {
	c.mu.Lock()
	defer c.mu.Unlock()
	if c.order == nil {
		return 0
	}
	return c.order.Len()
}

func NewCertManager(certDir string) (*CertManager, error) {
	cm := &CertManager{}
	cm.certCache.reset(certCacheMaxEntries)
	if err := cm.initCA(certDir); err != nil {
		return nil, err
	}
	return cm, nil
}

// Release drops every minted leaf certificate and the kernel's CA handle.
// Engine.StopStackMitm calls it so a torn-down MITM session does not keep an
// engine-lifetime cache (or a signing key) alive. It is idempotent, and
// GetCACertPEM keeps answering from the cached PEM afterwards.
func (cm *CertManager) Release() {
	if cm == nil {
		return
	}
	cm.certCache.reset(certCacheMaxEntries)
	cm.mu.Lock()
	ca := cm.ca
	cm.ca = nil
	cm.mu.Unlock()
	if ca != nil {
		ca.release()
	}
}

func (cm *CertManager) GetCACertPEM() string {
	cm.mu.RLock()
	defer cm.mu.RUnlock()
	return cm.caPEM
}

// caCertificate parses the cached PEM for logging; nil when nothing is loaded.
func (cm *CertManager) caCertificate() *x509.Certificate {
	cm.mu.RLock()
	certPEM := cm.caPEM
	cm.mu.RUnlock()
	block, _ := pem.Decode([]byte(certPEM))
	if block == nil {
		return nil
	}
	cert, err := x509.ParseCertificate(block.Bytes)
	if err != nil {
		return nil
	}
	return cert
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

	if cached, ok := cm.certCache.load(host); ok {
		if time.Now().Before(cached.expiresAt.Add(-5 * time.Minute)) {
			return cached.cert, nil
		}
		cm.certCache.delete(host)
	}

	wg := &sync.WaitGroup{}
	wg.Add(1)
	actual, loaded := cm.flightCache.LoadOrStore(host, wg)

	if loaded {
		// Another goroutine is already minting this host: wait, then read the
		// cache it just populated. flightCache is deleted in the winner's defer,
		// so a miss here means generation failed there.
		actual.(*sync.WaitGroup).Wait()

		if cached, ok := cm.certCache.load(host); ok {
			return cached.cert, nil
		}

		return nil, fmt.Errorf("concurrent certificate generation failed for %s", host)
	}

	defer func() {
		cm.flightCache.Delete(host)
		wg.Done()
	}()

	// A previous session's entries are dead weight; keeping them only delays the
	// bound from taking effect after the cache grew large.
	cm.certCache.purgeExpired(time.Now())
	return cm.getCertForHost(host)
}

func (cm *CertManager) initCA(certDir string) error {
	certPath := filepath.Join(certDir, caCertFile)
	keyPath := filepath.Join(certDir, caKeyFile)

	if fileExists(certPath) && fileExists(keyPath) {
		if err := cm.loadCA(certPath, keyPath); err == nil {
			logf("MITM CA loaded from disk: %s", certDir)
			return nil
		} else {
			logf("MITM CA: failed to load from disk (%v), regenerating...", err)
		}
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

// adopt publishes a CA handle plus the certificate PEM it was loaded from and, for a freshly
// generated CA, the key PEM to persist.
func (cm *CertManager) adopt(ca *nativeCertAuthority, certPEM string, keyPEM []byte) {
	cert, err := func() (*x509.Certificate, error) {
		block, _ := pem.Decode([]byte(certPEM))
		if block == nil {
			return nil, fmt.Errorf("no PEM block found")
		}
		return x509.ParseCertificate(block.Bytes)
	}()

	cm.mu.Lock()
	cm.ca = ca
	cm.caPEM = certPEM
	cm.caKeyPEM = keyPEM
	cm.mu.Unlock()

	if err == nil {
		logf("MITM CA: CN=%s, valid until %s", cert.Subject.CommonName,
			cert.NotAfter.Format("2006-01-02"))
	}
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

	ca, err := loadCertAuthority(certPEM, keyPEM, time.Now())
	if err != nil {
		return err
	}
	// The kernel re-encodes the certificate it holds; reuse the PEM from disk when it matches so
	// `GetCACertPEM` hands the installed root back byte for byte.
	decodeErr := func() error {
		kernelPEM, kernelErr := ca.caPEM()
		if kernelErr != nil {
			return kernelErr
		}
		if kernelPEM != string(certPEM) {
			certPEM = []byte(kernelPEM)
		}
		return nil
	}()
	if decodeErr != nil {
		ca.release()
		return decodeErr
	}

	cm.adopt(ca, string(certPEM), nil)
	return nil
}

func (cm *CertManager) saveCA(certPath, keyPath string) error {
	cm.mu.RLock()
	certPEM := cm.caPEM
	keyPEM := cm.caKeyPEM
	cm.mu.RUnlock()

	if len(certPEM) == 0 || len(keyPEM) == 0 {
		return fmt.Errorf("CA not initialized")
	}

	if err := os.WriteFile(certPath, []byte(certPEM), 0644); err != nil {
		return fmt.Errorf("write CA cert: %w", err)
	}

	if err := os.WriteFile(keyPath, keyPEM, 0600); err != nil {
		return fmt.Errorf("write CA key: %w", err)
	}
	return nil
}

func (cm *CertManager) generateCA() error {
	ca, keyPEM, err := generateCertAuthority(time.Now())
	if err != nil {
		return err
	}
	certPEM, err := ca.caPEM()
	if err != nil {
		ca.release()
		return err
	}
	cm.adopt(ca, certPEM, []byte(keyPEM))
	return nil
}

func (cm *CertManager) getCertForHost(host string) (*tls.Certificate, error) {
	if cached, ok := cm.certCache.load(host); ok {
		if time.Now().Before(cached.expiresAt.Add(-5 * time.Minute)) {
			return cached.cert, nil
		}
		cm.certCache.delete(host)
	}

	cm.mu.RLock()
	ca := cm.ca
	if ca == nil {
		cm.mu.RUnlock()
		return nil, fmt.Errorf("CA not initialized")
	}
	chainPEM, keyPEM, notAfter, err := ca.issue(host, time.Now())
	cm.mu.RUnlock()
	if err != nil {
		return nil, fmt.Errorf("sign leaf cert for %s: %w", host, err)
	}

	chain, err := certChainDER(chainPEM)
	if err != nil {
		return nil, fmt.Errorf("load leaf cert for %s: %w", host, err)
	}
	leafKey, err := cm.sharedLeafKey([]byte(keyPEM))
	if err != nil {
		return nil, fmt.Errorf("load leaf key for %s: %w", host, err)
	}

	tlsCert := &tls.Certificate{Certificate: chain, PrivateKey: leafKey}
	cm.certCache.store(host, &cachedCert{
		cert:      tlsCert,
		expiresAt: notAfter,
	})
	return tlsCert, nil
}

// sharedLeafKey parses the kernel's shared leaf key once; every minted certificate reuses the same
// key object, so N hosts cost one key rather than N.
func (cm *CertManager) sharedLeafKey(keyPEM []byte) (*ecdsa.PrivateKey, error) {
	cm.leafKeyOnce.Do(func() {
		block, _ := pem.Decode(keyPEM)
		if block == nil {
			cm.leafKeyErr = fmt.Errorf("decode leaf key PEM: no PEM block found")
			return
		}
		cm.leafKey, cm.leafKeyErr = x509.ParseECPrivateKey(block.Bytes)
		if cm.leafKeyErr != nil {
			cm.leafKeyErr = fmt.Errorf("parse leaf key: %w", cm.leafKeyErr)
		}
	})
	return cm.leafKey, cm.leafKeyErr
}

// certChainDER turns the kernel's chain PEM (leaf first, then the CA) into the DER list
// tls.Certificate wants.
func certChainDER(chainPEM string) ([][]byte, error) {
	var chain [][]byte
	rest := []byte(chainPEM)
	for {
		var block *pem.Block
		block, rest = pem.Decode(rest)
		if block == nil {
			break
		}
		if block.Type != "CERTIFICATE" {
			return nil, fmt.Errorf("unexpected PEM block %q in the leaf chain", block.Type)
		}
		chain = append(chain, block.Bytes)
	}
	if len(chain) == 0 {
		return nil, fmt.Errorf("no certificate in the leaf chain")
	}
	return chain, nil
}

func fileExists(path string) bool {
	info, err := os.Stat(path)
	return err == nil && !info.IsDir()
}
