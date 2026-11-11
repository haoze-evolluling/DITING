package querylog

import "sync"

// ring 定长内存环形缓冲，承载近期查询记录以支持快速检索。
//
// 采用覆盖写策略：写满后新记录覆盖最旧记录，读取始终保持"旧→新"有序，
// 检索时自尾向前遍历以便快速命中最近记录。
type ring struct {
	mu      sync.RWMutex
	buf     []Record
	start   int // 最旧元素下标
	size    int // 当前元素数量
	maxSize int
	total   uint64 // 累计写入条数（用于淘汰与展示）
}

// newRing 创建容量为 maxSize 的环形缓冲（maxSize <= 0 时回落默认值）。
func newRing(maxSize int) *ring {
	if maxSize <= 0 {
		maxSize = DefaultMaxEntries
	}
	return &ring{
		buf:     make([]Record, maxSize),
		maxSize: maxSize,
	}
}

// append 写入一条记录；写满时覆盖最旧记录。
func (r *ring) append(rec Record) {
	if r == nil {
		return
	}
	r.mu.Lock()
	defer r.mu.Unlock()

	if r.size < r.maxSize {
		r.buf[(r.start+r.size)%r.maxSize] = rec
		r.size++
	} else {
		// 覆盖最旧位置并顺移起始指针
		r.buf[r.start] = rec
		r.start = (r.start + 1) % r.maxSize
	}
	r.total++
}

// at 返回第 i 个逻辑元素（0 为最旧）。调用方须持有读锁。
func (r *ring) at(i int) Record {
	return r.buf[(r.start+i)%r.maxSize]
}

// len 返回当前元素数量。
func (r *ring) len() int {
	if r == nil {
		return 0
	}
	r.mu.RLock()
	defer r.mu.RUnlock()
	return r.size
}

// resize 调整容量（保留最近的 min(当前, maxSize) 条记录）。
func (r *ring) resize(maxSize int) {
	if r == nil || maxSize <= 0 || maxSize == r.maxSize {
		return
	}
	r.mu.Lock()
	defer r.mu.Unlock()

	keep := r.size
	if keep > maxSize {
		keep = maxSize
	}
	newBuf := make([]Record, maxSize)
	for i := 0; i < keep; i++ {
		// 取最近 keep 条
		newBuf[i] = r.at(r.size - keep + i)
	}
	r.buf = newBuf
	r.start = 0
	r.size = keep
	r.maxSize = maxSize
}

// clear 清空全部内存记录但保留容量配置。
func (r *ring) clear() {
	if r == nil {
		return
	}
	r.mu.Lock()
	defer r.mu.Unlock()
	r.buf = make([]Record, r.maxSize)
	r.start = 0
	r.size = 0
}

// search 在内存环内按条件检索并应用 offset/limit。
//
// 返回的匹配集合按"新→旧"（时间倒序）排列；Total 为环内全部命中数。
// 注意：分页只允许在最外层（QueryLog.Search）做一次，调用方若需自行分页
// 应使用 searchAll。
func (r *ring) search(q SearchQuery) ([]Record, int) {
	all, total := r.searchAll(q)
	if q.Offset > 0 {
		if q.Offset >= len(all) {
			return nil, total
		}
		all = all[q.Offset:]
	}
	if q.Limit > 0 && len(all) > q.Limit {
		all = all[:q.Limit]
	}
	return all, total
}

// searchAll 返回内存环内全部命中（新→旧）及命中总数，不做分页截断。
//
// 自尾向前遍历以优先覆盖最近记录，命中 StartMs 窗口下界外时提前终止。
func (r *ring) searchAll(q SearchQuery) ([]Record, int) {
	if r == nil {
		return nil, 0
	}
	r.mu.RLock()
	defer r.mu.RUnlock()

	if r.size == 0 {
		return nil, 0
	}

	matched := make([]Record, 0, 64)
	total := 0
	for i := r.size - 1; i >= 0; i-- {
		rec := r.at(i)
		// 时间窗口下界：更旧记录无需再扫
		if q.StartMs > 0 && rec.Timestamp < q.StartMs {
			break
		}
		if !q.matches(rec) {
			continue
		}
		total++
		matched = append(matched, rec)
	}
	return matched, total
}

// oldestTimestamp 返回环内最旧记录的时间戳；空环返回 0。
//
// 用于划清"内存覆盖范围"与"落盘历史"的边界，避免文件回退重复计入。
func (r *ring) oldestTimestamp() int64 {
	if r == nil {
		return 0
	}
	r.mu.RLock()
	defer r.mu.RUnlock()
	if r.size == 0 {
		return 0
	}
	return r.at(0).Timestamp
}
