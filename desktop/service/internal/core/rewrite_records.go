package core

import (
	"strings"
	"sync"

	"github.com/miekg/dns"
)

// RewriteRecord 描述一条自定义重写记录，承载 RewriteRule 中 IPs/CNAME/TXT 之外的
// 记录类型（MX / SRV / NS / PTR / HTTPS / SVCB）。取值语法与 AdGuard Home 的
// $dnsrewrite 一致：
//
//	MX     "32 example.mail"                优先级 空格 交换主机
//	SRV    "10 60 8080 example.com"         优先级 权重 端口 目标
//	NS     "ns1.example.com"
//	PTR    "host.example.com"
//	HTTPS  "32 example.com alpn=h3 ipv4hint=1.2.3.4"
//	SVCB   "1 . alpn=h3,h2 port=8443"
//
// 取值语法、类型表与目标域名校验都在 Rust 内核里（rust/diting-rewrite-core），这份结构体只是
// 配置的传输形态：JSON 从这里进 IPC，也在 buildRewriteRR 里交给内核解析。
type RewriteRecord struct {
	Type  string `json:"type"`
	Value string `json:"value"`
}

// RewriteRCodeNone 表示未指定应答码覆盖，按 NOERROR 处理
const RewriteRCodeNone = ""

// rewriteRCodeNames 支持在重写规则中覆盖的应答码
var rewriteRCodeNames = map[string]int{
	"NOERROR":  dns.RcodeSuccess,
	"FORMERR":  dns.RcodeFormatError,
	"SERVFAIL": dns.RcodeServerFailure,
	"NXDOMAIN": dns.RcodeNameError,
	"NOTIMP":   dns.RcodeNotImplemented,
	"REFUSED":  dns.RcodeRefused,
}

// ParseRewriteRCode 解析应答码名称，无法识别时返回 false
func ParseRewriteRCode(name string) (int, bool) {
	rcode, ok := rewriteRCodeNames[strings.ToUpper(strings.TrimSpace(name))]
	return rcode, ok
}

var (
	rewriteRecordTypesOnce sync.Once
	rewriteRecordTypesList []string
	rewriteRecordTypesErr  error
)

// RewriteRecordTypes 返回受支持的记录类型名（升序），供前端下拉与校验提示使用。
//
// 表由内核持有（rust/diting-rewrite-core/src/record.rs），这里只缓存第一次查询：缺失的库或
// 载荷不匹配都以错误返回，不会退回一份可能已经过期的 Go 侧副本。
func RewriteRecordTypes() ([]string, error) {
	rewriteRecordTypesOnce.Do(func() {
		rewriteRecordTypesList, rewriteRecordTypesErr = fetchRewriteRecordTypes()
	})
	if rewriteRecordTypesErr != nil {
		return nil, rewriteRecordTypesErr
	}
	return rewriteRecordTypesList, nil
}
