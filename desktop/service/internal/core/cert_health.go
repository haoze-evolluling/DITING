package core

import (
	"fmt"
	"path/filepath"
	"time"
)

// CertRenewBefore 自签证书的提前续签窗口。
//
// 证书到期后客户端握手一律失败，而本端监听器不会因此报错（它只是
// 继续提供一张过期证书），所以必须在到期前主动换掉。选 30 天是给
// 「服务不是常开」「用户几周才开一次控制台」这类部署留出余量。
const CertRenewBefore = 30 * 24 * time.Hour

// CertHealth 证书生命周期的健康状态。
type CertHealth struct {
	// Loaded 证书是否可用
	Loaded bool
	// SelfSigned 当前是否为自签来源
	SelfSigned bool
	// Expired 已过期
	Expired bool
	// NotYetValid 尚未生效（通常是系统时钟回拨）
	NotYetValid bool
	// ExpiresSoon 在 CertRenewBefore 窗口内
	ExpiresSoon bool
	// DaysRemaining 距过期的天数，已过期为负
	DaysRemaining int
	// NotAfter 到期时间
	NotAfter time.Time
}

// NeedsRenewal 报告当前证书是否应重新签发（仅自签来源有意义）。
func (h CertHealth) NeedsRenewal() bool {
	if !h.SelfSigned {
		return false
	}
	return !h.Loaded || h.Expired || h.NotYetValid || h.ExpiresSoon
}

// Health 返回当前证书的生命周期状态。
func (m *CertManager) Health() CertHealth {
	m.mu.RLock()
	defer m.mu.RUnlock()

	h := CertHealth{SelfSigned: m.cfg.Source == CertSourceSelfSigned || m.cfg.Source == ""}
	if !m.loaded || m.leaf == nil {
		return h
	}
	h.Loaded = true
	h.NotAfter = m.leaf.NotAfter
	remaining := time.Until(m.leaf.NotAfter)
	h.DaysRemaining = int(remaining.Hours() / 24)
	h.Expired = remaining <= 0
	h.NotYetValid = time.Now().Before(m.leaf.NotBefore)
	h.ExpiresSoon = !h.Expired && remaining <= CertRenewBefore
	return h
}

// RenewSelfSignedIfNeeded 在自签证书即将到期或已失效时重新签发。
//
// 返回 true 表示本次确实换了证书。非自签来源直接返回 false：外部证书
// 的续期不归本程序管，擅自生成一张自签证书顶上去只会掩盖配置问题。
func (m *CertManager) RenewSelfSignedIfNeeded(cfg CertConfig) (bool, error) {
	NormalizeCertConfig(&cfg)
	if cfg.Source != CertSourceSelfSigned && cfg.Source != "" {
		return false, nil
	}

	h := m.Health()
	if h.Loaded && !h.NeedsRenewal() {
		return false, nil
	}
	if !fileExists(m.selfSignedCertPath()) {
		// 从没生成过（或文件已被删）：走首次签发路径
		return m.EnsureSelfSigned(cfg)
	}
	// 其余情况一律重签：已过期、即将到期、尚未生效、或文件在但载入失败
	// （损坏/不配对）——重签是唯一能自愈的动作。
	if err := m.RegenerateSelfSigned(cfg); err != nil {
		return false, fmt.Errorf("自签证书续签失败: %w", err)
	}
	return true, nil
}

// selfSignedCertPath 返回自签证书文件路径。
func (m *CertManager) selfSignedCertPath() string {
	return filepath.Join(m.Dir(), SelfSignedCertFileName)
}
