package core

import (
	"github.com/miekg/dns"
)

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

// PadMessage 根据 RFC 7830 与 RFC 8467 将 DNS 报文填充至 blockSize 的整数倍字节
// 常用于 DoT、DoH 加密传输，抹平报文长度指纹，抵御侧信道流量分析
func PadMessage(msg *dns.Msg, blockSize int) bool {
	if msg == nil || blockSize <= 0 {
		return false
	}

	// 移除已有的 PADDING 选项以准确测量未填充长度
	RemoveEdns0Option(msg, dns.EDNS0PADDING)

	// 确保存在 OPT 记录
	optRecord := msg.IsEdns0()
	if optRecord == nil {
		optRecord = new(dns.OPT)
		optRecord.Hdr.Name = "."
		optRecord.Hdr.Rrtype = dns.TypeOPT
		optRecord.SetUDPSize(dns.DefaultMsgSize)
		msg.Extra = append(msg.Extra, optRecord)
	}

	// msg.Len() 返回报文在 wire 格式下的字节长度
	curLen := msg.Len()
	// 新增 EDNS0_PADDING 选项包含 4 字节头 (Code uint16 + Length uint16) + padLen
	// 我们期望 (curLen + 4 + padLen) % blockSize == 0
	rem := (curLen + 4) % blockSize
	padLen := 0
	if rem > 0 {
		padLen = blockSize - rem
	}

	// 报文填充后不得超过 DNS 报文最大上限 65535 字节
	if curLen+4+padLen > 65535 {
		return false
	}

	padding := make([]byte, padLen)
	padOpt := &dns.EDNS0_PADDING{Padding: padding}
	optRecord.Option = append(optRecord.Option, padOpt)
	return true
}

// StripECH 剥离报文 Answer/Extra/Ns 中所有 HTTPS/SVCB 记录的 ECH (Encrypted Client Hello) 参数
// 借鉴自 AdGuard Home 与 RFC 9460 §6.3，防止客户端利用 ECH 绕过局域网安全策略与审计
func StripECH(msg *dns.Msg) bool {
	if msg == nil {
		return false
	}
	modified := false
	stripFromValues := func(values []dns.SVCBKeyValue) ([]dns.SVCBKeyValue, bool) {
		newVals := make([]dns.SVCBKeyValue, 0, len(values))
		changed := false
		for _, kv := range values {
			if kv.Key() == dns.SVCB_ECHCONFIG {
				changed = true
				continue
			}
			if _, ok := kv.(*dns.SVCBECHConfig); ok {
				changed = true
				continue
			}
			newVals = append(newVals, kv)
		}
		return newVals, changed
	}

	for _, section := range []*[]dns.RR{&msg.Answer, &msg.Extra, &msg.Ns} {
		for _, rr := range *section {
			switch v := rr.(type) {
			case *dns.HTTPS:
				if newVals, changed := stripFromValues(v.Value); changed {
					v.Value = newVals
					modified = true
				}
			case *dns.SVCB:
				if newVals, changed := stripFromValues(v.Value); changed {
					v.Value = newVals
					modified = true
				}
			}
		}
	}
	return modified
}

// StripIPv6Hints 剥离报文 Answer/Extra/Ns 中所有 HTTPS/SVCB 记录的 IPv6 提示参数 (ipv6hint)
// 借鉴自 AdGuard Home (removeIPv6Hints)，配合 BlockIPv6 杜绝客户端利用 RFC 9460 HTTPS ipv6hint 绕过 AAAA 过滤
func StripIPv6Hints(msg *dns.Msg) bool {
	if msg == nil {
		return false
	}
	modified := false
	stripFromValues := func(values []dns.SVCBKeyValue) ([]dns.SVCBKeyValue, bool) {
		newVals := make([]dns.SVCBKeyValue, 0, len(values))
		changed := false
		for _, kv := range values {
			if kv.Key() == dns.SVCB_IPV6HINT {
				changed = true
				continue
			}
			if _, ok := kv.(*dns.SVCBIPv6Hint); ok {
				changed = true
				continue
			}
			newVals = append(newVals, kv)
		}
		return newVals, changed
	}

	for _, section := range []*[]dns.RR{&msg.Answer, &msg.Extra, &msg.Ns} {
		for _, rr := range *section {
			switch v := rr.(type) {
			case *dns.HTTPS:
				if newVals, changed := stripFromValues(v.Value); changed {
					v.Value = newVals
					modified = true
				}
			case *dns.SVCB:
				if newVals, changed := stripFromValues(v.Value); changed {
					v.Value = newVals
					modified = true
				}
			}
		}
	}
	return modified
}
