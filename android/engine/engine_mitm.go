// engine_mitm.go orchestrates MITM HTTPS interception lifecycle within Engine.
//
// Lifecycle & Configuration:
// - StartStackMitm initializes root CA certificates, compiles bypass rules, configures smart filtering,
//   and registers the flow-mode MITM handler on the userspace TCP/IP stack.
// - StopStackMitm tears down MITM handlers, flushes dynamic leaf certificate caches, and resets stack routing to direct passthrough.

package tunnel

import (
	"net"
	"os"
	"path/filepath"
	"strings"
)

const defaultTunMTU = 1400

var localAssetSynthIP = net.IPv4(198, 51, 100, 1)

func (e *Engine) StartStackMitm(certDir string) string {
	certMgr, err := NewCertManager(certDir)
	if err != nil {
		logf("StartStackMitm: cert manager init failed: %v", err)
		return ""
	}
	certMgr.WarmLocalAssetCert()

	e.mu.Lock()
	e.stackCertMgr = certMgr
	if e.stackMitmFilter == nil {
		e.stackMitmFilter = NewMitmFilter()
	}
	filter := e.stackMitmFilter
	e.certDir = certDir
	e.mu.Unlock()

	filter.LoadPersistentBlacklist(filepath.Join(certDir, "mitm_blacklist.txt"))

	return certMgr.GetCACertPEM()
}

func (e *Engine) StopStackMitm() {
	e.mu.Lock()
	certMgr := e.stackCertMgr
	e.stackCertMgr = nil
	e.stackMitmFilter = nil
	e.mu.Unlock()
	// Drop the minted leaf certificates with the session: they are keyed by host
	// and would otherwise outlive the engine that minted them.
	if certMgr != nil {
		certMgr.Release()
	}
}

// SetUseTcpStack is kept for gomobile API compatibility: the Android services
// still call it before StartFull. StartFull always runs the gVisor stack, and
// the legacy Start() path that this flag switched has been removed.
func (e *Engine) SetUseTcpStack(enabled bool) {}

// IsUsingTcpStack always reports true: StartFull is the only TUN data plane.
func (e *Engine) IsUsingTcpStack() bool { return true }

func (e *Engine) SetUIDResolver(r UIDResolver) {
	r = newCachingUIDResolver(r)
	e.mu.Lock()
	e.uidResolver = r
	stack := e.tcpStack
	e.mu.Unlock()

	if stack != nil {
		stack.SetUIDResolver(r)
	}
}

func (e *Engine) IsMitmActive() bool {
	e.mu.Lock()
	defer e.mu.Unlock()
	return e.stackCertMgr != nil
}

func (e *Engine) GetMitmCACert(certDir string) string {
	e.mu.Lock()
	certMgr := e.stackCertMgr
	e.mu.Unlock()

	if certMgr != nil {
		return certMgr.GetCACertPEM()
	}

	certPath := filepath.Join(certDir, caCertFile)
	if !fileExists(certPath) {
		return ""
	}
	data, err := os.ReadFile(certPath)
	if err != nil {
		logf("Failed to read persistent CA cert: %v", err)
		return ""
	}
	return string(data)
}

func (e *Engine) SetMitmAllowedUIDs(uidsCsv string) {
	e.mu.Lock()
	stackFilter := e.stackMitmFilter
	e.mu.Unlock()

	if stackFilter == nil {
		logf("MITM: SetAllowedUIDs called but stack MITM is not active")
		return
	}

	var uids []int
	for _, s := range strings.Split(uidsCsv, ",") {
		s = strings.TrimSpace(s)
		if s == "" {
			continue
		}
		uid := 0
		for _, c := range s {
			if c >= '0' && c <= '9' {
				uid = uid*10 + int(c-'0')
			}
		}
		if uid > 0 {
			uids = append(uids, uid)
		}
	}
	stackFilter.SetAllowedUIDs(uids)
}

func (e *Engine) SetHttpsBypassRules(content string) {
	e.mu.Lock()
	filter := e.stackMitmFilter
	e.mu.Unlock()
	if filter == nil {
		logf("SetHttpsBypassRules: stack MITM not active")
		return
	}
	filter.SetHttpsBypassRules(strings.Split(content, "\n"))
}

func (e *Engine) SetExtraPassthroughSuffixes(content string) {
	e.SetHttpsBypassRules(content)
}

func (e *Engine) ClearMitmBlacklist() {
	e.mu.Lock()
	filter := e.stackMitmFilter
	e.mu.Unlock()
	if filter != nil {
		filter.ClearBlacklist()
	}
}

// SetCosmeticRules replaces the domain-scoped cosmetic rule set (JSON, see
// SetCosmeticRules in mitm_cosmetic_inject.go).
func (e *Engine) SetCosmeticRules(payload string) {
	SetCosmeticRules(payload)
}

func (e *Engine) logHTTPEvent(flow flowID, authority, protocol, outcome, matchedRule string) {
	if e == nil {
		return
	}
	e.callbackMu.RLock()
	callback := e.httpLogCallback
	e.callbackMu.RUnlock()
	if callback == nil {
		return
	}
	packageName := e.appNameForFlow(flow, ProtocolTCP)
	if packageName == "" {
		packageName = "unknown"
	}
	callback.OnHttpEvent(packageName, authority, protocol, outcome, matchedRule)
}
