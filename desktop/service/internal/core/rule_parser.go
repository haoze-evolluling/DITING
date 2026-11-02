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

	// DenyAllow 目标域排除后缀（$denyallow=，小写去点）。
	// 借鉴自 AdGuard Home urlfilter 修饰符：命中该后缀集合的查询不受本条规则约束。
	DenyAllow []string
	// To 目标域排除后缀（$to=，小写去点）。
	// 在 DNS 层 $to= 与 $denyallow= 语义等价（均针对查询目标域），统一作为排除集合处理。
	To []string

	// Rewrite 为 $dnsrewrite= 修饰符的解析结果；为 nil 表示本条规则不参与重写。
	//
	// 例外规则上的 Rewrite 表示「取消」而非「改写」：裸形式取消该域名的全部重写，
	// 带取值的形式只取消取值相同的那一条。
	Rewrite *RewriteAction
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

// isCosmeticOrScriptRule 判断一行是否为 AdGuard 的元素隐藏 / 程序规则。
//
// 这些规则只作用于页面渲染，与 DNS 解析无关；不识别它们就会把
// `域名##选择器` 当成域名黑名单。
func isCosmeticOrScriptRule(line string) bool {
	return strings.Contains(line, "##") ||
		strings.Contains(line, "#@#") ||
		strings.Contains(line, "#?#") ||
		strings.Contains(line, "#@?#") ||
		strings.Contains(line, "#$#") ||
		strings.Contains(line, "#@$#") ||
		strings.Contains(line, "#%#") ||
		strings.Contains(line, "#@%#")
}

// ParseRuleLine 解析单行规则
func ParseRuleLine(line, source string) (*ParsedRule, bool) {
	origLine := line
	line = strings.TrimSpace(strings.TrimPrefix(line, "\ufeff"))

	// 忽略空行、整行注释与列表头信息
	if line == "" || line[0] == '!' || line[0] == '#' || line[0] == '[' {
		return nil, false
	}

	// 网页/程序过滤规则 (##, #@#, #?#) 必须在本行任何 "#" 截断之前判定：
	// AdGuard 语法里注释只在行首，中缀 "#" 是元素隐藏规则的分隔标记。
	// 顺序颠倒后 `youtube.com##.video-ads` 会被截成 `youtube.com`，
	// 降级成一条整域拦截规则——订阅含元素隐藏规则的列表即整站被拦。
	if isCosmeticOrScriptRule(line) {
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

	// 2. 检测例外规则 (@@ 开头)
	isAllow := false
	if strings.HasPrefix(line, "@@") {
		isAllow = true
		line = strings.TrimPrefix(line, "@@")
	}

	// 3. 处理修饰符 ($ 开头)
	important := false
	var dnsType uint16 = 0
	var denyAllow []string
	var toDomains []string
	var rewrite *RewriteAction
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
		modifiers := splitModifiers(modPart)
		for _, raw := range modifiers {
			// 关键字与域名均大小写不敏感，但记录取值（TXT、CNAME 目标）保留原文，
			// 因此只在判定分支上用小写形式，取值一律回传原文
			mod := strings.TrimSpace(strings.ToLower(raw))
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
			} else if strings.HasPrefix(mod, "denyallow=") {
				denyAllow = parseModifierDomains(strings.TrimPrefix(mod, "denyallow="))
			} else if strings.HasPrefix(mod, "to=") {
				toDomains = parseModifierDomains(strings.TrimPrefix(mod, "to="))
			} else if mod == "dnsrewrite" || strings.HasPrefix(mod, "dnsrewrite=") {
				// 取值区分大小写，必须从原文中截取
				action, err := parseDNSRewriteModifier(dnsRewriteValue(raw))
				if err != nil {
					// 无法解析的重写规则直接丢弃：保留下来只会变成一条语义不明的拦截规则
					return nil, false
				}
				rewrite = action
			} else if strings.HasPrefix(mod, "~denyallow=") || strings.HasPrefix(mod, "~to=") {
				// 取反形式在 DNS 层无可靠等价语义，安全忽略该修饰符（保留整条规则）
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
			DenyAllow: denyAllow,
			To:        toDomains,
			Rewrite:   rewrite,
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
		DenyAllow:  denyAllow,
		To:         toDomains,
		Rewrite:    rewrite,
	}, true
}

// splitModifiers 按逗号拆分修饰符列表，但保留 $dnsrewrite 取值内部的逗号。
//
// dnsrewrite 的取值本身可能含逗号（HTTPS / SVCB 的 alpn=h3,h2），
// 直接按逗号切分会把它拦腰截断成一条语法错误的取值。定位到 dnsrewrite
// 之后，只有看起来像新修饰符的片段才会开始下一项，其余一律并入当前取值。
func splitModifiers(modPart string) []string {
	head, tail, ok := cutRewriteModifier(modPart)
	if !ok {
		return strings.Split(modPart, ",")
	}

	merged := make([]string, 0, 4)
	merged = append(merged, head...)

	segments := strings.Split(tail, ",")
	current := segments[0]
	for _, seg := range segments[1:] {
		if looksLikeModifier(seg) {
			merged = append(merged, current)
			current = seg
			continue
		}
		current += "," + seg
	}
	return append(merged, current)
}

// cutRewriteModifier 以 dnsrewrite 修饰符为界把列表切成前后两段。
//
// 未出现 dnsrewrite 时返回 ok=false，调用方按普通逗号拆分即可。
func cutRewriteModifier(modPart string) (head []string, tail string, ok bool) {
	offset := 0
	for offset <= len(modPart) {
		next := strings.IndexByte(modPart[offset:], ',')
		end := len(modPart)
		if next >= 0 {
			end = offset + next
		}

		seg := strings.TrimSpace(strings.ToLower(modPart[offset:end]))
		if seg == "dnsrewrite" || strings.HasPrefix(seg, "dnsrewrite=") {
			prefix := strings.Trim(strings.TrimSpace(modPart[:offset]), ",")
			if prefix != "" {
				head = strings.Split(prefix, ",")
			}
			return head, modPart[offset:], true
		}

		if next < 0 {
			return nil, "", false
		}
		offset = end + 1
	}
	return nil, "", false
}

// looksLikeModifier 判断片段是否为修饰符关键字（用于切分 dnsrewrite 取值）
func looksLikeModifier(segment string) bool {
	mod := strings.TrimSpace(strings.ToLower(segment))
	if mod == "" {
		return true
	}
	switch {
	case mod == "important", mod == "badfilter", mod == "dnsrewrite":
		return true
	case strings.HasPrefix(mod, "dnsrewrite="),
		strings.HasPrefix(mod, "dnstype="),
		strings.HasPrefix(mod, "denyallow="),
		strings.HasPrefix(mod, "to="),
		strings.HasPrefix(mod, "~denyallow="),
		strings.HasPrefix(mod, "~to="):
		return true
	}
	return isWebOnlyModifier(mod)
}

// dnsRewriteValue 从原文修饰符中截取 dnsrewrite 的取值。
//
// 取值本身区分大小写（TXT 文本、CNAME 目标），因此不能复用已小写化的形式。
// 裸形式（$dnsrewrite 后无等号）返回空串。
func dnsRewriteValue(rawModifier string) string {
	if idx := strings.IndexByte(rawModifier, '='); idx >= 0 {
		return rawModifier[idx+1:]
	}
	return ""
}

// parseModifierDomains 解析修饰符中以 "|" 分隔的域名列表。
//
// 借鉴自 AdGuard Home urlfilter 的 $denyallow=/$to= 语义：条目为小写去点的域名后缀；
// 以 "~" 前缀的取反条目在 DNS 层无可靠等价语义，直接跳过（不丢弃整条规则）。
func parseModifierDomains(raw string) []string {
	if raw == "" {
		return nil
	}
	var out []string
	for _, part := range strings.Split(raw, "|") {
		part = strings.ToLower(strings.TrimSpace(part))
		if part == "" || strings.HasPrefix(part, "~") {
			continue
		}
		part = strings.TrimPrefix(part, "*")
		part = strings.Trim(part, ".")
		part = strings.TrimSuffix(part, "^")
		if part == "" || strings.ContainsAny(part, "/?#*") {
			continue
		}
		out = append(out, part)
	}
	if len(out) == 0 {
		return nil
	}
	return out
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
	// 注意：denyallow=/to= 已在修饰符循环中单独解析为排除集合，不再视为浏览器专有修饰符丢弃整条规则。
	if strings.HasPrefix(mod, "domain=") || strings.HasPrefix(mod, "app=") ||
		strings.HasPrefix(mod, "~app=") || strings.HasPrefix(mod, "method=") ||
		strings.HasPrefix(mod, "~method=") {
		return true
	}
	return false
}
