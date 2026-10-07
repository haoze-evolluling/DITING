package core

import (
	"bufio"
	"io"
	"net"
	"regexp"
	"strings"

	"github.com/miekg/dns"
	"golang.org/x/net/idna"
)

// ParsedRule 解析后的单条过滤规则
type ParsedRule struct {
	Raw        string         // 原始文本行
	Pattern    string         // 标准化后的域名或模式
	IsAllow    bool           // 是否为白名单例外规则 (@@)
	Important  bool           // 是否为重要规则 ($important)
	IsRegex    bool           // 是否为正则规则 (/.../)
	Regex      *regexp.Regexp // 正则表达式实例
	DNSType    uint16         // 限制的 DNS 记录类型 (0 表示全部)
	IsWildcard bool           // 是否含通配符 (*)
	IsExact    bool           // 是否为精确匹配 (|domain|)
	Source     string         // 来源 (如 "custom" 或 订阅列表 ID)
}

// ParseRules 从 io.Reader 读取并解析全部规则
func ParseRules(r io.Reader, source string) ([]*ParsedRule, error) {
	scanner := bufio.NewScanner(r)
	scanner.Buffer(make([]byte, 256*1024), 1024*1024)

	var rules []*ParsedRule
	for scanner.Scan() {
		line := scanner.Text()
		trimmed := strings.TrimSpace(strings.TrimPrefix(line, "\ufeff"))
		if trimmed == "" || trimmed[0] == '!' || trimmed[0] == '#' || trimmed[0] == '[' {
			continue
		}

		// 处理 /etc/hosts 多域名格式 (例如 0.0.0.0 ad1.com ad2.com)
		fields := strings.Fields(trimmed)
		if len(fields) >= 2 && isLiteralIP(fields[0]) {
			if isSinkholeIP(fields[0]) {
				for _, host := range fields[1:] {
					// 剥离行末注释
					if idx := strings.IndexByte(host, '#'); idx >= 0 {
						host = host[:idx]
					}
					if norm, ok := normalizeDomain(host); ok {
						rules = append(rules, &ParsedRule{
							Raw:     line,
							Pattern: norm,
							Source:  source,
						})
					}
				}
			}
			continue
		}

		parsed, ok := ParseRuleLine(line, source)
		if ok && parsed != nil {
			rules = append(rules, parsed)
		}
	}

	if err := scanner.Err(); err != nil {
		return nil, err
	}
	return rules, nil
}

// ParseRuleLine 解析单行规则
func ParseRuleLine(line, source string) (*ParsedRule, bool) {
	origLine := line
	line = strings.TrimSpace(strings.TrimPrefix(line, "\ufeff"))

	// 忽略空行、整行注释与列表头信息
	if line == "" || line[0] == '!' || line[0] == '#' || line[0] == '[' {
		return nil, false
	}

	// 剥离行末注释 (非正则情形)
	if !strings.HasPrefix(line, "/") {
		line = strings.TrimSpace(strings.SplitN(line, "#", 2)[0])
		if line == "" {
			return nil, false
		}
	}

	// 1. 处理 /etc/hosts 格式 (例如 0.0.0.0 ads.example.com 或 127.0.0.1 ad1 ad2)
	fields := strings.Fields(line)
	if len(fields) >= 2 && isLiteralIP(fields[0]) {
		if isSinkholeIP(fields[0]) {
			// 取首个 host，多 host 可由外层 ParseRules 拆分
			firstHost := fields[1]
			norm, ok := normalizeDomain(firstHost)
			if ok {
				return &ParsedRule{
					Raw:     origLine,
					Pattern: norm,
					Source:  source,
				}, true
			}
		}
		return nil, false
	}

	// 忽略网页/CSS 过滤规则 (##, #@#, #?# 等非 DNS 规则)
	if strings.Contains(line, "##") || strings.Contains(line, "#@#") || strings.Contains(line, "#?#") {
		return nil, false
	}

	// 2. 检测例外规则 (@@ 开头)
	isAllow := false
	if strings.HasPrefix(line, "@@") {
		isAllow = true
		line = strings.TrimPrefix(line, "@@")
	}

	// 3. 处理修饰符 ($ 开头)
	important := false
	var dnsType uint16 = 0
	var modPart string

	if strings.HasPrefix(line, "/") {
		// 正则规则: 修饰符必须在闭合斜杠 / 之后
		if lastSlash := strings.LastIndexByte(line, '/'); lastSlash > 0 && lastSlash < len(line)-1 {
			rem := line[lastSlash+1:]
			if dollarIdx := strings.IndexByte(rem, '$'); dollarIdx >= 0 {
				modPart = rem[dollarIdx+1:]
				line = line[:lastSlash+1]
			}
		}
	} else if modIdx := strings.IndexByte(line, '$'); modIdx >= 0 {
		modPart = line[modIdx+1:]
		line = strings.TrimSpace(line[:modIdx])
	}

	if modPart != "" {
		modifiers := strings.Split(modPart, ",")
		for _, mod := range modifiers {
			mod = strings.TrimSpace(strings.ToLower(mod))
			if mod == "important" {
				important = true
			} else if mod == "badfilter" {
				// badfilter 规则用于废止已有规则，DNS 内核阶段直接忽略
				return nil, false
			} else if strings.HasPrefix(mod, "dnstype=") {
				typeStr := strings.TrimPrefix(mod, "dnstype=")
				if t, ok := dns.StringToType[strings.ToUpper(typeStr)]; ok {
					dnsType = t
				}
			} else if isWebOnlyModifier(mod) {
				// 浏览器专有资源修饰符，在 DNS 阶段安全跳过，防止整域误杀
				return nil, false
			}
		}
	}

	// 4. 正则规则 (/pattern/)
	if strings.HasPrefix(line, "/") && strings.HasSuffix(line, "/") && len(line) > 2 {
		regexStr := line[1 : len(line)-1]
		rx, err := regexp.Compile("(?i)" + regexStr)
		if err != nil {
			return nil, false
		}
		return &ParsedRule{
			Raw:       origLine,
			Pattern:   regexStr,
			IsAllow:   isAllow,
			Important: important,
			IsRegex:   true,
			Regex:     rx,
			DNSType:   dnsType,
			Source:    source,
		}, true
	}

	// 5. AdGuard 域匹配语法解析
	isExact := false
	var domain string

	switch {
	case strings.HasPrefix(line, "||"):
		// ||example.com^ 表示匹配 example.com 及其所有子域名
		domain = strings.TrimPrefix(line, "||")
		domain = strings.TrimSuffix(domain, "^")
		if strings.HasSuffix(domain, "|") {
			domain = strings.TrimSuffix(domain, "|")
			isExact = true
		}
	case strings.HasPrefix(line, "|") && strings.HasSuffix(line, "|"):
		// |example.com| 精确匹配
		isExact = true
		domain = strings.Trim(line, "|")
	case strings.HasSuffix(line, "|"):
		// example.com| 精确匹配
		isExact = true
		domain = strings.TrimSuffix(line, "|")
		domain = strings.TrimSuffix(domain, "^")
	case strings.HasPrefix(line, "|"):
		domain = strings.TrimPrefix(line, "|")
		domain = strings.TrimSuffix(domain, "^")
	default:
		// 纯域名或包含通配符的域名
		domain = strings.TrimSuffix(line, "^")
	}

	domain = strings.TrimSpace(domain)
	if domain == "" || strings.ContainsAny(domain, "/?#") {
		return nil, false
	}

	// 6. 通配符匹配检测
	isWildcard := strings.Contains(domain, "*")
	var normDomain string
	var ok bool

	if isWildcard {
		normDomain, ok = normalizeWildcardDomain(domain)
	} else {
		normDomain, ok = normalizeDomain(domain)
	}
	if !ok {
		return nil, false
	}

	var rx *regexp.Regexp
	if isWildcard {
		rx = buildWildcardRegex(normDomain)
	}

	return &ParsedRule{
		Raw:        origLine,
		Pattern:    normDomain,
		IsAllow:    isAllow,
		Important:  important,
		IsRegex:    false,
		Regex:      rx,
		DNSType:    dnsType,
		IsWildcard: isWildcard,
		IsExact:    isExact,
		Source:     source,
	}, true
}

func isLiteralIP(val string) bool {
	return net.ParseIP(val) != nil || val == "0"
}

func isSinkholeIP(val string) bool {
	switch strings.ToLower(val) {
	case "0", "0.0.0.0", "127.0.0.1", "::", "::1":
		return true
	}
	return false
}

func normalizeDomain(domain string) (string, bool) {
	d := strings.TrimSuffix(strings.TrimSpace(strings.ToLower(domain)), ".")
	if d == "" || !strings.Contains(d, ".") {
		return "", false
	}
	// 过滤系统本地保留名称
	switch d {
	case "localhost", "local", "broadcasthost", "localdomain":
		return "", false
	}
	if net.ParseIP(d) != nil {
		return "", false
	}
	ascii, err := idna.Lookup.ToASCII(d)
	if err != nil || len(ascii) > 253 {
		return "", false
	}
	return strings.ToLower(ascii), true
}

func normalizeWildcardDomain(pattern string) (string, bool) {
	p := strings.TrimSuffix(strings.TrimSpace(strings.ToLower(pattern)), ".")
	if p == "" || p == "*" {
		return "*", true
	}
	if len(p) > 253 {
		return "", false
	}
	labels := strings.Split(p, ".")
	for _, label := range labels {
		if len(label) == 0 || len(label) > 63 {
			return "", false
		}
		for _, c := range label {
			if !(c >= 'a' && c <= 'z' || c >= '0' && c <= '9' || c == '-' || c == '*' || c == '_') {
				return "", false
			}
		}
	}
	return p, true
}

func buildWildcardRegex(pattern string) *regexp.Regexp {
	var sb strings.Builder
	sb.WriteString("^(?:.*\\.)?")
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
	return re
}

func isWebOnlyModifier(mod string) bool {
	switch mod {
	case "script", "image", "stylesheet", "font", "media", "subdocument",
		"websocket", "xhr", "xmlhttprequest", "ping", "popup", "document",
		"other", "third-party", "~third-party", "strict-third-party",
		"strict-first-party", "match-case", "all":
		return true
	}
	if strings.HasPrefix(mod, "domain=") || strings.HasPrefix(mod, "app=") ||
		strings.HasPrefix(mod, "~app=") || strings.HasPrefix(mod, "method=") ||
		strings.HasPrefix(mod, "~method=") || strings.HasPrefix(mod, "denyallow=") {
		return true
	}
	return false
}
