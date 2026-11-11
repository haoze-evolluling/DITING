package com.haoze.diting.watchdog;

import java.io.ByteArrayInputStream;
import java.io.DataInputStream;
import java.io.IOException;

/// Host-JVM smoke test for the VPN watchdog kernel's JNI boundary.
///
/// It proves the eight exported symbols match the signatures `VpnWatchdogNative.kt` declares and
/// that the phase/debounce/reconnect payloads round trip. The transition rules themselves belong
/// to the Rust tests.
public final class VpnWatchdogNative {
    private static int checks;

    public static void main(String[] args) throws IOException {
        System.load(args.length > 0 ? args[0] : "diting_vpn_config_core");
        VpnWatchdogNative native_ = new VpnWatchdogNative();

        long handle = native_.newHandle();
        check(handle != 0, "handle");
        check(native_.start(handle, 1_000) == 2_000, "grace");
        Step wait = step(native_.evaluate(handle, 3_000, false));
        check(wait.event == 0 && wait.delay == 1_000, "confirm poll");
        Step user = step(native_.evaluate(handle, 16_000, false));
        check(user.event == 3 && user.delay == 0, "user disconnect");
        native_.stop(handle);
        native_.free(handle);

        handle = native_.newHandle();
        native_.start(handle, 0);
        Step occupied = step(native_.evaluate(handle, 2_000, true));
        check(occupied.event == 1 && occupied.delay == 5_000, "occupied");
        Step debounce = step(native_.evaluate(handle, 3_000, false));
        check(debounce.event == 0 && debounce.delay == 3_000, "debounce start");
        Step nearly = step(native_.evaluate(handle, 5_999, false));
        check(nearly.event == 0 && nearly.delay == 1, "debounce remaining");
        Step released = step(native_.evaluate(handle, 6_000, false));
        check(released.event == 2 && released.delay == 5_000, "released");
        Step again = step(native_.evaluate(handle, 7_000, true));
        check(again.event == 1, "occupied again");
        native_.stop(handle);
        native_.free(handle);

        check(native_.shouldFollow(true, "normal", "normal", true), "should follow");
        check(!native_.shouldFollow(false, "normal", "normal", true), "switch off");
        check(!native_.shouldFollow(true, "express", "normal", true), "wrong mode");
        check(native_.reclaimAllowed(true, "normal", "normal"), "reclaim allowed");
        check(!native_.reclaimAllowed(true, "express", "normal"), "reclaim blocked");
        check(native_.reconnectDecision(true, "normal", "normal", false, true) == 0, "reconnect");
        check(native_.reconnectDecision(true, "normal", "normal", true, true) == 2, "needs consent");
        check(native_.reconnectDecision(true, "normal", "normal", false, false) == 3, "give up");
        check(native_.reconnectDecision(true, "express", "normal", false, true) == 1, "user disconnect");

        System.out.println("vpn-watchdog smoke ok: " + checks + " checks");
    }

    private static Step step(byte[] payload) throws IOException {
        check(payload != null && payload.length == 9, "payload length");
        DataInputStream input = new DataInputStream(new ByteArrayInputStream(payload));
        return new Step(input.readUnsignedByte(), input.readLong());
    }

    private static void check(boolean value, String label) {
        if (!value) throw new AssertionError(label);
        checks++;
    }

    private record Step(int event, long delay) {}

    native long newHandle();
    native void free(long handle);
    native long start(long handle, long nowMs);
    native byte[] evaluate(long handle, long nowMs, boolean occupied);
    native void stop(long handle);
    native boolean shouldFollow(
        boolean enabled,
        String currentMode,
        String expectedMode,
        boolean hasIntent
    );
    native boolean reclaimAllowed(boolean enabled, String currentMode, String expectedMode);
    native int reconnectDecision(
        boolean enabled,
        String currentMode,
        String expectedMode,
        boolean consentMissing,
        boolean hasIntent
    );
}
