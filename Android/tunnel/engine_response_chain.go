// engine_response_chain.go implements CNAME cloaking protection (P0-A of the DNS
// filtering gap analysis): an upstream answer must not be trusted just because
// the queried first-party domain passed the rules. Before an answer is written
// back to the client, every domain in the response chain — CNAME targets and
// SVCB/HTTPS (type 64/65) TargetName records — is re-evaluated against the
// policy engine, mirroring AdGuard Home semantics.

package tunnel

import (
	"strings"

	"github.com/miekg/dns"
)

// checkResponseChain re-runs filtering rules against every CNAME target and
// SVCB/HTTPS TargetName present in an upstream DNS answer.
//
// Semantics (aligned with AdGuard Home):
//   - A blocking match anywhere in the chain blocks the whole response.
//   - A whitelist ("__ALLOW__") hit only exempts that particular target;
//     evaluation continues with the remaining chain entries.
//   - Chain filtering is only active when the policy engine is active and has
//     rules; otherwise responses pass through unchanged.
//
// The returned reason carries a "cname:"/"svcb:" prefix plus the hit domain
// and the underlying rule source, e.g. "cname:tracker.example.com (filter_list)",
// so query logs can attribute the block to the actual chain hop.
func (e *Engine) checkResponseChain(msg *dns.Msg, appName string) (blocked bool, reason string) {
	if e == nil || msg == nil || len(msg.Answer) == 0 {
		return false, ""
	}
	if e.policyEngine == nil || !e.policyEngine.isActive() || !e.policyEngine.hasRules() {
		return false, ""
	}

	var qtype uint16
	if len(msg.Question) > 0 {
		qtype = msg.Question[0].Qtype
	}

	for _, rr := range msg.Answer {
		var target, kind string
		switch record := rr.(type) {
		case *dns.CNAME:
			target, kind = record.Target, "cname"
		case *dns.SVCB:
			target, kind = record.Target, "svcb"
		case *dns.HTTPS:
			// HTTPS (type 65) embeds SVCB; TargetName is carried in SVCB.Target.
			target, kind = record.SVCB.Target, "svcb"
		default:
			continue
		}

		domain := strings.TrimSuffix(strings.ToLower(strings.TrimSpace(target)), ".")
		if domain == "" {
			continue
		}

		if hit, res := e.policyEngine.evaluate(domain, appName, qtype); hit {
			if res == "" {
				return true, kind + ":" + domain
			}
			return true, kind + ":" + domain + " (" + res + ")"
		}
		// No match, or "__ALLOW__": a whitelist only exempts this target,
		// keep walking the rest of the chain.
	}
	return false, ""
}

// checkResponseChainTargets evaluates pre-extracted CNAME/SVCB chain targets against the policy engine.
// This is the fast-path version for cached responses to eliminate dns.Msg unpacking.
func (e *Engine) checkResponseChainTargets(targets []chainTarget, appName string, qtype uint16) (blocked bool, reason string) {
	if e == nil || len(targets) == 0 {
		return false, ""
	}
	if e.policyEngine == nil || !e.policyEngine.isActive() || !e.policyEngine.hasRules() {
		return false, ""
	}

	for _, target := range targets {
		if target.domain == "" {
			continue
		}
		if hit, res := e.policyEngine.evaluate(target.domain, appName, qtype); hit {
			if res == "" {
				return true, target.kind + ":" + target.domain
			}
			return true, target.kind + ":" + target.domain + " (" + res + ")"
		}
	}
	return false, ""
}

