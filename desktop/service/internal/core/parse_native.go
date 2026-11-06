package core

// parse_native.go drives the Rust rule parser (rust/diting-filter-core/src/parse.rs) through the
// same C ABI the matcher uses.
//
// Responsibility split: Rust owns everything that happens *while reading text* — comment and
// cosmetic-rule skipping, the hosts form, `@@` exceptions, the `$` modifier list, `$dnstype`,
// `$denyallow=`/`$to=`, the AdGuard domain forms, wildcard patterns and the IDNA normalization.
// Go keeps the compiled regexes (`regexp` for `/regex/`, `buildWildcardRegex` for wildcards, both
// of which the matcher needs as sources) and the `$dnsrewrite` value parsing, because that pulls in
// the whole rewrite-record subsystem.
//
// The kernel is required: a missing library, a stale ABI or a rejected request fails the parse.
// `ParseRules` reports that to its caller; `ParseRuleLine` has no error in its signature, so it logs
// and drops the line, and the rule index build that follows fails loudly anyway.

import (
	"encoding/binary"
	"fmt"
	"log"
	"regexp"
	"runtime"
	"unsafe"
)

// parseNativeLayoutVersion must match `LAYOUT_VERSION` in
// rust/diting-filter-core/src/parse_payload.rs.
const parseNativeLayoutVersion = 1

// parsedLine is one rule as the kernel reports it, before Go attaches the compiled regex and the
// parsed `$dnsrewrite` action.
type parsedLine struct {
	raw       string
	pattern   string
	flags     uint8
	dnsType   uint16
	denyAllow []string
	to        []string
	// rewrite is nil when the rule carries no `$dnsrewrite`; the raw value otherwise (empty for the
	// bare form).
	rewrite *string
}

// parseRulesText parses a whole list through the kernel.
func parseRulesText(text string) ([]parsedLine, error) {
	lib, err := filterKernel()
	if err != nil {
		return nil, err
	}
	payload := parseEncodeRequest(text)

	var input unsafe.Pointer
	if len(payload) > 0 {
		input = unsafe.Pointer(&payload[0])
	}
	var out unsafe.Pointer
	var outLen uintptr
	status := lib.parseRules(input, uintptr(len(payload)), &out, &outLen)
	runtime.KeepAlive(payload)
	data := filterTakePayload(lib, out, outLen)

	if status != filterStatusOK {
		if len(data) > 0 {
			return nil, fmt.Errorf("rule parser rejected the list: %s", data)
		}
		return nil, fmt.Errorf("rule parser returned status %d", status)
	}
	return decodeParsedLines(data)
}

// parseRuleText parses a single line through the kernel.
func parseRuleText(line string) (*parsedLine, error) {
	lib, err := filterKernel()
	if err != nil {
		return nil, err
	}
	payload := parseEncodeRequest(line)

	var input unsafe.Pointer
	if len(payload) > 0 {
		input = unsafe.Pointer(&payload[0])
	}
	var out unsafe.Pointer
	var outLen uintptr
	status := lib.parseRule(input, uintptr(len(payload)), &out, &outLen)
	runtime.KeepAlive(payload)
	data := filterTakePayload(lib, out, outLen)

	if status != filterStatusOK {
		if len(data) > 0 {
			return nil, fmt.Errorf("rule parser rejected the line: %s", data)
		}
		return nil, fmt.Errorf("rule parser returned status %d", status)
	}
	lines, err := decodeParsedLines(data)
	if err != nil {
		return nil, err
	}
	if len(lines) == 0 {
		return nil, nil
	}
	return &lines[0], nil
}

// parseEncodeRequest serializes the text in the layout src/parse_payload.rs decodes.
func parseEncodeRequest(text string) []byte {
	payload := make([]byte, 0, len(text)+5)
	payload = append(payload, parseNativeLayoutVersion)
	payload = binary.LittleEndian.AppendUint32(payload, uint32(len(text)))
	return append(payload, text...)
}

// decodeParsedLines reads the parser reply.
func decodeParsedLines(payload []byte) ([]parsedLine, error) {
	reader := &payloadReader{data: payload}
	layout, err := reader.u8()
	if err != nil {
		return nil, err
	}
	if layout != parseNativeLayoutVersion {
		return nil, fmt.Errorf("rule parse layout %d, expected %d", layout, parseNativeLayoutVersion)
	}
	count, err := reader.u32()
	if err != nil {
		return nil, err
	}
	lines := make([]parsedLine, 0, count)
	for i := uint32(0); i < count; i++ {
		line, err := decodeParsedLine(reader)
		if err != nil {
			return nil, err
		}
		lines = append(lines, line)
	}
	if remaining := reader.remaining(); remaining != 0 {
		return nil, fmt.Errorf("rule parse payload has %d trailing bytes", remaining)
	}
	return lines, nil
}

func decodeParsedLine(reader *payloadReader) (parsedLine, error) {
	var line parsedLine
	var err error
	if line.raw, err = reader.text32(); err != nil {
		return line, err
	}
	if line.pattern, err = reader.text32(); err != nil {
		return line, err
	}
	if line.flags, err = reader.u8(); err != nil {
		return line, err
	}
	if line.flags&^filterKnownFlags != 0 {
		return line, fmt.Errorf("rule parse flags %08b contain unknown bits", line.flags)
	}
	dnsType, err := reader.u16()
	if err != nil {
		return line, err
	}
	line.dnsType = uint16(dnsType)
	if line.denyAllow, err = reader.texts32(); err != nil {
		return line, err
	}
	if line.to, err = reader.texts32(); err != nil {
		return line, err
	}
	if line.flags&filterFlagRewrite != 0 {
		value, err := reader.text32()
		if err != nil {
			return line, err
		}
		line.rewrite = &value
	}
	return line, nil
}

// toParsedRule attaches what the kernel deliberately leaves to Go: the compiled pattern and the
// `$dnsrewrite` action. Both can fail, and a failure drops the rule exactly like the Go parser did
// (an uncompilable regex, an unparsable rewrite value).
func (l parsedLine) toParsedRule(source string) (*ParsedRule, bool) {
	rule := &ParsedRule{
		Raw:        l.raw,
		Pattern:    l.pattern,
		IsAllow:    l.flags&filterFlagAllow != 0,
		Important:  l.flags&filterFlagImportant != 0,
		IsRegex:    l.flags&filterFlagRegex != 0,
		DNSType:    l.dnsType,
		IsWildcard: l.flags&filterFlagWildcard != 0,
		IsExact:    l.flags&filterFlagExact != 0,
		Source:     source,
		DenyAllow:  l.denyAllow,
		To:         l.to,
	}

	if rule.IsRegex {
		// The source arrives without its slashes; `(?i)` is how Go always compiled it.
		compiled, err := regexp.Compile("(?i)" + rule.Pattern)
		if err != nil {
			return nil, false
		}
		rule.Regex = compiled
	} else if rule.IsWildcard {
		rule.Regex = buildWildcardRegex(rule.Pattern)
	}

	if l.rewrite != nil {
		action, err := parseDNSRewriteModifier(*l.rewrite)
		if err != nil {
			return nil, false
		}
		rule.Rewrite = action
	}
	return rule, true
}

// logParseFailure reports a parser failure on paths whose signature has no error to return.
func logParseFailure(what string, err error) {
	log.Printf("[RuleParser] Rust 规则解析失败（%s）: %v", what, err)
}
