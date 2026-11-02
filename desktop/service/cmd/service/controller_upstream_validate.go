package main

import (
	"fmt"
	"net/url"
	"strings"

	"github.com/haoze-evolluling/diting/server/internal/core"
)

// validateProviderList 校验并归一化一组上游配置。
//
// 主链路与回退链路共用此函数：两者的校验口径必须一致，
// 否则回退链可能放过主链会拒绝的非法配置。
// prefix 用于在错误信息中标记该组上游的归属（主链路为空）。
func validateProviderList(providers []core.ProviderConfig, seenIDs map[string]bool, prefix string) ([]core.ProviderConfig, error) {
	validated := make([]core.ProviderConfig, len(providers))
	for i, prov := range providers {
		id := strings.TrimSpace(prov.ID)
		if id == "" {
			id = fmt.Sprintf("%sprovider-%d", prefix, i+1)
			if prefix == "" {
				id = fmt.Sprintf("provider-%d", i+1)
			}
			prov.ID = id
		}
		if seenIDs[id] {
			return nil, fmt.Errorf("%s上游服务器 ID 重复: %s", prefix, id)
		}
		seenIDs[id] = true

		if !core.IsValidProtocol(string(prov.Protocol)) {
			return nil, fmt.Errorf("%s上游 %s: 不支持的解析协议 %q", prefix, id, prov.Protocol)
		}
		proto := core.ParseProtocol(string(prov.Protocol))
		prov.Protocol = proto

		switch proto {
		case core.ProtocolDoH, core.ProtocolDoH3:
			u, err := url.ParseRequestURI(prov.URL)
			if err != nil || u.Scheme != "https" || u.Host == "" {
				return nil, fmt.Errorf("%s上游 %s: 非法的 %s URL %q", prefix, id, proto, prov.URL)
			}
			if strings.TrimSpace(prov.Server) == "" {
				prov.Server = u.Host
			}
		case core.ProtocolDoT, core.ProtocolDoQ:
			if strings.TrimSpace(prov.Server) == "" {
				return nil, fmt.Errorf("%s上游 %s: %s 服务器地址不能为空", prefix, id, proto)
			}
		default:
			if strings.TrimSpace(prov.Server) == "" {
				return nil, fmt.Errorf("%s上游 %s: 服务器地址不能为空", prefix, id)
			}
		}
		if prov.Weight <= 0 {
			prov.Weight = 1
		}
		validated[i] = prov
	}
	return validated, nil
}
