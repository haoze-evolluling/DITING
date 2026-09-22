#!/usr/bin/env python3
"""
Batch refactoring script: DNSSR -> DITING (谛听)
1. Renames package directories and specific classes
2. Replaces package name, imports, identifiers, variables, and configs
3. Updates versionCode to 1, versionName to 1.0.0
4. Updates English localization strings, docs, and scripts
"""

import os
import re
import subprocess
import shutil
import time

ROOT_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))

def run_cmd(cmd):
    cmd_str = ' '.join(cmd) if isinstance(cmd, list) else cmd
    print(f"Running: {cmd_str}")
    res = subprocess.run(cmd, cwd=ROOT_DIR, shell=isinstance(cmd, str), capture_output=True, text=True)
    if res.returncode != 0:
        print(f"Command failed ({res.returncode}): {res.stderr.strip()}")
        return False
    return True

def move_path(src_rel, dst_rel):
    src_abs = os.path.normpath(os.path.join(ROOT_DIR, src_rel))
    dst_abs = os.path.normpath(os.path.join(ROOT_DIR, dst_rel))
    if not os.path.exists(src_abs):
        print(f"Source already moved or does not exist: {src_rel}")
        return
    os.makedirs(os.path.dirname(dst_abs), exist_ok=True)
    # Try git mv first using forward-slash paths
    src_git = src_rel.replace("\\", "/")
    dst_git = dst_rel.replace("\\", "/")
    if not run_cmd(["git", "mv", src_git, dst_git]):
        print(f"Fallback moving {src_rel} -> {dst_rel}")
        shutil.move(src_abs, dst_abs)

def replace_in_file(rel_path, replacements):
    path = os.path.normpath(os.path.join(ROOT_DIR, rel_path))
    if not os.path.exists(path):
        print(f"File not found: {rel_path}")
        return
    with open(path, "r", encoding="utf-8") as f:
        content = f.read()

    new_content = content
    for old, new in replacements:
        new_content = new_content.replace(old, new)

    if new_content != content:
        for attempt in range(10):
            try:
                with open(path, "w", encoding="utf-8", newline="\n") as f:
                    f.write(new_content)
                print(f"Updated: {rel_path}")
                break
            except OSError as e:
                print(f"Warning: OSError on {rel_path} (attempt {attempt + 1}): {e}")
                time.sleep(0.2)

def main():
    print("=== Step 1: Renaming directories ===")
    move_path(
        "app/src/main/java/com/haoze/dnssr",
        "app/src/main/java/com/haoze/diting"
    )
    move_path(
        "app/src/test/java/com/haoze/dnssr",
        "app/src/test/java/com/haoze/diting"
    )

    print("=== Step 2: Renaming specific Kotlin files ===")
    move_path(
        "app/src/main/java/com/haoze/diting/DnssrApp.kt",
        "app/src/main/java/com/haoze/diting/DitingApp.kt"
    )
    move_path(
        "app/src/main/java/com/haoze/diting/vpn/DnssrTileService.kt",
        "app/src/main/java/com/haoze/diting/vpn/DitingTileService.kt"
    )

    print("=== Step 3: Updating Kotlin files in app/src ===")
    kotlin_replacements = [
        ("com.haoze.dnssr", "com.haoze.diting"),
        ("class DnssrApp", "class DitingApp"),
        ("var instance: DnssrApp?", "var instance: DitingApp?"),
        ("DnssrApp.instance", "DitingApp.instance"),
        ("class DnssrTileService", "class DitingTileService"),
        ("const val TAG = \"DnssrTileService\"", "const val TAG = \"DitingTileService\""),
        ("DnssrTileService::class.java", "DitingTileService::class.java"),
        ("DnssrTileService.requestTileUpdate", "DitingTileService.requestTileUpdate"),
        ("fun DNSSRTheme(", "fun DITINGTheme("),
        ("DNSSRTheme(", "DITINGTheme("),
        # Constants and variables
        ("\"dnssr_database\"", "\"diting_database\""),
        ("PREFS_NAME = \"dnssr_crash_state\"", "PREFS_NAME = \"diting_crash_state\""),
        ("\"dnssr_outbound_proxy\"", "\"diting_outbound_proxy\""),
        ("\"DNSSR-config-$date.json\"", "\"DITING-config-$date.json\""),
        ("\"DNSSR-crash-$date.txt\"", "\"DITING-crash-$date.txt\""),
        ("\"dnssr-request-logs-", "\"diting-request-logs-"),
        ("\"DNSSR-crash-auto-backup-", "\"DITING-crash-auto-backup-"),
        ("\"User-Agent\", \"DNSSR-Android\"", "\"User-Agent\", \"DITING-Android\""),
        ("getOrDefault(\"DNSSR\")", "getOrDefault(\"DITING\")"),
        ("DNSSR Crash detected!", "DITING Crash detected!"),
        ("\"DNSSR CRASH LOGS EXPORT", "\"DITING CRASH LOGS EXPORT"),
        # Crash report titles
        ("DNSSR CRASH REPORT", "DITING CRASH REPORT"),
        ("DNSSR NATIVE CRASH REPORT", "DITING NATIVE CRASH REPORT"),
    ]

    for root, dirs, files in os.walk(os.path.join(ROOT_DIR, "app", "src")):
        for f in files:
            if f.endswith(".kt"):
                rel_path = os.path.relpath(os.path.join(root, f), ROOT_DIR)
                replace_in_file(rel_path, kotlin_replacements)

    print("=== Step 3b: Specific file enhancements ===")
    # AddressRuleBackupCodec.kt: update FORMAT, keep backward compatibility
    backup_codec = "app/src/main/java/com/haoze/diting/vpn/AddressRuleBackupCodec.kt"
    replace_in_file(backup_codec, [
        ('private const val FORMAT = "dnssr_address_rule_backup"', 'private const val FORMAT = "diting_address_rule_backup"'),
        ('require(format == FORMAT || format == LEGACY_FORMAT)', 'require(format == FORMAT || format == "dnssr_address_rule_backup" || format == LEGACY_FORMAT)'),
    ])

    # CrashLogManager.kt: backward compatible crash type check
    crash_manager = "app/src/main/java/com/haoze/diting/crash/CrashLogManager.kt"
    replace_in_file(crash_manager, [
        ('if (line.contains("DITING NATIVE CRASH REPORT")) crashType = "Native Crash"',
         'if (line.contains("DITING NATIVE CRASH REPORT") || line.contains("DNSSR NATIVE CRASH REPORT")) crashType = "Native Crash"'),
        ('if (line.contains("DITING CRASH REPORT")) crashType = "Java Crash"',
         'if (line.contains("DITING CRASH REPORT") || line.contains("DNSSR CRASH REPORT")) crashType = "Java Crash"'),
    ])

    # AppUpdateManagerTest.kt: update release asset mock names
    update_test = "app/src/test/java/com/haoze/diting/update/AppUpdateManagerTest.kt"
    replace_in_file(update_test, [
        ('"name":"DNSSR.apk"', '"name":"DITING.apk"'),
        ('"name":"DNSSR-arm64-v8a.apk"', '"name":"DITING-arm64-v8a.apk"'),
    ])

    # Update English localizations (DNSSR -> DITING)
    loc_dir = os.path.join(ROOT_DIR, "app", "src", "main", "java", "com", "haoze", "diting", "ui", "localization")
    if os.path.exists(loc_dir):
        for fn in os.listdir(loc_dir):
            if fn.endswith(".kt"):
                rel_path = os.path.relpath(os.path.join(loc_dir, fn), ROOT_DIR)
                replace_in_file(rel_path, [
                    ('"DNSSR"', '"DITING"'),
                    ('DNSSR ', 'DITING '),
                    (' DNSSR', ' DITING'),
                    ('DNSSR\'s', 'DITING\'s'),
                    ('DNSSR.', 'DITING.'),
                    ('DNSSR,', 'DITING,'),
                    ('DNSSR;', 'DITING;'),
                    ('DNSSR:', 'DITING:'),
                    ('DNSSR/', 'DITING/'),
                    ('/DNSSR', '/DITING'),
                ])

    print("=== Step 4: Updating Gradle & Project configurations ===")
    # settings.gradle.kts
    replace_in_file("settings.gradle.kts", [
        ('rootProject.name = "DNSSR"', 'rootProject.name = "DITING"')
    ])

    # app/build.gradle.kts
    replace_in_file("app/build.gradle.kts", [
        ('namespace = "com.haoze.dnssr"', 'namespace = "com.haoze.diting"'),
        ('applicationId = "com.haoze.dnssr"', 'applicationId = "com.haoze.diting"'),
        ('versionCode = 60017', 'versionCode = 1'),
        ('versionName = "6.17"', 'versionName = "1.0.0"'),
    ])

    # app/proguard-rules.pro
    replace_in_file("app/proguard-rules.pro", [
        ('com.haoze.dnssr', 'com.haoze.diting')
    ])

    # AndroidManifest.xml
    replace_in_file("app/src/main/AndroidManifest.xml", [
        ('android:name=".DnssrApp"', 'android:name=".DitingApp"'),
        ('android:name=".vpn.DnssrTileService"', 'android:name=".vpn.DitingTileService"'),
        ('android:theme="@style/Theme.DNSSR"', 'android:theme="@style/Theme.DITING"'),
    ])

    # Resource files
    for colors_file in ["app/src/main/res/values/colors.xml", "app/src/main/res/values-night/colors.xml"]:
        replace_in_file(colors_file, [
            ('name="dnssr_window_background"', 'name="diting_window_background"')
        ])

    for themes_file in ["app/src/main/res/values/themes.xml", "app/src/main/res/values-night/themes.xml"]:
        replace_in_file(themes_file, [
            ('<style name="Theme.DNSSR"', '<style name="Theme.DITING"'),
            ('@color/dnssr_window_background', '@color/diting_window_background')
        ])

    replace_in_file("app/src/main/res/values-en/strings.xml", [
        ('<string name="app_name">DNSSR</string>', '<string name="app_name">DITING</string>'),
        ('<string name="quick_settings_tile_label">DNSSR</string>', '<string name="quick_settings_tile_label">DITING</string>'),
        ('<string name="feature_hub_about_app">About DNSSR</string>', '<string name="feature_hub_about_app">About DITING</string>'),
        ('<string name="localized_text_641631276">About DNSSR</string>', '<string name="localized_text_641631276">About DITING</string>'),
        ('<string name="localized_text_1133425">DNSSR</string>', '<string name="localized_text_1133425">DITING</string>'),
    ])

    replace_in_file("app/src/main/assets/https_passthrough.txt", [
        ('# DITING (DNSSR) preset passthrough list', '# DITING preset passthrough list')
    ])

    print("=== Step 5: Updating Go tunnel sources ===")
    replace_in_file("tunnel/engine_request_filter.go", [
        ('Blocked by DNSSR', 'Blocked by DITING')
    ])
    replace_in_file("tunnel/mitm_cert_manager.go", [
        ('caOrganization = "DNSSR"', 'caOrganization = "DITING"'),
        ('caCommonName   = "DNSSR HTTPS Inspection Root CA"', 'caCommonName   = "DITING HTTPS Inspection Root CA"'),
    ])

    print("=== Step 6: Updating maintenance scripts ===")
    for script_fn in ["scripts/i18n_audit.py", "scripts/i18n_dedup.py", "scripts/i18n_dups.py"]:
        replace_in_file(script_fn, [
            ('"com", "haoze", "dnssr"', '"com", "haoze", "diting"'),
            ('DNSSR', 'DITING'),
        ])

    print("=== Step 7: Updating documentation ===")
    replace_in_file("README.md", [
        ('# DITING (DNSSR)', '# DITING'),
        ('DNSSR is a local DNS', 'DITING is a local DNS'),
        ('DNSSR', 'DITING'),
    ])
    replace_in_file("README.zh-CN.md", [
        ('# 谛听 (DNSSR)', '# 谛听 (DITING)'),
        ('谛听（DNSSR）', '谛听（DITING）'),
        ('DNSSR', 'DITING'),
    ])
    replace_in_file("docs/README.md", [
        ('DITING (DNSSR)', 'DITING')
    ])
    replace_in_file("docs/development/aar-build-notes.md", [
        ('DNSSR', 'DITING')
    ])
    replace_in_file("docs/development/dns-filtering-gap-analysis.md", [
        ('DNSSR', 'DITING')
    ])

    print("=== Refactoring completed! ===")

if __name__ == "__main__":
    main()
