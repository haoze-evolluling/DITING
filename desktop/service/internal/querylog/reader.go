package querylog

import (
	"bytes"
	"encoding/json"
	"io"
	"os"
	"strings"
	"time"
)

// 反向读取与文件日期解析参数。
const (
	// readBlockSize 反向读取文件时的块大小
	readBlockSize = 64 * 1024
	// maxLineSize 单行 JSON 允许的最大长度，防御损坏文件导致的内存膨胀
	maxLineSize = 64 * 1024
	// dayMs 一天的毫秒数
	dayMs = int64(24 * 60 * 60 * 1000)
)

// readFileReverse 自文件末尾向前逐行读取 JSON-Lines 记录。
//
// 回调 fn 按"新→旧"顺序接收记录；返回 false 表示提前终止读取。
// 无法解析的行（半行写入 / 损坏）直接跳过。
func readFileReverse(path string, fn func(Record) bool) error {
	f, err := os.Open(path)
	if err != nil {
		return err
	}
	defer f.Close()

	fi, err := f.Stat()
	if err != nil {
		return err
	}
	size := fi.Size()
	if size == 0 {
		return nil
	}

	buf := make([]byte, readBlockSize)
	var orphan []byte // 上一块开头残留的半行
	stopped := false

	for pos := size; pos > 0 && !stopped; {
		n := int64(readBlockSize)
		if n > pos {
			n = pos
		}
		pos -= n
		if _, err := f.ReadAt(buf[:n], pos); err != nil && err != io.EOF {
			return err
		}

		combined := make([]byte, 0, int(n)+len(orphan))
		combined = append(combined, buf[:n]...)
		combined = append(combined, orphan...)

		lines := bytes.Split(combined, []byte{'\n'})
		orphan = append(orphan[:0], lines[0]...)

		for i := len(lines) - 1; i >= 1; i-- {
			if emitLine(lines[i], fn) {
				stopped = true
				break
			}
		}
	}

	if !stopped && len(orphan) > 0 {
		emitLine(orphan, fn)
	}
	return nil
}

// emitLine 解析一行并回调；返回 true 表示请求停止。
func emitLine(line []byte, fn func(Record) bool) bool {
	line = bytes.TrimSpace(line)
	if len(line) == 0 || len(line) > maxLineSize {
		return false
	}
	var rec Record
	if err := json.Unmarshal(line, &rec); err != nil {
		return false
	}
	return !fn(rec)
}

// searchFilesReverse 跨多个日志文件自新到旧检索，命中经 collect 回调（新→旧顺序）。
//
// needCount 为 true 时扫描全部命中以得到准确的 Total（分页页码依赖它）；
// 为 false 时只做「采满候选即停」的快速检索，返回的 total 仅统计到停止点。
// collect 返回 true 表示候选已足够，可提前停止。
// 早于检索时间窗口下界的整份文件会被跳过。
func searchFilesReverse(paths []string, q SearchQuery, need int, needCount bool, collect func(Record) bool) int {
	total := 0
	for i := len(paths) - 1; i >= 0; i-- {
		path := paths[i]
		if q.StartMs > 0 {
			if fm := fileDateMs(path); fm > 0 && fm+dayMs <= q.StartMs {
				continue
			}
		}
		stopped := false
		_ = readFileReverse(path, func(rec Record) bool {
			if q.StartMs > 0 && rec.Timestamp < q.StartMs {
				return false // 该文件更旧记录均不满足，结束本文件
			}
			if !q.matches(rec) {
				return true
			}
			total++
			// 候选采满后仍回调：计数模式要继续扫描以得到准确 Total，
			// 回调方自行决定是否追加（searchFiles 按 len(hits) 判定）。
			// 快速模式（needCount=false）到此即可停止。
			if !needCount && need > 0 && total > need {
				return false
			}
			if collect(rec) {
				stopped = true
				return false
			}
			return true
		})
		if stopped {
			return total
		}
	}
	return total
}

// fileDateMs 从文件名解析所属日期（本地时区当天 00:00 的毫秒时间戳）。
// 解析失败返回 0。
func fileDateMs(path string) int64 {
	base := path
	if i := strings.LastIndexAny(base, `/\`); i >= 0 {
		base = base[i+1:]
	}
	day := strings.TrimSuffix(strings.TrimPrefix(base, writerFilePrefix), writerFileSuffix)
	t, err := time.ParseInLocation(dayLayout, day, time.Local)
	if err != nil {
		return 0
	}
	return t.UnixMilli()
}
