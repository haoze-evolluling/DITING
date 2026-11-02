package ipc

// CachePersistResponse 缓存落盘状态与操作结果
type CachePersistResponse struct {
	// Path 为生效的落盘文件路径
	Path string `json:"path"`
	// Restored 为本次从文件恢复的条目数（仅 Load 时有意义）
	Restored int `json:"restored,omitempty"`
	// EntryCount 为操作完成后内存中的条目总数
	EntryCount int `json:"entryCount"`
	// PersistOn 表示是否开启定期落盘
	PersistOn bool `json:"persistOn"`
	// IntervalSec 为定时落盘间隔（秒）
	IntervalSec int64 `json:"intervalSec"`
	// LastError 为最近一次落盘失败的原因（无失败时为空串）
	LastError string `json:"lastError,omitempty"`
	// ExcludeRules 为当前生效的排除正则
	ExcludeRules []string `json:"excludeRules,omitempty"`
	// ExcludeHits 为被排除规则拦下、绕过缓存的查询累计数
	ExcludeHits uint64 `json:"excludeHits"`
}
