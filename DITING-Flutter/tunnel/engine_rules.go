// engine_rules.go answers "is this domain blocked" for the HTTP/HTTPS (MITM) paths.
//
// All domain rules live in the Go policy engine (see policy_engine.go), loaded through
// ApplyRuleSnapshot. Until a snapshot has been applied, nothing is blocked.

package tunnel

import "strings"

func (e *Engine) checkDomainBlockedAndReason(host string, appName string) (blocked bool, reason string) {
	host = strings.ToLower(strings.TrimSpace(host))
	if host == "" {
		return false, ""
	}
	if e.policyEngine == nil || !e.policyEngine.isActive() {
		return false, ""
	}
	return e.policyEngine.evaluate(host, appName, 0)
}

func (e *Engine) IsDomainBlocked(host string) bool {
	return e.IsDomainBlockedForApp(host, "")
}

func (e *Engine) IsDomainBlockedForApp(host string, appName string) bool {
	blocked, _ := e.checkDomainBlockedAndReason(host, appName)
	return blocked
}
