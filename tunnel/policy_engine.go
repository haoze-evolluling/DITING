package tunnel

import (
	"encoding/binary"
	"encoding/json"
	"fmt"
	"os"
	"regexp"
	"strings"
	"sync"
	"sync/atomic"
	"time"

	"golang.org/x/sys/unix"
)

const (
	dtriMagic      = 0x44545249 // "DTRI" in hex
	dtriVersion    = 1
	dtriHeaderSize = 36
	dtriNodeSize   = 12
	dtriEdgeSize   = 12
)

// dtriReader provides read-only memory-mapped lookup for binary subscription tries compiled by Kotlin.
type dtriReader struct {
	file         *os.File
	data         []byte
	filePath     string
	modTime      int64
	size         int64
	nodes        int
	edges        int
	sources      int
	bloomBits    int
	bloomBytes   int
	nodeOffset   int
	edgeOffset   int
	labelOffset  int
	sourceOffset int
	sourceNames  []string
	bloom        []byte
}

// openDTRI opens and memory-maps a DTRI binary file.
func openDTRI(path string) (*dtriReader, error) {
	if path == "" {
		return nil, fmt.Errorf("empty path")
	}

	f, err := os.Open(path)
	if err != nil {
		return nil, fmt.Errorf("failed to open DTRI file %s: %w", path, err)
	}

	stat, err := f.Stat()
	if err != nil {
		f.Close()
		return nil, fmt.Errorf("failed to stat DTRI file %s: %w", path, err)
	}

	size := stat.Size()
	if size < dtriHeaderSize {
		f.Close()
		return nil, fmt.Errorf("file %s too small to be a valid DTRI", path)
	}

	data, err := unix.Mmap(int(f.Fd()), 0, int(size), unix.PROT_READ, unix.MAP_SHARED)
	if err != nil {
		f.Close()
		return nil, fmt.Errorf("mmap failed for %s: %w", path, err)
	}

	magic := binary.BigEndian.Uint32(data[0:4])
	if magic != dtriMagic {
		unix.Munmap(data)
		f.Close()
		return nil, fmt.Errorf("invalid DTRI magic: expected %X, got %X", dtriMagic, magic)
	}

	version := binary.BigEndian.Uint32(data[4:8])
	if version != dtriVersion {
		unix.Munmap(data)
		f.Close()
		return nil, fmt.Errorf("invalid DTRI version: expected %d, got %d", dtriVersion, version)
	}

	nodes := int(binary.BigEndian.Uint32(data[8:12]))
	edges := int(binary.BigEndian.Uint32(data[12:16]))
	sources := int(binary.BigEndian.Uint32(data[16:20]))
	bloomBits := int(binary.BigEndian.Uint32(data[20:24]))
	bloomBytes := int(binary.BigEndian.Uint32(data[24:28]))
	labelsBytes := int(binary.BigEndian.Uint32(data[28:32]))
	sourcesBytes := int(binary.BigEndian.Uint32(data[32:36]))

	nodeOffset := dtriHeaderSize + bloomBytes
	edgeOffset := nodeOffset + nodes*dtriNodeSize
	labelOffset := edgeOffset + edges*dtriEdgeSize
	sourceOffset := labelOffset + labelsBytes

	if sourceOffset+sourcesBytes > len(data) {
		unix.Munmap(data)
		f.Close()
		return nil, fmt.Errorf("corrupted DTRI file %s", path)
	}

	sourceNames := make([]string, sources)
	cursor := sourceOffset
	for i := 0; i < sources; i++ {
		if cursor+4 > len(data) {
			break
		}
		strLen := int(binary.BigEndian.Uint32(data[cursor : cursor+4]))
		cursor += 4
		if cursor+strLen > len(data) {
			break
		}
		sourceNames[i] = string(data[cursor : cursor+strLen])
		cursor += strLen
	}

	modTime := stat.ModTime().UnixNano()

	return &dtriReader{
		file:         f,
		data:         data,
		filePath:     path,
		modTime:      modTime,
		size:         size,
		nodes:        nodes,
		edges:        edges,
		sources:      sources,
		bloomBits:    bloomBits,
		bloomBytes:   bloomBytes,
		nodeOffset:   nodeOffset,
		edgeOffset:   edgeOffset,
		labelOffset:  labelOffset,
		sourceOffset: sourceOffset,
		sourceNames:  sourceNames,
		bloom:        data[dtriHeaderSize : dtriHeaderSize+bloomBytes],
	}, nil
}

// close unmaps the memory and closes the underlying file.
func (r *dtriReader) close() {
	if r == nil {
		return
	}
	if r.data != nil {
		_ = unix.Munmap(r.data)
		r.data = nil
	}
	if r.file != nil {
		_ = r.file.Close()
		r.file = nil
	}
}

func (r *dtriReader) compareEdge(edgeIndex int, domain string, start, end int) int {
	base := r.edgeOffset + edgeIndex*dtriEdgeSize
	offset := int(binary.BigEndian.Uint32(r.data[base : base+4]))
	length := int(binary.BigEndian.Uint32(r.data[base+4 : base+8]))
	targetLen := end - start
	minLen := targetLen
	if length < minLen {
		minLen = length
	}
	labelBase := r.labelOffset + offset
	for i := 0; i < minLen; i++ {
		cTarget := int(domain[start+i])
		cEdge := int(r.data[labelBase+i])
		if cTarget != cEdge {
			return cTarget - cEdge
		}
	}
	return targetLen - length
}

func (r *dtriReader) findChild(node int, domain string, start, end int) int {
	base := r.nodeOffset + node*dtriNodeSize
	first := int(binary.BigEndian.Uint32(r.data[base+4 : base+8]))
	count := int(binary.BigEndian.Uint32(r.data[base+8 : base+12]))
	low := first
	high := first + count - 1
	for low <= high {
		mid := int(uint(low+high) >> 1)
		cmp := r.compareEdge(mid, domain, start, end)
		if cmp < 0 {
			high = mid - 1
		} else if cmp > 0 {
			low = mid + 1
		} else {
			edgeBase := r.edgeOffset + mid*dtriEdgeSize
			return int(binary.BigEndian.Uint32(r.data[edgeBase+8 : edgeBase+12]))
		}
	}
	return -1
}

func dtriHashes(val string, start, end int) (int64, int64) {
	h1 := int64(-3750763034362895579)
	h2 := int64(-3750763034362895579)
	for i := start; i < end; i++ {
		b := int64(val[i]) & 0xff
		h1 = (h1 ^ b) * 1099511628211
		h2 = (h2 * 1099511628211) ^ b
	}
	return h1, h2 | 1
}

func (r *dtriReader) mightContainDomainOrParent(domain string) bool {
	if r.bloomBits <= 0 || len(r.bloom) == 0 {
		return true
	}
	mod := int64(r.bloomBits)
	start := 0
	for start < len(domain) {
		h1, h2 := dtriHashes(domain, start, len(domain))
		possible := true
		for i := 0; i < 7; i++ {
			sum := h1 + int64(i)*h2
			bit := int((sum%mod + mod) % mod)
			byteIdx := bit / 8
			if byteIdx >= len(r.bloom) || (r.bloom[byteIdx]&(1<<uint(bit%8))) == 0 {
				possible = false
				break
			}
		}
		if possible {
			return true
		}
		dot := strings.IndexByte(domain[start:], '.')
		if dot < 0 {
			break
		}
		start += dot + 1
	}
	return false
}

// containsOrParent checks if a domain or its parent suffix is present in the trie.
func (r *dtriReader) containsOrParent(domain string) (bool, string) {
	if r == nil || len(r.data) == 0 {
		return false, ""
	}
	domain = strings.TrimSuffix(strings.ToLower(domain), ".")
	if domain == "" || !r.mightContainDomainOrParent(domain) {
		return false, ""
	}
	node := 0
	end := len(domain)
	for end > 0 {
		dot := strings.LastIndexByte(domain[:end], '.')
		start := dot + 1
		child := r.findChild(node, domain, start, end)
		if child < 0 {
			return false, ""
		}
		node = child
		base := r.nodeOffset + node*dtriNodeSize
		sourceIdx := int(int32(binary.BigEndian.Uint32(r.data[base : base+4])))
		if sourceIdx >= 0 {
			sourceName := "filter_list"
			if sourceIdx < len(r.sourceNames) {
				sourceName = r.sourceNames[sourceIdx]
			}
			return true, sourceName
		}
		end = dot
	}
	return false, ""
}

// wildcardMatcher evaluates glob wildcard rules.
type wildcardMatcher struct {
	pattern string
	isAll   bool
	regex   *regexp.Regexp
}

// newWildcardMatcher compiles a wildcard string.
func newWildcardMatcher(pattern string) *wildcardMatcher {
	if pattern == "*" {
		return &wildcardMatcher{pattern: pattern, isAll: true}
	}
	var sb strings.Builder
	sb.WriteString("^")
	for _, ch := range pattern {
		if ch == '*' {
			sb.WriteString(".*")
		} else {
			sb.WriteString(regexp.QuoteMeta(string(ch)))
		}
	}
	sb.WriteString("$")
	re, err := regexp.Compile("(?i)" + sb.String())
	if err != nil {
		return nil
	}
	return &wildcardMatcher{pattern: pattern, isAll: false, regex: re}
}

// matches checks whether domain or any parent domain matches the wildcard.
func (w *wildcardMatcher) matches(domain string) bool {
	if w == nil {
		return false
	}
	if w.isAll {
		return true
	}
	if w.regex == nil {
		return false
	}
	if w.regex.MatchString(domain) {
		return true
	}
	d := domain
	for {
		dot := strings.IndexByte(d, '.')
		if dot < 0 || dot >= len(d)-1 {
			break
		}
		d = d[dot+1:]
		if w.regex.MatchString(d) {
			return true
		}
	}
	return false
}

// appRuleBucket holds rule collections specific to a single app package.
type appRuleBucket struct {
	allow     map[string]struct{}
	block     map[string]string
	important map[string]string

	allowWildcards     []*wildcardMatcher
	blockWildcards     []*wildcardMatcher
	importantWildcards []*wildcardMatcher
}

// invertedRule represents a global rule that excludes certain apps.
type invertedRule struct {
	pattern      string
	source       string
	important    bool
	excludedApps map[string]struct{}
	wildcard     *wildcardMatcher
}

// policySnapshot is an immutable snapshot of all DNS rules evaluated locally in Go.
type policySnapshot struct {
	filterEnabled bool
	hasRules      bool

	// Priority 1: App $important rules (in appBuckets[pkg].important)

	// Priority 2: Global $important rules
	globalImportant          map[string]string
	globalImportantWildcards []*wildcardMatcher
	importantInverted        []invertedRule
	importantBlockTrie       *dtriReader

	// Priority 3: App allow rules (in appBuckets[pkg].allow)

	// Priority 4: Global allow rules
	globalAllow          map[string]struct{}
	globalAllowWildcards []*wildcardMatcher
	allowInverted        []invertedRule
	allowTrie            *dtriReader

	// Priority 5: App block rules (in appBuckets[pkg].block)

	// Priority 6: Global regular block rules
	globalBlock          map[string]string
	globalBlockWildcards []*wildcardMatcher
	blockInverted        []invertedRule
	blockTrie            *dtriReader

	// Per-app buckets
	appBuckets map[string]*appRuleBucket
}

func matchDomainOrSuffix(domain string, m map[string]string) (string, bool) {
	if len(m) == 0 {
		return "", false
	}
	if val, ok := m[domain]; ok {
		return val, true
	}
	d := domain
	for {
		pos := strings.IndexByte(d, '.')
		if pos < 0 || pos >= len(d)-1 {
			break
		}
		d = d[pos+1:]
		if val, ok := m[d]; ok {
			return val, true
		}
	}
	return "", false
}

func matchDomainOrSuffixSet(domain string, s map[string]struct{}) bool {
	if len(s) == 0 {
		return false
	}
	if _, ok := s[domain]; ok {
		return true
	}
	d := domain
	for {
		pos := strings.IndexByte(d, '.')
		if pos < 0 || pos >= len(d)-1 {
			break
		}
		d = d[pos+1:]
		if _, ok := s[d]; ok {
			return true
		}
	}
	return false
}

func matchSingleDomainOrSuffix(domain, pattern string) bool {
	if domain == pattern {
		return true
	}
	return strings.HasSuffix(domain, "."+pattern)
}

// evaluate applies the 7-level domain decision matrix locally in Go memory.
// Returns:
//   - (true, reason) if blocked
//   - (false, "__ALLOW__") if explicitly allowed by allow list
//   - (false, "") if default pass (no matching rule)
func (s *policySnapshot) evaluate(domain, appName string) (blocked bool, reason string) {
	if s == nil || !s.filterEnabled {
		return false, ""
	}

	domain = strings.TrimSuffix(strings.ToLower(strings.TrimSpace(domain)), ".")
	if domain == "" {
		return false, ""
	}
	appName = strings.TrimSpace(appName)

	// 1. App 专属 $important 拦截规则
	if appName != "" && len(s.appBuckets) > 0 {
		if bucket, ok := s.appBuckets[appName]; ok {
			if r, hit := matchDomainOrSuffix(domain, bucket.important); hit {
				return true, r
			}
			for _, wc := range bucket.importantWildcards {
				if wc.matches(domain) {
					return true, wc.pattern
				}
			}
		}
	}

	// 2. 全局 $important 拦截规则 (含反向排除与订阅 trie)
	for _, inv := range s.importantInverted {
		if appName != "" {
			if _, excluded := inv.excludedApps[appName]; excluded {
				continue
			}
		}
		if inv.wildcard != nil {
			if inv.wildcard.matches(domain) {
				return true, inv.pattern
			}
		} else if matchSingleDomainOrSuffix(domain, inv.pattern) {
			return true, inv.pattern
		}
	}

	if r, hit := matchDomainOrSuffix(domain, s.globalImportant); hit {
		return true, r
	}
	for _, wc := range s.globalImportantWildcards {
		if wc.matches(domain) {
			return true, wc.pattern
		}
	}
	if s.importantBlockTrie != nil {
		if hit, src := s.importantBlockTrie.containsOrParent(domain); hit {
			return true, src
		}
	}

	// 3. App 专属白名单规则 (@@)
	if appName != "" && len(s.appBuckets) > 0 {
		if bucket, ok := s.appBuckets[appName]; ok {
			if matchDomainOrSuffixSet(domain, bucket.allow) {
				return false, "__ALLOW__"
			}
			for _, wc := range bucket.allowWildcards {
				if wc.matches(domain) {
					return false, "__ALLOW__"
				}
			}
		}
	}

	// 4. 全局白名单规则 (@@, 含反向排除与订阅 allowTrie)
	for _, inv := range s.allowInverted {
		if appName != "" {
			if _, excluded := inv.excludedApps[appName]; excluded {
				continue
			}
		}
		if inv.wildcard != nil {
			if inv.wildcard.matches(domain) {
				return false, "__ALLOW__"
			}
		} else if matchSingleDomainOrSuffix(domain, inv.pattern) {
			return false, "__ALLOW__"
		}
	}

	if matchDomainOrSuffixSet(domain, s.globalAllow) {
		return false, "__ALLOW__"
	}
	for _, wc := range s.globalAllowWildcards {
		if wc.matches(domain) {
			return false, "__ALLOW__"
		}
	}
	if s.allowTrie != nil {
		if hit, _ := s.allowTrie.containsOrParent(domain); hit {
			return false, "__ALLOW__"
		}
	}

	// 5. App 专属普通拦截规则 (包含 *$app=pkg 全阻断)
	if appName != "" && len(s.appBuckets) > 0 {
		if bucket, ok := s.appBuckets[appName]; ok {
			if r, hit := matchDomainOrSuffix(domain, bucket.block); hit {
				return true, r
			}
			for _, wc := range bucket.blockWildcards {
				if wc.matches(domain) {
					return true, wc.pattern
				}
			}
		}
	}

	// 6. 全局普通拦截规则 (含反向排除与订阅 blockTrie)
	for _, inv := range s.blockInverted {
		if appName != "" {
			if _, excluded := inv.excludedApps[appName]; excluded {
				continue
			}
		}
		if inv.wildcard != nil {
			if inv.wildcard.matches(domain) {
				return true, inv.pattern
			}
		} else if matchSingleDomainOrSuffix(domain, inv.pattern) {
			return true, inv.pattern
		}
	}

	if r, hit := matchDomainOrSuffix(domain, s.globalBlock); hit {
		return true, r
	}
	for _, wc := range s.globalBlockWildcards {
		if wc.matches(domain) {
			return true, wc.pattern
		}
	}
	if s.blockTrie != nil {
		if hit, src := s.blockTrie.containsOrParent(domain); hit {
			return true, src
		}
	}

	// 7. 默认放行
	return false, ""
}

// policyEngine coordinates thread-safe rule snapshot updates and local queries.
type policyEngine struct {
	snapshot    atomic.Pointer[policySnapshot]
	initialized atomic.Bool

	mu           sync.Mutex
	currentTries map[string]*dtriReader
}

// newPolicyEngine creates an empty policy engine.
func newPolicyEngine() *policyEngine {
	pe := &policyEngine{
		currentTries: make(map[string]*dtriReader),
	}
	pe.snapshot.Store(&policySnapshot{filterEnabled: true, hasRules: false})
	return pe
}

// isActive returns whether a snapshot has been pushed and initialized by Kotlin.
func (pe *policyEngine) isActive() bool {
	return pe != nil && pe.initialized.Load()
}

// hasRules returns whether any rules or tries are currently active.
func (pe *policyEngine) hasRules() bool {
	if pe == nil {
		return false
	}
	snap := pe.snapshot.Load()
	return snap != nil && snap.hasRules
}

// evaluate checks domain policy locally in Go memory without lock contention.
func (pe *policyEngine) evaluate(domain, appName string) (blocked bool, reason string) {
	if pe == nil {
		return false, ""
	}
	snap := pe.snapshot.Load()
	if snap == nil {
		return false, ""
	}
	return snap.evaluate(domain, appName)
}

// ruleSnapshotJSON defines the schema pushed by Kotlin.
type ruleSnapshotJSON struct {
	FilterEnabled          *bool                          `json:"filterEnabled"`
	BlockTriePath          string                         `json:"blockTriePath"`
	ImportantBlockTriePath string                         `json:"importantBlockTriePath"`
	AllowTriePath          string                         `json:"allowTriePath"`
	GlobalAllow            []string                       `json:"globalAllow"`
	GlobalBlock            []string                       `json:"globalBlock"`
	GlobalImportant        []string                       `json:"globalImportant"`
	AppRules               map[string]appRulesConfigJSON  `json:"appRules"`
	InvertedBlock          []invertedRuleConfigJSON       `json:"invertedBlock"`
	InvertedAllow          []invertedRuleConfigJSON       `json:"invertedAllow"`
}

// appRulesConfigJSON holds per-app rule lists in the snapshot JSON.
type appRulesConfigJSON struct {
	Allow     []string `json:"allow"`
	Block     []string `json:"block"`
	Important []string `json:"important"`
}

// invertedRuleConfigJSON holds app-inverted rules in the snapshot JSON.
type invertedRuleConfigJSON struct {
	Pattern      string   `json:"pattern"`
	Source       string   `json:"source"`
	Important    bool     `json:"important"`
	ExcludedApps []string `json:"excludedApps"`
}

// applySnapshot parses the JSON snapshot and updates the active policy snapshot atomically.
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
		appBuckets:      make(map[string]*appRuleBucket),
	}

	// 1. Global Important
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

	// 2. Global Allow
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

	// 3. Global Block
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

	// 4. App Rules
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

	// 5. Inverted Block
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

	// 6. Inverted Allow
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

	// 7. Manage Mmap Tries under lock
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

	// Helper to obtain or open a dtriReader
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
			// File has changed on disk! Retire old reader safely
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
	snap.allowTrie = getOrOpenTrie(req.AllowTriePath)

	snap.hasRules = len(snap.globalImportant) > 0 ||
		len(snap.globalImportantWildcards) > 0 ||
		len(snap.importantInverted) > 0 ||
		snap.importantBlockTrie != nil ||
		len(snap.globalAllow) > 0 ||
		len(snap.globalAllowWildcards) > 0 ||
		len(snap.allowInverted) > 0 ||
		snap.allowTrie != nil ||
		len(snap.globalBlock) > 0 ||
		len(snap.globalBlockWildcards) > 0 ||
		len(snap.blockInverted) > 0 ||
		snap.blockTrie != nil ||
		len(snap.appBuckets) > 0

	// Atomically switch active snapshot first so new queries use the updated policy
	pe.snapshot.Store(snap)
	pe.initialized.Store(true)

	// Safely retire unused tries with a grace delay so in-flight queries on the old snapshot complete
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

// close closes all open Mmap tries.
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
