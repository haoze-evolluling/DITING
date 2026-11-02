package core

import "log"

// BogusNXDomainMatcher 返回当前生效的伪应答匹配器；未启用时返回 nil。
//
// 总开关（FilterConfig.Enabled）优先：用户的"关闭拦截"意图应当覆盖子功能，
// 否则会出现"规则拦截已关闭却仍在改写应答"的矛盾状态。
func (e *RuleEngine) BogusNXDomainMatcher() *BogusNXDomainMatcher {
	e.mu.RLock()
	defer e.mu.RUnlock()
	if !e.cfg.Enabled || !e.cfg.BogusNXDomain {
		return nil
	}
	return e.bogusMatcher
}

// syncBogusMatcherUnlocked 依当前配置重建伪应答匹配器（调用方需持有 e.mu）。
//
// 重建失败时保留上一次可用的匹配器：一条写错的地址不应让整项防护失效，
// 但配置已关闭时必须真的清空，否则关闭开关毫无作用。
func (e *RuleEngine) syncBogusMatcherUnlocked() {
	if !e.cfg.Enabled || !e.cfg.BogusNXDomain {
		e.bogusMatcher = nil
		return
	}

	matcher, err := NewBogusNXDomainMatcher(e.cfg.BogusNXDomainNetworks)
	if err != nil {
		log.Printf("[BogusNXDomain] 部分伪应答地址无效: %v", err)
		if matcher.Size() == 0 {
			// 全部条目都非法：清空而非沿用旧集合，避免界面显示的清单与实际生效的不一致
			e.bogusMatcher = nil
			return
		}
	}
	e.bogusMatcher = matcher
}
