Unicode true

####
## 谛听 (DITING) Windows 端整合安装包配置
## 包含 Wails GUI 客户端 与 diting-service.exe 特权服务
####
!define INFO_PROJECTNAME    "diting-gui"
!define INFO_COMPANYNAME    "Diting"
!define INFO_PRODUCTNAME    "谛听 DNS"
!ifndef INFO_PRODUCTVERSION
  !ifdef PRODUCT_VERSION
    !define INFO_PRODUCTVERSION "1.3.3"
  !else
    !define INFO_PRODUCTVERSION "1.3.3"
  !endif
!endif
!define INFO_COPYRIGHT      "Copyright 2026 DITING"

!define PRODUCT_EXECUTABLE  "diting-gui.exe"
!define SERVICE_EXECUTABLE  "diting-service.exe"
!define SERVICE_NAME        "DitingDNSService"
!define UNINST_KEY_NAME     "DitingDNS"

!define REQUEST_EXECUTION_LEVEL "admin"

####
## Include the wails tools
####
!include "wails_tools.nsh"

# The version information for this two must consist of 4 parts
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

!include "MUI.nsh"

!define MUI_ICON "..\icon.ico"
!define MUI_UNICON "..\icon.ico"
!define MUI_FINISHPAGE_NOAUTOCLOSE
!define MUI_ABORTWARNING

!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES

# 安装完成后直接引导启动客户端
!define MUI_FINISHPAGE_RUN "$INSTDIR\${PRODUCT_EXECUTABLE}"
!define MUI_FINISHPAGE_RUN_TEXT "启动 ${INFO_PRODUCTNAME} 客户端"
!insertmacro MUI_PAGE_FINISH

!insertmacro MUI_UNPAGE_INSTFILES

!insertmacro MUI_LANGUAGE "SimpChinese"
!insertmacro MUI_LANGUAGE "English"

Name "${INFO_PRODUCTNAME}"
!ifdef OUTPUT_FILENAME
  OutFile "${OUTPUT_FILENAME}"
!else
  OutFile "..\..\bin\${INFO_PROJECTNAME}-${ARCH}-installer.exe"
!endif
!ifdef WAILS_INSTALL_SCOPE
  !if "${WAILS_INSTALL_SCOPE}" == "user"
    InstallDir "$LOCALAPPDATA\Programs\${INFO_PRODUCTNAME}"
  !else
    InstallDir "$PROGRAMFILES64\${INFO_COMPANYNAME}\${INFO_PRODUCTNAME}"
  !endif
!else
  InstallDir "$PROGRAMFILES64\${INFO_COMPANYNAME}\${INFO_PRODUCTNAME}"
!endif
ShowInstDetails show

Function .onInit
   !insertmacro wails.checkArchitecture
FunctionEnd

Section
    !insertmacro wails.setShellContext

    # 安装前先尝试关闭可能正在运行的旧版本进程以防止文件写锁
    DetailPrint "正在检查并终止正在运行的旧版本实例..."
    nsExec::Exec 'taskkill /F /IM "${PRODUCT_EXECUTABLE}" /T'
    nsExec::Exec '"$INSTDIR\${SERVICE_EXECUTABLE}" -service stop'
    nsExec::Exec 'net.exe stop "${SERVICE_NAME}"'

    !insertmacro wails.webview2runtime

    SetOutPath $INSTDIR

    # 1. 释放 GUI 客户端二进制
    !insertmacro wails.files

    # 2. 释放内核特权服务二进制
    File "/oname=${SERVICE_EXECUTABLE}" "..\..\bin\${SERVICE_EXECUTABLE}"

    # 3. 自动向系统注册并启动特权服务
    DetailPrint "正在向系统注册 ${INFO_PRODUCTNAME} 内核特权服务..."
    nsExec::Exec '"$INSTDIR\${SERVICE_EXECUTABLE}" -service install'
    nsExec::Exec 'sc.exe config ${SERVICE_NAME} start= auto'

    DetailPrint "正在启动 ${INFO_PRODUCTNAME} 内核特权服务..."
    nsExec::Exec '"$INSTDIR\${SERVICE_EXECUTABLE}" -service start'
    nsExec::Exec 'net.exe start ${SERVICE_NAME}'

    # 4. 创建桌面与开始菜单快捷方式
    CreateShortcut "$SMPROGRAMS\${INFO_PRODUCTNAME}.lnk" "$INSTDIR\${PRODUCT_EXECUTABLE}" "" "$INSTDIR\${PRODUCT_EXECUTABLE}" 0
    CreateShortCut "$DESKTOP\${INFO_PRODUCTNAME}.lnk" "$INSTDIR\${PRODUCT_EXECUTABLE}" "" "$INSTDIR\${PRODUCT_EXECUTABLE}" 0

    !insertmacro wails.associateFiles
    !insertmacro wails.associateCustomProtocols

    !insertmacro wails.writeUninstaller
SectionEnd

Section "uninstall"
    !insertmacro wails.setShellContext

    # 1. 关闭正在运行的 GUI 客户端
    DetailPrint "正在终止 ${INFO_PRODUCTNAME} 客户端进程..."
    nsExec::Exec 'taskkill /F /IM "${PRODUCT_EXECUTABLE}" /T'

    # 2. 优雅停止特权服务并自动还原系统网络 DNS 接管状态
    DetailPrint "正在安全停止特权服务并恢复系统网络 DNS..."
    nsExec::Exec '"$INSTDIR\${SERVICE_EXECUTABLE}" -service stop'
    nsExec::Exec 'net.exe stop "${SERVICE_NAME}"'

    # 优先执行离线生成的 restore-dns.bat 还原脚本（若存在）
    SetShellVarContext all
    IfFileExists "$APPDATA\DITING\restore-dns.bat" 0 +2
    nsExec::Exec 'cmd.exe /c "$\"$APPDATA\DITING\restore-dns.bat$\""'
    SetShellVarContext current

    # 调用服务特权二进制执行离线恢复与自愈
    nsExec::Exec '"$INSTDIR\${SERVICE_EXECUTABLE}" -restore'

    # 3. 强力兜底全网卡 DNS 还原机制：服务二进制已使用 Windows 原生 API 遍历并重置所有残留网卡
    DetailPrint "正在执行全网卡 DNS 兜底自愈与缓存刷新..."
    nsExec::Exec 'ipconfig /flushdns'

    # 4. 从系统服务管理器中注销清理特权服务
    DetailPrint "正在从系统服务中注销谛听服务..."
    nsExec::Exec '"$INSTDIR\${SERVICE_EXECUTABLE}" -service uninstall'
    nsExec::Exec 'sc.exe delete ${SERVICE_NAME}'

    # 5. 清除用户数据、残留状态与自启动注册表项
    SetShellVarContext all
    RMDir /r "$APPDATA\DITING"
    SetShellVarContext current
    RMDir /r "$AppData\${PRODUCT_EXECUTABLE}"
    DeleteRegValue HKCU "Software\Microsoft\Windows\CurrentVersion\Run" "DitingDNS"

    # 6. 删除程序本体
    Delete "$INSTDIR\${SERVICE_EXECUTABLE}"
    Delete "$INSTDIR\${PRODUCT_EXECUTABLE}"
    RMDir /r $INSTDIR

    # 6. 删除快捷方式
    Delete "$SMPROGRAMS\${INFO_PRODUCTNAME}.lnk"
    Delete "$DESKTOP\${INFO_PRODUCTNAME}.lnk"

    !insertmacro wails.unassociateFiles
    !insertmacro wails.unassociateCustomProtocols

    !insertmacro wails.deleteUninstaller
SectionEnd
