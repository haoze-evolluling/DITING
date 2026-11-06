package core

// filter_native.go loads the Rust rule index (rust/diting-filter-core) and drives it through the C
// ABI in that crate's src/ffi.rs.
//
// Responsibility split: Rust owns the tries, the bloom prefilter, the wildcard/regex lists, the
// `$denyallow=`/`$to=` exclusions, the priority walk and the `$dnsrewrite` selection. Go keeps the
// rule text (raw line, list name), the rule loading, and the `dns.RR` construction a rewrite hit
// needs, which is why a decision comes back as *rule indices* rather than as finished rules.
//
// The kernel is required. A missing library, a stale ABI or a rejected payload fails the rule index
// build, which fails the rule engine rebuild: there is no second matcher left, and a silent one
// would only keep working until a query landed on the rule set that differs.
//
// Loading is pure Go (syscall.LazyDLL on Windows, purego elsewhere), so the module stays
// CGO_ENABLED=0 and the existing cross-compiles keep working.

import (
	"encoding/binary"
	"errors"
	"fmt"
	"runtime"
	"sync"
	"unsafe"
)

// filterNativeABIVersion must match `ABI_VERSION` in rust/diting-filter-core/src/ffi.rs.
//
// Version 2 added the two parser entry points; a version 1 library has neither, so the loader
// refuses it instead of the first parse failing at run time.
const filterNativeABIVersion = 2

// Payload layout and status codes; keep in sync with src/payload.rs and src/ffi.rs.
const (
	filterPayloadLayoutVersion = 1
	filterStatusOK             = 0
	filterStatusRejected       = 1
	filterNoReasonCode         = 0xFF
	filterNoRuleIndex          = 0xFFFFFFFF
)

// Rule flags, mirroring the FLAG_* constants in rust/diting-filter-core/src/rule.rs.
const (
	filterFlagAllow     uint8 = 1 << 0
	filterFlagImportant uint8 = 1 << 1
	filterFlagRegex     uint8 = 1 << 2
	filterFlagWildcard  uint8 = 1 << 3
	filterFlagExact     uint8 = 1 << 4
	filterFlagRewrite   uint8 = 1 << 5

	// filterKnownFlags is `rule::KNOWN_FLAGS`: a payload with any other bit set is a layout mismatch.
	filterKnownFlags = filterFlagAllow | filterFlagImportant | filterFlagRegex |
		filterFlagWildcard | filterFlagExact | filterFlagRewrite
)

// Decision action codes (src/payload.rs `Action::code`).
const (
	filterActionPass    uint8 = 0
	filterActionAllow   uint8 = 1
	filterActionBlock   uint8 = 2
	filterActionRewrite uint8 = 3
)

// filterReasonNames maps `Reason::code` to the reason strings the query log, the rule test panel and
// the existing tests use.
var filterReasonNames = [...]string{
	"important_allow",
	"important_block",
	"whitelist",
	"blacklist",
	"wildcard_block",
	"regex_block",
}

// filterNativeLib is one loaded kernel: the matcher and the parser entry points.
type filterNativeLib struct {
	build      func(input unsafe.Pointer, inputLen uintptr, handleOut *unsafe.Pointer, out *unsafe.Pointer, outLen *uintptr) uint32
	match      func(handle unsafe.Pointer, domain unsafe.Pointer, domainLen uintptr, qtype uint16, out *unsafe.Pointer, outLen *uintptr) uint32
	parseRules func(input unsafe.Pointer, inputLen uintptr, out *unsafe.Pointer, outLen *uintptr) uint32
	parseRule  func(input unsafe.Pointer, inputLen uintptr, out *unsafe.Pointer, outLen *uintptr) uint32
	free       func(handle unsafe.Pointer)
	freeBytes  func(pointer unsafe.Pointer, length uintptr)
}

var (
	filterNativeOnce   sync.Once
	filterNativeShared *filterNativeLib
	filterNativeErr    error
)

func loadFilterNativeLibrary() (*filterNativeLib, error) {
	return loadNativeLibrary("DITING_FILTER_CORE_LIB", "diting_filter_core", "rule filter kernel", loadFilterLibrary)
}

// filterKernel returns the loaded library; the failure is kept so every build reports the same
// reason instead of retrying the probe.
func filterKernel() (*filterNativeLib, error) {
	filterNativeOnce.Do(func() {
		filterNativeShared, filterNativeErr = loadFilterNativeLibrary()
	})
	if filterNativeErr != nil {
		return nil, filterNativeErr
	}
	return filterNativeShared, nil
}

// filterIndexStats is the build report the kernel returns next to the handle.
type filterIndexStats struct {
	totalRules         uint32
	hasDenyAllow       bool
	uncompiledPatterns uint32
}

// filterRewriteAnswer names the rules whose `$dnsrewrite` values make up a rewrite answer.
type filterRewriteAnswer struct {
	rcode int
	rules []int32
}

// filterDecision is one raw verdict from the kernel.
type filterDecision struct {
	action    uint8
	reason    string
	ruleIndex int32
	rewrite   *filterRewriteAnswer
}

// filterBuildIndex hands the encoded rules to the kernel and returns its handle plus the stats.
func filterBuildIndex(payload []byte) (unsafe.Pointer, filterIndexStats, error) {
	lib, err := filterKernel()
	if err != nil {
		return nil, filterIndexStats{}, err
	}

	var input unsafe.Pointer
	if len(payload) > 0 {
		input = unsafe.Pointer(&payload[0])
	}
	var handle unsafe.Pointer
	var out unsafe.Pointer
	var outLen uintptr
	status := lib.build(input, uintptr(len(payload)), &handle, &out, &outLen)
	runtime.KeepAlive(payload)
	data := filterTakePayload(lib, out, outLen)

	switch status {
	case filterStatusOK:
		stats, err := decodeFilterStats(data)
		if err != nil {
			lib.free(handle)
			return nil, filterIndexStats{}, err
		}
		return handle, stats, nil
	case filterStatusRejected:
		if len(data) == 0 {
			return nil, filterIndexStats{}, errors.New("rule index rejected by the native kernel")
		}
		return nil, filterIndexStats{}, errors.New(string(data))
	default:
		return nil, filterIndexStats{}, fmt.Errorf("rule filter kernel returned status %d", status)
	}
}

// filterMatchDomain asks the kernel which rule answers one normalized domain.
func filterMatchDomain(handle unsafe.Pointer, domain string, qtype uint16) (filterDecision, error) {
	lib, err := filterKernel()
	if err != nil {
		return filterDecision{}, err
	}

	var input unsafe.Pointer
	if len(domain) > 0 {
		input = unsafe.Pointer(unsafe.StringData(domain))
	}
	var out unsafe.Pointer
	var outLen uintptr
	status := lib.match(handle, input, uintptr(len(domain)), qtype, &out, &outLen)
	runtime.KeepAlive(domain)
	data := filterTakePayload(lib, out, outLen)

	if status != filterStatusOK {
		return filterDecision{}, fmt.Errorf("rule filter kernel returned status %d", status)
	}
	return decodeFilterDecision(data)
}

// filterFreeIndex drops a built index.
func filterFreeIndex(handle unsafe.Pointer) {
	if handle == nil {
		return
	}
	lib, err := filterKernel()
	if err != nil {
		return
	}
	lib.free(handle)
}

// filterTakePayload copies a payload the kernel lent us and frees the original.
func filterTakePayload(lib *filterNativeLib, out unsafe.Pointer, outLen uintptr) []byte {
	if out == nil || outLen == 0 {
		if out != nil {
			lib.freeBytes(out, outLen)
		}
		return nil
	}
	payload := make([]byte, int(outLen))
	copy(payload, unsafe.Slice((*byte)(out), int(outLen)))
	lib.freeBytes(out, outLen)
	return payload
}

// filterEncodeRules serializes the rules Go wants indexed, in the layout src/payload.rs decodes.
func filterEncodeRules(rules []*ParsedRule) []byte {
	payload := make([]byte, 0, 16*len(rules)+8)
	payload = append(payload, filterPayloadLayoutVersion)
	payload = binary.LittleEndian.AppendUint32(payload, uint32(len(rules)))
	for _, rule := range rules {
		payload = append(payload, filterRuleFlags(rule))
		payload = binary.LittleEndian.AppendUint16(payload, rule.DNSType)
		payload = appendFilterText(payload, rule.Pattern)
		payload = appendFilterText(payload, filterRegexSource(rule))
		payload = appendFilterTexts(payload, rule.DenyAllow)
		payload = appendFilterTexts(payload, rule.To)
		if rule.Rewrite == nil {
			continue
		}
		bare := byte(0)
		if rule.Rewrite.Bare {
			bare = 1
		}
		payload = append(payload, bare)
		payload = append(payload, byte(rule.Rewrite.RCode))
		payload = binary.LittleEndian.AppendUint16(payload, rule.Rewrite.RRType)
		payload = appendFilterText(payload, rule.Rewrite.key())
	}
	return payload
}

// filterRuleFlags packs the booleans the matcher branches on.
func filterRuleFlags(rule *ParsedRule) uint8 {
	var flags uint8
	if rule.IsAllow {
		flags |= filterFlagAllow
	}
	if rule.Important {
		flags |= filterFlagImportant
	}
	if rule.IsRegex {
		flags |= filterFlagRegex
	}
	if rule.IsWildcard {
		flags |= filterFlagWildcard
	}
	if rule.IsExact {
		flags |= filterFlagExact
	}
	if rule.Rewrite != nil {
		flags |= filterFlagRewrite
	}
	return flags
}

// filterRegexSource returns the pattern source Go compiled for a wildcard/regex rule.
//
// Passing `Regex.String()` instead of `Pattern` keeps both engines on the same source: the wildcard
// form is derived by `buildWildcardRegex` in one place, and the `(?i)` prefix travels with it.
func filterRegexSource(rule *ParsedRule) string {
	if !rule.IsRegex && !rule.IsWildcard {
		return ""
	}
	if rule.Regex == nil {
		return ""
	}
	return rule.Regex.String()
}

func appendFilterText(payload []byte, value string) []byte {
	payload = binary.LittleEndian.AppendUint16(payload, uint16(len(value)))
	return append(payload, value...)
}

func appendFilterTexts(payload []byte, values []string) []byte {
	payload = binary.LittleEndian.AppendUint16(payload, uint16(len(values)))
	for _, value := range values {
		payload = appendFilterText(payload, value)
	}
	return payload
}

// decodeFilterStats reads the build report.
func decodeFilterStats(payload []byte) (filterIndexStats, error) {
	reader := &payloadReader{data: payload}
	layout, err := reader.u8()
	if err != nil {
		return filterIndexStats{}, err
	}
	if layout != filterPayloadLayoutVersion {
		return filterIndexStats{}, fmt.Errorf("rule index stats layout %d, expected %d", layout, filterPayloadLayoutVersion)
	}
	total, err := reader.u32()
	if err != nil {
		return filterIndexStats{}, err
	}
	hasDenyAllow, err := reader.u8()
	if err != nil {
		return filterIndexStats{}, err
	}
	uncompiled, err := reader.u32()
	if err != nil {
		return filterIndexStats{}, err
	}
	if remaining := reader.remaining(); remaining != 0 {
		return filterIndexStats{}, fmt.Errorf("rule index stats have %d trailing bytes", remaining)
	}
	return filterIndexStats{
		totalRules:         total,
		hasDenyAllow:       hasDenyAllow != 0,
		uncompiledPatterns: uncompiled,
	}, nil
}

// decodeFilterDecision reads one verdict.
func decodeFilterDecision(payload []byte) (filterDecision, error) {
	reader := &payloadReader{data: payload}
	layout, err := reader.u8()
	if err != nil {
		return filterDecision{}, err
	}
	if layout != filterPayloadLayoutVersion {
		return filterDecision{}, fmt.Errorf("rule decision layout %d, expected %d", layout, filterPayloadLayoutVersion)
	}
	action, err := reader.u8()
	if err != nil {
		return filterDecision{}, err
	}
	reasonCode, err := reader.u8()
	if err != nil {
		return filterDecision{}, err
	}
	index, err := reader.u32()
	if err != nil {
		return filterDecision{}, err
	}
	decision := filterDecision{action: action, ruleIndex: int32(index)}
	if reasonCode != filterNoReasonCode {
		if int(reasonCode) >= len(filterReasonNames) {
			return filterDecision{}, fmt.Errorf("rule decision reason %d is unknown", reasonCode)
		}
		decision.reason = filterReasonNames[reasonCode]
	}
	if index == filterNoRuleIndex {
		decision.ruleIndex = -1
	}

	hasRewrite, err := reader.u8()
	if err != nil {
		return filterDecision{}, err
	}
	if hasRewrite != 0 {
		rcode, err := reader.u8()
		if err != nil {
			return filterDecision{}, err
		}
		count, err := reader.u32()
		if err != nil {
			return filterDecision{}, err
		}
		answer := &filterRewriteAnswer{rcode: int(rcode), rules: make([]int32, 0, count)}
		for i := uint32(0); i < count; i++ {
			rule, err := reader.u32()
			if err != nil {
				return filterDecision{}, err
			}
			answer.rules = append(answer.rules, int32(rule))
		}
		decision.rewrite = answer
	}
	if remaining := reader.remaining(); remaining != 0 {
		return filterDecision{}, fmt.Errorf("rule decision has %d trailing bytes", remaining)
	}
	return decision, nil
}
