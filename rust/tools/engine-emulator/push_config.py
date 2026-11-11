#!/usr/bin/env python3
"""Point the on-device server mode at a given DNS config, without touching the app's UI.

The `DitingDnsServerService` is not exported, so `adb shell am start-foreground-service` cannot start
it (that is the app's own protection, not a test obstacle). What *is* reachable is the path the app
itself uses after a reboot or an in-app update: `DnsModeBootReceiver` replays
`diting_dns_mode_prefs.last_dns_config` when it receives `MY_PACKAGE_REPLACED`, and reinstalling the
debug APK delivers exactly that broadcast.

So the sequence is:

1. force-stop the app (no process holds the cached SharedPreferences);
2. overwrite `shared_prefs/diting_dns_mode_prefs.xml` through `run-as` with our config;
3. `adb install -r` the same APK, which fires `MY_PACKAGE_REPLACED` → receiver → service start;
4. wait for the frame's port to be listening.

    python rust/tools/engine-emulator/push_config.py --config doh.json --apk build/app/outputs/flutter-apk/app-debug.apk

Requires a debuggable APK (it uses `run-as`).
"""

from __future__ import annotations

import argparse
import base64
import json
import subprocess
import sys
import time
import xml.sax.saxutils as sax

PREFS_PATH = "shared_prefs/diting_dns_mode_prefs.xml"
PROBE_PORT = 15533


def adb(*args: str, serial: str | None = None, stdin: bytes | None = None) -> str:
    command = ["adb"]
    if serial:
        command += ["-s", serial]
    command += list(args)
    result = subprocess.run(command, input=stdin, capture_output=True)
    if result.returncode != 0:
        raise RuntimeError(
            f"adb {' '.join(args)} failed: {result.stderr.decode(errors='replace').strip()}"
        )
    return result.stdout.decode(errors="replace")


def build_prefs(dns_config: str, port: int, ad_block: bool) -> str:
    # The keys the service reads; `selected_upstream_id`/`custom_upstreams` are UI-only. Query logging
    # is forced on so the engine's own error rows land in `dns_log` and the probe run leaves evidence.
    return (
        "<?xml version='1.0' encoding='utf-8' standalone='yes' ?>\n"
        "<map>\n"
        f'    <string name="last_dns_config">{sax.escape(dns_config, {"\'": "&apos;"})}</string>\n'
        '    <boolean name="service_active" value="true" />\n'
        f'    <boolean name="last_ad_block_enabled" value="{str(ad_block).lower()}" />\n'
        f'    <int name="local_listen_port" value="{port}" />\n'
        '    <boolean name="log_queries" value="true" />\n'
        "</map>\n"
    )


def main() -> int:
    parser = argparse.ArgumentParser(description="Configure the on-device server mode via run-as")
    parser.add_argument("--config", required=True, help="file holding the ApplyDNSConfig JSON")
    parser.add_argument("--apk", required=True, help="debuggable APK to reinstall (restart trigger)")
    parser.add_argument("--port", type=int, default=1053)
    parser.add_argument("--ad-block", action="store_true")
    parser.add_argument("--skip-install", action="store_true", help="write prefs only")
    parser.add_argument("--host-port", type=int, default=PROBE_PORT, help="host side of adb forward")
    parser.add_argument("--serial", default=None)
    args = parser.parse_args()

    with open(args.config, encoding="utf-8") as handle:
        config = handle.read().strip()
    json.loads(config)  # fail early on a malformed document
    prefs = build_prefs(config, args.port, args.ad_block)

    adb("shell", "am", "force-stop", "com.haoze.diting", serial=args.serial)
    encoded = base64.b64encode(prefs.encode()).decode()
    adb(
        "shell",
        "run-as com.haoze.diting sh -c "
        f"'echo {encoded} | base64 -d > {PREFS_PATH} && wc -c {PREFS_PATH}'",
        serial=args.serial,
    )
    print("[device] prefs written", flush=True)

    if not args.skip_install:
        # A force-stopped package is in the "stopped" state and receives no broadcasts at all, so
        # the replace broadcast would be dropped. Launching the activity once clears that state;
        # the install that follows kills the process and delivers `MY_PACKAGE_REPLACED`.
        adb(
            "shell",
            "am",
            "start",
            "-n",
            "com.haoze.diting/.MainActivity",
            serial=args.serial,
        )
        time.sleep(2)
        adb("logcat", "-c", serial=args.serial)
        adb("install", "-r", args.apk, serial=args.serial)
        print("[device] reinstalled; waiting for MY_PACKAGE_REPLACED", flush=True)

    # The receiver starts the service, which binds UDP/TCP before `startStandalone` returns. The port
    # alone is not a readiness signal: the previous instance's socket can outlive the reinstall for a
    # moment, and probing then would query the *old* engine and silently test the wrong config. The
    # service's own log line is unambiguous, and it also carries the failure text when a config is
    # rejected.
    adb("forward", f"tcp:{args.host_port}", f"tcp:{args.port}", serial=args.serial)
    deadline = time.time() + 60
    while time.time() < deadline:
        log = adb("logcat", "-d", "-s", "DitingDnsServerService:*", serial=args.serial)
        if "standalone DNS server listening" in log:
            lines = [line for line in log.splitlines() if line.strip()]
            print(f"[device] {lines[-1].strip()}", flush=True)
            print(f"[device] host forward tcp:{args.host_port}", flush=True)
            return 0
        if "Unable to start standalone DNS server" in log:
            start_at = log.index("Unable to start standalone DNS server")
            print("[device] start failed: " + log[start_at:][:800], file=sys.stderr)
            return 1
        time.sleep(1)
    print(f"[device] server never reported listening on {args.port}", file=sys.stderr)
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
