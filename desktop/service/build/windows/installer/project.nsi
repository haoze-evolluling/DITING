Unicode true
SetCompressor /SOLID lzma
SetCompressorDictSize 32

####
## 谛听 (DITING) Windows 服务安装包配置
## 仅包含 diting-service.exe 特权服务；桌面前端与浏览器控制台已移除
####
!define INFO_PROJECTNAME    "diting-desktop"
!define INFO_COMPANYNAME    "Diting"
# 沿用旧版产品名与安装目录，确保覆盖升级与卸载信息连续。
!define INFO_PRODUCTNAME    "谛听 DNS"
# 版本号不在本文件存副本：由 build_installer.bat / build_manager.py 从
# desktop/service/VERSION 读取后以 -DINFO_PRODUCTVERSION 传入。
!ifndef INFO_PRODUCTVERSION
  !error "缺少 -DINFO_PRODUCTVERSION：请用 build_installer.bat 构建（版本号取自 desktop/service/VERSION）"
!endif
!define INFO_COPYRIGHT      "Copyright 2026 DITING"

!define SERVICE_EXECUTABLE  "diting-service.exe"
!define SERVICE_NAME        "DitingDNSService"
!define UNINST_KEY_NAME     "DitingDNS"
!define UNINST_KEY          "Software\Microsoft\Windows\CurrentVersion\Uninstall\${UNINST_KEY_NAME}"

!ifndef ARG_SERVICE_BINARY
  !error "缺少 -DARG_SERVICE_BINARY：diting-service.exe 路径"
!endif

RequestExecutionLevel admin

VIProductVersion "${INFO_PRODUCTVERSION}.0"
VIFileVersion    "${INFO_PRODUCTVERSION}.0"

VIAddVersionKey "CompanyName"     "${INFO_COMPANYNAME}"
VIAddVersionKey "FileDescription" "${INFO_PRODUCTNAME} Installer"
VIAddVersionKey "ProductVersion"  "${INFO_PRODUCTVERSION}"
VIAddVersionKey "FileVersion"     "${INFO_PRODUCTVERSION}"
VIAddVersionKey "LegalCopyright"  "${INFO_COPYRIGHT}"
VIAddVersionKey "ProductName"     "${INFO_PRODUCTNAME}"

# Enable HiDPI support. https://nsis.sourceforge.io/Reference/ManifestDPIAware
ManifestDPIAware true

!include "MUI2.nsh"
!include "nsDialogs.nsh"
!include "LogicLib.nsh"
!include "FileFunc.nsh"
!include "x64.nsh"
!include "WinVer.nsh"

Var un_Dialog
Var un_Checkbox
Var DeleteConfig

!define MUI_ICON "..\icon.ico"
!define MUI_UNICON "..\icon.ico"
!define MUI_FINISHPAGE_NOAUTOCLOSE
!define MUI_ABORTWARNING

!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH

UninstPage custom un.ConfirmPage un.ConfirmPageLeave
!insertmacro MUI_UNPAGE_INSTFILES

!insertmacro MUI_LANGUAGE "SimpChinese"
!insertmacro MUI_LANGUAGE "English"

# 卸载界面多语言字符串配置
LangString PAGE_UNINST_TITLE ${LANG_SIMPCHINESE} "卸载 ${INFO_PRODUCTNAME}"
LangString PAGE_UNINST_SUBTITLE ${LANG_SIMPCHINESE} "从您的计算机中卸载 ${INFO_PRODUCTNAME}。"
LangString PAGE_UNINST_LABEL ${LANG_SIMPCHINESE} "${INFO_PRODUCTNAME} 即将从下列文件夹中卸载。单击“卸载”即可开始卸载过程："
LangString PAGE_UNINST_CHECKBOX ${LANG_SIMPCHINESE} "卸载时删除本地配置"
LangString PAGE_UNINST_CHECKBOX_DESC ${LANG_SIMPCHINESE} "勾选此项将在卸载时清理所有本地配置文件及相关运行数据；若取消勾选，则保留配置与数据以便后续重新安装。"
LangString UNINST_DETAIL_CLEAN_DATA ${LANG_SIMPCHINESE} "正在清理本地配置文件及相关运行数据..."
LangString UNINST_DETAIL_KEEP_DATA ${LANG_SIMPCHINESE} "用户选择保留本地配置文件及相关数据，已跳过数据清理。"

LangString PAGE_UNINST_TITLE ${LANG_ENGLISH} "Uninstall ${INFO_PRODUCTNAME}"
LangString PAGE_UNINST_SUBTITLE ${LANG_ENGLISH} "Remove ${INFO_PRODUCTNAME} from your computer."
LangString PAGE_UNINST_LABEL ${LANG_ENGLISH} "${INFO_PRODUCTNAME} will be uninstalled from the following folder. Click Uninstall to start the uninstallation:"
LangString PAGE_UNINST_CHECKBOX ${LANG_ENGLISH} "Delete local configuration when uninstalling"
LangString PAGE_UNINST_CHECKBOX_DESC ${LANG_ENGLISH} "If checked, all local configuration files and runtime data will be removed. If unchecked, your configuration and data will be preserved for future use."
LangString UNINST_DETAIL_CLEAN_DATA ${LANG_ENGLISH} "Removing local configuration files and runtime data..."
LangString UNINST_DETAIL_KEEP_DATA ${LANG_ENGLISH} "Keeping local configuration files and data, skipping cleanup."

Name "${INFO_PRODUCTNAME}"
!ifdef OUTPUT_FILENAME
  OutFile "${OUTPUT_FILENAME}"
!else
  OutFile "..\..\bin\${INFO_PROJECTNAME}-installer.exe"
!endif
InstallDir "$PROGRAMFILES64\${INFO_COMPANYNAME}\${INFO_PRODUCTNAME}"
ShowInstDetails show
ShowUninstDetails show

Function .onInit
    ${IfNot} ${AtLeastWin10}
        MessageBox MB_OK "This product is only supported on Windows 10 (Server 2016) and later."
        Quit
    ${EndIf}

    ${IfNot} ${IsNativeAMD64}
        MessageBox MB_OK "This product can't be installed on the current Windows architecture. Supports: amd64"
        Quit
    ${EndIf}
FunctionEnd

Function un.onInit
    StrCpy $DeleteConfig "1"
    ${un.GetParameters} $R0

    # 支持 /KEEPCONFIG、-KEEPCONFIG 与 --KEEPCONFIG（大小写不敏感）
    ClearErrors
    ${un.GetOptions} $R0 "/KEEPCONFIG" $R1
    ${IfNot} ${Errors}
        StrCpy $DeleteConfig "0"
    ${EndIf}
    ClearErrors
    ${un.GetOptions} $R0 "-KEEPCONFIG" $R1
    ${IfNot} ${Errors}
        StrCpy $DeleteConfig "0"
    ${EndIf}
    ClearErrors
    ${un.GetOptions} $R0 "--KEEPCONFIG" $R1
    ${IfNot} ${Errors}
        StrCpy $DeleteConfig "0"
    ${EndIf}

    # 支持 /DELETECONFIG、-DELETECONFIG 与 --DELETECONFIG
    ClearErrors
    ${un.GetOptions} $R0 "/DELETECONFIG" $R1
    ${IfNot} ${Errors}
        StrCpy $DeleteConfig "1"
    ${EndIf}
    ClearErrors
    ${un.GetOptions} $R0 "-DELETECONFIG" $R1
    ${IfNot} ${Errors}
        StrCpy $DeleteConfig "1"
    ${EndIf}
    ClearErrors
    ${un.GetOptions} $R0 "--DELETECONFIG" $R1
    ${IfNot} ${Errors}
        StrCpy $DeleteConfig "1"
    ${EndIf}
FunctionEnd

Function un.ConfirmPage
    !insertmacro MUI_HEADER_TEXT $(PAGE_UNINST_TITLE) $(PAGE_UNINST_SUBTITLE)

    nsDialogs::Create 1018
    Pop $un_Dialog
    ${If} $un_Dialog == error
        Abort
    ${EndIf}

    # 修改“下一步”按钮文本为“卸载”
    GetDlgItem $0 $HWNDPARENT 1
    SendMessage $0 ${WM_SETTEXT} 0 "STR:$(^UninstallBtn)"

    # 禁用“上一步”按钮
    GetDlgItem $0 $HWNDPARENT 3
    EnableWindow $0 0

    ${NSD_CreateLabel} 0 0 100% 28u "$(PAGE_UNINST_LABEL)$\r$\n$INSTDIR"
    Pop $0

    ${NSD_CreateCheckbox} 0 36u 100% 12u "$(PAGE_UNINST_CHECKBOX)"
    Pop $un_Checkbox

    ${If} $DeleteConfig == "1"
        ${NSD_Check} $un_Checkbox
    ${Else}
        ${NSD_Uncheck} $un_Checkbox
    ${EndIf}

    ${NSD_CreateLabel} 12u 52u 88% 32u "$(PAGE_UNINST_CHECKBOX_DESC)"
    Pop $0

    nsDialogs::Show
FunctionEnd

Function un.ConfirmPageLeave
    ${NSD_GetState} $un_Checkbox $0
    ${If} $0 == ${BST_CHECKED}
        StrCpy $DeleteConfig "1"
    ${Else}
        StrCpy $DeleteConfig "0"
    ${EndIf}
FunctionEnd

Section
    SetShellVarContext all

    # 安装前先停止可能正在运行的旧版本服务
    DetailPrint "正在停止可能正在运行的旧版本服务..."
    nsExec::Exec '"$INSTDIR\${SERVICE_EXECUTABLE}" -service stop'
    nsExec::Exec 'net.exe stop "${SERVICE_NAME}"'

    # 兼容旧版前端安装包：清理不再提供的桌面端文件与快捷方式
    Delete "$INSTDIR\diting_desktop.exe"
    Delete "$INSTDIR\flutter_windows.dll"
    RMDir /r "$INSTDIR\data"
    Delete "$SMPROGRAMS\谛听 DNS.lnk"
    Delete "$DESKTOP\谛听 DNS.lnk"

    SetOutPath $INSTDIR

    # 释放内核特权服务二进制（纯 Rust，静态链接，无附带动态库）
    File "/oname=${SERVICE_EXECUTABLE}" "${ARG_SERVICE_BINARY}"

    # 自动向系统注册并启动特权服务
    DetailPrint "正在向系统注册 ${INFO_PRODUCTNAME}..."
    nsExec::Exec '"$INSTDIR\${SERVICE_EXECUTABLE}" -service install'
    nsExec::Exec 'sc.exe config ${SERVICE_NAME} start= auto'

    DetailPrint "正在启动 ${INFO_PRODUCTNAME}..."
    nsExec::Exec '"$INSTDIR\${SERVICE_EXECUTABLE}" -service start'
    nsExec::Exec 'net.exe start ${SERVICE_NAME}'

    # 写入卸载信息
    WriteUninstaller "$INSTDIR\uninstall.exe"

    SetRegView 64
    WriteRegStr HKLM "${UNINST_KEY}" "Publisher" "${INFO_COMPANYNAME}"
    WriteRegStr HKLM "${UNINST_KEY}" "DisplayName" "${INFO_PRODUCTNAME}"
    WriteRegStr HKLM "${UNINST_KEY}" "DisplayVersion" "${INFO_PRODUCTVERSION}"
    WriteRegStr HKLM "${UNINST_KEY}" "DisplayIcon" "$INSTDIR\${SERVICE_EXECUTABLE}"
    WriteRegStr HKLM "${UNINST_KEY}" "UninstallString" "$\"$INSTDIR\uninstall.exe$\""
    WriteRegStr HKLM "${UNINST_KEY}" "QuietUninstallString" "$\"$INSTDIR\uninstall.exe$\" /S"

    ${GetSize} "$INSTDIR" "/S=0K" $0 $1 $2
    IntFmt $0 "0x%08X" $0
    WriteRegDWORD HKLM "${UNINST_KEY}" "EstimatedSize" "$0"
SectionEnd

Section "uninstall"
    SetShellVarContext all

    # 优雅停止特权服务并自动还原系统网络 DNS 接管状态
    DetailPrint "正在安全停止特权服务并恢复系统网络 DNS..."
    nsExec::Exec '"$INSTDIR\${SERVICE_EXECUTABLE}" -service stop'
    nsExec::Exec 'net.exe stop "${SERVICE_NAME}"'

    # 优先执行离线生成的 restore-dns.bat 还原脚本（若存在）
    IfFileExists "$APPDATA\DITING\restore-dns.bat" 0 +2
    nsExec::Exec 'cmd.exe /c "$\"$APPDATA\DITING\restore-dns.bat$\""'

    # 调用服务特权二进制执行离线恢复与自愈
    nsExec::Exec '"$INSTDIR\${SERVICE_EXECUTABLE}" -restore'

    # 强力兜底全网卡 DNS 还原机制：服务二进制已使用 Windows 原生 API 遍历并重置所有残留网卡
    DetailPrint "正在执行全网卡 DNS 兜底自愈与缓存刷新..."
    nsExec::Exec 'ipconfig /flushdns'

    # 从系统服务管理器中注销清理特权服务
    DetailPrint "正在从系统服务中注销谛听服务..."
    nsExec::Exec '"$INSTDIR\${SERVICE_EXECUTABLE}" -service uninstall'
    nsExec::Exec 'sc.exe delete ${SERVICE_NAME}'

    # 清除用户数据、残留状态与自启动注册表项
    ${If} $DeleteConfig == "1"
        DetailPrint $(UNINST_DETAIL_CLEAN_DATA)
        RMDir /r "$APPDATA\DITING"
        RMDir /r "$LOCALAPPDATA\DITING"
    ${Else}
        DetailPrint $(UNINST_DETAIL_KEEP_DATA)
    ${EndIf}
    DeleteRegValue HKCU "Software\Microsoft\Windows\CurrentVersion\Run" "DitingDNS"

    # 删除程序本体
    Delete "$INSTDIR\uninstall.exe"
    RMDir /r $INSTDIR

    # 删除旧版快捷方式并注销卸载信息
    Delete "$SMPROGRAMS\谛听 DNS.lnk"
    Delete "$DESKTOP\谛听 DNS.lnk"

    SetRegView 64
    DeleteRegKey HKLM "${UNINST_KEY}"
SectionEnd
