package core

import (
	"encoding/base64"
	"encoding/binary"
	"errors"
	"fmt"
	"net"
	"strconv"
	"strings"
)

// DNS Stamps（sdns://）规范实现。
//
// 逐字节解析印章二进制，与 dnscrypt-proxy 的 go-dnsstamps 保持一致：
//   - 首字节为协议标识
//   - 紧随其后是 8 字节小端 props 位图
//   - 字符串字段统一为 lp-string（1 字节长度 + 内容）
//   - 指纹与引导 IP 使用 VLP（最高位 0x80 表示"还有下一项"）
//
// DNSCrypt 与 ODoH 印章在本项目中暂不支持，解析时会给出明确错误而非静默降级。

const (
	stampScheme = "sdns://"

	// 印章内字符串字段的默认端口
	stampDefaultHTTPSPort = 443
	stampDefaultTLSPort   = 853
	stampDefaultDNSPort   = 53

	stampHashLen = 32
)

// StampProtoType 印章协议标识
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
}

// IsSupported 判断本项目的上游实现是否支持该印章协议
func (s *ServerStamp) IsSupported() bool {
	switch s.Proto {
	case StampProtoPlain, StampProtoDoH, StampProtoTLS, StampProtoDoQ:
		return true
	default:
		return false
	}
}

// Protocol 把印章协议映射为上游协议枚举
func (s *ServerStamp) Protocol() (DNSProtocol, error) {
	switch s.Proto {
	case StampProtoPlain:
		return ProtocolPlain, nil
	case StampProtoDoH:
		return ProtocolDoH, nil
	case StampProtoTLS:
		return ProtocolDoT, nil
	case StampProtoDoQ:
		return ProtocolDoQ, nil
	default:
		return "", fmt.Errorf("stamp protocol %s is not supported by this resolver", s.Proto)
	}
}

// URL 为 HTTPS 语义的印章还原出完整 DoH URL
func (s *ServerStamp) URL() string {
	if s.Proto != StampProtoDoH {
		return ""
	}
	path := s.Path
	if path == "" {
		path = "/dns-query"
	}
	if !strings.HasPrefix(path, "/") {
		path = "/" + path
	}
	return "https://" + s.hostWithPort(stampDefaultHTTPSPort) + path
}

// Server 返回应填入 ProviderConfig.Server 的地址。
//
// 与 DNS Stamps 规范一致：等于协议默认端口的端口会被省略，
// 因为 URL 与 TLS 默认端口本身已能表达该语义。
func (s *ServerStamp) Server() string {
	host := s.ProviderName
	if host == "" {
		return s.ServerAddrStr
	}
	switch s.Proto {
	case StampProtoDoH:
		return s.hostWithPort(stampDefaultHTTPSPort)
	case StampProtoTLS, StampProtoDoQ:
		return s.hostWithPort(stampDefaultTLSPort)
	default:
		return s.hostWithPort(stampDefaultDNSPort)
	}
}

// hostWithPort 返回带端口的校验主机名；端口等于该协议默认值时省略端口。
//
// 端口来源优先级：印章主机名自带 > 直连地址 > 协议默认值。
func (s *ServerStamp) hostWithPort(defaultPort int) string {
	host, port := splitStampPort(s.ProviderName)
	if port == "" {
		port = s.portFromAddr()
	}
	host = strings.Trim(host, "[]")
	if port == "" || port == strconv.Itoa(defaultPort) {
		return host
	}
	return net.JoinHostPort(host, port)
}

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

// portFromAddr 从直连地址中取出端口（无端口返回空串）
func (s *ServerStamp) portFromAddr() string {
	_, port := splitStampPort(s.ServerAddrStr)
	return port
}

// ParseServerStamp 解析 sdns:// 印章字符串
func ParseServerStamp(stampStr string) (*ServerStamp, error) {
	s := strings.TrimSpace(stampStr)
	if s == "" {
		return nil, errors.New("empty stamp")
	}
	if !strings.HasPrefix(s, "sdns:") {
		return nil, errors.New(`stamps are expected to start with "sdns:"`)
	}

	encoded := strings.TrimPrefix(strings.TrimPrefix(s, "sdns:"), "//")
	bin, err := base64.RawURLEncoding.Strict().DecodeString(encoded)
	if err != nil {
		return nil, fmt.Errorf("decode stamp base64: %w", err)
	}
	if len(bin) < 1 {
		return nil, errors.New("stamp is too short")
	}

	switch StampProtoType(bin[0]) {
	case StampProtoPlain:
		return parsePlainStamp(bin)
	case StampProtoDoH:
		return parseDoHStamp(bin)
	case StampProtoTLS:
		return parseDoTStamp(bin)
	case StampProtoDoQ:
		return parseDoQStamp(bin)
	case StampProtoDNSCrypt, StampProtoDNSCryptRelay:
		return nil, errors.New("DNSCrypt 印章暂不支持，请改用 DoH / DoT / DoQ 印章")
	case StampProtoODoHTarget, StampProtoODoHRelay:
		return nil, errors.New("oDoH 印章暂不支持，请改用 DoH / DoT / DoQ 印章")
	default:
		return nil, fmt.Errorf("unsupported stamp protocol byte 0x%02x", bin[0])
	}
}

// stampReader 带边界检查的顺序读取器，避免手写下标越界
type stampReader struct {
	bin []byte
	pos int
}

func (r *stampReader) remaining() int { return len(r.bin) - r.pos }

// readProps 读取 8 字节小端属性位图
func (r *stampReader) readProps() (StampProperties, error) {
	if r.remaining() < 8 {
		return 0, errors.New("stamp is too short (props)")
	}
	v := binary.LittleEndian.Uint64(r.bin[r.pos : r.pos+8])
	r.pos += 8
	return StampProperties(v), nil
}

// readLPString 读取一个 lp-string（1 字节长度 + 内容）
func (r *stampReader) readLPString(allowEmpty bool) (string, error) {
	if r.remaining() < 1 {
		return "", errors.New("stamp is too short (length byte)")
	}
	length := int(r.bin[r.pos])
	r.pos++
	if r.remaining() < length {
		return "", errors.New("stamp is truncated (string body)")
	}
	if length == 0 && !allowEmpty {
		return "", errors.New("stamp contains an unexpected empty string")
	}
	val := string(r.bin[r.pos : r.pos+length])
	r.pos += length
	return val, nil
}

// readVLP 读取一组 VLP 字符串；每项最高位 0x80 表示后续还有一项
func (r *stampReader) readVLP(elemLen int) ([]string, error) {
	var out []string
	for {
		if r.remaining() < 1 {
			return nil, errors.New("stamp is truncated (VLP length byte)")
		}
		vlen := int(r.bin[r.pos])
		length := vlen &^ 0x80
		r.pos++
		if r.remaining() < length {
			return nil, errors.New("stamp is truncated (VLP body)")
		}
		if length > 0 {
			if elemLen > 0 && length != elemLen {
				return nil, fmt.Errorf("stamp has an invalid %d-byte element (want %d)", length, elemLen)
			}
			out = append(out, string(r.bin[r.pos:r.pos+length]))
		}
		r.pos += length
		if vlen&0x80 != 0x80 {
			break
		}
	}
	return out, nil
}

// readHashes 读取证书指纹列表（VLP，元素定长 32 字节）
func (r *stampReader) readHashes() ([][]byte, error) {
	var hashes [][]byte
	for {
		if r.remaining() < 1 {
			return nil, errors.New("stamp is truncated (hash length byte)")
		}
		vlen := int(r.bin[r.pos])
		length := vlen &^ 0x80
		r.pos++
		if r.remaining() < length {
			return nil, errors.New("stamp is truncated (hash body)")
		}
		if length > 0 {
			if length != stampHashLen {
				return nil, fmt.Errorf("stamp certificate hash must be %d bytes, got %d", stampHashLen, length)
			}
			hash := make([]byte, stampHashLen)
			copy(hash, r.bin[r.pos:r.pos+length])
			hashes = append(hashes, hash)
		}
		r.pos += length
		if vlen&0x80 != 0x80 {
			break
		}
	}
	return hashes, nil
}

// expectEnd 校验印章尾部没有多余字节
func (r *stampReader) expectEnd() error {
	if r.remaining() != 0 {
		return errors.New("stamp has garbage after end")
	}
	return nil
}

func parsePlainStamp(bin []byte) (*ServerStamp, error) {
	r := &stampReader{bin: bin, pos: 1}
	props, err := r.readProps()
	if err != nil {
		return nil, err
	}
	addr, err := r.readLPString(false)
	if err != nil {
		return nil, err
	}
	if err := r.expectEnd(); err != nil {
		return nil, err
	}

	addr, err = normalizeStampAddr(addr, stampDefaultDNSPort)
	if err != nil {
		return nil, err
	}
	return &ServerStamp{Proto: StampProtoPlain, Props: props, ServerAddrStr: addr}, nil
}

func parseDoHStamp(bin []byte) (*ServerStamp, error) {
	r := &stampReader{bin: bin, pos: 1}
	props, err := r.readProps()
	if err != nil {
		return nil, err
	}

	// DoH 的直连地址允许为空（表示按主机名常规解析）
	addr, err := r.readLPString(true)
	if err != nil {
		return nil, err
	}
	hashes, err := r.readHashes()
	if err != nil {
		return nil, err
	}
	provider, err := r.readLPString(false)
	if err != nil {
		return nil, err
	}
	path, err := r.readLPString(true)
	if err != nil {
		return nil, err
	}

	bootstrapIPs, err := readOptionalBootstrapIPs(r)
	if err != nil {
		return nil, err
	}
	if err := r.expectEnd(); err != nil {
		return nil, err
	}

	if addr != "" {
		if addr, err = normalizeStampAddr(addr, stampDefaultHTTPSPort); err != nil {
			return nil, err
		}
	}
	if err := validateStampHostname(provider); err != nil {
		return nil, err
	}

	return &ServerStamp{
		Proto:         StampProtoDoH,
		Props:         props,
		ServerAddrStr: addr,
		Hashes:        hashes,
		ProviderName:  provider,
		Path:          path,
		BootstrapIPs:  bootstrapIPs,
	}, nil
}

func parseDoTStamp(bin []byte) (*ServerStamp, error) {
	r := &stampReader{bin: bin, pos: 1}
	props, err := r.readProps()
	if err != nil {
		return nil, err
	}

	addr, err := r.readLPString(true)
	if err != nil {
		return nil, err
	}
	hashes, err := r.readHashes()
	if err != nil {
		return nil, err
	}
	provider, err := r.readLPString(false)
	if err != nil {
		return nil, err
	}

	bootstrapIPs, err := readOptionalBootstrapIPs(r)
	if err != nil {
		return nil, err
	}
	if err := r.expectEnd(); err != nil {
		return nil, err
	}

	if addr != "" {
		if addr, err = normalizeStampAddr(addr, stampDefaultTLSPort); err != nil {
			return nil, err
		}
	}
	if err := validateStampHostname(provider); err != nil {
		return nil, err
	}

	return &ServerStamp{
		Proto:         StampProtoTLS,
		Props:         props,
		ServerAddrStr: addr,
		Hashes:        hashes,
		ProviderName:  provider,
		BootstrapIPs:  bootstrapIPs,
	}, nil
}

func parseDoQStamp(bin []byte) (*ServerStamp, error) {
	stamp, err := parseDoTStamp(bin)
	if err != nil {
		return nil, err
	}
	stamp.Proto = StampProtoDoQ
	return stamp, nil
}

// readOptionalBootstrapIPs 读取可选的尾部引导 IP 段
func readOptionalBootstrapIPs(r *stampReader) ([]string, error) {
	if r.remaining() == 0 {
		return nil, nil
	}
	return r.readVLP(0)
}

// normalizeStampAddr 校验并补全印章内的直连地址端口
func normalizeStampAddr(addr string, defaultPort int) (string, error) {
	host, port := splitStampPort(addr)
	if port == "" {
		if strings.HasSuffix(addr, ":") {
			return "", errors.New("stamp has an empty port")
		}
		port = strconv.Itoa(defaultPort)
	} else if err := validateStampPort(port); err != nil {
		return "", err
	}

	ipOnly := strings.TrimSuffix(strings.TrimPrefix(host, "["), "]")
	if net.ParseIP(ipOnly) == nil {
		return "", fmt.Errorf("stamp server address %q is not an IP address", host)
	}
	return net.JoinHostPort(ipOnly, port), nil
}

// validateStampHostname 校验印章主机名（可带端口）
func validateStampHostname(hostname string) error {
	if hostname == "" {
		return errors.New("stamp has an empty hostname")
	}
	host, port := splitStampPort(hostname)
	if port != "" {
		if err := validateStampPort(port); err != nil {
			return err
		}
	} else if strings.HasSuffix(hostname, ":") {
		return errors.New("stamp has an empty port")
	}
	if strings.TrimSpace(host) == "" {
		return errors.New("stamp has an empty hostname")
	}
	return nil
}

func validateStampPort(port string) error {
	p, err := strconv.ParseUint(port, 10, 16)
	if err != nil || p == 0 {
		return fmt.Errorf("stamp has an invalid port %q", port)
	}
	return nil
}

// splitStampPort 按最后一处冒号切分主机与端口，正确处理 IPv6 字面量
func splitStampPort(s string) (host, port string) {
	colIndex := strings.LastIndex(s, ":")
	bracketIndex := strings.LastIndex(s, "]")
	if colIndex < bracketIndex || colIndex < 0 {
		return s, ""
	}
	return s[:colIndex], s[colIndex+1:]
}
