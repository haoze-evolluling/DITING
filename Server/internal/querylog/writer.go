package querylog

import (
	"bufio"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"sync"
	"time"
)

// 落盘写入参数。
const (
	// writerQueueSize 记录队列缓冲长度，写满即丢弃以保护 DNS 热路径
	writerQueueSize = 4096
	// writerFlushLines 达到该行数即刷新缓冲
	writerFlushLines = 256
	// writerFlushInterval 定时刷新间隔
	writerFlushInterval = time.Second
	// writerFilePrefix 日志文件前缀
	writerFilePrefix = "querylog-"
	// writerFileSuffix 日志文件后缀
	writerFileSuffix = ".jsonl"
	// dayLayout 按天滚动的日期格式
	dayLayout = "20060102"
)

// writer 异步按天滚动的 JSON-Lines 追加写入器。
//
// 单 goroutine 独占文件句柄；enqueue 为非阻塞投递，队列满时直接丢弃，
// 保证绝不阻塞 DNS 处理路径（与 ipc.Server.Broadcast 的丢弃策略一致）。
type writer struct {
	dir           string
	retentionDays int
	ch            chan Record
	clearReq      chan chan error // 删除落盘文件请求（由 run goroutine 关句柄后执行）
	stop          chan struct{}
	done          chan struct{}
	closeOnce     sync.Once

	// 仅 run goroutine 访问
	file    *os.File
	bw      *bufio.Writer
	curDay  string
	pending int
	lastErr error

	// clock 返回当前时间，run goroutine 与 cleanup 共用以支持测试注入
	clock func() time.Time
}

// writerOptions 写入器的可选项（当前仅测试用于注入时钟）。
type writerOptions struct {
	clock func() time.Time
}

// newWriter 创建写入器并确保目录可写；目录不可写时返回错误以便调用方降级。
func newWriter(dir string, retentionDays int, opts writerOptions) (*writer, error) {
	if strings.TrimSpace(dir) == "" {
		return nil, fmt.Errorf("查询日志目录为空")
	}
	if err := os.MkdirAll(dir, 0755); err != nil {
		return nil, fmt.Errorf("创建查询日志目录失败: %w", err)
	}
	// 预检可写性：创建并删除一个探针文件
	probe := filepath.Join(dir, ".probe")
	if err := os.WriteFile(probe, []byte{}, 0644); err != nil {
		return nil, fmt.Errorf("查询日志目录不可写: %w", err)
	}
	_ = os.Remove(probe)

	w := &writer{
		dir:           dir,
		retentionDays: retentionDays,
		ch:            make(chan Record, writerQueueSize),
		clearReq:      make(chan chan error, 1),
		stop:          make(chan struct{}),
		done:          make(chan struct{}),
		clock:         time.Now,
	}
	// 允许测试注入时钟
	if opts.clock != nil {
		w.clock = opts.clock
	}
	go w.run()
	return w, nil
}

// enqueue 非阻塞投递一条记录；队列满时丢弃并返回 false。
func (w *writer) enqueue(r Record) bool {
	if w == nil {
		return false
	}
	select {
	case w.ch <- r:
		return true
	default:
		return false
	}
}

// run 消费队列、按天轮转并定时刷新。
func (w *writer) run() {
	defer close(w.done)

	ticker := time.NewTicker(writerFlushInterval)
	defer ticker.Stop()

	// 启动即做一次留存清理
	w.cleanup()

	for {
		select {
		case rec := <-w.ch:
			w.writeRecord(rec)
		case reply := <-w.clearReq:
			reply <- w.removeFilesLocked()
		case <-ticker.C:
			w.rotateIfNeeded()
			w.flush()
		case <-w.stop:
			// 排空队列后收尾
			for {
				select {
				case rec := <-w.ch:
					w.writeRecord(rec)
					continue
				default:
				}
				break
			}
			w.flush()
			w.closeFile()
			return
		}
	}
}

// writeRecord 将单条记录序列化为一行 JSON 写入缓冲。
func (w *writer) writeRecord(r Record) {
	data, err := json.Marshal(r)
	if err != nil {
		w.lastErr = err
		return
	}
	if err := w.ensureFileLocked(); err != nil {
		w.lastErr = err
		return
	}
	if _, err := w.bw.Write(data); err != nil {
		w.lastErr = err
		return
	}
	if err := w.bw.WriteByte('\n'); err != nil {
		w.lastErr = err
		return
	}
	w.pending++
	if w.pending >= writerFlushLines {
		w.flush()
	}
}

// ensureFileLocked 确保当天文件句柄已就绪。
func (w *writer) ensureFileLocked() error {
	day := w.clock().Format(dayLayout)
	if w.file != nil && w.curDay == day {
		return nil
	}
	// 跨天：先落盘并关闭旧文件
	w.flush()
	w.closeFile()

	path := filepath.Join(w.dir, writerFilePrefix+day+writerFileSuffix)
	f, err := os.OpenFile(path, os.O_CREATE|os.O_APPEND|os.O_WRONLY, 0644)
	if err != nil {
		return err
	}
	w.file = f
	w.bw = bufio.NewWriterSize(f, 64*1024)
	w.curDay = day
	return nil
}

// rotateIfNeeded 在定时刷新时检查跨天并轮转文件。
func (w *writer) rotateIfNeeded() {
	if w.file == nil {
		return
	}
	if w.clock().Format(dayLayout) != w.curDay {
		w.flush()
		w.closeFile()
	}
}

// flush 刷新缓冲。
func (w *writer) flush() {
	if w.bw != nil {
		_ = w.bw.Flush()
		w.pending = 0
	}
}

// closeFile 关闭当前文件句柄。
func (w *writer) closeFile() {
	if w.bw != nil {
		_ = w.bw.Flush()
		w.bw = nil
	}
	if w.file != nil {
		_ = w.file.Close()
		w.file = nil
	}
}

// cleanup 删除超过留存期的日志文件。
func (w *writer) cleanup() {
	if w.retentionDays <= 0 {
		return
	}
	cutoff := w.clock().AddDate(0, 0, -w.retentionDays)
	entries, err := os.ReadDir(w.dir)
	if err != nil {
		return
	}
	for _, e := range entries {
		name := e.Name()
		if !strings.HasPrefix(name, writerFilePrefix) || !strings.HasSuffix(name, writerFileSuffix) {
			continue
		}
		day := strings.TrimSuffix(strings.TrimPrefix(name, writerFilePrefix), writerFileSuffix)
		fileDay, err := parseDay(day)
		if err != nil {
			continue
		}
		if fileDay.Before(cutoff) {
			_ = os.Remove(filepath.Join(w.dir, name))
		}
	}
}

// parseDay 按本地时区解析 YYYYMMDD 日期串。
func parseDay(day string) (time.Time, error) {
	return time.ParseInLocation(dayLayout, day, time.Local)
}

// removeFiles 请求写入器关闭当天句柄并删除全部日志文件。
//
// 删除必须由持有句柄的 run goroutine 执行：Windows 上被占用文件无法删除，
// POSIX 上删除后旧句柄会变成孤儿 inode，后续写入全部丢失。
func (w *writer) removeFiles() error {
	if w == nil {
		return nil
	}
	reply := make(chan error, 1)
	select {
	case w.clearReq <- reply:
	case <-w.done:
		return nil
	}
	select {
	case err := <-reply:
		return err
	case <-w.done:
		return nil
	}
}

// removeFilesLocked 在 run goroutine 内关闭当前文件并删除全部日志文件。
func (w *writer) removeFilesLocked() error {
	w.closeFile()
	var errs []string
	for _, p := range w.listFiles() {
		if err := os.Remove(p); err != nil {
			errs = append(errs, fmt.Sprintf("%s: %v", filepath.Base(p), err))
		}
	}
	if len(errs) > 0 {
		return fmt.Errorf("删除查询日志文件失败: %s", strings.Join(errs, "; "))
	}
	return nil
}

// close 停止写入器并落盘。
func (w *writer) close() error {
	if w == nil {
		return nil
	}
	w.closeOnce.Do(func() {
		close(w.stop)
		<-w.done
	})
	return nil
}

// listFiles 返回按文件名（即日期）升序排列的日志文件绝对路径。
func (w *writer) listFiles() []string {
	entries, err := os.ReadDir(w.dir)
	if err != nil {
		return nil
	}
	var names []string
	for _, e := range entries {
		name := e.Name()
		if strings.HasPrefix(name, writerFilePrefix) && strings.HasSuffix(name, writerFileSuffix) {
			names = append(names, name)
		}
	}
	sort.Strings(names)
	paths := make([]string, 0, len(names))
	for _, n := range names {
		paths = append(paths, filepath.Join(w.dir, n))
	}
	return paths
}
