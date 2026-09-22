// policy_engine.go implements the unified high-performance policy engine for domain filtering,
// managing policy lifecycle, atomic snapshot swaps, DTRI binary trie caching, and rule ingestion.

package tunnel

import (
	"encoding/json"
	"fmt"
	"os"
	"regexp"
	"strings"
	"sync"
	"sync/atomic"
	"time"

	"github.com/miekg/dns"
)

type policyEngine struct {
	snapshot    atomic.Pointer[policySnapshot]
	initialized atomic.Bool

	mu           sync.Mutex
	currentTries map[string]*dtriReader
}

func newPolicyEngine() *policyEngine {
	pe := &policyEngine{
		currentTries: make(map[string]*dtriReader),
	}
	pe.snapshot.Store(&policySnapshot{filterEnabled: true, hasRules: false})
	return pe
}

func (pe *policyEngine) isActive() bool {
	return pe != nil && pe.initialized.Load()
}

func (pe *policyEngine) hasRules() bool {
	if pe == nil {
		return false
	}
	snap := pe.snapshot.Load()
	return snap != nil && snap.hasRules
}

func (pe *policyEngine) evaluate(domain, appName string, qtype uint16) (blocked bool, reason string) {
	if pe == nil {
		return false, ""
	}
	snap := pe.snapshot.Load()
	if snap == nil {
		return false, ""
	}
	return snap.evaluate(domain, appName, qtype)
}

type ruleSnapshotJSON struct {
	FilterEnabled          *bool                         `json:"filterEnabled"`
	BlockTriePath          string                        `json:"blockTriePath"`
	ImportantBlockTriePath string                        `json:"importantBlockTriePath"`
	AllowTriePath          string                        `json:"allowTriePath"`
	ImportantAllowTriePath string                        `json:"importantAllowTriePath"`
	GlobalAllow            []string                      `json:"globalAllow"`
	GlobalBlock            []string                      `json:"globalBlock"`
	GlobalImportant        []string                      `json:"globalImportant"`
	AppRules               map[string]appRulesConfigJSON `json:"appRules"`
	InvertedBlock          []invertedRuleConfigJSON      `json:"invertedBlock"`
	InvertedAllow          []invertedRuleConfigJSON      `json:"invertedAllow"`
	SpecialBlock           []specialRuleConfigJSON       `json:"specialBlock"`
	SpecialAllow           []specialRuleConfigJSON       `json:"specialAllow"`
	DisabledRules          []string                      `json:"disabledRules"`
}

type appRulesConfigJSON struct {
	Allow     []string `json:"allow"`
	Block     []string `json:"block"`
	Important []string `json:"important"`
}

type invertedRuleConfigJSON struct {
	Pattern      string   `json:"pattern"`
	Source       string   `json:"source"`
	Important    bool     `json:"important"`
	ExcludedApps []string `json:"excludedApps"`
}

type specialRuleConfigJSON struct {
	Pattern     string `json:"pattern"`
	Source      string `json:"source"`
	Important   bool   `json:"important"`
	AppScope    string `json:"appScope"`
	AppInverted bool   `json:"appInverted"`
	IsWildcard  bool   `json:"isWildcard"`
	Denyallow   string `json:"denyallow"`
	IsRegex     bool   `json:"isRegex"`
	DnsType     string `json:"dnsType"`
}

func parseSpecialRule(cfg specialRuleConfigJSON, isAllow bool) *specialRule {
	rule := &specialRule{
		pattern:     strings.TrimSpace(cfg.Pattern),
		source:      cfg.Source,
		important:   cfg.Important,
		isAllow:     isAllow,
		appInverted: cfg.AppInverted,
		isRegex:     cfg.IsRegex,
	}

	if rule.isRegex {
		rxPattern := rule.pattern
		if !strings.HasPrefix(rxPattern, "(?i)") {
			rxPattern = "(?i)" + rxPattern
		}
		rx, err := regexp.Compile(rxPattern)
		if err != nil {
			logf("policyEngine: failed to compile regex rule '%s': %v", rule.pattern, err)
			return nil
		}
		rule.regex = rx
	} else {
		rule.pattern = strings.ToLower(rule.pattern)
		if cfg.IsWildcard || strings.Contains(rule.pattern, "*") {
			rule.wildcard = newWildcardMatcher(rule.pattern)
		}
	}

	if cfg.AppScope != "" {
		pkgs := strings.Split(cfg.AppScope, "|")
		rule.appScope = make(map[string]struct{}, len(pkgs))
		for _, pkg := range pkgs {
			pkg = strings.ToLower(strings.TrimSpace(pkg))
			if pkg != "" {
				rule.appScope[pkg] = struct{}{}
			}
		}
	}

	if cfg.Denyallow != "" {
		exceptions := strings.Split(cfg.Denyallow, "|")
		for _, exc := range exceptions {
			exc = strings.TrimSuffix(strings.ToLower(strings.TrimSpace(exc)), ".")
			if exc != "" {
				rule.denyallow = append(rule.denyallow, exc)
			}
		}
	}

	if cfg.DnsType != "" {
		raw := strings.TrimSpace(cfg.DnsType)
		isNegative := strings.HasPrefix(raw, "~")
		if isNegative {
			raw = strings.TrimPrefix(raw, "~")
		}
		types := strings.Split(raw, "|")
		targetMap := make(map[uint16]struct{})
		for _, t := range types {
			t = strings.TrimPrefix(strings.TrimSpace(strings.ToUpper(t)), "~")
			if t == "" {
				continue
			}
			if qt, ok := dns.StringToType[t]; ok {
				targetMap[qt] = struct{}{}
			}
		}
		if len(targetMap) > 0 {
			if isNegative {
				rule.excludeQtypes = targetMap
			} else {
				rule.includeQtypes = targetMap
			}
		}
	}

	return rule
}

func (pe *policyEngine) applySnapshot(jsonStr string) error {
	if pe == nil {
		return fmt.Errorf("policy engine is nil")
	}

	var req ruleSnapshotJSON
	if err := json.Unmarshal([]byte(jsonStr), &req); err != nil {
		return fmt.Errorf("unmarshal rule snapshot json: %w", err)
	}

	filterEnabled := true
	if req.FilterEnabled != nil {
		filterEnabled = *req.FilterEnabled
	}

	snap := &policySnapshot{
		filterEnabled:   filterEnabled,
		globalImportant: make(map[string]string),
		globalAllow:     make(map[string]struct{}),
		globalBlock:     make(map[string]string),
		disabledRules:   make(map[string]struct{}),
		appBuckets:      make(map[string]*appRuleBucket),
	}

	for _, p := range req.DisabledRules {
		p = strings.ToLower(strings.TrimSpace(p))
		if p != "" {
			snap.disabledRules[p] = struct{}{}
		}
	}

	for _, p := range req.GlobalImportant {
		p = strings.ToLower(strings.TrimSpace(p))
		if p == "" {
			continue
		}
		if p == "*" || strings.Contains(p, "*") {
			if wc := newWildcardMatcher(p); wc != nil {
				snap.globalImportantWildcards = append(snap.globalImportantWildcards, wc)
			}
		} else {
			snap.globalImportant[p] = "important"
		}
	}

	for _, p := range req.GlobalAllow {
		p = strings.ToLower(strings.TrimSpace(p))
		if p == "" {
			continue
		}
		if p == "*" || strings.Contains(p, "*") {
			if wc := newWildcardMatcher(p); wc != nil {
				snap.globalAllowWildcards = append(snap.globalAllowWildcards, wc)
			}
		} else {
			snap.globalAllow[p] = struct{}{}
		}
	}

	for _, p := range req.GlobalBlock {
		p = strings.ToLower(strings.TrimSpace(p))
		if p == "" {
			continue
		}
		if p == "*" || strings.Contains(p, "*") {
			if wc := newWildcardMatcher(p); wc != nil {
				snap.globalBlockWildcards = append(snap.globalBlockWildcards, wc)
			}
		} else {
			snap.globalBlock[p] = p
		}
	}

	for pkg, bucketConf := range req.AppRules {
		pkg = strings.ToLower(strings.TrimSpace(pkg))
		if pkg == "" {
			continue
		}
		bucket := &appRuleBucket{
			allow:     make(map[string]struct{}),
			block:     make(map[string]string),
			important: make(map[string]string),
		}

		for _, p := range bucketConf.Allow {
			p = strings.ToLower(strings.TrimSpace(p))
			if p == "" {
				continue
			}
			if p == "*" || strings.Contains(p, "*") {
				if wc := newWildcardMatcher(p); wc != nil {
					bucket.allowWildcards = append(bucket.allowWildcards, wc)
				}
			} else {
				bucket.allow[p] = struct{}{}
			}
		}

		for _, p := range bucketConf.Block {
			p = strings.ToLower(strings.TrimSpace(p))
			if p == "" {
				continue
			}
			if p == "*" || strings.Contains(p, "*") {
				if wc := newWildcardMatcher(p); wc != nil {
					bucket.blockWildcards = append(bucket.blockWildcards, wc)
				}
			} else {
				bucket.block[p] = p
			}
		}

		for _, p := range bucketConf.Important {
			p = strings.ToLower(strings.TrimSpace(p))
			if p == "" {
				continue
			}
			if p == "*" || strings.Contains(p, "*") {
				if wc := newWildcardMatcher(p); wc != nil {
					bucket.importantWildcards = append(bucket.importantWildcards, wc)
				}
			} else {
				bucket.important[p] = "important"
			}
		}

		snap.appBuckets[pkg] = bucket
	}

	for _, inv := range req.InvertedBlock {
		p := strings.ToLower(strings.TrimSpace(inv.Pattern))
		if p == "" {
			continue
		}
		excluded := make(map[string]struct{})
		for _, app := range inv.ExcludedApps {
			app = strings.ToLower(strings.TrimSpace(app))
			if app != "" {
				excluded[app] = struct{}{}
			}
		}
		var wc *wildcardMatcher
		if p == "*" || strings.Contains(p, "*") {
			wc = newWildcardMatcher(p)
		}
		item := invertedRule{
			pattern:      p,
			source:       inv.Source,
			important:    inv.Important,
			excludedApps: excluded,
			wildcard:     wc,
		}
		if inv.Important {
			snap.importantInverted = append(snap.importantInverted, item)
		} else {
			snap.blockInverted = append(snap.blockInverted, item)
		}
	}

	for _, inv := range req.InvertedAllow {
		p := strings.ToLower(strings.TrimSpace(inv.Pattern))
		if p == "" {
			continue
		}
		excluded := make(map[string]struct{})
		for _, app := range inv.ExcludedApps {
			app = strings.ToLower(strings.TrimSpace(app))
			if app != "" {
				excluded[app] = struct{}{}
			}
		}
		var wc *wildcardMatcher
		if p == "*" || strings.Contains(p, "*") {
			wc = newWildcardMatcher(p)
		}
		snap.allowInverted = append(snap.allowInverted, invertedRule{
			pattern:      p,
			source:       inv.Source,
			important:    false,
			excludedApps: excluded,
			wildcard:     wc,
		})
	}

	for _, cfg := range req.SpecialBlock {
		r := parseSpecialRule(cfg, false)
		if r == nil {
			continue
		}
		hasAppScope := len(r.appScope) > 0
		if r.important {
			if hasAppScope && !r.appInverted {
				snap.importantAppBlockSpecial = append(snap.importantAppBlockSpecial, r)
			} else {
				snap.importantGlobalBlockSpecial = append(snap.importantGlobalBlockSpecial, r)
			}
		} else {
			if hasAppScope && !r.appInverted {
				snap.appBlockSpecial = append(snap.appBlockSpecial, r)
			} else {
				snap.globalBlockSpecial = append(snap.globalBlockSpecial, r)
			}
		}
	}

	for _, cfg := range req.SpecialAllow {
		r := parseSpecialRule(cfg, true)
		if r == nil {
			continue
		}
		hasAppScope := len(r.appScope) > 0
		if hasAppScope && !r.appInverted {
			snap.appAllowSpecial = append(snap.appAllowSpecial, r)
		} else {
			snap.globalAllowSpecial = append(snap.globalAllowSpecial, r)
		}
	}

	pe.mu.Lock()
	defer pe.mu.Unlock()

	neededPaths := make(map[string]bool)
	if req.BlockTriePath != "" {
		neededPaths[req.BlockTriePath] = true
	}
	if req.ImportantBlockTriePath != "" {
		neededPaths[req.ImportantBlockTriePath] = true
	}
	if req.AllowTriePath != "" {
		neededPaths[req.AllowTriePath] = true
	}
	if req.ImportantAllowTriePath != "" {
		neededPaths[req.ImportantAllowTriePath] = true
	}

	getOrOpenTrie := func(path string) *dtriReader {
		if path == "" {
			return nil
		}
		stat, err := os.Stat(path)
		if err != nil {
			logf("policyEngine: failed to stat DTRI trie %s: %v", path, err)
			return nil
		}
		if reader, ok := pe.currentTries[path]; ok {
			if reader.modTime == stat.ModTime().UnixNano() && reader.size == stat.Size() {
				return reader
			}

			rToClose := reader
			time.AfterFunc(2*time.Second, func() {
				rToClose.close()
			})
			delete(pe.currentTries, path)
		}
		reader, err := openDTRI(path)
		if err != nil {
			logf("policyEngine: failed to open DTRI trie %s: %v", path, err)
			return nil
		}
		pe.currentTries[path] = reader
		logf("policyEngine: loaded DTRI trie %s (size=%d)", path, stat.Size())
		return reader
	}

	snap.blockTrie = getOrOpenTrie(req.BlockTriePath)
	snap.importantBlockTrie = getOrOpenTrie(req.ImportantBlockTriePath)
	snap.importantAllowTrie = getOrOpenTrie(req.ImportantAllowTriePath)
	snap.allowTrie = getOrOpenTrie(req.AllowTriePath)

	snap.hasRules = len(snap.globalImportant) > 0 ||
		len(snap.globalImportantWildcards) > 0 ||
		len(snap.importantInverted) > 0 ||
		snap.importantBlockTrie != nil ||
		len(snap.globalAllow) > 0 ||
		len(snap.globalAllowWildcards) > 0 ||
		len(snap.allowInverted) > 0 ||
		snap.importantAllowTrie != nil ||
		snap.allowTrie != nil ||
		len(snap.globalBlock) > 0 ||
		len(snap.globalBlockWildcards) > 0 ||
		len(snap.blockInverted) > 0 ||
		snap.blockTrie != nil ||
		len(snap.appBuckets) > 0 ||
		len(snap.importantAppBlockSpecial) > 0 ||
		len(snap.importantGlobalBlockSpecial) > 0 ||
		len(snap.appAllowSpecial) > 0 ||
		len(snap.globalAllowSpecial) > 0 ||
		len(snap.appBlockSpecial) > 0 ||
		len(snap.globalBlockSpecial) > 0

	pe.snapshot.Store(snap)
	pe.initialized.Store(true)

	for path, reader := range pe.currentTries {
		if !neededPaths[path] {
			rToClose := reader
			time.AfterFunc(2*time.Second, func() {
				rToClose.close()
			})
			delete(pe.currentTries, path)
		}
	}

	return nil
}

func (pe *policyEngine) close() {
	if pe == nil {
		return
	}
	pe.mu.Lock()
	defer pe.mu.Unlock()

	for path, reader := range pe.currentTries {
		reader.close()
		delete(pe.currentTries, path)
	}
	pe.initialized.Store(false)
	pe.snapshot.Store(&policySnapshot{filterEnabled: true, hasRules: false})
}
