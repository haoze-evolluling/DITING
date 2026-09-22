package com.haoze.diting.ui

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
}
