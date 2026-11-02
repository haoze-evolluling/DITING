package dns

import (
	"sync"
)

// Middleware 定义洋葱模型中间件函数签名
type Middleware func(ctx *DNSContext, next func() error) error

// Pipeline 中间件流水线编排器
type Pipeline struct {
	mu          sync.RWMutex
	middlewares []Middleware
}

// NewPipeline 创建流水线编排器
func NewPipeline(middlewares ...Middleware) *Pipeline {
	p := &Pipeline{
		middlewares: make([]Middleware, 0, len(middlewares)),
	}
	p.Use(middlewares...)
	return p
}

// Use 向流水线末尾追加中间件
func (p *Pipeline) Use(middlewares ...Middleware) {
	p.mu.Lock()
	defer p.mu.Unlock()
	p.middlewares = append(p.middlewares, middlewares...)
}

// Execute 按照注册顺序递归执行中间件调用链
func (p *Pipeline) Execute(ctx *DNSContext) error {
	p.mu.RLock()
	ms := make([]Middleware, len(p.middlewares))
	copy(ms, p.middlewares)
	p.mu.RUnlock()

	if len(ms) == 0 {
		return nil
	}

	var step func(index int) error
	step = func(index int) error {
		if index >= len(ms) {
			return nil
		}
		return ms[index](ctx, func() error {
			return step(index + 1)
		})
	}

	return step(0)
}
