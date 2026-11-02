package dns

import (
	"net"
	"unicode/utf8"

	"github.com/haoze-evolluling/diting/server/internal/core"
	"github.com/miekg/dns"
)

// MaxEDETextLength 限制 EDE extra text 长度，防止 UDP 报文溢出
const MaxEDETextLength = 200

// EDNS0Option 为泛型 EDNS0 选项约束接口
type EDNS0Option interface {
	*dns.EDNS0_SUBNET | *dns.EDNS0_EDE | *dns.EDNS0_LOCAL | *dns.EDNS0_NSID | *dns.EDNS0_COOKIE | *dns.EDNS0_UL | *dns.EDNS0_PADDING
	Option() uint16
}

// SetEdns0Option 向 DNS 报文的 OPT RR Extra 区域追加或覆盖指定的 EDNS0 选项
func SetEdns0Option(msg *dns.Msg, opt dns.EDNS0) bool {
	if msg == nil || opt == nil {
		return false
	}

	optRecord := msg.IsEdns0()
	if optRecord == nil {
		optRecord = new(dns.OPT)
		optRecord.Hdr.Name = "."
		optRecord.Hdr.Rrtype = dns.TypeOPT
		optRecord.SetUDPSize(dns.DefaultMsgSize)
		msg.Extra = append(msg.Extra, optRecord)
	}

	newOpts := make([]dns.EDNS0, 0, len(optRecord.Option)+1)
	for _, o := range optRecord.Option {
		if o.Option() != opt.Option() {
			newOpts = append(newOpts, o)
		}
	}
	newOpts = append(newOpts, opt)
	optRecord.Option = newOpts
	return true
}

// GetEdns0Option 从 DNS 报文的 OPT RR 中提取指定类型的 EDNS0 选项
func GetEdns0Option[T EDNS0Option](msg *dns.Msg) T {
	if msg == nil {
		return nil
	}
	optRecord := msg.IsEdns0()
	if optRecord == nil {
		return nil
	}
	for _, o := range optRecord.Option {
		if res, ok := o.(T); ok {
			return res
		}
	}
	return nil
}

// SetEDE 向 DNS 报文附加 RFC 8914 Extended DNS Error (EDE) 选项
func SetEDE(msg *dns.Msg, infoCode uint16, extraText string) bool {
	if msg == nil {
		return false
	}
	ede := &dns.EDNS0_EDE{
		InfoCode:  infoCode,
		ExtraText: TruncateText(extraText, MaxEDETextLength),
	}
	return SetEdns0Option(msg, ede)
}

// TruncateText 将字符串截断至至多 maxLen 字节，并在 UTF-8 字符边界对齐截断
func TruncateText(s string, maxLen int) string {
	if len(s) <= maxLen {
		return s
	}
	cut := maxLen
	for cut > 0 && !utf8.RuneStart(s[cut]) {
		cut--
	}
	return s[:cut]
}

// RemoveEdns0Option 从 DNS 报文的 OPT RR 中移除指定 Option 类型的选项
func RemoveEdns0Option(msg *dns.Msg, optionCode uint16) bool {
	if msg == nil {
		return false
	}
	optRecord := msg.IsEdns0()
	if optRecord == nil {
		return false
	}
	newOpts := make([]dns.EDNS0, 0, len(optRecord.Option))
	removed := false
	for _, o := range optRecord.Option {
		if o.Option() == optionCode {
			removed = true
		} else {
			newOpts = append(newOpts, o)
		}
	}
	if removed {
		optRecord.Option = newOpts
	}
	return removed
}

// StripECS 从 DNS 请求报文中剥离 EDNS Client Subnet (RFC 7871) 选项，保护客户端隐私
func StripECS(msg *dns.Msg) bool {
	return RemoveEdns0Option(msg, dns.EDNS0SUBNET)
}

// SetECS 向 DNS 报文附加指定的 EDNS Client Subnet 选项
func SetECS(msg *dns.Msg, subnetCIDR string) error {
	if msg == nil || subnetCIDR == "" {
		return nil
	}
	_, ipNet, err := net.ParseCIDR(subnetCIDR)
	if err != nil {
		return err
	}
	maskLen, _ := ipNet.Mask.Size()
	var family uint16
	var addr net.IP
	if v4 := ipNet.IP.To4(); v4 != nil {
		family = 1 // IPv4
		addr = v4
	} else {
		family = 2 // IPv6
		addr = ipNet.IP.To16()
	}
	ecs := &dns.EDNS0_SUBNET{
		Code:          dns.EDNS0SUBNET,
		Family:        family,
		SourceNetmask: uint8(maskLen),
		SourceScope:   0,
		Address:       addr,
	}
	SetEdns0Option(msg, ecs)
	return nil
}

// PadMessage 根据 RFC 7830 与 RFC 8467 将 DNS 报文填充至 blockSize 的整数倍字节
// 常用于 DoT、DoH 加密传输，抹平报文长度指纹，抵御侧信道流量分析
func PadMessage(msg *dns.Msg, blockSize int) bool {
	return core.PadMessage(msg, blockSize)
}

// StripECH 剥离报文 Answer/Extra/Ns 中所有 HTTPS/SVCB 记录的 ECH (Encrypted Client Hello) 参数
// 借鉴自 AdGuard Home 与 RFC 9460 §6.3，防止客户端利用 ECH 绕过局域网安全策略与审计
func StripECH(msg *dns.Msg) bool {
	return core.StripECH(msg)
}

// StripIPv6Hints 剥离报文 Answer/Extra/Ns 中所有 HTTPS/SVCB 记录的 IPv6 提示参数 (ipv6hint)
// 借鉴自 AdGuard Home，配合 BlockIPv6 杜绝客户端利用 RFC 9460 HTTPS ipv6hint 绕过 AAAA 过滤
func StripIPv6Hints(msg *dns.Msg) bool {
	return core.StripIPv6Hints(msg)
}
