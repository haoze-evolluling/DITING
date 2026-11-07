// engine_request_filter.go provides HTTP request-level path and URL-prefix filtering.
//
// What is left here after the migration to rust/diting-request-core:
// - `SetRequestRules`: `encoding/json` decoding, the handle swap under the engine lock and closing
//   the previous handle (so a request in flight never sees a freed one).
// - `requestFilterDecision`: one kernel match, then the domain-rule fallback (`policyEngine`) when no
//   URL rule matched.
// - `writeBlockedHTTPResponse`: the 403 the relay writes back.
//
// What moved to the kernel: the rule normalization (trim, lower-case, the `block` / `allow`
// whitelist, the mandatory `http(s)://` prefix) and the whole decision (host fold, default-port
// strip, `path == ""`, the `scheme://host path` URL build, the longest-prefix walk with allow
// winning ties, and the host the fallback should be asked about).
//
// Rule Resolution:
// - Request rules take precedence over general domain rules.
// - Evaluation uses longest-prefix matching with allow rules winning ties before falling back to domain filtering.

package tunnel

import (
	"encoding/json"
	"io"
	"net"
	"net/http"
	"strings"
)

type requestRule struct {
	Pattern string `json:"pattern"`
	Kind    string `json:"kind"`
}

func (e *Engine) SetRequestRules(content string) {
	var rules []requestRule
	if content != "" {
		if err := json.Unmarshal([]byte(content), &rules); err != nil {
			logf("SetRequestRules: invalid JSON: %v", err)
			return
		}
	}

	// The kernel drops the rules it cannot match (unknown kind, no scheme prefix) silently, exactly
	// like the old normalization loop did.
	set, err := newNativeRequestRules(rules)
	if err != nil {
		set = nil
	}

	e.mu.Lock()
	previous := e.requestRules
	e.requestRules = set
	e.mu.Unlock()

	if previous != nil {
		previous.release()
	}
}

// requestFilterDecision answers whether one request is blocked and, if so, by which rule.
//
// The kernel match runs under the engine lock: `SetRequestRules` swaps the handle under the same
// lock, so the handle cannot be freed while this call is inside it.
func (e *Engine) requestFilterDecision(scheme, host, path, appName string) (blocked bool, matched string) {
	e.mu.Lock()
	rules := e.requestRules
	var decision requestDecision
	decided := false
	if rules != nil {
		if result, err := rules.match(scheme, host, path); err == nil {
			decision, decided = result, true
		}
	}
	e.mu.Unlock()

	domainHost := host
	if decided {
		if decision.matched {
			return decision.blocked, decision.pattern
		}
		domainHost = decision.domainHost
	}
	if blocked, reason := e.checkDomainBlockedAndReason(domainHost, appName); blocked {
		return true, reason
	}
	return false, ""
}

func writeBlockedHTTPResponse(client net.Conn, req *http.Request) {
	resp := &http.Response{
		StatusCode: http.StatusForbidden,
		ProtoMajor: 1,
		ProtoMinor: 1,
		Header:     make(http.Header),
		Body:       io.NopCloser(strings.NewReader("Blocked by DITING")),
		Request:    req,
	}
	resp.Header.Set("Content-Type", "text/plain; charset=utf-8")
	resp.Header.Set("Content-Length", "16")
	_ = resp.Write(client)
}
