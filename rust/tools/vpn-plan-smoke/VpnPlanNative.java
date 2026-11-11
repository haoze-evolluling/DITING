package com.haoze.diting.vpn;

/// Host-JVM smoke test for the VPN plan kernel's JNI boundary.
///
/// It proves the three exported symbols match the signatures `VpnPlanNative.kt` declares and that
/// the route/start payloads round trip. The plan rules themselves belong to the Rust tests.
public final class VpnPlanNative {
    private static int checks;

    public static void main(String[] args) {
        System.load(args.length > 0 ? args[0] : "diting_vpn_config_core");
        VpnPlanNative native_ = new VpnPlanNative();

        String normal = native_.routePlan(
            "normal", "disabled", false, true, "com.app", "com.self", "com.proxy"
        );
        check(normal.contains("\"enableIpv6\":false"), "normal ipv6 off");
        check(normal.contains("\"mtu\":1400"), "normal mtu");
        check(normal.contains("\"address\":\"1.0.0.0\",\"prefix\":8"), "bypass lan route");
        check(normal.contains("\"address\":\"10.0.0.1\",\"prefix\":32"), "dns route");
        check(normal.contains("\"excludedPackages\":[\"com.app\",\"com.self\",\"com.proxy\"]"), "excluded union");

        String express = native_.routePlan(
            "express", "enabled", false, false, "", "com.self", ""
        );
        check(express.contains("\"enableIpv6\":true"), "express ipv6 on");
        check(express.contains("\"address\":\"8.8.8.8\",\"prefix\":32"), "express v4 hijack");
        check(express.contains("\"address\":\"fd00:abcd::1\",\"prefix\":128"), "express v6 dns route");
        check(!express.contains("\"address\":\"0.0.0.0\",\"prefix\":0"), "no default route");

        check(!native_.ipv6ProbeNeeded("enabled"), "explicit mode needs no probe");
        check(!native_.ipv6ProbeNeeded("DISABLED"), "disabled needs no probe");
        check(native_.ipv6ProbeNeeded("auto"), "auto probes");

        String defaults = native_.startDefaults();
        check(defaults.contains("\"bypassLan\":true"), "default bypass lan");
        check(defaults.contains("\"ipv6Mode\":\"auto\""), "default ipv6");
        check(defaults.contains("SOCKS5"), "default proxy document");

        System.out.println("vpn-plan smoke ok: " + checks + " checks");
    }

    private static void check(boolean value, String label) {
        if (!value) throw new AssertionError(label);
        checks++;
    }

    native String routePlan(
        String mode,
        String ipv6Mode,
        boolean ipv6Supported,
        boolean bypassLan,
        String excluded,
        String selfPackage,
        String proxyPackage
    );
    native boolean ipv6ProbeNeeded(String ipv6Mode);
    native String startDefaults();
}
