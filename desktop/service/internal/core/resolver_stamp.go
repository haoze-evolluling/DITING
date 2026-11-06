package core

import (
	"fmt"
	"strings"
)

// DNS Stamps（sdns://）的取值类型。
//
// 解析、地址校验与派生字符串（URL() / Server()）都由 Rust 内核（rust/diting-stamp-core）
// 完成，这里只保留调用方需要的字段与枚举，不再有第二套解析逻辑可跑：内核缺失、ABI 不符或
// 印章被拒时 ParseServerStamp 直接返回错误，上层据此判定上游配置失败。

// StampProtoType 印章协议标识，取值与印章首字节一致（Rust 侧 `stamp::Proto::code`）。
type StampProtoType uint8

const (
	StampProtoPlain         StampProtoType = 0x00
	StampProtoDNSCrypt      StampProtoType = 0x01
	StampProtoDoH           StampProtoType = 0x02
	StampProtoTLS           StampProtoType = 0x03
	StampProtoDoQ           StampProtoType = 0x04
	StampProtoODoHTarget    StampProtoType = 0x05
	StampProtoDNSCryptRelay StampProtoType = 0x81
	StampProtoODoHRelay     StampProtoType = 0x85
)

func (t StampProtoType) String() string {
	switch t {
	case StampProtoPlain:
		return "Plain"
	case StampProtoDNSCrypt:
		return "DNSCrypt"
	case StampProtoDoH:
		return "DoH"
	case StampProtoTLS:
		return "TLS"
	case StampProtoDoQ:
		return "DoQ"
	case StampProtoODoHTarget:
		return "oDoH target"
	case StampProtoDNSCryptRelay:
		return "DNSCrypt relay"
	case StampProtoODoHRelay:
		return "oDoH relay"
	default:
		return fmt.Sprintf("unknown(0x%02x)", uint8(t))
	}
}

// StampProperties 印章中的服务方非正式属性位图（仅为声明，不做校验）
type StampProperties uint64

const (
	StampPropDNSSEC   StampProperties = 1 << 0
	StampPropNoLog    StampProperties = 1 << 1
	StampPropNoFilter StampProperties = 1 << 2
)

// Has 判断属性位是否置位
func (p StampProperties) Has(flag StampProperties) bool { return p&flag != 0 }

// ServerStamp 解析后的 DNS 印章
type ServerStamp struct {
	Proto         StampProtoType
	Props         StampProperties
	ServerAddrStr string   // 直连地址，可为空（表示需要自行解析主机名）
	Hashes        [][]byte // SHA-256(RawTBSCertificate) 证书指纹列表
	ProviderName  string   // 上游主机名（DoH/DoT/DoQ 的 SNI 与校验名）
	Path          string   // DoH 路径
	BootstrapIPs  []string // 印章内附带的引导 IP

	// 以下字段由内核在解析时一并算好，Go 侧只读：
	// 端口归属、默认端口省略、DoH 默认路径这类规则只有 Rust 一份实现。
	derivedURL    string
	derivedServer string
	protocol      DNSProtocol
}

// IsSupported 判断本项目的上游实现是否支持该印章协议
func (s *ServerStamp) IsSupported() bool { return s.protocol != "" }

// Protocol 把印章协议映射为上游协议枚举
func (s *ServerStamp) Protocol() (DNSProtocol, error) {
	if s.protocol == "" {
		return "", fmt.Errorf("stamp protocol %s is not supported by this resolver", s.Proto)
	}
	return s.protocol, nil
}

// URL 为 HTTPS 语义的印章还原出完整 DoH URL
func (s *ServerStamp) URL() string { return s.derivedURL }

// Server 返回应填入 ProviderConfig.Server 的地址。
//
// 与 DNS Stamps 规范一致：等于协议默认端口的端口会被省略，
// 因为 URL 与 TLS 默认端口本身已能表达该语义。
func (s *ServerStamp) Server() string { return s.derivedServer }

// Pins 把印章指纹转为证书固定列表
func (s *ServerStamp) Pins() ([]*CertPin, error) {
	pins := make([]*CertPin, 0, len(s.Hashes))
	for _, h := range s.Hashes {
		pin, err := CertPinFromRaw(h)
		if err != nil {
			return nil, err
		}
		pins = append(pins, pin)
	}
	return pins, nil
}

// ParseServerStamp 解析 sdns:// 印章字符串。
//
// 载荷解码失败（布局版本或长度不符）同样报错：那说明 .so/.dll 与 Go 侧不是同一次构建，
// 静默降级只会让问题在下一个字段上换个样子出现。
func ParseServerStamp(stampStr string) (*ServerStamp, error) {
	payload, err := parseStampNative(stampStr)
	if err != nil {
		return nil, err
	}
	return decodeStampPayload(payload)
}

// splitStampPort 按最后一处冒号切分主机与端口，正确处理 IPv6 字面量。
//
// 印章解析已整体搬进 Rust（同一套规则在那里实现），这个函数留给按主机名查证书指纹的
// `pinHost`：它处理的是普通 host:port 字符串，与印章无关。
func splitStampPort(s string) (host, port string) {
	colIndex := strings.LastIndex(s, ":")
	bracketIndex := strings.LastIndex(s, "]")
	if colIndex < bracketIndex || colIndex < 0 {
		return s, ""
	}
	return s[:colIndex], s[colIndex+1:]
}
