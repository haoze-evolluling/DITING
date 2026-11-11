#!/usr/bin/env python3
"""Query the on-device DNS server through `adb forward`, the way a LAN client would.

The engine's standalone server listens on UDP **and** TCP; `adb forward` only forwards TCP, so this
probe speaks the 2-byte-framed TCP form (RFC 1035 §4.2.2) that `standalone.rs` serves. That is enough
to exercise the whole pipeline on a device: server → cache → policy → resolver → DoH/DoT/DoQ.

    adb forward tcp:15353 tcp:1053
    python rust/tools/engine-emulator/probe.py --name example.com
    python rust/tools/engine-emulator/probe.py --name example.com --count 30 --json

Exit code is 0 only when every query got the expected result, so the probe can gate a script.
"""

from __future__ import annotations

import argparse
import json
import socket
import statistics
import struct
import sys
import time

TYPE_A = 1
TYPE_AAAA = 28
TYPES = {"A": TYPE_A, "AAAA": TYPE_AAAA}


def build_query(name: str, qtype: int, txid: int) -> bytes:
    header = struct.pack(">HHHHHH", txid, 0x0100, 1, 0, 0, 0)
    question = b""
    for label in name.rstrip(".").split("."):
        question += bytes([len(label)]) + label.encode("ascii")
    question += b"\x00" + struct.pack(">HH", qtype, 1)
    return header + question


def read_name(message: bytes, offset: int) -> tuple[str, int]:
    labels = []
    while True:
        length = message[offset]
        if length == 0:
            return ".".join(labels), offset + 1
        if length & 0xC0 == 0xC0:
            pointer = struct.unpack(">H", message[offset : offset + 2])[0] & 0x3FFF
            name, _ = read_name(message, pointer)
            return ".".join([*labels, name]) if labels else name, offset + 2
        labels.append(message[offset + 1 : offset + 1 + length].decode("ascii", "replace"))
        offset += 1 + length


def parse_response(message: bytes) -> dict:
    txid, flags, qdcount, ancount, _, _ = struct.unpack(">HHHHHH", message[:12])
    rcode = flags & 0x000F
    offset = 12
    for _ in range(qdcount):
        _, offset = read_name(message, offset)
        offset += 4
    answers = []
    for _ in range(ancount):
        name, offset = read_name(message, offset)
        rtype, rclass, ttl, rdlength = struct.unpack(">HHIH", message[offset : offset + 10])
        offset += 10
        rdata = message[offset : offset + rdlength]
        offset += rdlength
        if rtype == TYPE_A and rdlength == 4:
            answers.append(
                {"name": name, "type": "A", "ttl": ttl, "value": ".".join(str(b) for b in rdata)}
            )
        elif rtype == TYPE_AAAA and rdlength == 16:
            answers.append(
                {
                    "name": name,
                    "type": "AAAA",
                    "ttl": ttl,
                    "value": ":".join(f"{rdata[i]:02x}{rdata[i + 1]:02x}" for i in range(0, 16, 2)),
                }
            )
        else:
            answers.append({"name": name, "type": rtype, "ttl": ttl, "value": rdata.hex()})
    return {"txid": txid, "rcode": rcode, "answers": answers}


def exchange(port: int, name: str, qtype: int, timeout: float) -> tuple[dict, int]:
    txid = int(time.time() * 1000) & 0xFFFF
    query = build_query(name, qtype, txid)
    started = time.perf_counter()
    with socket.create_connection(("127.0.0.1", port), timeout=timeout) as connection:
        connection.sendall(struct.pack(">H", len(query)) + query)
        header = connection.recv(2)
        if len(header) != 2:
            raise RuntimeError("server closed before the length prefix")
        length = struct.unpack(">H", header)[0]
        body = b""
        while len(body) < length:
            chunk = connection.recv(length - len(body))
            if not chunk:
                raise RuntimeError("server closed mid-message")
            body += chunk
    elapsed_ms = (time.perf_counter() - started) * 1000.0
    response = parse_response(body)
    if response["txid"] != txid:
        raise RuntimeError(f"transaction id {response['txid']} != {txid}")
    return response, round(elapsed_ms, 1)


def main() -> int:
    parser = argparse.ArgumentParser(description="Query the on-device DNS server (TCP, framed)")
    parser.add_argument("--port", type=int, default=15353, help="host port from `adb forward`")
    parser.add_argument("--name", default="example.com")
    parser.add_argument("--type", choices=sorted(TYPES), default="A")
    parser.add_argument("--count", type=int, default=1)
    parser.add_argument("--timeout", type=float, default=10.0)
    parser.add_argument("--expect-rcode", type=int, default=0, help="0 = NOERROR, 3 = NXDOMAIN")
    parser.add_argument("--expect-empty", action="store_true", help="expect zero answers")
    parser.add_argument("--retry", type=int, default=2, help="retries when the connection closes early")
    parser.add_argument("--json", action="store_true", help="print one JSON summary line")
    args = parser.parse_args()

    qtype = TYPES[args.type]
    timings: list[float] = []
    records = []
    for index in range(args.count):
        attempt = 0
        while True:
            try:
                response, elapsed = exchange(args.port, args.name, qtype, args.timeout)
                break
            except OSError as error:
                # A server that is being restarted closes the socket before the length prefix; that
                # is a startup race, not a transport failure, so give it a moment and try again.
                attempt += 1
                if attempt > args.retry:
                    print(f"[probe] query {index + 1} failed: {error}", file=sys.stderr)
                    return 1
                time.sleep(1.0)
            except Exception as error:  # noqa: BLE001 - the probe reports any failure as a failure
                print(f"[probe] query {index + 1} failed: {error}", file=sys.stderr)
                return 1
        if response["rcode"] != args.expect_rcode:
            print(
                f"[probe] query {index + 1}: rcode {response['rcode']} != {args.expect_rcode}",
                file=sys.stderr,
            )
            return 1
        if args.expect_empty and response["answers"]:
            print(f"[probe] query {index + 1}: unexpected answers {response['answers']}", file=sys.stderr)
            return 1
        timings.append(elapsed)
        records = response["answers"]
        if not args.json and args.count == 1:
            print(
                json.dumps(
                    {"rcode": response["rcode"], "elapsed_ms": elapsed, "answers": records},
                    ensure_ascii=False,
                )
            )

    timings.sort()
    summary = {
        "name": args.name,
        "type": args.type,
        "count": args.count,
        "rcode": args.expect_rcode,
        "answers": records,
        "min_ms": round(timings[0], 1),
        "p50_ms": round(statistics.median(timings), 1),
        "p95_ms": round(timings[min(len(timings) - 1, int(len(timings) * 0.95))], 1),
        "max_ms": round(timings[-1], 1),
        "mean_ms": round(statistics.fmean(timings), 1),
        "qps": round(1000.0 * args.count / sum(timings), 1) if timings else 0.0,
    }
    print(json.dumps(summary, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
