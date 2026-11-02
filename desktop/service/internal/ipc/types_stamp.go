package ipc

// ParseStampRequest 解析 sdns:// 印章请求
type ParseStampRequest struct {
	Stamp string `json:"stamp"`
}

// ParseStampResponse 印章解析结果，字段可直接回填至上游编辑表单
type ParseStampResponse struct {
	// Protocol 为映射后的上游协议（PLAIN/DOH/DOT/DOQ）
	Protocol string `json:"protocol"`
	// Server 为应填入"服务器地址"的 host[:port]
	Server string `json:"server"`
	// URL 为 DoH/DoH3 的完整解析地址，其余协议为空
	URL string `json:"url,omitempty"`
	// ProviderName 为印章声明的主机名（SNI 与证书校验名）
	ProviderName string `json:"providerName"`
	// Path 为 DoH 路径
	Path string `json:"path,omitempty"`
	// ServerAddr 为印章携带的直连 IP（可能为空）
	ServerAddr string `json:"serverAddr,omitempty"`
	// BootstrapIPs 为印章携带的引导 IP 列表
	BootstrapIPs []string `json:"bootstrapIps,omitempty"`
	// Pin 为证书固定指纹（冒号分隔大写十六进制），未携带指纹时为空
	Pin string `json:"pin,omitempty"`
	// Props 为服务方自述属性（仅供参考，不参与校验）
	Props StampProps `json:"props"`
	// ProtoName 为印章协议的展示名
	ProtoName string `json:"protoName"`
}

// StampProps 印章中的服务方非正式属性声明
type StampProps struct {
	DNSSEC   bool `json:"dnssec"`
	NoLog    bool `json:"noLog"`
	NoFilter bool `json:"noFilter"`
}
