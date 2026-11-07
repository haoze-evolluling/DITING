package core

import (
	"io"
	"net"
	"os"
	"path/filepath"
	"runtime"
	"sync"

	"github.com/miekg/dns"
)

// DefaultHostsTTL 本地 hosts 映射记录的默认 TTL 秒数
const DefaultHostsTTL uint32 = 60

// HostsConfig Hosts 解析器配置
type HostsConfig struct {
	Enabled       bool     `json:"enabled"`
	UseSystemHost bool     `json:"useSystemHost"` // 是否加载操作系统默认 hosts 文件
	CustomFiles   []string `json:"customFiles"`   // 自定义 hosts 文件路径列表
	TTL           uint32   `json:"ttl"`           // 返回记录的 TTL，默认 60
}

// DefaultHostsConfig 默认 hosts 配置
func DefaultHostsConfig() HostsConfig {
	return HostsConfig{
		Enabled:       true,
		UseSystemHost: true,
		CustomFiles:   []string{},
		TTL:           DefaultHostsTTL,
	}
}

// SystemHostsPath 获取当前操作系统的主机 hosts 文件绝对路径
func SystemHostsPath() string {
	if runtime.GOOS == "windows" {
		sysRoot := os.Getenv("SystemRoot")
		if sysRoot == "" {
			sysRoot = `C:\Windows`
		}
		return filepath.Join(sysRoot, "System32", "drivers", "etc", "hosts")
	}
	return "/etc/hosts"
}

// HostsResolver 本地系统与自定义 Hosts 文件解析器
// 借鉴自 blocky (hosts_file_resolver.go) 与 AdGuard Home
//
// 解析与查表都在 Rust 内核（rust/diting-hosts-core）里：这里只保留配置、TTL、
// 以及把内核回传的地址拼成 dns.RR 的那一层。内核里的一张表是不可变的，
// 热重载先建新表、再在写锁内换指针并释放旧表，旧表不会在有查询在飞时被释放。
type HostsResolver struct {
	mu      sync.RWMutex
	enabled bool
	ttl     uint32
	// sources 是当前这张表由什么构建而来：Reload 重读 loadedFiles，
	// LoadFile / LoadReader 在其后追加，UpdateConfig 整体替换成新配置。
	sources     []hostsSource
	loadedFiles []string
	kernel      *hostsNativeTable
}

// NewHostsResolver 创建并初始化 Hosts 解析器
func NewHostsResolver(cfg HostsConfig) (*HostsResolver, error) {
	ttl := cfg.TTL
	if ttl == 0 {
		ttl = DefaultHostsTTL
	}
	resolver := &HostsResolver{
		enabled: cfg.Enabled,
		ttl:     ttl,
	}

	if cfg.Enabled {
		// 读取失败的文件只是跳过（原实现的 LoadFile 也是这样，错误被忽略）；
		// 建不出表是内核缺失这类硬错误，必须让服务启动失败。
		table, sources, loaded, err := buildHostsTable(hostsConfigSources(cfg))
		if table == nil {
			return nil, err
		}
		resolver.kernel = table
		resolver.sources = sources
		resolver.loadedFiles = loaded
	}
	return resolver, nil
}

// IsEnabled 获取 Hosts 解析器当前是否启用
func (r *HostsResolver) IsEnabled() bool {
	r.mu.RLock()
	defer r.mu.RUnlock()
	return r.enabled
}

// UpdateConfig 动态更新配置并热重载映射文件
//
// 先在新映射上构建完整结果、最后一次性换指针：旧实现在锁内清空映射、
// 解锁后再逐文件重填，重填窗口内所有内网域名既解析不出、也不再被判定
// 为本地权威，会被原样转发到公网上游（BUG-59）。
func (r *HostsResolver) UpdateConfig(cfg HostsConfig) error {
	table, sources, loaded, err := buildHostsTable(hostsConfigSources(cfg))
	if table == nil {
		return err
	}

	r.mu.Lock()
	r.enabled = cfg.Enabled
	if cfg.TTL > 0 {
		r.ttl = cfg.TTL
	}
	old := r.kernel
	r.kernel, r.sources, r.loadedFiles = table, sources, loaded
	r.mu.Unlock()
	old.free()
	return err
}

// Reload 重新加载所有已注册的 hosts 文件
//
// 重读的是上次真正读成功的文件（加上 LoadReader 传入的文本），
// 与旧实现拿 loadedFiles 逐条 parse 的语义一致。
func (r *HostsResolver) Reload() error {
	r.mu.RLock()
	sources := reloadHostsSources(r.loadedFiles, r.sources)
	r.mu.RUnlock()

	table, sources, loaded, err := buildHostsTable(sources)
	if table == nil {
		return err
	}

	r.mu.Lock()
	old := r.kernel
	r.kernel, r.sources, r.loadedFiles = table, sources, loaded
	r.mu.Unlock()
	old.free()
	return err
}

// LoadFile 加载并解析指定的 hosts 文件内容
func (r *HostsResolver) LoadFile(path string) error {
	r.mu.RLock()
	sources := appendHostsSource(r.sources, hostsSourceFile(path))
	r.mu.RUnlock()
	table, sources, loaded, err := buildHostsTable(sources)
	if table == nil {
		return err
	}

	r.mu.Lock()
	old := r.kernel
	r.kernel, r.sources, r.loadedFiles = table, sources, loaded
	r.mu.Unlock()
	old.free()
	return err
}

// LoadReader 从指定 Reader 加载 hosts 格式文本
func (r *HostsResolver) LoadReader(rd io.Reader) {
	text, err := io.ReadAll(rd)
	if err != nil {
		return
	}
	r.loadText(string(text))
}

// loadText 加载一段 hosts 文本（缓存的是文本本身，重载时不需要再去读一次）。
func (r *HostsResolver) loadText(text string) {
	r.mu.RLock()
	sources := appendHostsSource(r.sources, hostsSourceText(text))
	r.mu.RUnlock()
	table, sources, loaded, _ := buildHostsTable(sources)
	if table == nil {
		return
	}

	r.mu.Lock()
	old := r.kernel
	r.kernel, r.sources, r.loadedFiles = table, sources, loaded
	r.mu.Unlock()
	old.free()
}

// hostsConfigSources 把一份配置摊平成内核的 source 列表。
//
// 禁用时不带任何文件：旧实现的 emptyHostsMaps 也是这个意思（空表、空文件列表、
// 不往上抛读取错误）。UpdateConfig 会丢掉 LoadReader 加载过的文本，
// 与旧实现整体替换映射的行为一致。
func hostsConfigSources(cfg HostsConfig) []hostsSource {
	if !cfg.Enabled {
		return nil
	}
	sources := make([]hostsSource, 0, len(cfg.CustomFiles)+1)
	if cfg.UseSystemHost {
		sources = append(sources, hostsSourceFile(SystemHostsPath()))
	}
	for _, file := range cfg.CustomFiles {
		sources = append(sources, hostsSourceFile(file))
	}
	return sources
}

// reloadHostsSources 用上次读成功的文件重建 source 列表，保留其中的文本来源。
func reloadHostsSources(loaded []string, previous []hostsSource) []hostsSource {
	sources := make([]hostsSource, 0, len(loaded)+1)
	for _, file := range loaded {
		sources = append(sources, hostsSourceFile(file))
	}
	for _, source := range previous {
		if !source.isFile() {
			sources = append(sources, source)
		}
	}
	return sources
}

func appendHostsSource(sources []hostsSource, source hostsSource) []hostsSource {
	next := make([]hostsSource, len(sources), len(sources)+1)
	copy(next, sources)
	return append(next, source)
}

// buildHostsTable 构建一张新表；返回值里的 sources 是内核接受的那一份
// （读取失败的文件不在 loadedFiles 里，但仍在 sources 里，方便后续重载重试）。
func buildHostsTable(sources []hostsSource) (*hostsNativeTable, []hostsSource, []string, error) {
	table, err := buildHostsNativeTable(sources)
	if err != nil {
		return nil, sources, nil, err
	}
	loaded, readErr := table.info()
	return table, sources, loaded, readErr
}

// HasDomain 检查本地 hosts 是否收录了指定域名（用于判定是否可提供权威 NODATA）
func (r *HostsResolver) HasDomain(domain string) bool {
	r.mu.RLock()
	defer r.mu.RUnlock()
	return r.kernel.contains(domain)
}

// Lookup 正向解析 domain
func (r *HostsResolver) Lookup(domain string, qtype uint16) []dns.RR {
	r.mu.RLock()
	defer r.mu.RUnlock()

	addresses, err := r.kernel.lookup(domain, qtype)
	if err != nil {
		// 句柄建好之后单次查询不应失败（只有 ABI 错配才会走到这里）。
		return nil
	}
	if len(addresses) == 0 {
		return nil
	}

	fqdn := dns.Fqdn(domain)
	records := make([]dns.RR, 0, len(addresses))
	for _, address := range addresses {
		header := dns.RR_Header{Name: fqdn, Rrtype: qtype, Class: dns.ClassINET, Ttl: r.ttl}
		switch qtype {
		case dns.TypeA:
			if len(address) != net.IPv4len {
				continue
			}
			records = append(records, &dns.A{Hdr: header, A: net.IP(address)})
		case dns.TypeAAAA:
			if len(address) != net.IPv6len {
				continue
			}
			records = append(records, &dns.AAAA{Hdr: header, AAAA: net.IP(address)})
		}
	}
	return records
}

// LookupPTR 反向解析 IP 对应的 PTR 记录（返回所有关联主机名别名）
func (r *HostsResolver) LookupPTR(arpaName string) []dns.RR {
	r.mu.RLock()
	defer r.mu.RUnlock()

	hosts := r.kernel.ptr(arpaName)
	if len(hosts) == 0 {
		return nil
	}

	fqdn := dns.Fqdn(arpaName)
	records := make([]dns.RR, 0, len(hosts))
	for _, host := range hosts {
		records = append(records, &dns.PTR{
			Hdr: dns.RR_Header{Name: fqdn, Rrtype: dns.TypePTR, Class: dns.ClassINET, Ttl: r.ttl},
			Ptr: dns.Fqdn(host),
		})
	}
	return records
}

// LookupReverse 实现 ReverseLookuper 接口，根据 IP 反向查询首选主机名
func (r *HostsResolver) LookupReverse(ip net.IP) string {
	if ip == nil {
		return ""
	}
	if v4 := ip.To4(); v4 != nil {
		ip = v4
	}
	r.mu.RLock()
	defer r.mu.RUnlock()
	return r.kernel.reverse(ip)
}

// ParseIPFromArpa 从 .in-addr.arpa 或 .ip6.arpa 解析出原生 IP
//
// 解析器在内核里：hosts 反查与重写引擎的反查都要它，留两份迟早会在
// 「多少段标签才算合法」这类细节上分叉。
func ParseIPFromArpa(arpa string) net.IP {
	address, ok := hostsParseArpa(arpa)
	if !ok {
		return nil
	}
	return net.IP(address)
}
