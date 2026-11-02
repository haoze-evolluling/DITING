//go:build !windows

package protect

// ProtectPathPrivate 在非 Windows 平台是空操作。
//
// POSIX 下私钥的访问控制已由文件 mode（0o600）表达，没有额外的 ACL 层
// 需要收紧。
func ProtectPathPrivate(path string) error { return nil }
