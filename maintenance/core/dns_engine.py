#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
谛听 (DITING) DNS 核心引擎与验证套件
纯标准库实现，支持 UDP/TCP 双栈，包含结构化查询、批量压测与阶段 1 自动化验证。
"""

import argparse
import random
import socket
import struct
import sys
import time
from enum import IntEnum
from typing import Any, Callable, Dict, List, Optional, Tuple

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")
if hasattr(sys.stderr, "reconfigure"):
    sys.stderr.reconfigure(encoding="utf-8")


class DNSType(IntEnum):
    A = 1
    NS = 2
    CNAME = 5
    SOA = 6
    PTR = 12
    MX = 15
    TXT = 16
    AAAA = 28
    ANY = 255

    @classmethod
    def from_str(cls, name: str) -> "DNSType":
        upper = name.strip().upper()
        if hasattr(cls, upper):
            return cls[upper]
        try:
            return cls(int(name))
        except ValueError:
            raise ValueError(f"未知 DNS 记录类型: {name}")


class DNSRcode(IntEnum):
    NOERROR = 0
    FORMERR = 1
    SERVFAIL = 2
    NXDOMAIN = 3
    NOTIMP = 4
    REFUSED = 5

    @classmethod
    def to_name(cls, code: int) -> str:
        for item in cls:
            if item.value == code:
                return item.name
        return f"RCODE_{code}"


def encode_domain_name(domain: str) -> bytes:
    domain = domain.rstrip(".")
    if not domain:
        return b"\x00"
    out = bytearray()
    for label in domain.split("."):
        encoded = label.encode("idna")
        if len(encoded) > 63:
            raise ValueError(f"Label 长度超过 63 字节: {label}")
        out.append(len(encoded))
        out.extend(encoded)
    out.append(0)
    return bytes(out)


def decode_domain_name(data: bytes, offset: int) -> Tuple[str, int]:
    labels: List[str] = []
    jumped = False
    original_offset = offset
    jumps = 0
    max_jumps = 32

    while True:
        if offset >= len(data):
            raise ValueError("域名解析越界")
        length = data[offset]
        if length == 0:
            offset += 1
            if not jumped:
                original_offset = offset
            break
        if (length & 0xC0) == 0xC0:
            if offset + 1 >= len(data):
                raise ValueError("压缩指针越界")
            pointer = ((length & 0x3F) << 8) | data[offset + 1]
            if not jumped:
                original_offset = offset + 2
                jumped = True
            jumps += 1
            if jumps > max_jumps:
                raise ValueError("解析域名时检测到压缩指针循环引用")
            offset = pointer
            continue

        offset += 1
        if offset + length > len(data):
            raise ValueError("Label 数据越界")
        raw_label = data[offset : offset + length]
        try:
            label = raw_label.decode("idna")
        except Exception:
            label = raw_label.decode("utf-8", errors="replace")
        labels.append(label)
        offset += length

    domain = ".".join(labels)
    return domain, (original_offset if jumped else offset)


class DNSQuestion:
    def __init__(self, name: str, qtype: int, qclass: int = 1):
        self.name = name.rstrip(".")
        self.qtype = qtype
        self.qclass = qclass

    def to_bytes(self) -> bytes:
        return encode_domain_name(self.name) + struct.pack("!HH", self.qtype, self.qclass)


class DNSRecord:
    def __init__(self, name: str, rtype: int, rclass: int, ttl: int, rdata: Any, raw_rdata: bytes):
        self.name = name
        self.rtype = rtype
        self.rclass = rclass
        self.ttl = ttl
        self.rdata = rdata
        self.raw_rdata = raw_rdata

    def to_dict(self) -> dict:
        type_str = DNSType(self.rtype).name if self.rtype in DNSType._value2member_map_ else f"TYPE{self.rtype}"
        return {
            "name": self.name,
            "type": type_str,
            "ttl": self.ttl,
            "value": str(self.rdata),
        }

    def __str__(self) -> str:
        type_str = DNSType(self.rtype).name if self.rtype in DNSType._value2member_map_ else f"TYPE{self.rtype}"
        return f"{self.name}.\t{self.ttl}\tIN\t{type_str}\t{self.rdata}"


class DNSMessage:
    def __init__(self):
        self.id = random.randint(1, 65535)
        self.qr = 0
        self.opcode = 0
        self.aa = 0
        self.tc = 0
        self.rd = 1
        self.ra = 0
        self.rcode = 0
        self.questions: List[DNSQuestion] = []
        self.answers: List[DNSRecord] = []
        self.authorities: List[DNSRecord] = []
        self.additionals: List[DNSRecord] = []

    def to_bytes(self) -> bytes:
        flags = (
            ((self.qr & 1) << 15)
            | ((self.opcode & 0xF) << 11)
            | ((self.aa & 1) << 10)
            | ((self.tc & 1) << 9)
            | ((self.rd & 1) << 8)
            | ((self.ra & 1) << 7)
            | (self.rcode & 0xF)
        )
        header = struct.pack(
            "!HHHHHH",
            self.id,
            flags,
            len(self.questions),
            len(self.answers),
            len(self.authorities),
            len(self.additionals),
        )
        body = bytearray(header)
        for q in self.questions:
            body.extend(q.to_bytes())
        return bytes(body)

    @classmethod
    def from_bytes(cls, data: bytes) -> "DNSMessage":
        if len(data) < 12:
            raise ValueError(f"DNS 报文长度过短: {len(data)} 字节")

        msg = cls()
        msg.id, flags, qdcount, ancount, nscount, arcount = struct.unpack("!HHHHHH", data[:12])
        msg.qr = (flags >> 15) & 1
        msg.opcode = (flags >> 11) & 0xF
        msg.aa = (flags >> 10) & 1
        msg.tc = (flags >> 9) & 1
        msg.rd = (flags >> 8) & 1
        msg.ra = (flags >> 7) & 1
        msg.rcode = flags & 0xF

        offset = 12
        for _ in range(qdcount):
            name, offset = decode_domain_name(data, offset)
            if offset + 4 > len(data):
                raise ValueError("Question 节格式错误")
            qtype, qclass = struct.unpack("!HH", data[offset : offset + 4])
            offset += 4
            msg.questions.append(DNSQuestion(name, qtype, qclass))

        def parse_records(count: int) -> List[DNSRecord]:
            nonlocal offset
            records: List[DNSRecord] = []
            for _ in range(count):
                rname, offset = decode_domain_name(data, offset)
                if offset + 10 > len(data):
                    raise ValueError("Resource Record 头格式错误")
                rtype, rclass, ttl, rdlength = struct.unpack("!HHIH", data[offset : offset + 10])
                offset += 10
                if offset + rdlength > len(data):
                    raise ValueError("RDATA 长度超出报文范围")

                raw_rdata = data[offset : offset + rdlength]
                rdata_val: Any = None
                if rtype == DNSType.A and rdlength == 4:
                    rdata_val = socket.inet_ntoa(raw_rdata)
                elif rtype == DNSType.AAAA and rdlength == 16:
                    rdata_val = socket.inet_ntop(socket.AF_INET6, raw_rdata)
                elif rtype in (DNSType.CNAME, DNSType.PTR, DNSType.NS):
                    rdata_val, _ = decode_domain_name(data, offset)
                elif rtype == DNSType.TXT:
                    txts: List[str] = []
                    t_off = offset
                    t_end = offset + rdlength
                    while t_off < t_end:
                        t_len = data[t_off]
                        t_off += 1
                        txts.append(data[t_off : t_off + t_len].decode("utf-8", errors="replace"))
                        t_off += t_len
                    rdata_val = '"' + '" "'.join(txts) + '"'
                elif rtype == DNSType.MX and rdlength >= 2:
                    pref = struct.unpack("!H", raw_rdata[:2])[0]
                    mx_host, _ = decode_domain_name(data, offset + 2)
                    rdata_val = f"{pref} {mx_host}"
                else:
                    rdata_val = raw_rdata.hex()

                offset += rdlength
                records.append(DNSRecord(rname, rtype, rclass, ttl, rdata_val, raw_rdata))
            return records

        msg.answers = parse_records(ancount)
        msg.authorities = parse_records(nscount)
        msg.additionals = parse_records(arcount)
        return msg


class DNSClient:
    def __init__(self, server: str = "127.0.0.1", port: int = 53, timeout: float = 3.0):
        self.server = server
        self.port = port
        self.timeout = timeout
        self.is_ipv6 = ":" in server

    def query(self, domain: str, qtype: DNSType = DNSType.A, use_tcp: bool = False) -> Tuple[DNSMessage, float]:
        req = DNSMessage()
        req.questions.append(DNSQuestion(domain, qtype))
        req_bytes = req.to_bytes()

        start_time = time.perf_counter()
        if use_tcp:
            resp_bytes = self._query_tcp(req_bytes)
        else:
            resp_bytes = self._query_udp(req_bytes)
        elapsed_ms = (time.perf_counter() - start_time) * 1000.0

        resp = DNSMessage.from_bytes(resp_bytes)
        if not use_tcp and resp.tc:
            start_time = time.perf_counter()
            resp_bytes = self._query_tcp(req_bytes)
            elapsed_ms = (time.perf_counter() - start_time) * 1000.0
            resp = DNSMessage.from_bytes(resp_bytes)
        return resp, elapsed_ms

    def _query_udp(self, req_bytes: bytes) -> bytes:
        family = socket.AF_INET6 if self.is_ipv6 else socket.AF_INET
        with socket.socket(family, socket.SOCK_DGRAM) as sock:
            sock.settimeout(self.timeout)
            sock.sendto(req_bytes, (self.server, self.port))
            data, _ = sock.recvfrom(4096)
            return data

    def _query_tcp(self, req_bytes: bytes) -> bytes:
        family = socket.AF_INET6 if self.is_ipv6 else socket.AF_INET
        with socket.socket(family, socket.SOCK_STREAM) as sock:
            sock.settimeout(self.timeout)
            sock.connect((self.server, self.port))
            sock.sendall(struct.pack("!H", len(req_bytes)) + req_bytes)
            len_bytes = self._recv_exact(sock, 2)
            resp_len = struct.unpack("!H", len_bytes)[0]
            return self._recv_exact(sock, resp_len)

    def _recv_exact(self, sock: socket.socket, num_bytes: int) -> bytes:
        buf = bytearray()
        while len(buf) < num_bytes:
            chunk = sock.recv(num_bytes - len(buf))
            if not chunk:
                raise ConnectionError("TCP 连接在数据完全读取前被对端关闭")
            buf.extend(chunk)
        return bytes(buf)


def format_response(domain: str, qtype: str, server: str, port: int, proto: str, msg: DNSMessage, elapsed_ms: float) -> str:
    lines = [
        f"; <<>> DITING DNS Client <<>> {domain} {qtype} @{server}:{port} ({proto})",
        ";; Got answer:",
        f";; ->>HEADER<<- opcode: QUERY, status: {DNSRcode.to_name(msg.rcode)}, id: {msg.id}",
    ]
    flags = [f for f, v in [("qr", msg.qr), ("aa", msg.aa), ("tc", msg.tc), ("rd", msg.rd), ("ra", msg.ra)] if v]
    lines.append(f";; flags: {' '.join(flags)}; QUERY: {len(msg.questions)}, ANSWER: {len(msg.answers)}, AUTHORITY: {len(msg.authorities)}, ADDITIONAL: {len(msg.additionals)}")
    if msg.questions:
        lines.append("\n;; QUESTION SECTION:")
        for q in msg.questions:
            q_name = DNSType(q.qtype).name if q.qtype in DNSType._value2member_map_ else f"TYPE{q.qtype}"
            lines.append(f";{q.name}.\t\tIN\t{q_name}")
    if msg.answers:
        lines.append("\n;; ANSWER SECTION:")
        for rr in msg.answers:
            lines.append(str(rr))
    lines.append(f"\n;; Query time: {elapsed_ms:.1f} msec")
    lines.append(f";; SERVER: {server}#{port}({server}) ({proto})")
    lines.append(f";; WHEN: {time.strftime('%Y-%m-%d %H:%M:%S')}")
    return "\n".join(lines)


def execute_dns_query(domain: str, server: str = "127.0.0.1", port: int = 53, qtype_str: str = "A", use_tcp: bool = False, timeout: float = 3.0) -> dict:
    try:
        qtype = DNSType.from_str(qtype_str)
        client = DNSClient(server=server, port=port, timeout=timeout)
        proto = "TCP" if use_tcp else "UDP"
        resp, elapsed_ms = client.query(domain, qtype, use_tcp=use_tcp)
        return {
            "success": True,
            "domain": domain,
            "server": server,
            "port": port,
            "proto": proto,
            "type": qtype.name,
            "rcode": DNSRcode.to_name(resp.rcode),
            "raw_rcode": resp.rcode,
            "elapsed_ms": round(elapsed_ms, 2),
            "answers": [rr.to_dict() for rr in resp.answers],
            "authorities": [rr.to_dict() for rr in resp.authorities],
            "additionals": [rr.to_dict() for rr in resp.additionals],
            "raw_output": format_response(domain, qtype.name, server, port, proto, resp, elapsed_ms),
        }
    except Exception as e:
        return {"success": False, "error": str(e), "domain": domain, "server": server, "port": port}


def execute_benchmark(server: str, port: int, domain: str, qtype_str: str = "A", count: int = 5, use_tcp: bool = False, timeout: float = 3.0, on_progress: Optional[Callable[[str], None]] = None) -> dict:
    latencies = []
    success_count = 0
    errors = []
    for i in range(1, count + 1):
        res = execute_dns_query(domain, server, port, qtype_str, use_tcp, timeout)
        if res.get("success") and res.get("raw_rcode") == DNSRcode.NOERROR:
            success_count += 1
            lat = res["elapsed_ms"]
            latencies.append(lat)
            msg = f"[{i}/{count}] 成功: {lat:.1f}ms"
        else:
            err = res.get("error") or res.get("rcode") or "查询失败"
            errors.append(err)
            msg = f"[{i}/{count}] 失败: {err}"
        if on_progress:
            on_progress(msg)
        time.sleep(0.05)

    avg_ms = round(sum(latencies) / len(latencies), 2) if latencies else 0.0
    min_ms = round(min(latencies), 2) if latencies else 0.0
    max_ms = round(max(latencies), 2) if latencies else 0.0
    loss_rate = round((count - success_count) / count * 100, 1)

    return {
        "success": True,
        "count": count,
        "success_count": success_count,
        "loss_rate": loss_rate,
        "avg_ms": avg_ms,
        "min_ms": min_ms,
        "max_ms": max_ms,
        "errors": errors,
    }


def execute_phase1_verification(server: str, port: int, on_log: Optional[Callable[[str, str], None]] = None) -> dict:
    client = DNSClient(server=server, port=port, timeout=4.0)
    tests = [
        {"id": 1, "name": "UDP A 记录解析 (www.bing.com)", "domain": "www.bing.com", "type": DNSType.A, "tcp": False},
        {"id": 2, "name": "UDP AAAA 记录解析 (www.bing.com)", "domain": "www.bing.com", "type": DNSType.AAAA, "tcp": False},
        {"id": 3, "name": "TCP 协议查询 (www.bing.com)", "domain": "www.bing.com", "type": DNSType.A, "tcp": True},
        {"id": 4, "name": "异常域 NXDOMAIN 处理", "domain": f"diting-test-{random.randint(10000, 99999)}.invalid", "type": DNSType.A, "tcp": False},
    ]

    results = []
    passed_count = 0
    for t in tests:
        test_info = {"id": t["id"], "name": t["name"], "passed": False, "details": "", "latency_ms": 0}
        try:
            resp, ms = client.query(t["domain"], t["type"], use_tcp=t["tcp"])
            test_info["latency_ms"] = round(ms, 2)
            if t["id"] in (1, 2, 3):
                recs = [rr.rdata for rr in resp.answers if rr.rtype == t["type"]]
                if resp.rcode == DNSRcode.NOERROR and len(recs) > 0:
                    test_info["passed"] = True
                    test_info["details"] = f"{ms:.1f}ms, 解析记录: {recs[0]}"
                else:
                    test_info["details"] = f"RCODE: {DNSRcode.to_name(resp.rcode)}, 记录数: {len(resp.answers)}"
            else:
                if resp.rcode in (DNSRcode.NXDOMAIN, DNSRcode.NOERROR) and len(resp.answers) == 0:
                    test_info["passed"] = True
                    test_info["details"] = f"{ms:.1f}ms, 状态码正确: {DNSRcode.to_name(resp.rcode)}"
                else:
                    test_info["details"] = f"状态码: {DNSRcode.to_name(resp.rcode)}, 记录数: {len(resp.answers)}"
        except Exception as e:
            test_info["details"] = f"异常: {e}"

        if test_info["passed"]:
            passed_count += 1
            if on_log:
                on_log("info", f"[PASS] {t['name']} -> {test_info['details']}")
        else:
            if on_log:
                on_log("error", f"[FAIL] {t['name']} -> {test_info['details']}")
        results.append(test_info)

    all_passed = passed_count == len(tests)
    return {
        "success": all_passed,
        "total": len(tests),
        "passed": passed_count,
        "rate": round(passed_count / len(tests) * 100, 1),
        "tests": results,
    }


def main():
    parser = argparse.ArgumentParser(description="谛听 (DITING) DNS 核心工具")
    parser.add_argument("pos_domain", nargs="?", default=None)
    parser.add_argument("pos_server", nargs="?", default="127.0.0.1")
    parser.add_argument("pos_type", nargs="?", default="A")
    parser.add_argument("-p", "--port", type=int, default=53)
    parser.add_argument("--tcp", action="store_true")
    parser.add_argument("--verify", action="store_true")
    args = parser.parse_args()

    if args.verify or not args.pos_domain:
        res = execute_phase1_verification(args.pos_server, args.port, lambda lvl, msg: print(f"[{lvl.upper()}] {msg}"))
        print(f"验证完成: {res['passed']}/{res['total']} 通过 ({res['rate']}%)")
        sys.exit(0 if res["success"] else 1)

    result = execute_dns_query(args.pos_domain, args.pos_server, args.port, args.pos_type, args.tcp)
    if result.get("success"):
        print(result["raw_output"])
        sys.exit(0 if result.get("raw_rcode") == 0 else 2)
    else:
        print(f"查询失败: {result.get('error')}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
