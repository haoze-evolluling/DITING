package ipc

import (
	"encoding/json"
	"net/http"

	"github.com/haoze-evolluling/diting/server/internal/core"
)

// handleParseStamp 解析 sdns:// 印章并返回可回填至表单的字段。
//
// 该操作是纯粹的字符串解析，不触碰任何运行态，故无需经过 ServiceController；
// 改为无状态处理可避免为一次性动作扩散接口与测试桩。
func (s *Server) handleParseStamp(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		writeJSON(w, http.StatusMethodNotAllowed, Response[any]{Success: false, Error: "method not allowed"})
		return
	}

	var req ParseStampRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, Response[any]{Success: false, Error: err.Error()})
		return
	}

	stamp, err := core.ParseServerStamp(req.Stamp)
	if err != nil {
		writeJSON(w, http.StatusBadRequest, Response[any]{Success: false, Error: err.Error()})
		return
	}
	if !stamp.IsSupported() {
		writeJSON(w, http.StatusBadRequest, Response[any]{
			Success: false,
			Error:   "该印章协议暂不支持，请使用 DoH / DoT / DoQ 印章",
		})
		return
	}

	proto, err := stamp.Protocol()
	if err != nil {
		writeJSON(w, http.StatusBadRequest, Response[any]{Success: false, Error: err.Error()})
		return
	}

	result := ParseStampResponse{
		Protocol:     string(proto),
		Server:       stamp.Server(),
		URL:          stamp.URL(),
		ProviderName: stamp.ProviderName,
		Path:         stamp.Path,
		ServerAddr:   stamp.ServerAddrStr,
		BootstrapIPs: stamp.BootstrapIPs,
		ProtoName:    stamp.Proto.String(),
		Props: StampProps{
			DNSSEC:   stamp.Props.Has(core.StampPropDNSSEC),
			NoLog:    stamp.Props.Has(core.StampPropNoLog),
			NoFilter: stamp.Props.Has(core.StampPropNoFilter),
		},
	}

	// 印章可携带多个指纹（轮换期）。此处只回填第一个，与解析器的固定策略一致：
	// "任一匹配即通过"会显著削弱固定的意义。
	if pins, pErr := stamp.Pins(); pErr == nil && len(pins) > 0 {
		result.Pin = pins[0].Hex()
	}

	writeJSON(w, http.StatusOK, Response[ParseStampResponse]{Success: true, Data: result})
}
