package tunnel

import (
	"path/filepath"
	"strings"
)

// SetTries loads the native memory-mapped domain tries and bloom filters for
// fast lookups in Go. It accepts comma-separated absolute paths to the
// ad/security binary trie files and their corresponding bloom filter files.
func (e *Engine) SetTries(adTriePathsCsv, secTriePathsCsv, adBloomPathsCsv, secBloomPathsCsv string) {
	e.mu.Lock()
	defer e.mu.Unlock()

	for _, t := range e.adTries {
		if t != nil {
			t.Close()
		}
	}
	e.adTries = nil
	e.adTrieIDs = nil

	for _, t := range e.secTries {
		if t != nil {
			t.Close()
		}
	}
	e.secTries = nil
	e.secTrieIDs = nil

	for _, bf := range e.adBlooms {
		if bf != nil {
			bf.Close()
		}
	}
	e.adBlooms = nil

	for _, bf := range e.secBlooms {
		if bf != nil {
			bf.Close()
		}
	}
	e.secBlooms = nil

	for _, path := range strings.Split(adTriePathsCsv, ",") {
		path = strings.TrimSpace(path)
		if path == "" { continue }
		t, err := LoadMmapTrie(path)
		if err != nil {
			logf("Failed to load Ad Trie from %s: %v", path, err)
		} else {
			e.adTries = append(e.adTries, t)
			id := strings.TrimSuffix(filepath.Base(path), ".trie")
			e.adTrieIDs = append(e.adTrieIDs, id)
			logf("Loaded Ad Trie from Go native Mmap: %s", path)
		}
	}

	for _, path := range strings.Split(secTriePathsCsv, ",") {
		path = strings.TrimSpace(path)
		if path == "" { continue }
		t, err := LoadMmapTrie(path)
		if err != nil {
			logf("Failed to load Security Trie from %s: %v", path, err)
		} else {
			e.secTries = append(e.secTries, t)
			id := strings.TrimSuffix(filepath.Base(path), ".trie")
			e.secTrieIDs = append(e.secTrieIDs, id)
			logf("Loaded Security Trie from Go native Mmap: %s", path)
		}
	}

	for _, path := range strings.Split(adBloomPathsCsv, ",") {
		path = strings.TrimSpace(path)
		if path == "" { continue }
		bf, err := LoadBloomFilter(path)
		if err != nil {
			logf("Failed to load Ad Bloom Filter from %s: %v", path, err)
		} else {
			e.adBlooms = append(e.adBlooms, bf)
			logf("Loaded Ad Bloom Filter for fast pre-filtering: %s", path)
		}
	}

	for _, path := range strings.Split(secBloomPathsCsv, ",") {
		path = strings.TrimSpace(path)
		if path == "" { continue }
		bf, err := LoadBloomFilter(path)
		if err != nil {
			logf("Failed to load Security Bloom Filter from %s: %v", path, err)
		} else {
			e.secBlooms = append(e.secBlooms, bf)
			logf("Loaded Security Bloom Filter for fast pre-filtering: %s", path)
		}
	}
	e.hasNativeRules.Store(len(e.adTries) > 0 || len(e.secTries) > 0)
}

// SetImportantTries loads important-rule tries. They are checked before any
// custom allow rule so a $important block cannot be silently downgraded.
func (e *Engine) SetImportantTries(pathsCsv string) {
	e.mu.Lock()
	defer e.mu.Unlock()
	for _, trie := range e.importantTries { if trie != nil { trie.Close() } }
	e.importantTries = nil
	for _, path := range strings.Split(pathsCsv, ",") {
		path = strings.TrimSpace(path)
		if path == "" { continue }
		trie, err := LoadMmapTrie(path)
		if err != nil { logf("Failed to load important Trie from %s: %v", path, err); continue }
		e.importantTries = append(e.importantTries, trie)
	}
	e.hasImportantRules.Store(len(e.importantTries) > 0)
}

func (e *Engine) hasImportantMatch(domain string) bool {
	if !e.hasImportantRules.Load() {
		return false
	}
	e.mu.Lock()
	tries := e.importantTries
	e.mu.Unlock()
	for _, trie := range tries { if trie != nil && trie.ContainsOrParent(domain) { return true } }
	return false
}

func (e *Engine) checkDomainBlockedAndReason(host string, appName string) (blocked bool, reason string) {
	host = strings.ToLower(strings.TrimSpace(host))
	if host == "" {
		return false, ""
	}
	// 1. Local Go PolicyEngine check (zero JNI, fast path)
	if e.policyEngine != nil && e.policyEngine.isActive() {
		blocked, res := e.policyEngine.evaluate(host, appName)
		if blocked {
			return true, res
		}
		return false, ""
	} else {
		if e.hasImportantMatch(host) {
			return true, "important"
		}

		// Custom & Subscription rule check via single-shot CheckDomain.
		if e.domainChecker != nil {
			res := e.domainChecker.CheckDomain(host, appName)
			if res == "__ALLOW__" {
				return false, "" // explicitly allowed
			}
			if res != "" {
				return true, res // explicitly blocked with reason
			}
		}
	}

	if !e.hasNativeRules.Load() {
		return false, ""
	}

	// Security trie (bloom pre-filter → mmap trie).
	e.mu.Lock()
	secBlooms := e.secBlooms
	secTries := e.secTries
	adBlooms := e.adBlooms
	adTries := e.adTries
	e.mu.Unlock()

	for i, secTrie := range secTries {
		if secTrie == nil { continue }
		var secBloom *BloomFilter
		if i < len(secBlooms) {
			secBloom = secBlooms[i]
		}
		if secBloom == nil || secBloom.MightContainDomainOrParent(host) {
			if secTrie.ContainsOrParent(host) {
				return true, "security"
			}
		}
	}

	// Ad trie (bloom pre-filter → mmap trie).
	for i, adTrie := range adTries {
		if adTrie == nil { continue }
		var adBloom *BloomFilter
		if i < len(adBlooms) {
			adBloom = adBlooms[i]
		}
		if adBloom == nil || adBloom.MightContainDomainOrParent(host) {
			if adTrie.ContainsOrParent(host) {
				return true, "filter_list"
			}
		}
	}

	return false, ""
}

// IsDomainBlocked satisfies the AdBlockChecker interface used by the MITM
// proxy. It replicates the same blocking pipeline used for DNS queries:
// CustomRule(allow override) → SecurityTrie → AdTrie → Kotlin DomainChecker.
func (e *Engine) IsDomainBlocked(host string) bool {
	return e.IsDomainBlockedForApp(host, "")
}

func (e *Engine) IsDomainBlockedForApp(host string, appName string) bool {
	blocked, _ := e.checkDomainBlockedAndReason(host, appName)
	return blocked
}

func (e *Engine) httpBlockReason(host string) string {
	return e.httpBlockReasonForApp(host, "")
}

func (e *Engine) httpBlockReasonForApp(host string, appName string) string {
	if e == nil {
		return "filter_list"
	}
	_, reason := e.checkDomainBlockedAndReason(host, appName)
	if reason == "" {
		return "filter_list"
	}
	return reason
}
