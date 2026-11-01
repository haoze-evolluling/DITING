package ipc

import (
	"context"
	"sync"
	"time"

	"github.com/haoze-evolluling/diting/desktop/internal/core"
	"github.com/haoze-evolluling/diting/desktop/internal/platform"
	"github.com/haoze-evolluling/diting/desktop/internal/querylog"
)

type mockController struct {
	// 后续 Step 新增的 Controller 方法桩集中在 mock_extra_test.go，
	// 通过匿名字段挂载，避免本文件触碰 600 行上限。
	mockExtra

	mu                   sync.Mutex
	dnsRunning           bool
	takeoverOn           bool
	startErr             error
	stopErr              error
	takeoverErr          error
	restoreErr           error
	emergencyErr         error
	emergencyResult      *EmergencyRestoreResponse
	statusResult         *StatusResponse
	portResult           *platform.PortCheckResult
	cacheConfig          *core.CacheConfig
	filterConfig         *core.FilterConfig
	scheduleConfig       *ScheduleConfigResponse
	scheduleConfigureErr error
	filterPause          *FilterPauseResponse
	filterPauseErr       error
	clientGroups         *ClientGroupConfigResponse
	clientGroupsErr      error
	queryLogConfig       *querylog.QueryLogConfig
	queryLogCleared      bool
	bgConfig             *LoginBackgroundResponse
	bgImageData          []byte
	authInitialized      bool
	safeSearch           *SafeSearchConfigResponse
	safeSearchErr        error
	serviceStatus        *platform.CoreServiceStatus
}

func (m *mockController) StartDNS(ctx context.Context) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	if m.startErr != nil {
		return m.startErr
	}
	m.dnsRunning = true
	return nil
}

func (m *mockController) StopDNS(ctx context.Context) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	if m.stopErr != nil {
		return m.stopErr
	}
	m.dnsRunning = false
	return nil
}

func (m *mockController) EnableTakeover(ctx context.Context) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	if m.takeoverErr != nil {
		return m.takeoverErr
	}
	m.takeoverOn = true
	return nil
}

func (m *mockController) DisableTakeover(ctx context.Context) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	if m.restoreErr != nil {
		return m.restoreErr
	}
	m.takeoverOn = false
	return nil
}

func (m *mockController) GetCoreServiceStatus(ctx context.Context) (*platform.CoreServiceStatus, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	if m.serviceStatus != nil {
		return m.serviceStatus, nil
	}
	return &platform.CoreServiceStatus{
		Installed:      true,
		Running:        true,
		State:          "running",
		StateText:      "运行中",
		ExecutablePath: "/usr/local/bin/diting-service",
		CanInstall:     true,
		Message:        "核心服务正常运行中。",
		AutoStart: &platform.AutoStartStatus{
			Enabled:   true,
			Mechanism: platform.AutoStartMechanismSystemd,
			Detail:    "systemd 单元已 enable，开机无需登录即可守护运行。",
		},
	}, nil
}

func (m *mockController) GetStatus(ctx context.Context) (*StatusResponse, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	if m.statusResult != nil {
		return m.statusResult, nil
	}
	return &StatusResponse{
		Version:       "0.1.0-test",
		PID:           1000,
		UptimeSeconds: 120,
		DNS: DNSStatus{
			Running:         m.dnsRunning,
			ListenAddresses: []string{"127.0.0.1:53"},
			Mode:            "PRIMARY_BACKUP",
		},
		Takeover: TakeoverStatus{
			Active: m.takeoverOn,
		},
		Metrics: MetricsStatus{
			TotalQueries: 42,
		},
	}, nil
}

func (m *mockController) CheckPortConflicts(ctx context.Context) (*platform.PortCheckResult, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	if m.portResult != nil {
		return m.portResult, nil
	}
	return &platform.PortCheckResult{
		Available:  true,
		Conflicts:  []platform.PortConflict{},
		HasICS:     false,
		Diagnostic: "53 端口空闲且可用",
	}, nil
}

func (m *mockController) AutofixPortConflicts(ctx context.Context, startDNS bool) (*platform.PortCheckResult, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	if startDNS {
		m.dnsRunning = true
	}
	return &platform.PortCheckResult{
		Available:  true,
		Conflicts:  []platform.PortConflict{},
		HasICS:     false,
		Diagnostic: "53 端口冲突已自动修复",
	}, nil
}

func (m *mockController) GetAdapters(ctx context.Context) ([]platform.AdapterInfo, error) {
	return []platform.AdapterInfo{
		{
			ID:         "{GUID-TEST}",
			Name:       "WLAN",
			Index:      8,
			Status:     "Up",
			Gateway:    "192.168.1.1",
			IsPhysical: true,
		},
	}, nil
}

func (m *mockController) ConfigureUpstream(ctx context.Context, req ConfigureUpstreamRequest) error {
	return nil
}

func (m *mockController) GetUpstreamConfig(ctx context.Context) (*core.ResolverConfig, error) {
	return &core.ResolverConfig{
		Mode: "primary_backup",
		Providers: []core.ProviderConfig{
			{ID: "mock-1", Protocol: core.ProtocolPlain, Server: "1.1.1.1:53", Weight: 1},
		},
	}, nil
}

func (m *mockController) TestUpstream(ctx context.Context, req TestUpstreamRequest) (*TestUpstreamResponse, error) {
	return &TestUpstreamResponse{Success: true, LatencyMs: 12.5}, nil
}

func (m *mockController) SetAdapterTakeover(ctx context.Context, req AdapterTakeoverRequest) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.takeoverOn = req.Enable
	return nil
}

func (m *mockController) GetCacheStats(ctx context.Context) (*core.CacheStats, error) {
	return &core.CacheStats{
		Enabled:     true,
		TotalHits:   10,
		TotalMisses: 2,
		HitRatio:    0.833,
		EntryCount:  5,
		MaxEntries:  4096,
	}, nil
}

func (m *mockController) GetCacheEntries(ctx context.Context, query string, limit int) (*CacheEntriesResponse, error) {
	return &CacheEntriesResponse{
		Total: 1,
		Entries: []core.CacheEntryItem{
			{
				Domain:       "test.com",
				QType:        "A",
				TTL:          60,
				RemainingTTL: 55,
				HitCount:     10,
				Status:       "fresh",
			},
		},
	}, nil
}

func (m *mockController) GetCacheTopDomains(ctx context.Context, limit int) ([]core.CacheDomainStat, error) {
	return []core.CacheDomainStat{
		{Domain: "test.com", QType: "A", HitCount: 10},
	}, nil
}

func (m *mockController) ClearCache(ctx context.Context) error {
	return nil
}

func (m *mockController) GetCacheConfig(ctx context.Context) (*core.CacheConfig, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	if m.cacheConfig != nil {
		cpy := *m.cacheConfig
		return &cpy, nil
	}
	cfg := core.DefaultCacheConfig()
	return &cfg, nil
}

func (m *mockController) UpdateCacheConfig(ctx context.Context, cfg core.CacheConfig) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.cacheConfig = &cfg
	return nil
}

func (m *mockController) GetQueryLog(ctx context.Context, query querylog.SearchQuery) (*querylog.SearchResult, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	return &querylog.SearchResult{
		Total: 1,
		Entries: []querylog.Record{
			{Timestamp: 1700000000000, Domain: "example.com", QType: "A", Status: querylog.StatusAllowed},
		},
	}, nil
}

func (m *mockController) GetQueryStats(ctx context.Context) (*QueryStatsResponse, error) {
	return &QueryStatsResponse{
		Summary:    querylog.Summary{Queries: 100, Blocked: 20, Cached: 30, Forwarded: 50, AvgResponseMs: 12.5, CacheHitRate: 0.3},
		PerHour:    []querylog.HourPoint{{HourMs: 1700000000000, Queries: 10, Blocked: 2, Cached: 3}},
		TopDomains: []querylog.NameCount{{Name: "example.com", Count: 20}},
		TopBlocked: []querylog.NameCount{{Name: "ads.example.com", Count: 5}},
		TopClients: []querylog.NameCount{{Name: "192.168.1.50", Count: 30}},
	}, nil
}

func (m *mockController) ClearQueryLog(ctx context.Context) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.queryLogCleared = true
	return nil
}

func (m *mockController) GetQueryLogConfig(ctx context.Context) (*querylog.QueryLogConfig, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	if m.queryLogConfig != nil {
		cpy := *m.queryLogConfig
		return &cpy, nil
	}
	cfg := querylog.DefaultQueryLogConfig()
	return &cfg, nil
}

func (m *mockController) UpdateQueryLogConfig(ctx context.Context, cfg querylog.QueryLogConfig) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.queryLogConfig = &cfg
	return nil
}

func (m *mockController) GetFilterStats(ctx context.Context) (*core.FilterStats, error) {
	return &core.FilterStats{Enabled: true, TotalRules: 100, ActiveLists: 1, BlockedQueries: 5, BlockRate: 5.0}, nil
}

func (m *mockController) GetFilterConfig(ctx context.Context) (*core.FilterConfig, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	if m.filterConfig != nil {
		cpy := *m.filterConfig
		return &cpy, nil
	}
	cfg := core.DefaultFilterConfig()
	return &cfg, nil
}

func (m *mockController) UpdateFilterConfig(ctx context.Context, cfg core.FilterConfig) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.filterConfig = &cfg
	return nil
}

func (m *mockController) GetBlockingSchedule(ctx context.Context) (*ScheduleConfigResponse, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	if m.scheduleConfig != nil {
		cpy := *m.scheduleConfig
		return &cpy, nil
	}
	return &ScheduleConfigResponse{Enabled: false, Schedules: []core.BlockingSchedule{}, Active: true}, nil
}

func (m *mockController) ConfigureBlockingSchedule(ctx context.Context, req ConfigureScheduleRequest) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	if m.scheduleConfigureErr != nil {
		return m.scheduleConfigureErr
	}
	if m.scheduleConfig == nil {
		m.scheduleConfig = &ScheduleConfigResponse{}
	}
	if req.Enabled != nil {
		m.scheduleConfig.Enabled = *req.Enabled
	}
	if req.Schedules != nil {
		m.scheduleConfig.Schedules = *req.Schedules
	}
	return nil
}

func (m *mockController) GetFilterPause(ctx context.Context) (*FilterPauseResponse, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	if m.filterPauseErr != nil {
		return nil, m.filterPauseErr
	}
	if m.filterPause != nil {
		cpy := *m.filterPause
		return &cpy, nil
	}
	return &FilterPauseResponse{Paused: false, BlockingEnabled: true}, nil
}

func (m *mockController) SetFilterPause(ctx context.Context, req FilterPauseRequest) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	if m.filterPauseErr != nil {
		return m.filterPauseErr
	}
	if m.filterPause == nil {
		m.filterPause = &FilterPauseResponse{BlockingEnabled: true}
	}
	m.filterPause.Paused = req.Paused
	if req.Paused {
		m.filterPause.RemainingSeconds = req.DurationSec
		m.filterPause.PausedUntilMs = time.Now().Add(time.Duration(req.DurationSec) * time.Second).UnixMilli()
	} else {
		m.filterPause.RemainingSeconds = 0
		m.filterPause.PausedUntilMs = 0
	}
	return nil
}

func (m *mockController) GetClientGroups(ctx context.Context) (*ClientGroupConfigResponse, error) {	m.mu.Lock()
	defer m.mu.Unlock()
	if m.clientGroups != nil {
		cpy := *m.clientGroups
		return &cpy, nil
	}
	return &ClientGroupConfigResponse{Enabled: false, Groups: []core.ClientGroup{}}, nil
}

func (m *mockController) ConfigureClientGroups(ctx context.Context, req ConfigureClientGroupsRequest) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	if m.clientGroupsErr != nil {
		return m.clientGroupsErr
	}
	if m.clientGroups == nil {
		m.clientGroups = &ClientGroupConfigResponse{}
	}
	if req.Enabled != nil {
		m.clientGroups.Enabled = *req.Enabled
	}
	if req.Groups != nil {
		m.clientGroups.Groups = *req.Groups
	}
	return nil
}

func (m *mockController) GetFilterLists(ctx context.Context) ([]core.FilterList, error) {
	return []core.FilterList{{ID: "test-list", Name: "Test List", Enabled: true, RulesCount: 10}}, nil
}

func (m *mockController) AddFilterList(ctx context.Context, list core.FilterList) error {
	return nil
}

func (m *mockController) UpdateFilterList(ctx context.Context, list core.FilterList) error {
	return nil
}

func (m *mockController) DeleteFilterList(ctx context.Context, id string) error {
	return nil
}

func (m *mockController) RefreshFilterLists(ctx context.Context, id string) error {
	return nil
}

func (m *mockController) GetCustomRules(ctx context.Context) ([]string, error) {
	return []string{"||ad.com^"}, nil
}

func (m *mockController) SetCustomRules(ctx context.Context, rules []string) error {
	return nil
}

func (m *mockController) CheckHostRule(ctx context.Context, domain string, qtype uint16) (*core.CheckHostResult, error) {
	return &core.CheckHostResult{Blocked: true, Action: "block", MatchedRule: "||ad.com^", Reason: "blacklist"}, nil
}

func (m *mockController) GetLANStatus(ctx context.Context) (*LANStatusResponse, error) {
	return &LANStatusResponse{
		AllowLAN:        true,
		ListenAddresses: []string{"0.0.0.0:53", "[::]:53"},
		LANAddresses:    []string{"192.168.1.100"},
		FirewallAllowed: true,
	}, nil
}

func (m *mockController) ConfigureLAN(ctx context.Context, req ConfigureLANRequest) error {
	return nil
}

func (m *mockController) ConfigureFirewall(ctx context.Context, enable bool) error {
	return nil
}
