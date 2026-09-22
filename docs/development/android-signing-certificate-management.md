# Android 签名证书管理与发布签名规范

本文档用于记录 DITING 项目全新 Android 正式发布签名证书的技术规格、安全管理规范、离线私有保管流程以及多环境配置指引。

---

## 1. 迁移背景与旧证书废弃说明

在早期开发阶段，项目仓库中曾直接包含了 `app/keystore/debug.keystore`，且在 `app/build.gradle.kts` 中对 Release 构建也指定了该调试证书及明文密码（`android`）。

这种做法存在严重的**密钥暴露安全隐患**：
1. **私钥泄露**：任何获取代码仓库的人都可以提取私钥并伪造合法签名的恶意更新包。
2. **身份不可信**：调试证书的所有人与颁发者均为通用的 `Android Debug`，无法确立开发团队的真实软件发布者身份。

**迁移处置：**
- **彻底废弃旧证书**：旧证书已从 Git 跟踪及仓库目录中彻底移除（`git rm`）。
- **建立全新签名体系**：重新生成高强度（RSA 4096 位、PKCS12 格式）的专属正式签名证书，今后统一使用新证书编译和签名发布版本。
- **凭据与代码解耦**：密钥文件和凭据严格置于本地，仅提交脱敏模版 `keystore.properties.example`，避免敏感凭据再次入库。

---

## 2. 新证书技术规格与指纹

新生成的正式发布证书技术参数如下：

| 参数项 | 取值 |
| :--- | :--- |
| **密钥库文件** | `DITING-keystore/diting-release.jks`（本地私有，不入库） |
| **密钥库格式** | `PKCS12`（业界标准格式） |
| **签名别名 (Alias)** | `diting-release` |
| **密钥算法与长度** | `RSA` / `4096 bits` |
| **签名算法** | `SHA384withRSA` |
| **证书所有人 (DName)** | `CN=DITING, OU=DITING Team, O=DITING, C=CN` |
| **证书序列号** | `c5f16296648d2cc6` |
| **有效期至** | 2054 年 02 月 07 日（10,000 天） |

### 证书指纹 (Certificate Fingerprints)
在发布或验证第三方平台集成时，可使用以下指纹进行核对：

- **SHA-256**:
  ```text
  27:64:23:E1:3A:C0:B3:53:42:13:C3:80:74:91:DD:22:B2:AB:B2:15:A1:AE:18:B7:A5:68:1A:FC:63:6D:B2:F4
  ```
- **SHA-1**:
  ```text
  FA:5E:7E:BB:F1:5C:D8:1F:1F:CC:B4:6B:C7:F1:2D:3E:3E:0D:79:26
  ```
- **MD5**:
  ```text
  0F:1B:BF:4E:5E:FE:D5:39:A3:C8:31:AF:A0:C6:A9:25
  ```

---

## 3. 私密凭据保管规范（Google Drive 离线/私有存储）

> [!CAUTION]
> **绝对禁止将 `.jks` 证书文件及包含真实密码的 `keystore.properties` 提交到 GitHub 仓库或任何公开网络介质！**
> `.gitignore` 已配置规则拦截相关文件，但仍需保持安全意识。

### Google Drive 归档指引
新证书及密钥凭据仅保存在个人私有 Google Drive 中进行离线/私密保管：

1. **创建专用保管目录**：
   在个人 Google Drive 根目录下创建专用私密文件夹，如：
   `My Drive/Private-Credentials/DITING-Android-Signing/`
2. **上传必要凭据（推荐直接上传整个 `DITING-keystore` 文件夹）**：
   本地所有的签名私密文件均统一存放在 `DITING-keystore/` 目录下（受 `.gitignore` 保护不入库）：
   - `DITING-keystore/diting-release.jks`（密钥库文件）
   - `DITING-keystore/keystore.properties`（签名密码与别名配置）
   您可以直接将整个 `DITING-keystore` 目录（或压缩包）上传至 Google Drive 专用目录中。
3. **安全权限控制**：
   - 确保该文件夹的共享设置处于 **“仅限个人访问”（Restricted）**，切勿创建公开可访问链接。
   - 确保个人 Google 账号已启用两步验证（2FA / Passkey）。
4. **冗余冷备份（推荐）**：
   将上述凭据在个人加密 U 盘或离线固态硬盘中存放一份脱机冷备份，防止单个云服务不可用风险。

---

## 4. 多设备开发与构建配置流程

当在新开发机、重装系统后或授权开发者需要编译正式签名包时，请按如下步骤配置：

### 步骤 1：从 Google Drive 获取密钥
1. 从个人的私有 Google Drive 目录中下载整个 `DITING-keystore` 文件夹（包含 `diting-release.jks` 和 `keystore.properties`）。
2. 放置到项目根目录下：
   ```text
   DITING/
   └── DITING-keystore/
       ├── diting-release.jks
       └── keystore.properties
   ```
   > 注：若之前仅备份了 `.jks` 密钥文件与密码记录，也可复制根目录下的 `keystore.properties.example` 至 `DITING-keystore/keystore.properties`（或项目根目录），填入实际密码即可。

### 步骤 2：编译与打包构建选项
- **使用构建脚本（推荐）**：
  直接运行项目根目录下的 `build.bat`（或 `build_apk.bat`），菜单提供以下选项：
  - `[1] Debug`：开发调试版，使用本地 Android SDK 默认调试密钥。
  - `[2] Release`：正式发布包，开启 R8 混淆优化，使用 `DITING-keystore` 正式证书签名。
  - `[3] Debug (Release Key)`：开发调试版，快速编译且可断点调试，但统一使用 `DITING-keystore` 正式证书签名（支持直接覆盖安装测试，无需卸载已有的正式版）。
  - `[4] Clean Project`：一键执行 `./gradlew clean` 清理历史构建缓存。
- **使用命令行**：
  ```powershell
  # 编译正式发布版
  .\gradlew.bat assembleRelease

  # 编译使用 Release 证书签名的 Debug 版（方便覆盖安装）
  .\gradlew.bat assembleDebug -PsignDebugWithRelease=true

  # 清理项目构建缓存
  .\gradlew.bat clean
  ```
- **构建产物位置**：
  - 标准输出路径：`app/build/outputs/apk/release/app-release.apk`
  - 带版本号命名输出：`app/build/outputs/apk/versioned/release/DITING-release-v<version>.apk`

---

## 5. 用户升级与覆盖安装注意事项

> [!WARNING]
> **签名指纹不匹配导致的覆盖安装失败说明**
> - Android 操作系统基于 APK 的签名证书建立应用身份认证与沙箱隔离体系。
> - 由于此前历史版本使用旧的调试证书签名，本次迁移后的新版本使用全新的正式发布证书签名，**两者签名指纹不一致**。
> - 若设备上已安装过旧版本，直接安装新版本会提示 `INSTALL_FAILED_UPDATE_INCOMPATIBLE`（应用签名与现有版本不一致）。
> - **升级操作**：终端用户需要先**卸载手机上的旧版本**，然后再安装新签名的 APK。
> - 本次迁移之后的所有正式版本都将使用该新证书持续签名，后续版本更新均支持正常的直接覆盖升级。

---

## 6. 签名验证操作参考

在发布正式 APK 前，可随时通过 Android SDK 的 `apksigner` 工具检验 APK 的签名完整性与签名方案生效情况：

```powershell
# 验证签名并打印证书信息
& "$env:LOCALAPPDATA\Android\Sdk\build-tools\<version>\apksigner.bat" verify --verbose --print-certs "app/build/outputs/apk/release/app-release.apk"
```

输出应满足：
- `Verifies` 为成功状态。
- `Verified using v2/v3 scheme` 为 `true`。
- `Signer #1 certificate DN` 明确显示 `CN=DITING, OU=DITING Team, O=DITING, C=CN`。
- 证书 SHA-256 指纹与本规范第 2 节记录的指纹完全相符。
