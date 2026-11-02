// Package querylog 提供谛听 DNS 的查询历史持久化与运行统计能力。
//
// 设计借鉴自 AdGuardHome (internal/querylog、internal/stats) 与 blocky
// (stats/collector.go、querylog/)：以零第三方依赖的方式实现
//   - 定长内存环形缓冲，承载近期查询的快速检索；
//   - 24 小时滚动按小时聚合的运行统计（总量、拦截、缓存命中、Top-N 排行）；
//   - 按天滚动的 JSON-Lines 落盘与留存清理，供历史回溯。
//
// 本包仅依赖标准库与 internal/platform，不得反向依赖 internal/dns，
// 以避免与 DNS 流水线包形成循环引用。
package querylog
