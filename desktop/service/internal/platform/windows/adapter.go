//go:build windows

package windows

import (
	"context"
	"strings"

	"github.com/haoze-evolluling/diting/server/internal/platform"
)

// NativeAdapterScanner 基于 Windows 原生 API 的物理网卡扫描器。
//
// AdapterInfo / AdapterScanner 等跨平台类型与接口定义于 internal/platform，
// 本类型仅负责 Windows 侧的 GetAdaptersAddresses 原生枚举实现。
type NativeAdapterScanner struct{}

// NewAdapterScanner 创建网卡扫描器。
//
// executor 形参保留是为了与跨平台构造签名一致；Windows 侧全部走原生 API，
// 不执行任何外部命令，因此不使用它（此前实现了却静默丢弃，容易让人以为
// 注入的执行器会生效）。
func NewAdapterScanner(_ platform.CommandExecutor) *NativeAdapterScanner {
	return &NativeAdapterScanner{}
}

// ScanAll 枚举系统中的所有网卡（调用 Windows 原生 API）。
func (s *NativeAdapterScanner) ScanAll(ctx context.Context) ([]platform.AdapterInfo, error) {
	return scanAdaptersNative(ctx)
}

// GetActivePhysicalAdapters 筛选出当前处于 Up 状态且具备有效 IPv4 默认网关的活动物理网卡。
func (s *NativeAdapterScanner) GetActivePhysicalAdapters(ctx context.Context) ([]platform.AdapterInfo, error) {
	all, err := s.ScanAll(ctx)
	if err != nil {
		return nil, err
	}

	filtered := make([]platform.AdapterInfo, 0, len(all))
	for _, a := range all {
		if !a.IsPhysical {
			continue
		}
		if !strings.EqualFold(a.Status, "Up") {
			continue
		}
		if !platform.HasValidIPv4Gateway(a.Gateway) {
			continue
		}
		filtered = append(filtered, a)
	}
	return filtered, nil
}
