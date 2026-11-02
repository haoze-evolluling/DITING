package core

import (
	"fmt"
	"sync"

	"github.com/miekg/dns"
)

// flightCall 表示一个并发处理中的 DNS 请求调用
type flightCall struct {
	wg       sync.WaitGroup
	val      *dns.Msg
	err      error
	panicked bool
}

// singleFlightGroup 实现防并发击穿/惊群的 SingleFlight 调用编排器
type singleFlightGroup struct {
	mu    sync.Mutex
	calls map[string]*flightCall
}

// newSingleFlightGroup 创建 SingleFlight 实例
func newSingleFlightGroup() *singleFlightGroup {
	return &singleFlightGroup{
		calls: make(map[string]*flightCall),
	}
}

// Do 执行指定 key 的请求。若已有同 key 请求在处理中，则阻塞等待并共享其执行结果
func (g *singleFlightGroup) Do(key string, fn func() (*dns.Msg, error)) (val *dns.Msg, shared bool, err error) {
	g.mu.Lock()
	if g.calls == nil {
		g.calls = make(map[string]*flightCall)
	}
	if c, ok := g.calls[key]; ok {
		g.mu.Unlock()
		c.wg.Wait()
		if c.panicked {
			return nil, true, fmt.Errorf("singleflight panic in query for %s", key)
		}
		if c.val != nil {
			return c.val.Copy(), true, c.err
		}
		return nil, true, c.err
	}

	c := &flightCall{}
	c.wg.Add(1)
	g.calls[key] = c
	g.mu.Unlock()

	defer func() {
		if r := recover(); r != nil {
			c.panicked = true
			c.err = fmt.Errorf("singleflight panic: %v", r)
			err = c.err
		}
		g.mu.Lock()
		delete(g.calls, key)
		g.mu.Unlock()
		c.wg.Done()
	}()

	res, callErr := fn()
	// 发布快照而不是调用方持有的活对象：领导者返回后仍会改写自己的
	// ctx.Resp（重写 Id、按 UDP 尺寸截断），而跟随者此刻正从 c.val 复制。
	// 只有把发布值钉成不可变副本，singleflight 的「发布后不可变」契约才成立。
	if res != nil {
		c.val = res.Copy()
	}
	c.err = callErr
	if c.val != nil {
		return c.val.Copy(), false, c.err
	}
	return nil, false, c.err
}
