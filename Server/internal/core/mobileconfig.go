package core

import (
	"crypto/rand"
	"encoding/hex"
	"fmt"
	"strings"
)

// Apple 配置描述文件（.mobileconfig）里与本功能有关的常量。
const (
	// MobileConfigPayloadType 是 DNS 设置载荷的类型标识
	MobileConfigPayloadType = "com.apple.dnsSettings.managed"
	// MobileConfigContentType 是该文件的媒体类型
	MobileConfigContentType = "application/x-apple-aspen-config"
	// MobileConfigFileExt 是设备认可的文件扩展名
	MobileConfigFileExt = ".mobileconfig"

	// Apple DNSProtocol 的两种加密取值。明文（Cleartext）不在这里支持：
	// 这个描述文件的意义就是让终端改用加密解析。
	MobileConfigProtocolHTTPS = "HTTPS"
	MobileConfigProtocolTLS   = "TLS"
)

// MobileConfigOptions 生成描述文件所需的全部信息。
type MobileConfigOptions struct {
	// ServerName 客户端连接用的服务器名，会成为证书校验的基准
	ServerName string
	// ServerURL 为 DoH 的完整地址；HTTPS 模式下必填
	ServerURL string
	// Protocol 取值见 MobileConfigProtocol* 常量
	Protocol string
	// DisplayName 设备「设置」里显示的名字
	DisplayName string
	// Description 描述文件说明
	Description string
	// UUID 配置描述文件的标识，需在多次下载间保持不变；
	// 为空时现场生成一个
	UUID string
}

// BuildMobileConfig 生成一份未签名的 Apple 配置描述文件。
//
// 未签名意味着 iOS/macOS 会把它标记为「未验证」，用户需要在设置里
// 手动确认安装——这正是自签证书场景下的预期行为，签名用的企业证书
// 本就不该由本项目代持。
func BuildMobileConfig(opts MobileConfigOptions) ([]byte, error) {
	serverName := strings.TrimSpace(opts.ServerName)
	if serverName == "" {
		return nil, fmt.Errorf("缺少服务器名：描述文件需要它作为证书校验基准")
	}

	protocol := strings.ToUpper(strings.TrimSpace(opts.Protocol))
	if protocol == "" {
		protocol = MobileConfigProtocolHTTPS
	}
	if protocol != MobileConfigProtocolHTTPS && protocol != MobileConfigProtocolTLS {
		return nil, fmt.Errorf("不支持的协议 %q", opts.Protocol)
	}

	// 每一项都必须经 plistString 包成 <string>：直接放裸文本会生成
	// 一份语法上就解析不了的 plist，设备会当作损坏文件拒绝导入
	dnsSettings := []plistEntry{{Key: "DNSProtocol", Value: plistString(protocol)}}
	switch protocol {
	case MobileConfigProtocolHTTPS:
		url := strings.TrimSpace(opts.ServerURL)
		if url == "" {
			return nil, fmt.Errorf("DoH 模式需要提供完整地址")
		}
		// ServerURL 必须是绝对 URL，否则设备会静默忽略整条载荷
		if !strings.HasPrefix(url, "https://") {
			return nil, fmt.Errorf("DoH 地址必须以 https:// 开头，实得 %q", url)
		}
		dnsSettings = append(dnsSettings,
			plistEntry{Key: "ServerURL", Value: plistString(url)},
			// ServerName 在这里是证书校验用的主机名，与 URL 里的主机
			// 必须一致，否则设备会因名称不符拒绝连接
			plistEntry{Key: "ServerName", Value: plistString(serverName)},
		)
	default:
		dnsSettings = append(dnsSettings, plistEntry{Key: "ServerName", Value: plistString(serverName)})
	}

	uuid := strings.TrimSpace(opts.UUID)
	if uuid == "" {
		generated, err := NewUUID()
		if err != nil {
			return nil, err
		}
		uuid = generated
	}

	displayName := strings.TrimSpace(opts.DisplayName)
	if displayName == "" {
		displayName = "DITING 加密 DNS"
	}
	description := strings.TrimSpace(opts.Description)
	if description == "" {
		description = "由 DITING 提供的加密 DNS 解析配置"
	}

	// 载荷标识与 UUID 共用同一个值：一个描述文件里只有一条载荷，
	// 再造一个标识只会让排查问题时多一个对不上的字符串
	payloadID := "com.diting.encrypted-dns." + uuid

	payload := plistDict([]plistEntry{
		{Key: "PayloadType", Value: plistString(MobileConfigPayloadType)},
		{Key: "PayloadIdentifier", Value: plistString(payloadID + ".dns")},
		{Key: "PayloadUUID", Value: plistString(uuid)},
		{Key: "PayloadDisplayName", Value: plistString(displayName)},
		{Key: "PayloadVersion", Value: plistInteger(1)},
		{Key: "DNSSettings", Value: plistDict(dnsSettings)},
	})

	root := plistDict([]plistEntry{
		{Key: "PayloadContent", Value: plistArray(payload)},
		{Key: "PayloadType", Value: plistString("Configuration")},
		{Key: "PayloadIdentifier", Value: plistString(payloadID)},
		{Key: "PayloadUUID", Value: plistString(uuid)},
		{Key: "PayloadDisplayName", Value: plistString(displayName)},
		{Key: "PayloadDescription", Value: plistString(description)},
		{Key: "PayloadVersion", Value: plistInteger(1)},
	})

	var sb strings.Builder
	sb.WriteString(`<?xml version="1.0" encoding="UTF-8"?>` + "\n")
	sb.WriteString(`<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" ` +
		`"http://www.apple.com/DTDs/PropertyList-1.0.dtd">` + "\n")
	sb.WriteString(`<plist version="1.0">` + "\n")
	sb.WriteString(root)
	sb.WriteString("\n</plist>\n")

	return []byte(sb.String()), nil
}

// NewUUID 生成一个随机的 v4 UUID（小写、带连字符）。
//
// 不引入第三方 UUID 库：这里只需要「每次都不一样且格式合法」，
// 而 crypto/rand 加上自定义版本位就够了——多一个依赖只为一处调用
// 不划算。
func NewUUID() (string, error) {
	var b [16]byte
	if _, err := rand.Read(b[:]); err != nil {
		return "", fmt.Errorf("生成 UUID 失败: %w", err)
	}
	// 版本 4（随机）与 RFC 4122 变体位
	b[6] = (b[6] & 0x0f) | 0x40
	b[8] = (b[8] & 0x3f) | 0x80

	raw := hex.EncodeToString(b[:])
	return raw[0:8] + "-" + raw[8:12] + "-" + raw[12:16] + "-" +
		raw[16:20] + "-" + raw[20:32], nil
}

// EnsureEncryptedUUID 返回配置里已有的 UUID，没有就生成一个并写回。
//
// UUID 必须在多次下载之间保持不变：同一个 UUID 换内容会被设备当成
// 「更新已有描述文件」，而每次下载都换一个 UUID 会让设备里堆满
// 一份份外观相同、实际互相冲突的配置。
func EnsureEncryptedUUID(cfg *EncryptedDNSConfig) (string, error) {
	if cfg == nil {
		return "", fmt.Errorf("配置为空")
	}
	if id := strings.TrimSpace(cfg.UUID); id != "" {
		return id, nil
	}
	id, err := NewUUID()
	if err != nil {
		return "", err
	}
	cfg.UUID = id
	return id, nil
}
