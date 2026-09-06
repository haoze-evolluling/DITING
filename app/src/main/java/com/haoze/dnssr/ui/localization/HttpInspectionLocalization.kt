package com.haoze.dnssr.ui.localization

/**
 * HTTPS 流量检查、CA 根证书状态、证书指纹、安装卸载指南及 QUIC/DoT 拦截本地化词条。
 */
internal fun translateHttpInspectionExact(text: String): String? = when (text) {
    "阻断所选应用的 QUIC，促使其回退到可检查的 TCP；部分站点可能加载失败" -> "Block QUIC for selected apps so they fall back to inspectable TCP; some sites may fail to load"
    "仅阻断所选应用的 DNS-over-TLS（DoT/TCP 853），防止绕过域名规则" -> "Block DNS-over-TLS (DoT/TCP 853) only for selected apps to prevent bypassing domain rules"
    "查看 HTTPS 流量检查的逐请求结果和 HTTPS 检查自动旁路记录" -> "View per-request HTTPS inspection results and automatic bypass records"
    "启用 HTTPS 检查" -> "Enable HTTPS inspection"
    "需先安装并验证 CA 根证书" -> "Install and verify the CA root certificate first"
    "需先启用 HTTPS 检查" -> "Enable HTTPS inspection first"
    "请先在 HTTPS 流量检查中开启检查" -> "Enable inspection in HTTPS traffic inspection first"
    "请先在 HTTPS 流量检查中选择目标应用" -> "Select target apps in HTTPS traffic inspection first"
    "解密内容过滤" -> "Decrypted content filtering"
    "启用 URL 规则与重定向" -> "Enable URL rules and rewrites"
    "开启解密流量下的 URL 屏蔽、放行及 CNAME 重定向" -> "Enable URL blocking, allowlist, and CNAME rewrites for decrypted traffic"
    "已暂停 · 解密请求直接放行，不应用 URL 规则及 CNAME 重定向" -> "Paused · Decrypted requests passed directly without URL rules or CNAME rewrites"
    "请先在 HTTPS 流量检查中开启【启用 URL 规则与重定向】" -> "Enable [Enable URL rules and rewrites] in HTTPS traffic inspection first"
    "需同时开启域名规则" -> "Domain rules must also be enabled"
    "确认同时关闭 HTTPS 检查？" -> "Confirm pausing HTTPS inspection too?"
    "HTTPS 流量检查基于 DNS 域名过滤基础之上运行。开启 HTTPS 检查将同时开启【启用域名规则】，确保域名级屏蔽与白名单规则在检测期间持续生效。" -> "HTTPS traffic inspection runs on top of DNS domain filtering. Enabling HTTPS inspection will also enable [Enable domain rules] to ensure domain-level rules remain active."
    "HTTPS 流量检查运行在 DNS 域名过滤基础之上。关闭域名规则后，依赖它的 HTTPS 检查也将同步暂停。" -> "HTTPS traffic inspection runs on top of DNS domain filtering. Disabling domain rules will also pause the dependent HTTPS inspection."
    "同时开启" -> "Enable both"
    "确认关闭" -> "Confirm disable"
    "URL 规则当前未就绪" -> "URL rules currently not ready"
    "CA 证书" -> "CA certificate"
    "证书已就绪，可查看或重置" -> "Certificate ready; tap to view or reset"
    "拦截 HTTP/3 (QUIC)" -> "Intercept HTTP/3 (QUIC)"
    "阻断 QUIC 促使回退至 TCP 以便解密；若异常请关闭" -> "Block QUIC to force fallback to TCP for decryption; disable if issues occur"
    "阻断加密 DNS (DoT)" -> "Block encrypted DNS (DoT)"
    "阻断 TCP 853 端口，防止绕过域名规则" -> "Block TCP 853 to prevent bypassing domain rules"
    "查看解密明细与自动旁路记录" -> "View decryption details and automatic bypass records"
    "此功能不适合没有相关经验的用户。安装、卸载或重新安装 CA 证书需要一定操作能力，操作不当可能导致部分应用无法联网；仅在你能自行处理这些问题时使用。" -> "This feature is not suitable for users without relevant experience. Installing, removing, or reinstalling a CA certificate requires care; mistakes may prevent some apps from connecting. Use it only if you can handle these issues yourself."
    "开启后，Go 隧道会接管流量，但仅检查明确选择的应用；其他应用直接转发。HTTPS 仅在应用信任 HTTPS 检查根证书且未使用证书固定或自定义校验时才能解密。" -> "When enabled, the Go tunnel takes over traffic but inspects only explicitly selected apps; other apps are forwarded directly. HTTPS can be decrypted only when an app trusts the HTTPS inspection root certificate and does not use certificate pinning or custom validation."
    "不兼容的连接会作为 HTTPS 检查自动旁路直接转发。HTTP/3（QUIC）默认直连；开启“尝试检查 HTTP/3”后，会阻断所选应用的 UDP 443，促使支持回退的客户端改用 TCP。" -> "Incompatible connections are forwarded directly as automatic HTTPS inspection bypasses. HTTP/3 (QUIC) is direct by default; enabling “Try to inspect HTTP/3” blocks UDP 443 for selected apps so clients that support fallback can use TCP."
    "启用所选应用的 HTTPS 流量检查" -> "Enable HTTPS inspection for selected apps"
    "仅汇总 DNS 与 HTTPS 的拦截、错误和旁路记录。" -> "Only blocked, failed, and bypassed DNS and HTTPS records are summarized."
    "HTTP CONNECT 不支持 UDP；UDP 会被严格阻断，QUIC 可回退到 TCP。代理应用本身将绕过 DNSSR。" -> "HTTP CONNECT does not support UDP; UDP is strictly blocked, and QUIC can fall back to TCP. The proxy app itself bypasses DNSSR."
    "Go 隧道接管流量后，HTTPS 流量检查仅检查所选应用的 HTTP(S) 请求，其他应用直接转发。选择应用会取消其“排除应用”状态。" -> "After the Go tunnel takes over traffic, HTTPS inspection checks HTTP(S) requests only for selected apps; other apps are forwarded directly. Selecting an app removes it from excluded apps."
    "查看 HTTPS 检查根证书" -> "View HTTPS inspection root certificate"
    "安装和卸载 CA 证书方法" -> "How to install and remove CA certificates"
    "证书状态" -> "Certificate status"
    "根证书状态" -> "Root certificate status"
    "用于目标应用的 HTTPS 流量解密" -> "Used for HTTPS traffic decryption of target apps"
    "正在验证系统凭据库中的证书状态" -> "Verifying the certificate status in the system credential store"
    "用于所选应用的 HTTPS 流量检查" -> "Used for HTTPS inspection of selected apps"
    "仅已验证的根证书支持流量检查；启用了证书绑定（SSL Pinning）的应用将自动旁路。" -> "Only verified root certificates support inspection; apps with certificate pinning are bypassed automatically."
    "仅已安装并通过验证的根证书可用于 HTTPS 流量检查；部分应用可能因证书固定或自定义校验而不受支持。" -> "Only installed and verified root certificates can be used for HTTPS inspection; some apps may be unsupported due to certificate pinning or custom validation."
    "证书操作" -> "Certificate operations"
    "查看各机型系统证书的安装、移除及安全说明" -> "View guide for installing, removing, and security notes"
    "安装和卸载 HTTPS 检查根证书" -> "Install or remove the HTTPS inspection root certificate"
    "查看 Android 系统 CA 证书的安装、卸载和安全说明" -> "View Android system CA certificate installation, removal, and security notes"
    "安装根证书" -> "Install root certificate"
    "导出证书文件并前往系统设置安装" -> "Export certificate and complete install in system settings"
    "安装 HTTPS 检查根证书" -> "Install HTTPS inspection root certificate"
    "导出谛听 HTTPS 检查根证书，并前往系统设置完成安装" -> "Export the Ting HTTPS inspection root certificate and finish installation in system settings"
    "证书指纹" -> "Certificate fingerprint"
    "查看当前根证书的 SHA-256 指纹" -> "View SHA-256 fingerprint of current root certificate"
    "查看当前 HTTPS 检查根证书的 SHA-256 指纹" -> "View the current HTTPS inspection root certificate SHA-256 fingerprint"
    "证书管理" -> "Certificate management"
    "重新生成根证书" -> "Regenerate root certificate"
    "作废当前私钥并生成新证书，重置后需重新安装" -> "Revoke current key and generate new certificate; reinstall required"
    "重置 HTTPS 检查根证书" -> "Reset HTTPS inspection root certificate"
    "废止当前证书并生成新证书；之后需要重新安装" -> "Revoke the current certificate and create a new one; it must then be installed again"
    "CA 证书指纹" -> "CA certificate fingerprint"
    "正在读取证书指纹…" -> "Reading certificate fingerprint..."
    "验证根证书" -> "Verify root certificate"
    "重新生成将销毁当前 CA 私钥并生成全新证书。系统中已安装的旧证书需手动在系统设置中移除，新证书安装并验证后方可继续检查流量。" -> "Regenerating will destroy the current CA private key and create a new certificate. Remove the old certificate from system settings manually; install and verify the new certificate before resuming traffic inspection."
    "根证书已重新生成" -> "Root certificate regenerated"
    "重新生成根证书失败" -> "Failed to regenerate root certificate"
    "HTTPS 检查根证书已重置" -> "HTTPS inspection root certificate reset"
    "重置 HTTPS 检查根证书失败" -> "Failed to reset HTTPS inspection root certificate"
    "CA 证书安装与卸载指南" -> "CA Certificate Installation & Removal Guide"
    "统计 Bootstrap DNS 解析加密服务商域名（DoH/DoT/DoQ）的使用情况。" -> "Statistics for encrypted provider-domain (DoH/DoT/DoQ) usage resolved through Bootstrap DNS."
    "统计 Bootstrap DNS 解析 DoH/DoT 服务商域名的使用情况。" -> "Statistics for DoH/DoT provider-domain usage resolved through Bootstrap DNS."
    "使用独立递归 DNS 解析加密服务商域名，支持智能权重优选与自动回退" -> "Use independent recursive DNS to resolve encrypted provider domains with smart weight prioritization and auto-fallback"
    "开启后将通过加权算法动态优选 Bootstrap IP；关闭后将通过系统 DNS 解析加密上游域名。" -> "When enabled, Bootstrap IPs are dynamically chosen via a weighted algorithm; when disabled, encrypted upstream domains are resolved via system DNS."
    "使用独立递归 DNS 解析 DoH/DoT 服务商域名，失败时自动尝试备用 IP" -> "Use independent recursive DNS to resolve DoH/DoT provider domains and try backup IPs on failure"
    "关闭后 DoH 使用系统 DNS，DoT 直接连接服务商域名。" -> "When disabled, DoH uses system DNS and DoT connects directly to the provider domain."
    "需先安装并验证 HTTPS 检查根证书" -> "Install and verify the HTTPS inspection root certificate first"
    "安装并验证 HTTPS 检查根证书" -> "Install and verify the HTTPS inspection root certificate"
    "保存后会自动从禁止联网应用、HTTPS 流量检查和排除 VPN 应用中移除。" -> "After saving, these apps are removed from blocked apps, HTTPS inspection, and VPN exclusions."
    "CA 证书设置" -> "CA certificate settings"
    "CA证书设置" -> "CA certificate settings"
    "安装和卸载CA证书方法" -> "How to install and remove CA certificates"
    "HTTPS 检查自动旁路" -> "HTTPS inspection bypass"
    "选择、添加或编辑 DoH/DoT 服务" -> "Choose, add, or edit DoH/DoT services"
    "HTTPS 检查根证书" -> "HTTPS inspection root certificate"
    "验证 HTTPS 检查根证书" -> "Verify HTTPS inspection root certificate"
    "HTTPS 流量检查" -> "HTTPS traffic inspection"
    "支持 DNS、DoH 与 DoT，并可管理自定义服务商。" -> "Supports DNS, DoH, and DoT, with custom provider management."
    "按应用检查 HTTP(S) 请求并应用域名和 URL 规则，需安装 HTTPS 检查根证书。" -> "Inspect HTTP(S) requests per app and apply domain and URL rules; an HTTPS inspection root certificate is required."
    "缓存、日志、规则与配置保存在设备本机。上游仍会收到必要查询；仅 DoH、DoT 加密到上游的 DNS 传输。" -> "Caches, logs, rules, and settings are stored on this device. Upstreams still receive necessary queries; only DoH and DoT encrypt DNS transport to upstreams."
    "CA 文件已保存，请在系统设置中手动安装" -> "CA file saved. Install it manually in system settings."
    "统一管理域名屏蔽、放行及 IPv4/IPv6 覆写，DNS 与 HTTPS 检查共用" -> "Manage domain blocking, allowing, and IPv4/IPv6 overrides shared by DNS and HTTPS inspection"
    "管理 HTTPS 解密后匹配的 URL 地址和路径前缀屏蔽、放行规则" -> "Manage URL address and path-prefix block and allow rules after HTTPS decryption"
    "仅在 HTTPS 流量检查可解密的请求中生效，包含屏蔽、放行及 CNAME 覆写" -> "Applies only to decryptable HTTPS inspection requests; includes block, allow, and CNAME override rules"
    "设置 DoT 服务器地址" -> "Set the DoT server address"
    "设置 DoT 服务端口" -> "Set the DoT service port"
    "仅切换阿里云和 DNSPod 内置服务的 DNS、DoT 或 DoH 协议" -> "Switch the DNS, DoT, or DoH protocol of built-in Alibaba Cloud and DNSPod services"
    "确定要重置所有应用设置新手引导和首次使用协议吗？这不会删除任何配置、规则、缓存、日志或证书。操作完成后应用将退出；下次打开时需要重新同意使用协议，所有新手引导也会再次显示。" -> "Reset all app setup guides and the first-use agreement? This will not delete configuration, rules, cache, logs, or certificates. The app will exit when complete; the agreement must be accepted again next time, and all setup guides will be shown again."
    else -> null
}

internal fun translateHttpInspectionPattern(text: String): String? = when {
    text.startsWith("“已放行/已拦截”表示") -> "“Allowed/Blocked” means DNSSR has read the HTTP request's authority and matched it against the existing domain rules.\n\n" +
        "“HTTPS inspection bypass” means the connection was forwarded directly because of certificate pinning, mutual TLS, EV certificates, the secure-domain policy, or a handshake failure; the HTTP request inside was not read.\n\n" +
        "Request records store only the app, authority, protocol, result, matched rule, and time; paths, headers, and bodies are never saved."
    text.startsWith("仅在 HTTPS 流量检查可解密的 HTTP(S) 请求中生效。") -> text.replace("仅在 HTTPS 流量检查可解密的 HTTP(S) 请求中生效。", "Applies only to HTTP(S) requests decrypted by HTTPS inspection. ").replace("域名规则 ", "Domain rules ").replace(" 条，URL 屏蔽/放行规则 ", ", URL block/allow rules ").replace(" 条，CNAME 覆写 ", ", CNAME overrides ").replace(" 条。", ".")
    text.startsWith("导出根证书失败：") -> text.replace("导出根证书失败：", "Failed to export root certificate: ")
    text.startsWith("导出 HTTPS 检查根证书失败：") -> text.replace("导出 HTTPS 检查根证书失败：", "Failed to export HTTPS inspection root certificate: ")
    text.startsWith("请在系统设置中选择“从存储设备安装 CA 证书”") -> {
                val fileName = if (text.contains("导出的 ")) {
                    text.substringAfter("导出的 ").substringBefore(" 文件")
                } else if (text.contains("中的 ")) {
                    text.substringAfter("中的 ").substringBefore("。返回后")
                } else {
                    "diting-ca-cert.crt"
                }
                "In system settings, choose “Install CA certificate from storage”, then select $fileName. Return here and DNSSR will verify the installation status. Connections using certificate pinning or custom validation will be bypassed automatically."
            }
    text.startsWith("根证书已验证；") -> text.replace("根证书已验证；", "Root certificate verified; ").replace("可查看、重新安装或重置", "view, reinstall, or reset it")
    text.startsWith("仅切换阿里云和 DNSPod 内置服务") -> "Switch only the DNS, DoT, or DoH protocol of the built-in Alibaba Cloud and DNSPod services, and sync the corresponding preset providers in all four modes"
    text.startsWith("正在读取 HTTPS 检查根证书的 SHA-256 指纹") -> "Reading the HTTPS inspection root certificate SHA-256 fingerprint..."
    text.startsWith("重置会删除当前 HTTPS 检查私有 CA") -> "Resetting deletes the current private HTTPS inspection CA and creates a new private key and root certificate. Existing system certificates are not removed automatically. Remove the old certificate from system credential settings, then install and verify the new certificate before resuming HTTPS inspection in compatible apps."
    text.startsWith("仅已安装并通过验证的根证书") -> "Only an installed and verified root certificate can be used for HTTPS traffic inspection. Some apps may not be supported because of certificate pinning or custom validation."
    text.startsWith("关闭后 DoH 使用系统 DNS") -> "When disabled, DoH uses the system DNS and DoT connects directly to the provider domain."
    text.startsWith("统计 Bootstrap DNS 解析") -> "Track Bootstrap DNS resolution usage for DoH/DoT provider domains."
    text.startsWith("软件介绍\n") -> "App overview\nDNSSR is a DNS management tool based on Android's local VPN. It supports DNS, DoH, DoT, provider management, caching, rules, logs, and per-app controls.\n\nImportant notes\nThe app relies on the local VPN and upstream DNS services. Resolution speed, stability, and availability depend on your network, selected upstream, and rule configuration. Caches, logs, rules, and settings are stored on this device, but upstream services still receive the queries required for resolution. Extended features such as HTTPS traffic inspection may affect network behavior; use them carefully after understanding their purpose.\n\nDisclaimer\nThis software is provided as-is, without guarantees of availability, speed, or compatibility with every device and network. Verify the reliability of upstream services, rules, and configuration sources, and accept the associated risks. Do not use this software for illegal purposes; you are responsible for any network, data, or other losses caused by its configuration or use."
    text.startsWith("使用独立递归 DNS") -> "Use independent recursive DNS to resolve DoH/DoT provider domains, with automatic fallback to backup IPs on failure"
    else -> null
}
