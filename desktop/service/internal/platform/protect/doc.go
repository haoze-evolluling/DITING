// Package protect 提供「收紧文件访问权限到系统级」的平台实现。
//
// 从 platform 主包拆出：platform/windows 已导入 platform，若把 ACL 实现
// 放在主包再让 windows 侧提供，会形成导入环。调用方只依赖本包。
package protect
