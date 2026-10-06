#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
谛听 (DITING) DNS 查询与阶段 1 验证工具
用于在 Windows / 跨平台环境下发送真实 DNS 查询请求 (UDP/TCP)，
绕过 Windows 自带 nslookup 在反向解析、自定义端口与本地回环上的兼容缺陷。
具备零第三方依赖 (纯标准库)、支持 A/AAAA/CNAME/TXT/MX 等解析、支持阶段 1 自动化验证套件。
"""

import argparse
import random
import socket
import struct
import sys
import time
from enum import IntEnum
from typing import Any, List, Optional, Tuple

# 确保在 Windows 终端中 UTF-8 中文正常输出
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
    """将域名编码为 DNS Wire 格式 (RFC 1035)。"""
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
    """从二进制数据流中解析域名，支持 RFC 1035 压缩指针，防环深度上限 32。"""
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

        # 检查是否为压缩指针 (高两位为 11, 0xC0)
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

        # 普通 Label
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

        # 1. 解析 Question 节
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
                    # TXT 由一或多个 length-prefixed 字符串组成
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
    """DNS 客户端，支持 UDP / TCP 双栈通信与耗时统计。"""

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
        # 若 UDP 响应被截断 (TC=1) 且非 TCP 请求，自动升级 TCP 重试
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
            # RFC 7858 / 1035: TCP 需带 2 字节大端长度前缀
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
    """输出仿 dig 风格的格式化结果。"""
    lines: List[str] = []
    lines.append(f"; <<>> DITING DNS Client <<>> {domain} {qtype} @{server}:{port} ({proto})")
    lines.append(f";; Got answer:")
    lines.append(
        f";; ->>HEADER<<- opcode: QUERY, status: {DNSRcode.to_name(msg.rcode)}, id: {msg.id}"
    )
    flags = []
    if msg.qr: flags.append("qr")
    if msg.aa: flags.append("aa")
    if msg.tc: flags.append("tc")
    if msg.rd: flags.append("rd")
    if msg.ra: flags.append("ra")
    lines.append(
        f";; flags: {' '.join(flags)}; QUERY: {len(msg.questions)}, ANSWER: {len(msg.answers)}, "
        f"AUTHORITY: {len(msg.authorities)}, ADDITIONAL: {len(msg.additionals)}"
    )

    if msg.questions:
        lines.append("\n;; QUESTION SECTION:")
        for q in msg.questions:
            q_name = DNSType(q.qtype).name if q.qtype in DNSType._value2member_map_ else f"TYPE{q.qtype}"
            lines.append(f";{q.name}.\t\tIN\t{q_name}")

    if msg.answers:
        lines.append("\n;; ANSWER SECTION:")
        for rr in msg.answers:
            lines.append(str(rr))

    if msg.authorities:
        lines.append("\n;; AUTHORITY SECTION:")
        for rr in msg.authorities:
            lines.append(str(rr))

    if msg.additionals:
        lines.append("\n;; ADDITIONAL SECTION:")
        for rr in msg.additionals:
            lines.append(str(rr))

    lines.append(f"\n;; Query time: {elapsed_ms:.1f} msec")
    lines.append(f";; SERVER: {server}#{port}({server}) ({proto})")
    lines.append(f";; WHEN: {time.strftime('%Y-%m-%d %H:%M:%S')}")
    return "\n".join(lines)


def run_phase1_verification(server: str, port: int) -> bool:
    """执行阶段 1 核心 DNS 转发与服务层完整验证套件。"""
    print("=" * 60)
    print(f"谛听 (DITING) 阶段 1 DNS 内核服务验证套件")
    print(f"目标服务器: {server}:{port}")
    print("=" * 60)

    client = DNSClient(server=server, port=port, timeout=4.0)
    passed_count = 0
    total_tests = 4

    # 1. 验证 UDP IPv4 A 记录解析
    print("[1/4] 测试 UDP A 记录解析 (www.bing.com)...", end=" ", flush=True)
    try:
        resp, ms = client.query("www.bing.com", DNSType.A, use_tcp=False)
        a_records = [rr.rdata for rr in resp.answers if rr.rtype == DNSType.A]
        if resp.rcode == DNSRcode.NOERROR and len(a_records) > 0:
            print(f"PASS ({ms:.1f}ms, 解析到 {len(a_records)} 个 A 记录: {a_records[0]})")
            passed_count += 1
        else:
            print(f"FAIL (RCODE: {DNSRcode.to_name(resp.rcode)}, Answers: {len(resp.answers)})")
    except Exception as e:
        print(f"ERROR ({e})")

    # 2. 验证 UDP IPv6 AAAA 记录解析
    print("[2/4] 测试 UDP AAAA 记录解析 (www.bing.com)...", end=" ", flush=True)
    try:
        resp, ms = client.query("www.bing.com", DNSType.AAAA, use_tcp=False)
        aaaa_records = [rr.rdata for rr in resp.answers if rr.rtype == DNSType.AAAA]
        if resp.rcode == DNSRcode.NOERROR and len(aaaa_records) > 0:
            print(f"PASS ({ms:.1f}ms, 解析到 {len(aaaa_records)} 个 AAAA 记录: {aaaa_records[0]})")
            passed_count += 1
        else:
            print(f"FAIL (RCODE: {DNSRcode.to_name(resp.rcode)}, Answers: {len(resp.answers)})")
    except Exception as e:
        print(f"ERROR ({e})")

    # 3. 验证 TCP A 记录解析
    print("[3/4] 测试 TCP 协议查询 (www.bing.com)...", end=" ", flush=True)
    try:
        resp, ms = client.query("www.bing.com", DNSType.A, use_tcp=True)
        a_records = [rr.rdata for rr in resp.answers if rr.rtype == DNSType.A]
        if resp.rcode == DNSRcode.NOERROR and len(a_records) > 0:
            print(f"PASS ({ms:.1f}ms, TCP 链路通畅, A 记录: {a_records[0]})")
            passed_count += 1
        else:
            print(f"FAIL (RCODE: {DNSRcode.to_name(resp.rcode)}, Answers: {len(resp.answers)})")
    except Exception as e:
        print(f"ERROR ({e})")

    # 4. 验证 NXDOMAIN 异常域名处理
    nx_domain = f"diting-test-nxdomain-{random.randint(100000, 999999)}.invalid"
    print(f"[4/4] 测试异常域 NXDOMAIN 处理 ({nx_domain})...", end=" ", flush=True)
    try:
        resp, ms = client.query(nx_domain, DNSType.A, use_tcp=False)
        # 上游可能返回 NXDOMAIN 或 NOERROR 空结果
        if resp.rcode in (DNSRcode.NXDOMAIN, DNSRcode.NOERROR) and len(resp.answers) == 0:
            print(f"PASS ({ms:.1f}ms, 状态码: {DNSRcode.to_name(resp.rcode)}, 0 记录)")
            passed_count += 1
        else:
            print(f"FAIL (RCODE: {DNSRcode.to_name(resp.rcode)}, Answers: {len(resp.answers)})")
    except Exception as e:
        print(f"ERROR ({e})")

    print("-" * 60)
    print(f"验证完成: {passed_count}/{total_tests} 通过 (通过率 {passed_count / total_tests * 100:.1f}%)")
    print("=" * 60)
    return passed_count == total_tests


def test_encode_and_decode_domain_name():
    """测试标准域名编码与解码往返。"""
    raw_domain = "www.bing.com"
    encoded = encode_domain_name(raw_domain)
    decoded, off = decode_domain_name(encoded, 0)
    assert decoded == raw_domain, f"域名解码不匹配: {decoded} != {raw_domain}"
    assert off == len(encoded), f"偏移量不匹配: {off} != {len(encoded)}"


def test_decode_domain_name_pointer():
    """测试 RFC 1035 压缩指针正确解析与防环。"""
    raw_domain = "www.bing.com"
    encoded = encode_domain_name(raw_domain)
    buf = bytearray(b"\x00" * 12)
    buf.extend(encoded)
    buf.extend(b"\xc0\x0c")
    ptr_decoded, p_off = decode_domain_name(bytes(buf), 12 + len(encoded))
    assert ptr_decoded == raw_domain, f"压缩指针解析错误: {ptr_decoded}"
    assert p_off == 12 + len(encoded) + 2, f"压缩指针结束偏移错误: {p_off}"


def test_dns_message_pack_unpack():
    """测试 DNS 报文序列化与反序列化。"""
    msg = DNSMessage()
    msg.id = 0xABCD
    msg.questions.append(DNSQuestion("example.com", DNSType.A))
    wire = msg.to_bytes()
    assert len(wire) == 12 + len(encode_domain_name("example.com")) + 4
    unpacked = DNSMessage.from_bytes(wire)
    assert unpacked.id == 0xABCD
    assert len(unpacked.questions) == 1
    assert unpacked.questions[0].name == "example.com"
    assert unpacked.questions[0].qtype == DNSType.A


def run_selftest() -> bool:
    """内部单元自测：编解码、压缩指针与消息转换。"""
    print("运行 DNS 客户端内部单元自测...")
    test_encode_and_decode_domain_name()
    test_decode_domain_name_pointer()
    test_dns_message_pack_unpack()
    print("自测全部通过 (PASS)!")
    return True


def resolve_target_port(server: str, port: Optional[int]) -> int:
    """若用户显式指定端口则直接使用；若未指定且目标为本地回环，探测 53 与 1053 自动适配。"""
    if port is not None:
        return port
    if server in ("127.0.0.1", "::1", "localhost"):
        # 1. 优先探测标准 53 端口
        probe_client_53 = DNSClient(server=server, port=53, timeout=0.25)
        try:
            probe_client_53.query("www.bing.com", DNSType.A)
            return 53
        except Exception:
            pass
        # 2. 探测 1053 调试端口
        probe_client_1053 = DNSClient(server=server, port=1053, timeout=0.25)
        try:
            probe_client_1053.query("www.bing.com", DNSType.A)
            print("[提示] 本地 53 端口无响应 (可能受 Windows ICS/SharedAccess 占用)，自动使用 1053 调试端口。")
            return 1053
        except Exception:
            pass
        return 53
    return 53


def main():
    parser = argparse.ArgumentParser(
        description="谛听 (DITING) DNS 查询与验证工具 (替代 Windows 存在兼容缺陷的 nslookup)",
        usage="%(prog)s [domain] [server] [type] [options]",
    )
    # 支持位置参数 (兼容 nslookup domain server 习惯)
    parser.add_argument("pos_domain", nargs="?", default=None, help="待查询的域名 (如 www.bing.com)")
    parser.add_argument("pos_server", nargs="?", default=None, help="目标 DNS 服务器 (如 127.0.0.1)")
    parser.add_argument("pos_type", nargs="?", default=None, help="查询记录类型 (如 A, AAAA, CNAME)")

    # 具名参数选项
    parser.add_argument("-q", "--domain", dest="named_domain", help="待查询的域名")
    parser.add_argument("-s", "--server", dest="named_server", default="127.0.0.1", help="目标 DNS 服务器 IP (默认 127.0.0.1)")
    parser.add_argument("-p", "--port", type=int, default=None, help="目标 DNS 服务端口 (默认自动探测 53/1053)")
    parser.add_argument("-t", "--type", dest="named_type", default="A", help="DNS 记录类型 (默认 A)")
    parser.add_argument("--tcp", action="store_true", help="强制使用 TCP 协议进行查询")
    parser.add_argument("--timeout", type=float, default=3.0, help="查询超时时间 (秒，默认 3.0)")
    parser.add_argument("--verify", action="store_true", help="执行阶段 1 核心 DNS 功能自动化验证套件")
    parser.add_argument("--selftest", action="store_true", help="运行纯内部编解码单元测试")

    args = parser.parse_args()

    if args.selftest:
        success = run_selftest()
        sys.exit(0 if success else 1)

    # 确定目标服务器与端口
    server = args.pos_server if args.pos_server else args.named_server
    port = resolve_target_port(server, args.port)

    if args.verify:
        success = run_phase1_verification(server, port)
        sys.exit(0 if success else 1)

    domain = args.pos_domain if args.pos_domain else args.named_domain
    if not domain:
        # 如果未传入域名且未指定验证，默认执行阶段 1 验证
        print("未指定查询域名，默认启动阶段 1 自动化验证模式...")
        success = run_phase1_verification(server, port)
        sys.exit(0 if success else 1)

    type_str = args.pos_type if args.pos_type else args.named_type
    try:
        qtype = DNSType.from_str(type_str)
    except ValueError as e:
        print(f"错误: {e}", file=sys.stderr)
        sys.exit(1)

    client = DNSClient(server=server, port=port, timeout=args.timeout)
    proto = "TCP" if args.tcp else "UDP"
    try:
        resp, ms = client.query(domain, qtype, use_tcp=args.tcp)
        print(format_response(domain, qtype.name, server, port, proto, resp, ms))
        # 若 RCODE 不为 NOERROR，退出码设为 2
        if resp.rcode != DNSRcode.NOERROR:
            sys.exit(2)
    except Exception as e:
        print(f"DNS 查询失败 ({proto} @{server}:{port}): {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
