package ipc

import "github.com/haoze-evolluling/diting/server/internal/core"

// 证书导入的两种输入形态
const (
	// CertImportModePEM 一对 PEM 文本
	CertImportModePEM = "pem"
	// CertImportModePKCS12 一个 base64 编码的 PKCS#12 容器
	CertImportModePKCS12 = "pkcs12"
)

// EncryptedDNSStatusResponse 加密 DNS 服务的配置、证书与监听状态
type EncryptedDNSStatusResponse struct {
	Config core.EncryptedDNSConfig `json:"config"`
	// Cert 服务端证书摘要；不含私钥材料
	Cert core.CertInfo `json:"cert"`
	// CertDir 证书落盘目录，供界面提示自签证书的位置
	CertDir string `json:"certDir"`
	// Defaults 约定的默认端口与路径，供界面在重置时回填
	DefaultDoTPort int    `json:"defaultDotPort"`
	DefaultDoHPort int    `json:"defaultDohPort"`
	DefaultDoQPort int    `json:"defaultDoqPort"`
	DefaultDoHPath string `json:"defaultDohPath"`
	// DoTListen 实际生效的 DoT 监听地址；未在监听时为空串。
	// 与配置里的端口分开：配置写着 853 不代表真的绑上了，
	// 可能证书载入失败，也可能端口被别人占了。
	DoTListen string `json:"dotListen"`
	// DoHListen 实际生效的 DoH 监听地址；未在监听时为空串
	DoHListen string `json:"dohListen"`
	// DoQListen 实际生效的 DoQ 监听地址；未在监听时为空串
	DoQListen string `json:"doqListen"`
	// DoHURLs 可直接交给终端使用的 DoH 地址，含服务器名与各网卡地址
	DoHURLs []string `json:"dohUrls"`
	// UnrestrictedTrust 可信代理列表里存在 0.0.0.0/0 或 ::/0；
	// 界面需据此给出「任何人都能伪造来源」的显著警告
	UnrestrictedTrust bool `json:"unrestrictedTrust"`
	// CertExpiresSoon 自签证书已进入续签窗口（30 天内到期）
	CertExpiresSoon bool `json:"certExpiresSoon"`
	// CertExpired 自签证书已过期：客户端握手必然失败，界面必须显式提示
	CertExpired bool `json:"certExpired"`
}

// ConfigureEncryptedDNSRequest 更新加密 DNS 配置。
//
// 字段均为可选：省略表示沿用当前值。数组/结构体字段传指针而非值，
// 是为了让「关闭」与「未表态」在传输层就分得开——布尔零值承担不了
// 这个区分，而界面上的开关恰恰大量使用它。
type ConfigureEncryptedDNSRequest struct {
	Enabled       *bool            `json:"enabled,omitempty"`
	DoTEnabled    *bool            `json:"dotEnabled,omitempty"`
	DoHEnabled    *bool            `json:"dohEnabled,omitempty"`
	DoQEnabled    *bool            `json:"doqEnabled,omitempty"`
	DDREnabled    *bool            `json:"ddrEnabled,omitempty"`
	ListenAddress *string          `json:"listenAddress,omitempty"`
	DoTPort       *int             `json:"dotPort,omitempty"`
	DoHPort       *int             `json:"dohPort,omitempty"`
	DoQPort       *int             `json:"doqPort,omitempty"`
	DoHPath       *string          `json:"dohPath,omitempty"`
	ServerName    *string          `json:"serverName,omitempty"`
	Cert          *core.CertConfig `json:"cert,omitempty"`
}

// GenerateCertRequest 生成自签证书的参数。
//
// 与 CertConfig 分开：那些字段是「配置里长期存着的东西」，而这里是
// 「这一次生成用这些参数」。生成完成即结束，不该混进配置的语义里。
// 证书生成是覆盖性动作，故单列一个接口而不是塞进 configure。
type GenerateCertRequest struct {
	KeyType     string   `json:"keyType,omitempty"`
	CommonName  string   `json:"commonName,omitempty"`
	DNSNames    []string `json:"dnsNames,omitempty"`
	IPAddresses []string `json:"ipAddresses,omitempty"`
	ValidDays   int      `json:"validDays,omitempty"`
	// Force 覆盖已存在的证书，会让已信任它的客户端全部失效
	Force bool `json:"force,omitempty"`
}

// ImportCertRequest 导入服务端证书。
//
// 两种来源共用一个接口：它们对调用方的意义相同（换一张证书），
// 差别只在字节怎么装。分开两个接口会让界面不得不在两种形态间做选择，
// 而用户手里是什么文件自己最清楚。
type ImportCertRequest struct {
	// Mode 取值见 CertImportMode* 常量
	Mode string `json:"mode"`
	// CertPEM / KeyPEM 一对 PEM 文本（Mode 为 pem 时使用）
	CertPEM string `json:"certPem,omitempty"`
	KeyPEM  string `json:"keyPem,omitempty"`
	// Data PKCS#12 容器的 base64 编码（Mode 为 pkcs12 时使用）；
	// 用 base64 而非裸串是因为 JSON 承载二进制并不安全
	Data string `json:"data,omitempty"`
	// Password PKCS#12 口令
	Password string `json:"password,omitempty"`
}
