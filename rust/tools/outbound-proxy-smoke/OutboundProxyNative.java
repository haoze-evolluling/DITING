package com.haoze.diting.proxy;

/// Host-JVM smoke test for the outbound-proxy kernel's JNI boundary.
///
/// It proves the five exported symbols match the signatures `OutboundProxyNative.kt` declares and
/// that the package/UID rewrite round trips. The rules themselves belong to the Rust tests.
public final class OutboundProxyNative {
    private static int checks;

    public static void main(String[] args) {
        System.load(args.length > 0 ? args[0] : "diting_outbound_proxy_core");
        OutboundProxyNative native_ = new OutboundProxyNative();

        check(native_.normalizeProtocol(" HTTP ").equals("http"), "protocol http");
        check(native_.normalizeProtocol("quic").equals("socks5"), "protocol fallback");
        check(native_.normalizeScope(" APPS ").equals("apps"), "scope apps");
        check(native_.normalizeScope("weird").equals("all"), "scope fallback");
        check(native_.normalizeTargets("a\n\na\nb").equals("a\nb"), "targets");

        String json = "{\"enabled\":true,\"scope\":\"apps\",\"packages\":[\"com.a\",\"com.b\"]}";
        check("com.a\ncom.b".equals(native_.packages(json)), "packages");
        check(native_.packages("{\"enabled\":true}") == null, "no packages");
        String rewritten = native_.applyUids(json, "10001,10002");
        check(rewritten.contains("\"uids\":[10001,10002]"), "uids rewritten");
        check(!rewritten.contains("\"packages\""), "packages removed");
        check(native_.applyUids("not json", "1").equals("not json"), "malformed untouched");

        System.out.println("outbound-proxy smoke ok: " + checks + " checks");
    }

    private static void check(boolean value, String label) {
        if (!value) throw new AssertionError(label);
        checks++;
    }

    native String normalizeProtocol(String value);
    native String normalizeScope(String value);
    native String normalizeTargets(String value);
    native String packages(String proxyJson);
    native String applyUids(String proxyJson, String uidsCsv);
}
