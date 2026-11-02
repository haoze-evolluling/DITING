package querylog

import (
	"sync"
	"time"
)

// QueryLog 查询历史与统计门面，聚合内存环、统计收集器与异步落盘写入器。
//
// 所有对外方法均线程安全；Record 位于 DNS 热路径，须保持"短锁 + 非阻塞"。
type QueryLog struct {
	mu        sync.RWMutex
	cfg       QueryLogConfig
	ring      *ring
	collector *Collector
	writer    *writer
	fileOK    bool // 落盘是否可用（目录不可写时为 false，降级纯内存）
}

// New 创建查询日志门面。落盘不可用时自动降级为纯内存模式，不返回错误。
func New(cfg QueryLogConfig) *QueryLog {
	NormalizeQueryLogConfig(&cfg)
	q := &QueryLog{
		cfg:       cfg,
		ring:      newRing(cfg.MaxEntries),
		collector: NewCollector(),
	}
	q.initWriterLocked()
	return q
}

// initWriterLocked 依据当前配置尝试初始化落盘写入器。
func (q *QueryLog) initWriterLocked() {
	if q.writer != nil {
		_ = q.writer.close()
		q.writer = nil
	}
	q.fileOK = false
	if !q.cfg.FileEnabled {
		return
	}
	w, err := newWriter(q.cfg.DataDir, q.cfg.RetentionDays, writerOptions{})
	if err != nil {
		return
	}
	q.writer = w
	q.fileOK = true
}

// Record 记录一条查询（DNS 热路径）。未启用时立即返回。
func (q *QueryLog) Record(r Record) {
	if q == nil {
		return
	}
	q.mu.RLock()
	enabled := q.cfg.Enabled
	logClients := q.cfg.LogClients
	ringRef := q.ring
	collector := q.collector
	writerRef := q.writer
	fileOK := q.fileOK
	q.mu.RUnlock()

	if !enabled {
		return
	}

	r.Status = NormalizeStatus(r.Status)
	if r.Timestamp <= 0 {
		// 未显式提供时间戳时补齐，保证内存环、统计与落盘三处时间一致
		r.Timestamp = time.Now().UnixMilli()
	}
	if !logClients {
		r.ClientIP = ""
		r.ClientName = ""
	}

	ringRef.append(r)
	collector.Record(r)
	if fileOK && writerRef != nil {
		writerRef.enqueue(r)
	}
}

// Search 按条件检索查询历史：内存环覆盖近期，落盘文件覆盖更早的历史。
//
// 返回结果按时间"旧→新"排序，Total 为命中的记录总数。
func (q *QueryLog) Search(sq SearchQuery) SearchResult {
	if q == nil {
		return SearchResult{}
	}
	if sq.Limit <= 0 || sq.Limit > MaxSearchLimit {
		sq.Limit = MaxSearchLimit
	}
	if sq.Offset < 0 {
		sq.Offset = 0
	}

	q.mu.RLock()
	ringRef := q.ring
	writerRef := q.writer
	fileOK := q.fileOK
	q.mu.RUnlock()

	// 内存环返回全部命中（新→旧），分页统一在最外层做一次，避免双重偏移
	mem, memTotal := ringRef.searchAll(sq)

	// 内存结果不足以覆盖请求页时，回退扫描落盘文件补齐更早的历史
	var fileHits []Record // 新→旧
	var fileTotal int
	needFile := sq.IncludeFile && fileOK && writerRef != nil && memTotal < sq.Offset+sq.Limit+1
	if needFile {
		fileHits, fileTotal = searchFiles(writerRef, sq, memTotal, ringRef.oldestTimestamp())
	}

	total := memTotal + fileTotal
	// 合并（新→旧），再按 offset/limit 截取；结果保持"新→旧"（时间倒序）
	combined := make([]Record, 0, len(fileHits)+len(mem))
	combined = append(combined, fileHits...)
	combined = append(combined, mem...)

	start := sq.Offset
	if start > len(combined) {
		start = len(combined)
	}
	end := start + sq.Limit
	if end > len(combined) {
		end = len(combined)
	}
	page := combined[start:end]
	return SearchResult{Total: total, Entries: page}
}

// searchFiles 扫描落盘文件补齐更早的历史命中（返回新→旧顺序）。
//
// 以内存环最旧记录的时间为上界，仅扫描更旧的部分，避免与内存结果重复计数。
// 仅收集到 offset+limit 条候选后不再追加，但继续计数。
// searchFiles 扫描落盘文件补齐更早的历史命中（返回新→旧顺序）。
//
// 以内存环最旧记录的时间为上界，仅扫描更旧的部分，避免与内存结果重复计数。
// 返回的 total 是文件窗口内的全部命中数（不是本页候选数），保证翻页时 Total 稳定。
//
// 同一次调用里既需要「补齐本页候选」又需要「准确总数」：分页页码由 Total 算出，
// 若把「采满即停」当作总数，Total 会随 offset 增长、第 1 页永远没有下一页
// （BUG-65）。因此这里始终走计数模式，候选收够后继续扫描但不再追加。
func searchFiles(w *writer, sq SearchQuery, memTotal int, memOldest int64) ([]Record, int) {
	fileQ := sq
	if memOldest > 0 && (fileQ.EndMs == 0 || fileQ.EndMs > memOldest) {
		fileQ.EndMs = memOldest - 1
	}

	// 文件部分只需补足内存未覆盖的页内候选
	need := sq.Offset + sq.Limit - memTotal
	if need < 0 {
		need = 0
	}
	var hits []Record
	total := searchFilesReverse(w.listFiles(), fileQ, need, true, func(r Record) bool {
		if len(hits) >= need {
			return false // 已采足候选，继续计数但不追加
		}
		hits = append(hits, r)
		return false
	})
	return hits, total
}

// Stats 返回当前 24 小时滚动窗口的汇总统计。
func (q *QueryLog) Stats() Summary {
	if q == nil {
		return Summary{}
	}
	q.mu.RLock()
	collector := q.collector
	q.mu.RUnlock()
	return collector.Summary()
}

// PerHour 返回最近 24 小时的逐小时趋势数据点。
func (q *QueryLog) PerHour() []HourPoint {
	if q == nil {
		return nil
	}
	q.mu.RLock()
	collector := q.collector
	q.mu.RUnlock()
	return collector.PerHour()
}

// TopDomains 返回窗口内访问量最高的域名排行。
func (q *QueryLog) TopDomains(n int) []NameCount {
	return q.topFromCollector(n, func(c *Collector, n int) []NameCount { return c.TopDomains(n) })
}

// TopBlockedDomains 返回窗口内被拦截次数最高的域名排行。
func (q *QueryLog) TopBlockedDomains(n int) []NameCount {
	return q.topFromCollector(n, func(c *Collector, n int) []NameCount { return c.TopBlockedDomains(n) })
}

// TopClients 返回窗口内查询量最高的客户端排行。
func (q *QueryLog) TopClients(n int) []NameCount {
	return q.topFromCollector(n, func(c *Collector, n int) []NameCount { return c.TopClients(n) })
}

func (q *QueryLog) topFromCollector(n int, fn func(*Collector, int) []NameCount) []NameCount {
	if q == nil {
		return nil
	}
	q.mu.RLock()
	collector := q.collector
	q.mu.RUnlock()
	return fn(collector, n)
}

// Config 返回当前配置副本。
func (q *QueryLog) Config() QueryLogConfig {
	if q == nil {
		return QueryLogConfig{}
	}
	q.mu.RLock()
	defer q.mu.RUnlock()
	return q.cfg
}

// UpdateConfig 热更新配置：调整内存容量、落盘开关与留存策略。
func (q *QueryLog) UpdateConfig(cfg QueryLogConfig) error {
	if q == nil {
		return nil
	}
	NormalizeQueryLogConfig(&cfg)

	q.mu.Lock()
	defer q.mu.Unlock()

	q.cfg = cfg
	q.ring.resize(cfg.MaxEntries)

	needReinit := (q.writer == nil) != !cfg.FileEnabled ||
		(q.writer != nil && q.writer.dir != cfg.DataDir) ||
		(q.writer != nil && q.writer.retentionDays != cfg.RetentionDays)
	if needReinit {
		q.initWriterLocked()
	}
	return nil
}

// Clear 清空内存环与统计（可选同时清空落盘文件）。
//
// 删除落盘文件必须经由写入器关闭句柄后执行，否则 Windows 上删除失败、
// POSIX 上写入进入孤儿 inode；失败时返回聚合错误供调用方如实上报。
func (q *QueryLog) Clear(removeFiles bool) error {
	if q == nil {
		return nil
	}
	q.mu.RLock()
	ringRef := q.ring
	collector := q.collector
	writerRef := q.writer
	fileOK := q.fileOK
	q.mu.RUnlock()

	ringRef.clear()
	collector.Clear()

	if removeFiles && fileOK && writerRef != nil {
		return writerRef.removeFiles()
	}
	return nil
}

// Close 停止写入器并落盘。
func (q *QueryLog) Close() error {
	if q == nil {
		return nil
	}
	q.mu.Lock()
	w := q.writer
	q.writer = nil
	q.mu.Unlock()
	if w != nil {
		return w.close()
	}
	return nil
}
