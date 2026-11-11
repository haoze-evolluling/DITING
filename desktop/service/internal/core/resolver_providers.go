package core

import (
	"fmt"
	"net/url"
	"strings"
)

// stampExpandResult 记录一次印章展开的产物
type stampExpandResult struct {
	Provider ProviderConfig
	Pin      *CertPin
}

// ExpandStamp 把 sdns:// 印章展开为可直接使用的上游配置与证书指纹。
//
// 印章自带的引导 IP 会并入 BootstrapIPs 返回值，供上层决定是否补充引导配置。
func ExpandStamp(stampStr string) (ProviderConfig, *CertPin, []string, error) {
	stamp, err := ParseServerStamp(stampStr)
	if err != nil {
		return ProviderConfig{}, nil, nil, err
	}
	if !stamp.IsSupported() {
		return ProviderConfig{}, nil, nil, fmt.Errorf("印章协议 %s 暂不支持", stamp.Proto)
	}

	proto, err := stamp.Protocol()
	if err != nil {
		return ProviderConfig{}, nil, nil, err
	}

	prov := ProviderConfig{
		Protocol: proto,
		Server:   stamp.Server(),
	}
	if proto.IsHTTPStyleProtocol() {
		prov.URL = stamp.URL()
	}

	pins, err := stamp.Pins()
	if err != nil {
		return ProviderConfig{}, nil, nil, err
	}

	// 印章可携带多个指纹（轮换期常见）。这里只取第一个作为固定目标：
	// 多指纹"任一匹配即通过"会显著放宽校验强度，与固定的本意相悖。
	var pin *CertPin
	if len(pins) > 0 {
		pin = pins[0]
	}

	return prov, pin, stamp.BootstrapIPs, nil
}

// providerBuildInput 单个上游的构建入参（印章与显式配置的统一表示）
type providerBuildInput struct {
	cfg ProviderConfig
	pin *CertPin
}

// buildProviderSet 把用户配置展开并校验为一组可调度的上游。
//
// 主链路与回退链路共用此函数：两者的展开、校验与统计继承规则必须一致，
// 否则回退链会在统计口径或印章处理上与主链产生偏差。
// oldStats 用于在配置热更新时平滑保留健康与延迟历史，可为 nil。
func buildProviderSet(cfgs []ProviderConfig, oldStats map[string]*ProviderStats) ([]*ConfiguredProvider, error) {
	if len(cfgs) == 0 {
		return nil, nil
	}

	inputs, err := buildProviderInputs(cfgs)
	if err != nil {
		return nil, err
	}

	providers := make([]*ConfiguredProvider, 0, len(inputs))
	for _, in := range inputs {
		prov, err := normalizeProvider(in.cfg, in.pin)
		if err != nil {
			return nil, err
		}
		if stats := oldStats[prov.ID]; stats != nil {
			prov.Stats = stats
		} else {
			prov.Stats = NewProviderStats()
		}
		providers = append(providers, prov)
	}
	return providers, nil
}

// buildProviderInputs 校验并归一化上游列表，同时展开其中的印章。
//
// 印章既可单独作为上游（Server 字段填 sdns://...），
// 也可与显式字段混用；显式字段优先，便于用户覆盖印章中的默认值。
func buildProviderInputs(cfgs []ProviderConfig) ([]providerBuildInput, error) {
	out := make([]providerBuildInput, 0, len(cfgs))
	for i, p := range cfgs {
		if p.ID == "" {
			p.ID = fmt.Sprintf("provider-%d", i+1)
		}

		if stampStr, field := stampFromProvider(p); stampStr != "" {
			expanded, pin, _, err := ExpandStamp(stampStr)
			if err != nil {
				return nil, fmt.Errorf("provider %s: %w", p.ID, err)
			}
			// 显式填写的字段优先于印章推导值；
			// 但承载印章的那个字段本身不算"显式值"，否则会用印章原文覆盖展开结果。
			if s := strings.TrimSpace(p.Server); s != "" && field != stampFieldServer {
				expanded.Server = s
			}
			if u := strings.TrimSpace(p.URL); u != "" && field != stampFieldURL {
				expanded.URL = u
			}
			if p.Protocol != "" {
				expanded.Protocol = p.Protocol
			}
			if p.Weight > 0 {
				expanded.Weight = p.Weight
			}
			// 显式指纹同样优先于印章携带的指纹
			explicitPin, err := parseExplicitPin(p)
			if err != nil {
				return nil, err
			}
			if explicitPin != nil {
				pin = explicitPin
			}
			out = append(out, providerBuildInput{cfg: expanded, pin: pin})
			continue
		}

		pin, err := parseExplicitPin(p)
		if err != nil {
			return nil, err
		}
		out = append(out, providerBuildInput{cfg: p, pin: pin})
	}
	return out, nil
}

// 印章可能出现在 Server 或 URL 字段，需记录来源以便区分"印章"与"显式覆盖值"
const (
	stampFieldServer = "server"
	stampFieldURL    = "url"
)

// stampFromProvider 判断该上游是否以印章形式提供，并返回印章及其所在字段
func stampFromProvider(p ProviderConfig) (stamp, field string) {
	if f := strings.TrimSpace(p.Server); isStampString(f) {
		return f, stampFieldServer
	}
	if f := strings.TrimSpace(p.URL); isStampString(f) {
		return f, stampFieldURL
	}
	return "", ""
}

func isStampString(s string) bool {
	return strings.HasPrefix(s, "sdns://") || strings.HasPrefix(s, "sdns:")
}

// normalizeProvider 校验协议与地址，补齐派生字段
func normalizeProvider(p ProviderConfig, pin *CertPin) (*ConfiguredProvider, error) {
	if !IsValidProtocol(string(p.Protocol)) {
		return nil, fmt.Errorf("provider %s: unsupported protocol %q", p.ID, p.Protocol)
	}
	proto := ParseProtocol(string(p.Protocol))

	server := strings.TrimSpace(p.Server)
	urlStr := strings.TrimSpace(p.URL)
	if proto.IsHTTPStyleProtocol() {
		u, err := url.ParseRequestURI(urlStr)
		if err != nil || u.Scheme != "https" || u.Host == "" {
			return nil, fmt.Errorf("provider %s: invalid %s URL %q", p.ID, proto, urlStr)
		}
		if server == "" {
			server = u.Host
		}
	} else if server == "" {
		return nil, fmt.Errorf("provider %s: empty server address", p.ID)
	}

	weight := p.Weight
	if weight <= 0 {
		weight = 1
	}

	return &ConfiguredProvider{
		ID:       p.ID,
		Protocol: proto,
		Server:   server,
		URL:      urlStr,
		Weight:   weight,
		Pin:      pin,
	}, nil
}

// buildPinLookup 汇总各上游的证书指纹，生成按主机名分派的固定表。
//
// 同一主机名被多个上游指向且指纹不一致时保留先出现者，
// 并在上层由校验逻辑保证"未命中即回落标准链校验"。
func buildPinLookup(providers []*ConfiguredProvider) PinLookup {
	table := make(map[string]*CertPin)
	for _, p := range providers {
		if p == nil || p.Pin == nil || len(p.Pin.Sha256) == 0 {
			continue
		}
		host := pinHost(p.Server)
		if host == "" {
			continue
		}
		if _, exists := table[host]; !exists {
			table[host] = p.Pin
		}
	}
	if len(table) == 0 {
		return nil
	}
	return func(host string) *CertPin {
		return table[pinHost(host)]
	}
}

// pinHost 归一化主机名：去掉端口与 IPv6 方括号，统一小写
func pinHost(host string) string {
	host = strings.TrimSpace(host)
	if host == "" {
		return ""
	}
	if h, _, err := splitHostPortLoose(host); err == nil {
		host = h
	}
	return strings.ToLower(strings.Trim(host, "[]"))
}

// splitHostPortLoose 在无端口时也返回主机名，而不是报错
func splitHostPortLoose(s string) (host, port string, err error) {
	h, p := splitStampPort(s)
	if p == "" {
		return s, "", nil
	}
	return h, p, nil
}

// parseExplicitPin 解析用户显式填写的证书指纹，未填写时返回 nil
func parseExplicitPin(p ProviderConfig) (*CertPin, error) {
	raw := strings.TrimSpace(p.Pin)
	if raw == "" {
		return nil, nil
	}
	pin, err := ParseCertPin(raw)
	if err != nil {
		return nil, fmt.Errorf("provider %s: %w", p.ID, err)
	}
	return pin, nil
}
