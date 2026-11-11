package core

// rule_parser.go is the Go side of rule parsing.
//
// The parsing itself lives in Rust (`rust/diting-filter-core/src/parse.rs`, driven through
// parse_native.go): lines, hosts forms, `@@` exceptions, modifiers, `$dnstype`,
// `$denyallow=`/`$to=`, the AdGuard domain forms, wildcards and IDNA normalization. What stays here
// is the part that needs Go:
//
//   - `buildWildcardRegex`, because the wildcard pattern source the matcher receives is derived
//     here (`filter_native.go` hands `Regex.String()` over, so both engines see one source);
//   - `regexp.Compile` for `/regex/` rules, whose compiled form Go itself needs.
//
// The `$dnsrewrite` value grammar is not here either: the parser hands the raw text to the rewrite
// kernel (`rewrite_action_native.go`), which validates it through the same record builder a
// configured rewrite rule uses.
//
// A rule the kernel accepts can still be dropped here — an uncompilable regex or an unparsable
// rewrite value — exactly like the Go parser dropped it before the move.

import (
	"io"
	"regexp"
	"strings"
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

// ParseRules 从 io.Reader 读取并解析全部规则。
//
// 一次调用把整份列表交给 Rust：解析在那边按行进行，返回的规则保持列表顺序。解析器缺失、
// ABI 不符或载荷被拒都是错误，调用方（规则引擎 / 订阅更新）据此让本次加载失败。
func ParseRules(r io.Reader, source string) ([]*ParsedRule, error) {
	data, err := io.ReadAll(r)
	if err != nil {
		return nil, err
	}
	lines, err := parseRulesText(string(data))
	if err != nil {
		return nil, err
	}

	rules := make([]*ParsedRule, 0, len(lines))
	for _, line := range lines {
		if rule, ok := line.toParsedRule(source); ok && rule != nil {
			rules = append(rules, rule)
		}
	}
	return rules, nil
}

// ParseRuleLine 解析单行规则。
//
// 没有 error 返回值：解析器不可用时记日志并丢弃该行，随后构建规则索引会因为同一个内核缺失
// 而失败，不会以「规则静默变少」的状态跑起来。
func ParseRuleLine(line, source string) (*ParsedRule, bool) {
	parsed, err := parseRuleText(line)
	if err != nil {
		logParseFailure("单行", err)
		return nil, false
	}
	if parsed == nil {
		return nil, false
	}
	return parsed.toParsedRule(source)
}

// buildWildcardRegex 由通配模式推导匹配正则。
//
// `(?i)^(?:.*\.)?` + 逐字符 QuoteMeta（`*` 转 `.*`）+ `$`：子域可选、大小写不敏感。
// 迁移后这个源仍是唯一一份——它经 `filter_native.go` 一起交给 Rust 内核编译。
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
