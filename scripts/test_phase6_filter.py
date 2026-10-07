#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
谛听 (DITING) 阶段 6 规则过滤引擎黑盒验证工具
用于验证 AdGuard 语法解析、Trie 树与 Bloom 预检、广告拦截响应 (0.0.0.0 / ::)、白名单例外放行与 IPC 规则控制。
"""

import json
import os
import sys
import time
import urllib.request
import urllib.error
from test_dns import DNSClient, DNSType, DNSRcode, resolve_target_port

def test_ipc_filter(ipc_base: str = "http://127.0.0.1:15353", token: str = "") -> bool:
    print("-" * 65)
    print(f"[*] 测试 IPC 规则过滤接口: {ipc_base}")
    headers = {"Content-Type": "application/json"}
    if token:
        headers["Authorization"] = f"Bearer {token}"

    passed = 0
    total = 3

    # 1. GET /api/v1/filter/stats
    print("[1/3] 测试获取过滤统计 (GET /api/v1/filter/stats)...", end=" ", flush=True)
    try:
        req = urllib.request.Request(f"{ipc_base}/api/v1/filter/stats", headers=headers)
        with urllib.request.urlopen(req, timeout=3) as resp:
            data = json.loads(resp.read().decode("utf-8"))
            if data.get("success") and "data" in data:
                print(f"PASS (总规则数: {data['data'].get('totalRules')}, 拦截数: {data['data'].get('blockedQueries')})")
                passed += 1
            else:
                print(f"FAIL ({data})")
    except Exception as e:
        print(f"SKIP ({e})")

    # 2. POST /api/v1/filter/rules (注入临时测试规则)
    print("[2/3] 测试保存自定义规则 (POST /api/v1/filter/rules)...", end=" ", flush=True)
    try:
        rules_payload = json.dumps({
            "rules": [
                "||diting-test-ad.local^",
                "@@||allow.diting-test-ad.local^",
            ]
        }).encode("utf-8")
        req = urllib.request.Request(f"{ipc_base}/api/v1/filter/rules", data=rules_payload, headers=headers, method="POST")
        with urllib.request.urlopen(req, timeout=3) as resp:
            data = json.loads(resp.read().decode("utf-8"))
            if data.get("success"):
                print("PASS (自定义规则注入成功)")
                passed += 1
            else:
                print(f"FAIL ({data})")
    except Exception as e:
        print(f"SKIP ({e})")

    # 3. POST /api/v1/filter/check (检测域名命中)
    print("[3/3] 测试域名规则检测 (POST /api/v1/filter/check)...", end=" ", flush=True)
    try:
        check_payload = json.dumps({"domain": "diting-test-ad.local", "qtype": "A"}).encode("utf-8")
        req = urllib.request.Request(f"{ipc_base}/api/v1/filter/check", data=check_payload, headers=headers, method="POST")
        with urllib.request.urlopen(req, timeout=3) as resp:
            data = json.loads(resp.read().decode("utf-8"))
            if data.get("success") and data.get("data", {}).get("blocked") is True:
                print("PASS (域名正确判定为 blocked)")
                passed += 1
            else:
                print(f"FAIL ({data})")
    except Exception as e:
        print(f"SKIP ({e})")

    return passed == total

def run_phase6_verification(server: str = "127.0.0.1", port: int = 53, ipc_base: str = "http://127.0.0.1:15353") -> bool:
    print("=" * 65)
    print("谛听 (DITING) 阶段 6 规则过滤引擎与阻断响应黑盒验证套件")
    print(f"目标 DNS 服务: {server}:{port}")
    print(f"目标 IPC 地址: {ipc_base}")
    print("=" * 65)

    client = DNSClient(server=server, port=port, timeout=3.0)
    passed = 0
    total = 4

    # 尝试配置测试规则
    test_ipc_filter(ipc_base)

    # 1. 验证黑名单域名阻断 (Type A -> 0.0.0.0)
    bad_domain = "diting-test-ad.local"
    print(f"[1/4] 测试广告拦截与空 IP 应答 ({bad_domain})...", end=" ", flush=True)
    try:
        resp, ms = client.query(bad_domain, DNSType.A)
        if resp.rcode == DNSRcode.NOERROR and len(resp.answers) > 0 and resp.answers[0].data == "0.0.0.0":
            print(f"PASS (返回 0.0.0.0, 耗时 {ms:.1f}ms, 成功阻断)")
            passed += 1
        else:
            ans = [a.data for a in resp.answers]
            print(f"FAIL (未按预期拦截: rcode={resp.rcode}, answers={ans})")
    except Exception as e:
        print(f"ERROR ({e})")

    # 2. 验证子域名继承阻断 (sub.diting-test-ad.local)
    sub_bad_domain = "sub.diting-test-ad.local"
    print(f"[2/4] 测试倒序 Trie 树子域继承阻断 ({sub_bad_domain})...", end=" ", flush=True)
    try:
        resp, ms = client.query(sub_bad_domain, DNSType.A)
        if resp.rcode == DNSRcode.NOERROR and len(resp.answers) > 0 and resp.answers[0].data == "0.0.0.0":
            print(f"PASS (返回 0.0.0.0, 子域名成功拦截)")
            passed += 1
        else:
            ans = [a.data for a in resp.answers]
            print(f"FAIL (子域名未拦截: {ans})")
    except Exception as e:
        print(f"ERROR ({e})")

    # 3. 验证白名单例外放行 (@@||allow.diting-test-ad.local^)
    allow_domain = "allow.diting-test-ad.local"
    print(f"[3/4] 测试白名单例外放行优先级 ({allow_domain})...", end=" ", flush=True)
    try:
        resp, ms = client.query(allow_domain, DNSType.A)
        # 白名单会穿透至上游，返回正常上游结果或 NXDOMAIN，但绝不应为 0.0.0.0
        ans = [a.data for a in resp.answers]
        if "0.0.0.0" not in ans:
            print(f"PASS (白名单未被阻断为 0.0.0.0, 正常穿透上游)")
            passed += 1
        else:
            print(f"FAIL (白名单被错误阻断: {ans})")
    except Exception as e:
        print(f"ERROR ({e})")

    # 4. 验证干净域名透传与 Bloom 预检
    clean_domain = "www.bing.com"
    print(f"[4/4] 测试干净域名透传与 Bloom 过滤 ({clean_domain})...", end=" ", flush=True)
    try:
        resp, ms = client.query(clean_domain, DNSType.A)
        if resp.rcode == DNSRcode.NOERROR and len(resp.answers) > 0 and "0.0.0.0" not in [a.data for a in resp.answers]:
            print(f"PASS (正常解析交付, 耗时 {ms:.1f}ms)")
            passed += 1
        else:
            print(f"FAIL (干净域名解析异常: rcode={resp.rcode})")
    except Exception as e:
        print(f"ERROR ({e})")

    print("-" * 65)
    print(f"阶段 6 验证结果: {passed}/{total} 项通过 ({passed/total*100:.1f}%)")
    print("=" * 65)
    return passed == total

if __name__ == "__main__":
    server = sys.argv[1] if len(sys.argv) > 1 else "127.0.0.1"
    port = int(sys.argv[2]) if len(sys.argv) > 2 else resolve_target_port(server, None)
    ipc_addr = sys.argv[3] if len(sys.argv) > 3 else "http://127.0.0.1:15353"
    ok = run_phase6_verification(server, port, ipc_addr)
    sys.exit(0 if ok else 1)
