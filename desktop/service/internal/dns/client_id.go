package dns

import (
	"fmt"
	"strings"
)

// 单个 DNS 名字标签的长度上限（RFC 1035）
const maxClientIDLen = 63

// ValidateClientID 校验 ClientID 是否为合法的单个主机名标签。
//
// 只接受字母数字与内部连字符：ClientID 会以子域形式出现在
// <id>.<服务器名> 与 DoH 的 <路径>/<id> 中，允许点号会让它越级变成另一个
// 域名，允许别的字符则会让两种入口的解析结果对不上。
func ValidateClientID(id string) error {
	label := strings.TrimSpace(id)
	if label == "" {
		return fmt.Errorf("ClientID 不能为空")
	}
	if len(label) > maxClientIDLen {
		return fmt.Errorf("ClientID 长度 %d 超过上限 %d", len(label), maxClientIDLen)
	}
	for i := 0; i < len(label); i++ {
		c := label[i]
		alnum := (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9')
		if alnum {
			continue
		}
		// 连字符只能出现在中间，这是主机名标签的通行约定
		if c == '-' && i > 0 && i < len(label)-1 {
			continue
		}
		return fmt.Errorf("ClientID %q 含非法字符", label)
	}
	return nil
}

// ClientIDFromServerName 从客户端 SNI 中提取 ClientID。
//
// hostSNI 是本机认定的服务器名，cliSNI 是客户端实际发来的名字：
//
//	cliSNI == hostSNI                    → 未指定 ClientID，返回空串
//	cliSNI 是 hostSNI 的直接子域          → 取最外层那一级标签作为 ClientID
//	其余（含大小写不一致、更深的子域）    → 不是 ClientID
//
// 只认「直接子域」而不是任意后代，是为了让 a.b.dns.lan 不至于被读成
// ClientID "a.b"：那个名字说不清客户端想表达什么，静默取一层反而会把它
// 归到一个它从未声明过的身份上。大小写不敏感，因为服务器名由用户填写，
// 而 DNS 客户端把名字小写化是常态。
func ClientIDFromServerName(hostSNI, cliSNI string) string {
	host := normalizeServerName(hostSNI)
	client := normalizeServerName(cliSNI)
	if host == "" || client == "" || client == host {
		return ""
	}

	// IsImmediateSubdomain：恰好深一层，且以 ".<host>" 结尾
	tail := "." + host
	if !strings.HasSuffix(client, tail) {
		return ""
	}
	prefix := client[:len(client)-len(tail)]
	if prefix == "" || strings.Contains(prefix, ".") {
		return ""
	}
	if err := ValidateClientID(prefix); err != nil {
		return ""
	}
	return strings.ToLower(prefix)
}

// normalizeServerName 去掉末尾的根标签并统一为小写。
//
// SNI 不带末尾点，而配置里手写的服务器名常带上，两者必须先对齐再比较；
// 否则一个多余的 "." 就会让 ClientID 识别整个失效。
func normalizeServerName(name string) string {
	return strings.ToLower(strings.TrimSuffix(strings.TrimSpace(name), "."))
}
