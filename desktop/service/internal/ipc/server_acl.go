package ipc

import (
	"errors"
	"net/http"

	"github.com/haoze-evolluling/diting/server/internal/core"
)

// errUnrestrictedTrust 全放行配置未获确认时的拒绝原因
var errUnrestrictedTrust = errors.New(
	"可信来源包含 0.0.0.0/0 或 ::/0：任何直连方都可伪造客户端来源，" +
		"访问控制与限速会同时失效。请缩小范围，或显式确认接受该风险")

// handleEncryptedDNSACL 处理 /api/v1/encrypted/dns/acl
//
// GET 返回当前可信代理配置，POST 更新。与 cert 系列一样，更新后回传
// 完整状态——可信列表会被归一化（去重、trim），界面需要看到真正生效的值。
func (s *Server) handleEncryptedDNSACL(w http.ResponseWriter, r *http.Request) {
	switch r.Method {
	case http.MethodGet:
		s.writeEncryptedStatus(w, r, "")
	case http.MethodPost:
		req, ok := decodeJSON[ConfigureACLRequest](w, r)
		if !ok {
			return
		}
		// 请求里自带的全放行列表在这里就先拦一道，不必等控制器合并完
		// 持久化状态才发现。控制器里还会再查一次：它能看到本次请求之外
		// 已存下的列表，而这一层只看得见请求体。
		if req.TrustedSources != nil {
			if err := ValidateACLUnrestricted(*req.TrustedSources, req.ConfirmUnrestricted); err != nil {
				writeJSON(w, http.StatusBadRequest, Response[any]{Success: false, Error: err.Error()})
				return
			}
		}
		if err := s.controller.ConfigureEncryptedACL(r.Context(), req); err != nil {
			// 非法 IP/CIDR 属于用户输入问题，用 400 让界面当表单错误展示
			writeJSON(w, http.StatusBadRequest, Response[any]{Success: false, Error: err.Error()})
			return
		}
		s.writeEncryptedStatus(w, r, "反向代理可信来源已更新")
	default:
		writeJSON(w, http.StatusMethodNotAllowed, Response[any]{
			Success: false, Error: "只支持 GET 与 POST 请求",
		})
	}
}

// ConfigureACLRequest 更新反向代理可信来源。
//
// 字段均为可选，省略表示沿用当前值；数组用指针以便区分
// 「传了空列表」（清空）与「没传」（不动）。
type ConfigureACLRequest struct {
	Enabled *bool `json:"enabled,omitempty"`
	// TrustedSources 可信代理的 IP 或 CIDR 列表
	TrustedSources *[]string `json:"trustedSources,omitempty"`
	// ClientIPHeader 自定义转发头名；空串表示按 XFF → X-Real-IP 依次尝试
	ClientIPHeader *string `json:"clientIpHeader,omitempty"`
	// ConfirmUnrestricted 确认接受 0.0.0.0/0 这类全放行配置。
	//
	// 没有它就把全放行配置挡在服务端，光靠界面弹窗不算数：
	// 直接调接口的人绕过界面后，得到的是一个任何人加个头就能
	// 伪装成白名单成员、并按 IP 绕过限速的 DoH 入口。
	ConfirmUnrestricted bool `json:"confirmUnrestricted,omitempty"`
}

// ValidateACLUnrestricted 在未确认时拒绝全放行配置
func ValidateACLUnrestricted(sources []string, confirmed bool) error {
	if confirmed {
		return nil
	}
	if core.HasUnrestrictedTrust(sources) {
		return errUnrestrictedTrust
	}
	return nil
}
