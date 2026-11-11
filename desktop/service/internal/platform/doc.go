// Package platform 提供跨操作系统的平台能力抽象层。只包含三类内容，且不依赖项目内
// 其他业务包：
//
//  1. 跨平台共享的数据类型（AdapterInfo、AdapterState、PortCheckResult 等）；
//  2. 平台实现必须满足的接口（DNSManager、AdapterScanner、StateStore 等）；
//  3. 与操作系统无关的纯逻辑与路径解析（网卡判定、端口绑定探测、状态持久化）。
//
// 平台实现位于 platform/windows 与 platform/linux，由 cmd/service 在组合根按构建标签选择。
package platform
