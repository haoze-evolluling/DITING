package core

import (
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"strings"
)

// listFetchResult 规则源条件拉取结果
type listFetchResult struct {
	data         []byte // 200 时的新内容；304/传输失败时为 nil
	etag         string // 响应 ETag（可能为空）
	lastModified string // 响应 Last-Modified（可能为空）
	notModified  bool   // 上游返回 304，本地缓存仍有效
}

// httpStatusError 携带 HTTP 状态码的错误。
//
// 借鉴 blocky downloaded_cache：4xx/5xx 属于服务端明确拒绝，应照实报错而非沿用旧缓存；
// 仅传输层错误（超时/连接失败）才允许退回本地缓存。
type httpStatusError struct {
	code int
	url  string
}

func (e *httpStatusError) Error() string {
	return fmt.Sprintf("HTTP 状态码异常: %d (%s)", e.code, e.url)
}

// isTransientFetchError 判断是否为可退回本地缓存的传输类错误（非明确的 HTTP 错误码）。
func isTransientFetchError(err error) bool {
	if err == nil {
		return false
	}
	var se *httpStatusError
	return !errors.As(err, &se)
}

// fetchListContentConditional 以条件请求拉取规则源内容。
//
// 借鉴 blocky downloaded_cache 的 ETag + If-Modified-Since 协商：
// 携带上次的 ETag / Last-Modified 发起请求，命中 200 返回新内容，命中 304 复用本地副本，
// 从而避免每次刷新都整文件下载。本地文件源直接读取，不参与协商。
func (e *RuleEngine) fetchListContentConditional(urlStr, etag, lastModified string) (*listFetchResult, error) {
	if !strings.HasPrefix(urlStr, "http://") && !strings.HasPrefix(urlStr, "https://") {
		data, err := os.ReadFile(urlStr)
		if err != nil {
			return nil, err
		}
		return &listFetchResult{data: data}, nil
	}

	req, err := http.NewRequest(http.MethodGet, urlStr, nil)
	if err != nil {
		return nil, err
	}
	req.Header.Set("User-Agent", "DITING-DNS-Engine/1.0")
	if etag != "" {
		req.Header.Set("If-None-Match", etag)
	}
	if lastModified != "" {
		req.Header.Set("If-Modified-Since", lastModified)
	}

	resp, err := e.httpClient.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	switch {
	case resp.StatusCode == http.StatusNotModified:
		return &listFetchResult{notModified: true, etag: etag, lastModified: lastModified}, nil
	case resp.StatusCode != http.StatusOK:
		return nil, &httpStatusError{code: resp.StatusCode, url: urlStr}
	}

	data, err := io.ReadAll(io.LimitReader(resp.Body, 50*1024*1024))
	if err != nil {
		return nil, err
	}
	return &listFetchResult{
		data:         data,
		etag:         resp.Header.Get("ETag"),
		lastModified: resp.Header.Get("Last-Modified"),
	}, nil
}

// writeListCacheAtomic 以 .tmp + rename 原子替换规则源缓存文件（对齐 internal/config/store.go 既有做法），
// 避免刷新中途崩溃留下半截文件导致规则集残缺。
func writeListCacheAtomic(dir, id string, data []byte) error {
	finalPath := filepath.Join(dir, id+".txt")
	tmp, err := os.CreateTemp(dir, id+".*.tmp")
	if err != nil {
		return err
	}
	tmpPath := tmp.Name()

	if _, err := tmp.Write(data); err != nil {
		tmp.Close()
		_ = os.Remove(tmpPath)
		return err
	}
	if err := tmp.Sync(); err != nil {
		tmp.Close()
		_ = os.Remove(tmpPath)
		return err
	}
	if err := tmp.Close(); err != nil {
		_ = os.Remove(tmpPath)
		return err
	}
	if err := os.Rename(tmpPath, finalPath); err != nil {
		_ = os.Remove(tmpPath)
		return err
	}
	return nil
}

// readListCache 读取本地规则源缓存，返回内容与是否存在。
func readListCache(dir, id string) ([]byte, bool) {
	data, err := os.ReadFile(filepath.Join(dir, id+".txt"))
	if err != nil {
		return nil, false
	}
	return data, true
}

// listChecksum 计算规则源内容校验和。
func listChecksum(data []byte) string {
	sum := sha256.Sum256(data)
	return hex.EncodeToString(sum[:])
}
