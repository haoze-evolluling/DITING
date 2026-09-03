package com.haoze.dnssr.update

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AppUpdateManagerTest {
    @Test
    fun comparesNumericVersionsAndIgnoresPrereleaseSuffix() {
        assertTrue(isNewerVersion("v3.0.18", "3.0.17"))
        assertFalse(isNewerVersion("v3.0.17", "3.0.17"))
        assertFalse(isNewerVersion("v3.0.17-beta", "3.0.17"))
        assertFalse(isNewerVersion("not-a-version", "3.0.17"))
    }

    @Test
    fun parsesNewerReleaseAndPrefersArm64Asset() {
        val update = parseLatestRelease(
            """{"tag_name":"v3.0.18","body":"- 修复网络问题","assets":[{"name":"DNSSR.apk","browser_download_url":"https://example.com/universal.apk"},{"name":"DNSSR-arm64-v8a.apk","browser_download_url":"https://example.com/arm64.apk"}]}""",
            "3.0.17",
        )

        requireNotNull(update)
        assertEquals("3.0.18", update.version)
        assertEquals("https://example.com/arm64.apk", update.downloadUrl)
        assertEquals("- 修复网络问题", update.releaseNotes)
    }
}
