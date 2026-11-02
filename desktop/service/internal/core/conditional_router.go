package core

import (
	"context"
	"fmt"
	"strings"
	"sync"

	"github.com/miekg/dns"
)

// ConditionalRouter 条件分流解析路由器 (Split-Horizon DNS)
// 借鉴自 blocky (conditional_upstream_resolver.go) 与 AdGuard Home (upstreams.go)
// 根据请求域名的后缀将 DNS 查询分流至指定的专有上游解析器（如企业内网 DNS、路由器等）。
type ConditionalRouter struct {
	mu              sync.RWMutex
	defaultResolver Resolver
	routes          map[string]Resolver // domainSuffix (lowercase without dots) -> Resolver
}

// NewConditionalRouter 创建条件分流路由器
func NewConditionalRouter(defaultResolver Resolver) *ConditionalRouter {
	return &ConditionalRouter{
		defaultResolver: defaultResolver,
		routes:          make(map[string]Resolver),
	}
}

// SetRoute 注册或更新特定域名的专有上游解析器
func (cr *ConditionalRouter) SetRoute(pattern string, r Resolver) {
	cr.mu.Lock()
	defer cr.mu.Unlock()
	cleaned := cleanDomainPattern(pattern)
	if cleaned != "" && r != nil {
		cr.routes[cleaned] = r
	}
}

// RemoveRoute 移除指定域名的分流规则
func (cr *ConditionalRouter) RemoveRoute(pattern string) {
	cr.mu.Lock()
	defer cr.mu.Unlock()
	cleaned := cleanDomainPattern(pattern)
	delete(cr.routes, cleaned)
}

// ClearRoutes 清空所有分流规则
func (cr *ConditionalRouter) ClearRoutes() {
	cr.mu.Lock()
	defer cr.mu.Unlock()
	cr.routes = make(map[string]Resolver)
}

// SetDefaultResolver 更新默认后备解析器
func (cr *ConditionalRouter) SetDefaultResolver(r Resolver) {
	cr.mu.Lock()
	defer cr.mu.Unlock()
	cr.defaultResolver = r
}

// MatchRoute 寻找最长匹配的条件分流解析器 (Longest Suffix Match)
func (cr *ConditionalRouter) MatchRoute(domain string) Resolver {
	cr.mu.RLock()
	defer cr.mu.RUnlock()

	cleaned := cleanDomainPattern(domain)
	if len(cr.routes) == 0 || cleaned == "" {
		return cr.defaultResolver
	}

	// 1. 完全精确匹配
	if r, ok := cr.routes[cleaned]; ok {
		return r
	}

	// 2. 逐级向父域名查找最长后缀匹配
	curr := cleaned
	for {
		idx := strings.Index(curr, ".")
		if idx == -1 {
			break
		}
		curr = curr[idx+1:]
		if r, ok := cr.routes[curr]; ok {
			return r
		}
	}

	return cr.defaultResolver
}

// Resolve 实现 Resolver 接口
func (cr *ConditionalRouter) Resolve(ctx context.Context, rawQuery []byte) ([]byte, error) {
	req := new(dns.Msg)
	if err := req.Unpack(rawQuery); err == nil && len(req.Question) > 0 {
		target := cr.MatchRoute(req.Question[0].Name)
		if target != nil {
			return target.Resolve(ctx, rawQuery)
		}
	}

	cr.mu.RLock()
	def := cr.defaultResolver
	cr.mu.RUnlock()
	if def == nil {
		return nil, fmt.Errorf("no upstream resolver available")
	}
	return def.Resolve(ctx, rawQuery)
}

// Exchange 实现 Resolver 接口
func (cr *ConditionalRouter) Exchange(ctx context.Context, req *dns.Msg) (*dns.Msg, error) {
	if req == nil {
		return nil, fmt.Errorf("nil dns request")
	}

	var target Resolver
	if len(req.Question) > 0 {
		target = cr.MatchRoute(req.Question[0].Name)
	}
	if target == nil {
		cr.mu.RLock()
		target = cr.defaultResolver
		cr.mu.RUnlock()
	}
	if target == nil {
		return nil, fmt.Errorf("no upstream resolver available")
	}
	return target.Exchange(ctx, req)
}

// Configure 实现 Resolver 接口
func (cr *ConditionalRouter) Configure(cfg ResolverConfig) error {
	cr.mu.RLock()
	def := cr.defaultResolver
	cr.mu.RUnlock()
	if def != nil {
		return def.Configure(cfg)
	}
	return nil
}

// Shutdown 实现 Resolver 接口
func (cr *ConditionalRouter) Shutdown() error {
	cr.mu.Lock()
	defer cr.mu.Unlock()

	var firstErr error
	if cr.defaultResolver != nil {
		if err := cr.defaultResolver.Shutdown(); err != nil && firstErr == nil {
			firstErr = err
		}
	}
	for _, r := range cr.routes {
		if r != nil {
			if err := r.Shutdown(); err != nil && firstErr == nil {
				firstErr = err
			}
		}
	}
	return firstErr
}

func cleanDomainPattern(s string) string {
	s = strings.ToLower(strings.TrimSpace(s))
	s = strings.TrimPrefix(s, "*")
	return strings.Trim(s, ".")
}
