//go:build windows

package protect

import (
	"fmt"

	"golang.org/x/sys/windows"
)

// aclProtectedDACL 一条「仅 SYSTEM 与 Administrators 可访问」的 DACL 的 SDDL。
//
// Windows 上 os.Chmod / WriteFile(0o600) 只切换只读属性，不设置任何 ACL：
// 私钥落在 %ProgramData%\DITING\certs 时继承 ProgramData 的默认 ACL，
// BUILTIN\Users 具备读取权，同机任意标准用户都能读出 DoT/DoH/DoQ 私钥。
// OICI 让继承项同时覆盖新建子目录与文件，避免之后新建的文件再次放开；
// OW（OWNER RIGHTS）保留当前属主自身的完整权限——目录可能由以管理员
// 身份运行的 GUI 创建，收紧后它仍要能继续写入证书。
const aclProtectedDACL = "D:P(A;OICI;FA;;;SY)(A;OICI;FA;;;BA)(A;OICI;FA;;;OW)"

// ProtectPathPrivate 用受保护 DACL 收紧文件或目录的访问权限。
//
// 失败不改变文件内容，调用方应按「加固失败」处理而不是假装成功。
func ProtectPathPrivate(path string) error {
	sd, err := windows.SecurityDescriptorFromString(aclProtectedDACL)
	if err != nil {
		return fmt.Errorf("构造安全描述符失败: %w", err)
	}
	dacl, _, err := sd.DACL()
	if err != nil {
		return fmt.Errorf("提取 DACL 失败: %w", err)
	}
	if err := windows.SetNamedSecurityInfo(
		path,
		windows.SE_FILE_OBJECT,
		windows.DACL_SECURITY_INFORMATION|windows.PROTECTED_DACL_SECURITY_INFORMATION,
		nil,
		nil,
		dacl,
		nil,
	); err != nil {
		return fmt.Errorf("设置 %s 访问控制失败: %w", path, err)
	}
	return nil
}
