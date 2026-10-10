package ipc

import (
	"context"

	"github.com/haoze-evolluling/diting/windows/internal/core"
	"github.com/haoze-evolluling/diting/windows/internal/platform/windows"
)

// ServiceController 抽象服务核心控制操作接口
type ServiceController interface {
	StartDNS(ctx context.Context) error
	StopDNS(ctx context.Context) error
	EnableTakeover(ctx context.Context) error
	DisableTakeover(ctx context.Context) error
	GetStatus(ctx context.Context) (*StatusResponse, error)
	CheckPortConflicts(ctx context.Context) (*windows.PortCheckResult, error)
	AutofixPortConflicts(ctx context.Context, startDNS bool) (*windows.PortCheckResult, error)
	GetAdapters(ctx context.Context) ([]windows.AdapterInfo, error)
	ConfigureUpstream(ctx context.Context, req ConfigureUpstreamRequest) error
	TestUpstream(ctx context.Context, req TestUpstreamRequest) (*TestUpstreamResponse, error)
	SetAdapterTakeover(ctx context.Context, req AdapterTakeoverRequest) error
	GetCacheStats(ctx context.Context) (*core.CacheStats, error)
	GetCacheEntries(ctx context.Context, query string, limit int) (*CacheEntriesResponse, error)
	GetCacheTopDomains(ctx context.Context, limit int) ([]core.CacheDomainStat, error)
	ClearCache(ctx context.Context) error
	GetCacheConfig(ctx context.Context) (*core.CacheConfig, error)
	UpdateCacheConfig(ctx context.Context, cfg core.CacheConfig) error
	GetFilterStats(ctx context.Context) (*core.FilterStats, error)
	GetFilterConfig(ctx context.Context) (*core.FilterConfig, error)
	UpdateFilterConfig(ctx context.Context, cfg core.FilterConfig) error
	GetFilterLists(ctx context.Context) ([]core.FilterList, error)
	AddFilterList(ctx context.Context, list core.FilterList) error
	UpdateFilterList(ctx context.Context, list core.FilterList) error
	DeleteFilterList(ctx context.Context, id string) error
	RefreshFilterLists(ctx context.Context, id string) error
	GetCustomRules(ctx context.Context) ([]string, error)
	SetCustomRules(ctx context.Context, rules []string) error
	CheckHostRule(ctx context.Context, domain string, qtype uint16) (*core.CheckHostResult, error)
	GetLANStatus(ctx context.Context) (*LANStatusResponse, error)
	ConfigureLAN(ctx context.Context, req ConfigureLANRequest) error
	ConfigureFirewall(ctx context.Context, enable bool) error
	GetWebStatus(ctx context.Context) (*WebStatusResponse, error)
	ConfigureWeb(ctx context.Context, req ConfigureWebRequest) error
	ConfigureWebFirewall(ctx context.Context, enable bool) error
	GetAuthStatus(ctx context.Context) (*AuthStatusResponse, error)
	Login(ctx context.Context, req LoginRequest, clientIP string) (*LoginResponse, error)
	Logout(ctx context.Context, token string) error
	SetupAuth(ctx context.Context, req SetupAuthRequest) error
	ChangePassword(ctx context.Context, req ChangePasswordRequest, bypassOldAuth bool) error
	ValidateSession(token string) bool
}
