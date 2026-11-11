package ipc

import (
	"encoding/json"
	"io"
	"net/http"
)

// handleEncryptedDNSStatus 处理 GET /api/v1/encrypted/dns/status
func (s *Server) handleEncryptedDNSStatus(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		writeJSON(w, http.StatusMethodNotAllowed, Response[any]{Success: false, Error: "只支持 GET 请求"})
		return
	}
	res, err := s.controller.GetEncryptedDNS(r.Context())
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, Response[any]{Success: false, Error: err.Error()})
		return
	}
	writeJSON(w, http.StatusOK, Response[*EncryptedDNSStatusResponse]{Success: true, Data: res})
}

// handleEncryptedDNSConfigure 处理 POST /api/v1/encrypted/dns/configure
//
// 更新后回传完整状态：端口与路径会被归一化，让界面立刻看到真正生效的
// 值，而不是它填进去的那个。
func (s *Server) handleEncryptedDNSConfigure(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		writeJSON(w, http.StatusMethodNotAllowed, Response[any]{Success: false, Error: "只支持 POST 请求"})
		return
	}
	req, ok := decodeJSON[ConfigureEncryptedDNSRequest](w, r)
	if !ok {
		return
	}
	if err := s.controller.ConfigureEncryptedDNS(r.Context(), req); err != nil {
		writeJSON(w, http.StatusInternalServerError, Response[any]{Success: false, Error: err.Error()})
		return
	}
	s.writeEncryptedStatus(w, r, "加密 DNS 配置已更新")
}

// handleEncryptedCertGenerate 处理 POST /api/v1/encrypted/dns/cert/generate
//
// 证书生成失败是用户输入问题而非服务故障（名字全空、IP 非法、
// 目录不可写），统一以 400 呈现，让界面能直接把它当作表单错误展示。
func (s *Server) handleEncryptedCertGenerate(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		writeJSON(w, http.StatusMethodNotAllowed, Response[any]{Success: false, Error: "只支持 POST 请求"})
		return
	}
	req, ok := decodeJSON[GenerateCertRequest](w, r)
	if !ok {
		return
	}
	if err := s.controller.GenerateEncryptedCert(r.Context(), req); err != nil {
		writeJSON(w, http.StatusBadRequest, Response[any]{Success: false, Error: err.Error()})
		return
	}
	s.writeEncryptedStatus(w, r, "证书已生成")
}

// handleEncryptedCertImport 处理 POST /api/v1/encrypted/dns/cert/import
func (s *Server) handleEncryptedCertImport(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		writeJSON(w, http.StatusMethodNotAllowed, Response[any]{Success: false, Error: "只支持 POST 请求"})
		return
	}
	req, ok := decodeJSON[ImportCertRequest](w, r)
	if !ok {
		return
	}
	if err := s.controller.ImportEncryptedCert(r.Context(), req); err != nil {
		writeJSON(w, http.StatusBadRequest, Response[any]{Success: false, Error: err.Error()})
		return
	}
	s.writeEncryptedStatus(w, r, "证书已导入")
}

// writeEncryptedStatus 回传操作后的完整状态；
// 取状态失败不算操作失败，退化为只回一句成功提示
func (s *Server) writeEncryptedStatus(w http.ResponseWriter, r *http.Request, message string) {
	res, err := s.controller.GetEncryptedDNS(r.Context())
	if err != nil {
		writeJSON(w, http.StatusOK, Response[any]{Success: true, Message: message})
		return
	}
	writeJSON(w, http.StatusOK, Response[*EncryptedDNSStatusResponse]{
		Success: true,
		Message: message,
		Data:    res,
	})
}

// decodeJSON 读取并解析请求体；失败时已写好响应，返回 ok=false
func decodeJSON[T any](w http.ResponseWriter, r *http.Request) (T, bool) {
	var out T
	body, err := io.ReadAll(r.Body)
	if err != nil {
		writeJSON(w, http.StatusBadRequest, Response[any]{Success: false, Error: "读取请求体失败"})
		return out, false
	}
	if err := json.Unmarshal(body, &out); err != nil {
		writeJSON(w, http.StatusBadRequest, Response[any]{Success: false, Error: "解析请求 JSON 失败: " + err.Error()})
		return out, false
	}
	return out, true
}
