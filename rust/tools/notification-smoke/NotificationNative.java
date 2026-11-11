package com.haoze.diting.platform;

/// Host-JVM smoke test for the notification kernel's JNI boundary.
///
/// It proves the three exported symbols match the signatures `NotificationNative.kt` declares and
/// that the item list, running-text chain and detail line round trip. The rules themselves belong
/// to the Rust tests.
public final class NotificationNative {
    private static int checks;

    public static void main(String[] args) {
        System.load(args.length > 0 ? args[0] : "diting_notification_core");
        NotificationNative native_ = new NotificationNative();

        check(native_.statsItems("", false, true).equals("speed"), "legacy speed");
        check(native_.statsItems("", false, false).isEmpty(), "no legacy speed");
        check(
            native_.statsItems(" total, ,passed,total, speed ", true, true)
                .equals("total\npassed\nspeed"),
            "ordered and deduplicated"
        );
        check(native_.statsItems("", true, true).isEmpty(), "explicit empty");

        check(
            native_.runningText("  custom  ", "mode", "fallback").equals("  custom  "),
            "custom text"
        );
        check(native_.runningText("  ", "mode", "fallback").equals("mode"), "mode default");
        check(native_.runningText("", " ", "fallback").equals("fallback"), "fallback");

        String line = native_.compose(
            "total\nspeed\npassed",
            "{\"total\":\"Requests\"}",
            1_234,
            7,
            3,
            1,
            2,
            4,
            true,
            1_572_864,
            524_288
        );
        check(
            line.equals("Requests 1,234  ·  ↑ 1.5 MB/s  ↓ 512 KB/s  ·  通过 7"),
            "composed line"
        );
        check(
            native_.compose("passed", "{\"passed\":\"  \"}", 0, 7, 0, 0, 0, 0, false, 0, 0)
                .equals("通过 7"),
            "blank label falls back"
        );
        check(
            native_.compose("cached", "not json", 0, 0, 0, 0, 2, 0, false, 0, 0)
                .equals("缓存命中 2"),
            "malformed labels"
        );
        check(
            native_.compose("speed", "", 0, 0, 0, 0, 0, 0, false, 1, 1) == null,
            "no monitor"
        );
        check(
            native_.compose("unknown", "", 0, 0, 0, 0, 0, 0, true, 0, 0) == null,
            "unknown item"
        );

        System.out.println("notification smoke ok: " + checks + " checks");
    }

    private static void check(boolean value, String label) {
        if (!value) throw new AssertionError(label);
        checks++;
    }

    native String statsItems(String raw, boolean hasRaw, boolean legacySpeed);
    native String runningText(String custom, String modeDefault, String fallback);
    native String compose(
        String items,
        String labelsJson,
        long total,
        long passed,
        long filtered,
        long failed,
        long cached,
        long rewritten,
        boolean withSpeed,
        long txBps,
        long rxBps
    );
}
