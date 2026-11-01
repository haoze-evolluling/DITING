package ipc

import (
	"context"
	"fmt"

	"github.com/haoze-evolluling/diting/desktop/internal/core"
)

// mockExtra 汇总后续 Step 新增的 ServiceController 方法桩。
//
// mockController 通过匿名嵌入本类型获得这些方法，
// 从而让 mock_test.go 不随功能增长触碰 600 行上限。
// 每个新增方法请在此文件内按 Step 分组实现。
type mockExtra struct {
	// A6 缓存落盘：由各测试按需注入
	cachePersist    *CachePersistResponse
	cachePersistErr bool
	cacheDumped     bool
	cacheLoaded     bool

	// B3 内置阻断服务：由各测试按需注入
	blockedServices        *BlockedServicesResponse
	blockedServicesErr     bool
	blockedServicesUpdated bool
	lastServicesReq        ConfigureBlockedServicesRequest

	// B5 本地权威区：由各测试按需注入
	zoneConfig  *ZoneConfigResponse
	zoneErr     bool
	zoneUpdated bool
	lastZoneReq ConfigureZoneRequest

	// B6 声誉查询：由各测试按需注入
	safeBrowsing        *SafeBrowsingResponse
	safeBrowsingErr     bool
	safeBrowsingUpdated bool
	lastSafeBrowsingReq ConfigureSafeBrowsingRequest

	// C1 加密 DNS 服务：由各测试按需注入
	encrypted         *EncryptedDNSStatusResponse
	encryptedErr      bool
	encryptedUpdated  bool
	lastEncryptedReq  ConfigureEncryptedDNSRequest
	certGenerated     bool
	lastCertGenReq    GenerateCertRequest
	certImported      bool
	lastCertImportReq ImportCertRequest

	// C6 Apple 配置描述文件
	mobileConfigProtocol string
	mobileConfigData     []byte
	mobileConfigErr      bool

	// C7 反向代理可信来源
	aclUpdated  bool
	lastACLReq  ConfigureACLRequest
	aclWriteErr bool
}

// EmergencyRestore 实现 ServiceController 接口：应急恢复系统 DNS。
func (m *mockController) EmergencyRestore(ctx context.Context) (*EmergencyRestoreResponse, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	if m.emergencyErr != nil {
		return nil, m.emergencyErr
	}
	if m.emergencyResult != nil {
		return m.emergencyResult, nil
	}
	healed := m.takeoverOn
	m.takeoverOn = false
	if healed {
		return &EmergencyRestoreResponse{Healed: true, Message: "已成功恢复网络 DNS 设置！"}, nil
	}
	return &EmergencyRestoreResponse{Healed: false, Message: "网络 DNS 状态正常，无需修复。"}, nil
}

// CachePersistStatus 实现 ServiceController 接口（A6）
func (m *mockExtra) CachePersistStatus(ctx context.Context) (*CachePersistResponse, error) {
	if m.cachePersistErr {
		return nil, errCachePersistUnavailable
	}
	if m.cachePersist != nil {
		return m.cachePersist, nil
	}
	return &CachePersistResponse{Path: "/tmp/cache.json", EntryCount: 0}, nil
}

// DumpCache 实现 ServiceController 接口（A6）
func (m *mockExtra) DumpCache(ctx context.Context) (*CachePersistResponse, error) {
	m.cacheDumped = true
	return &CachePersistResponse{Path: "/tmp/cache.json", EntryCount: 7}, nil
}

// LoadCache 实现 ServiceController 接口（A6）
func (m *mockExtra) LoadCache(ctx context.Context) (*CachePersistResponse, error) {
	m.cacheLoaded = true
	return &CachePersistResponse{Path: "/tmp/cache.json", Restored: 7, EntryCount: 7}, nil
}

// errCachePersistUnavailable 供需要错误路径的用例注入
var errCachePersistUnavailable = fmt.Errorf("cache persist unavailable")

// GetBlockedServices 实现 ServiceController 接口（B3）
func (m *mockExtra) GetBlockedServices(ctx context.Context) (*BlockedServicesResponse, error) {
	if m.blockedServicesErr {
		return nil, errBlockedServicesUnavailable
	}
	if m.blockedServices != nil {
		return m.blockedServices, nil
	}
	return &BlockedServicesResponse{
		Services: []core.BlockedService{
			{ID: "bilibili", Name: "Bilibili", Group: "streaming", RuleN: 2,
				Source: "service:bilibili"},
		},
		Groups:         []core.BlockedServiceGroup{{ID: "streaming", Name: "流媒体", Count: 1}},
		BlockedIDs:     []string{},
		Schedules:      map[string][]core.BlockingSchedule{},
		ScheduleStates: []core.ServiceScheduleState{},
	}, nil
}

// ConfigureBlockedServices 实现 ServiceController 接口（B3）
func (m *mockExtra) ConfigureBlockedServices(ctx context.Context, req ConfigureBlockedServicesRequest) error {
	if m.blockedServicesErr {
		return errBlockedServicesUnavailable
	}
	m.blockedServicesUpdated = true
	m.lastServicesReq = req
	return nil
}

// errBlockedServicesUnavailable 供需要错误路径的用例注入
var errBlockedServicesUnavailable = fmt.Errorf("blocked services unavailable")

// GetZoneConfig 实现 ServiceController 接口（B5）
func (m *mockExtra) GetZoneConfig(ctx context.Context) (*ZoneConfigResponse, error) {
	if m.zoneErr {
		return nil, errZoneUnavailable
	}
	if m.zoneConfig != nil {
		return m.zoneConfig, nil
	}
	return &ZoneConfigResponse{
		Enabled:    false,
		TTL:        300,
		Zones:      []core.ZoneEntry{},
		States:     []core.ZoneState{},
		MaxZones:   core.MaxZoneCount,
		MaxRecords: core.MaxZoneRecords,
	}, nil
}

// ConfigureZone 实现 ServiceController 接口（B5）
func (m *mockExtra) ConfigureZone(ctx context.Context, req ConfigureZoneRequest) error {
	if m.zoneErr {
		return errZoneUnavailable
	}
	m.zoneUpdated = true
	m.lastZoneReq = req
	return nil
}

// errZoneUnavailable 供需要错误路径的用例注入
var errZoneUnavailable = fmt.Errorf("zone unavailable")

// GetSafeBrowsing 实现 ServiceController 接口（B6）
func (m *mockExtra) GetSafeBrowsing(ctx context.Context) (*SafeBrowsingResponse, error) {
	if m.safeBrowsingErr {
		return nil, errSafeBrowsingUnavailable
	}
	if m.safeBrowsing != nil {
		return m.safeBrowsing, nil
	}
	return &SafeBrowsingResponse{
		Config:    core.DefaultSafeBrowsingConfig(),
		BlockMode: core.BlockModeNullIP,
	}, nil
}

// ConfigureSafeBrowsing 实现 ServiceController 接口（B6）
func (m *mockExtra) ConfigureSafeBrowsing(ctx context.Context, req ConfigureSafeBrowsingRequest) error {
	if m.safeBrowsingErr {
		return errSafeBrowsingUnavailable
	}
	m.safeBrowsingUpdated = true
	m.lastSafeBrowsingReq = req
	return nil
}

// errSafeBrowsingUnavailable 供需要错误路径的用例注入
var errSafeBrowsingUnavailable = fmt.Errorf("safe browsing unavailable")

// GetEncryptedDNS 实现 ServiceController 接口（C1）
func (m *mockExtra) GetEncryptedDNS(ctx context.Context) (*EncryptedDNSStatusResponse, error) {
	if m.encryptedErr {
		return nil, errEncryptedUnavailable
	}
	if m.encrypted != nil {
		return m.encrypted, nil
	}
	return &EncryptedDNSStatusResponse{
		Config:         core.DefaultEncryptedDNSConfig(),
		Cert:           core.CertInfo{Source: core.CertSourceSelfSigned},
		DefaultDoTPort: core.DefaultDoTPort,
		DefaultDoHPort: core.DefaultDoHPort,
		DefaultDoQPort: core.DefaultDoQPort,
		DefaultDoHPath: core.DefaultDoHPath,
	}, nil
}

// ConfigureEncryptedDNS 实现 ServiceController 接口（C1）
func (m *mockExtra) ConfigureEncryptedDNS(ctx context.Context, req ConfigureEncryptedDNSRequest) error {
	if m.encryptedErr {
		return errEncryptedUnavailable
	}
	m.encryptedUpdated = true
	m.lastEncryptedReq = req
	return nil
}

// GenerateEncryptedCert 实现 ServiceController 接口（C1）
func (m *mockExtra) GenerateEncryptedCert(ctx context.Context, req GenerateCertRequest) error {
	if m.encryptedErr {
		return errEncryptedUnavailable
	}
	m.certGenerated = true
	m.lastCertGenReq = req
	return nil
}

// ImportEncryptedCert 实现 ServiceController 接口（C1）
func (m *mockExtra) ImportEncryptedCert(ctx context.Context, req ImportCertRequest) error {
	if m.encryptedErr {
		return errEncryptedUnavailable
	}
	m.certImported = true
	m.lastCertImportReq = req
	return nil
}

// errEncryptedUnavailable 供需要错误路径的用例注入
var errEncryptedUnavailable = fmt.Errorf("encrypted dns unavailable")

// BuildEncryptedMobileConfig 实现 ServiceController 接口（C6）
func (m *mockExtra) BuildEncryptedMobileConfig(ctx context.Context, protocol string) ([]byte, error) {
	if m.mobileConfigErr {
		return nil, errEncryptedUnavailable
	}
	m.mobileConfigProtocol = protocol
	if m.mobileConfigData != nil {
		return m.mobileConfigData, nil
	}
	return []byte(`<plist version="1.0"></plist>`), nil
}

// ConfigureEncryptedACL 实现 ServiceController 接口（C7）
func (m *mockExtra) ConfigureEncryptedACL(ctx context.Context, req ConfigureACLRequest) error {
	if m.aclWriteErr {
		return errEncryptedUnavailable
	}
	m.aclUpdated = true
	m.lastACLReq = req
	return nil
}
