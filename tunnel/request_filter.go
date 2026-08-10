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

// SetRequestRules replaces the Go-tunnel HTTP URL-prefix rules. Rules are
// normalized on Android; this boundary validates only their transport shape.
func (e *Engine) SetRequestRules(content string) {
	var rules []requestRule
	if content != "" {
		if err := json.Unmarshal([]byte(content), &rules); err != nil {
			logf("SetRequestRules: invalid JSON: %v", err)
			return
		}
	}
	valid := make([]requestRule, 0, len(rules))
	for _, rule := range rules {
		rule.Pattern = strings.ToLower(strings.TrimSpace(rule.Pattern))
		if (rule.Kind == "block" || rule.Kind == "allow") &&
			(strings.HasPrefix(rule.Pattern, "http://") || strings.HasPrefix(rule.Pattern, "https://")) {
			valid = append(valid, rule)
		}
	}
	e.mu.Lock()
	e.requestRules = valid
	e.mu.Unlock()
}

// requestFilterDecision evaluates URL rules first. The longest matching URL
// wins, with an allow winning ties, then the existing domain policy applies.
func (e *Engine) requestFilterDecision(scheme, host, path string) (blocked bool, matched string) {
	host = strings.ToLower(strings.TrimSpace(host))
	if parsedHost, port, err := net.SplitHostPort(host); err == nil {
		if (scheme == "http" && port == "80") || (scheme == "https" && port == "443") {
			host = parsedHost
		}
	}
	if path == "" { path = "/" }
	url := strings.ToLower(scheme + "://" + host + path)
	e.mu.RLock()
	rules := append([]requestRule(nil), e.requestRules...)
	e.mu.RUnlock()
	bestLen := -1
	bestAllow := false
	bestPattern := ""
	for _, rule := range rules {
		if strings.HasPrefix(url, rule.Pattern) {
			length := len(rule.Pattern)
			allow := rule.Kind == "allow"
			if length > bestLen || (length == bestLen && allow && !bestAllow) {
				bestLen, bestAllow, bestPattern = length, allow, rule.Pattern
			}
		}
	}
	if bestLen >= 0 {
		return !bestAllow, bestPattern
	}
	domainHost := host
	if parsedHost, _, err := net.SplitHostPort(host); err == nil { domainHost = parsedHost }
	if e.IsDomainBlocked(domainHost) { return true, e.httpBlockReason(domainHost) }
	return false, ""
}

func writeBlockedHTTPResponse(client net.Conn, req *http.Request) {
	resp := &http.Response{
		StatusCode: http.StatusForbidden,
		ProtoMajor: 1,
		ProtoMinor: 1,
		Header: make(http.Header),
		Body: io.NopCloser(strings.NewReader("Blocked by DNSSR")),
		Request: req,
	}
	resp.Header.Set("Content-Type", "text/plain; charset=utf-8")
	resp.Header.Set("Content-Length", "16")
	_ = resp.Write(client)
}
