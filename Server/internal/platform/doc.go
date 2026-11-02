// Package platform 提供跨操作系统的平台能力抽象层。
//
// 本包只包含三类内容，且不依赖项目内任何其他业务包：
//
//  1. 跨平台共享的数据类型（AdapterInfo、AdapterState、PortCheckResult 等）；
//  2. 平台实现必须满足的接口（DNSManager、AdapterScanner、StateStore 等）；
//  3. 与具体操作系统无关的纯逻辑与路径解析（网卡判定、端口绑定探测、状态持久化）。
//
// 具体的平台实现分别位于 platform/windows 与 platform/linux，并由上层
// （cmd/service）在组合根处按构建标签选择，避免出现包导入环。
package platform
