package com.haoze.diting.ui

import com.haoze.diting.ui.localization.LocalizationEngine
import com.haoze.diting.ui.localization.translateSettingsAndAppearanceExact
import com.haoze.diting.ui.localization.translateSettingsAndAppearancePattern
import org.junit.Assert.assertEquals
import org.junit.Test

class SettingsAndAppearanceLocalizationTest {

    @Test
    fun `proxy status translation matches expected strings`() {
        assertEquals("Proxy ready", translateSettingsAndAppearanceExact("代理可用"))
        assertEquals("Proxy unavailable", translateSettingsAndAppearanceExact("代理不可用"))
        assertEquals("Outbound proxy unavailable", translateSettingsAndAppearanceExact("出站代理不可用"))
        assertEquals("Connection failed", translateSettingsAndAppearanceExact("连接失败"))
        assertEquals("Proxy not running or port not open", translateSettingsAndAppearanceExact("代理未启动或端口未开放"))
        assertEquals("Proxy connection timed out", translateSettingsAndAppearanceExact("连接代理超时"))
        assertEquals("Proxy authentication failed", translateSettingsAndAppearanceExact("代理认证失败"))
        assertEquals("Proxy does not support authentication method", translateSettingsAndAppearanceExact("代理不支持当前的认证方式"))
        assertEquals("SOCKS5 proxy does not support UDP associate", translateSettingsAndAppearanceExact("SOCKS5 代理不支持 UDP 转发"))
        assertEquals("Cannot connect to proxy service", translateSettingsAndAppearanceExact("无法连接到代理服务"))
        assertEquals("HTTP proxy returned error", translateSettingsAndAppearanceExact("HTTP 代理返回错误"))
    }

    @Test
    fun `pattern translation correctly formats composite proxy error messages`() {
        val composite1 = "出站代理不可用 · 代理未启动或端口未开放"
        assertEquals("Outbound proxy unavailable · Proxy not running or port not open", translateSettingsAndAppearancePattern(composite1))

        val composite2 = "出站代理不可用 · 连接代理超时"
        assertEquals("Outbound proxy unavailable · Proxy connection timed out", translateSettingsAndAppearancePattern(composite2))

        val composite3 = "代理不可用 · 代理认证失败"
        assertEquals("Proxy unavailable · Proxy authentication failed", translateSettingsAndAppearancePattern(composite3))
    }

    @Test
    fun `hidden features translation matches expected strings`() {
        assertEquals("Hidden features", translateSettingsAndAppearanceExact("隐藏功能"))
        assertEquals("Hidden features list", translateSettingsAndAppearanceExact("隐藏功能列表"))
        assertEquals("Show all", translateSettingsAndAppearanceExact("恢复全部显示"))
        assertEquals("Shown in Feature Hub", translateSettingsAndAppearanceExact("在功能中心显示"))
        assertEquals("Hidden from Feature Hub", translateSettingsAndAppearanceExact("已在功能中心隐藏"))
        assertEquals("Interface and settings", translateSettingsAndAppearanceExact("界面与设置"))
        assertEquals("Data & maintenance", translateSettingsAndAppearanceExact("数据与维护"))
    }

    @Test
    fun `data cleanup translation matches expected strings`() {
        assertEquals("Data cleanup", LocalizationEngine.translateExact("数据清理"))
        assertEquals("Runtime data", LocalizationEngine.translateExact("运行数据"))
        assertEquals("Weight data", LocalizationEngine.translateExact("权重数据"))
        assertEquals("Rules and subscriptions", LocalizationEngine.translateExact("规则与订阅"))
        assertEquals("Storage and security", LocalizationEngine.translateExact("存储与安全"))
        assertEquals("Guides and reset", LocalizationEngine.translateExact("引导与重置"))

        assertEquals("Delete request logs", LocalizationEngine.translateExact("删除请求日志"))
        assertEquals("Delete traffic statistics", LocalizationEngine.translateExact("删除流量统计"))
        assertEquals("Delete crash logs", LocalizationEngine.translateExact("删除崩溃日志"))
        assertEquals("Delete DNS cache", LocalizationEngine.translateExact("删除 DNS 缓存"))
        assertEquals("Restore default DNS weights", LocalizationEngine.translateExact("恢复 DNS 默认权重"))
        assertEquals("Restore Bootstrap weights", LocalizationEngine.translateExact("恢复 Bootstrap 权重"))
        assertEquals("Delete all domain rules", LocalizationEngine.translateExact("删除全部域名规则"))
        assertEquals("Delete all address rules", LocalizationEngine.translateExact("删除全部地址规则"))
        assertEquals("Delete all rule subscriptions", LocalizationEngine.translateExact("删除全部规则订阅"))
        assertEquals("Reset HTTPS inspection certificate", LocalizationEngine.translateExact("重置 HTTPS 抓包证书"))
        assertEquals("Clear downloads and temporary cache", LocalizationEngine.translateExact("清理下载与临时缓存"))
        assertEquals("Clear custom background cache", LocalizationEngine.translateExact("清除自定义背景缓存"))
        assertEquals("Reset all onboarding guides", LocalizationEngine.translateExact("重置所有新手引导"))
        assertEquals("Clear all local data", LocalizationEngine.translateExact("清理全部本地数据"))
    }
}

