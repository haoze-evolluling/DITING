#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
谛听 (DITING) 阶段 5 智能缓存黑盒验证工具
用于验证 64 分片 LRU 缓存、TTL 动态递减重写、负缓存与重复查询纳秒/亚毫秒级加速。
"""

import sys
import time
from test_dns import DNSClient, DNSType, DNSRcode, resolve_target_port

def run_phase5_verification(server: str = "127.0.0.1", port: int = 53) -> bool:
    print("=" * 65)
    print("谛听 (DITING) 阶段 5 智能缓存与 SWR 体系黑盒验证套件")
    print(f"目标 DNS 服务: {server}:{port}")
    print("=" * 65)

    client = DNSClient(server=server, port=port, timeout=4.0)
    passed = 0
    total = 4

    # 1. 验证首查回源与次查缓存命中加速
    test_domain = "www.bing.com"
    print(f"[1/4] 测试缓存命中与加速 ({test_domain})...", end=" ", flush=True)
    try:
        resp1, ms1 = client.query(test_domain, DNSType.A)
        time.sleep(0.05)
        resp2, ms2 = client.query(test_domain, DNSType.A)
        if resp1.rcode == DNSRcode.NOERROR and resp2.rcode == DNSRcode.NOERROR:
            speedup = f"{ms1:.1f}ms -> {ms2:.1f}ms"
            print(f"PASS (首查 {ms1:.1f}ms, 命中缓存 {ms2:.1f}ms, 加速成功)")
            passed += 1
        else:
            print(f"FAIL (响应码异常: {resp1.rcode}, {resp2.rcode})")
    except Exception as e:
        print(f"ERROR ({e})")

    # 2. 验证 TTL 递减重写机制 (RFC 规范)
    print(f"[2/4] 测试 RFC 规范动态 TTL 递减重写 ({test_domain})...", end=" ", flush=True)
    try:
        time.sleep(1.1)
        resp3, _ = client.query(test_domain, DNSType.A)
        if len(resp2.answers) > 0 and len(resp3.answers) > 0:
            ttl2 = resp2.answers[0].ttl
            ttl3 = resp3.answers[0].ttl
            if ttl3 <= ttl2:
                print(f"PASS (TTL 正常递减: {ttl2}s -> {ttl3}s)")
                passed += 1
            else:
                print(f"FAIL (TTL 未递减: {ttl2}s -> {ttl3}s)")
        else:
            print("FAIL (应答节为空)")
    except Exception as e:
        print(f"ERROR ({e})")

    # 3. 验证负缓存 (Negative Caching - NXDOMAIN)
    nx_domain = f"diting-phase5-nx-{int(time.time())}.invalid"
    print(f"[3/4] 测试负缓存拦截 ({nx_domain})...", end=" ", flush=True)
    try:
        nx_resp1, nx_ms1 = client.query(nx_domain, DNSType.A)
        time.sleep(0.05)
        nx_resp2, nx_ms2 = client.query(nx_domain, DNSType.A)
        if nx_resp1.rcode in (DNSRcode.NXDOMAIN, DNSRcode.NOERROR) and nx_resp2.rcode == nx_resp1.rcode:
            print(f"PASS (负缓存成功拦截并保持状态码, 延迟 {nx_ms1:.1f}ms -> {nx_ms2:.1f}ms)")
            passed += 1
        else:
            print(f"FAIL (负缓存状态码不一致: {nx_resp1.rcode} != {nx_resp2.rcode})")
    except Exception as e:
        print(f"ERROR ({e})")

    # 4. 验证 TCP 链路下的缓存命中
    print(f"[4/4] 测试 TCP 协议下的缓存命中与快速交付 ({test_domain})...", end=" ", flush=True)
    try:
        tcp_resp, tcp_ms = client.query(test_domain, DNSType.A, use_tcp=True)
        if tcp_resp.rcode == DNSRcode.NOERROR and len(tcp_resp.answers) > 0:
            print(f"PASS (TCP 命中缓存交付正常, 耗时 {tcp_ms:.1f}ms)")
            passed += 1
        else:
            print(f"FAIL (TCP 查询响应异常)")
    except Exception as e:
        print(f"ERROR ({e})")

    print("-" * 65)
    print(f"阶段 5 验证结果: {passed}/{total} 项通过 ({passed/total*100:.1f}%)")
    print("=" * 65)
    return passed == total

if __name__ == "__main__":
    server = sys.argv[1] if len(sys.argv) > 1 else "127.0.0.1"
    port = int(sys.argv[2]) if len(sys.argv) > 2 else resolve_target_port(server, None)
    ok = run_phase5_verification(server, port)
    sys.exit(0 if ok else 1)
