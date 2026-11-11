import java.io.ByteArrayOutputStream;
import java.io.DataOutputStream;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.List;

/**
 * Corpus generator for the Android diagnostics probes.
 *
 * <p>The parsers live in {@code ProbeParsers} (host text and DNS wire) and {@code ProbeText}
 * (`ping` / `traceroute` output and the latency arithmetic), both line-for-line JVM ports of the
 * Kotlin the app used. This file holds the inputs (real {@code ping} / {@code ping6} / toybox
 * output, traceroute hops, hand-built DNS replies) and writes the fixtures under
 * {@code rust/diting-probe-core/tests/fixtures/}, which {@code tests/corpus.rs} replays against the
 * Rust kernel:
 *
 * <pre>
 *   javac -d /tmp/probe-ref rust/tools/probe-reference/*.java
 *   java -cp /tmp/probe-ref ProbeReference --corpus rust/diting-probe-core/tests/fixtures
 * </pre>
 *
 * <p>Each fixture stores the payload the Rust kernel must answer, in the layout documented in
 * {@code rust/diting-probe-core/src/api.rs}, so a fixture pins the parse result and the payload
 * layout at the same time. Text fields are escaped ({@code \}, {@code 
}, {@code 
},
 * {@code 	}) and byte fields are lowercase hex.
 */
public final class ProbeReference {

    // ---------------------------------------------------------------------------------------
    // Corpus generation
    // ---------------------------------------------------------------------------------------

    private static final String[] PING_OUTPUTS = {
        // iputils, IPv4, one lost packet, mdev reported.
        "PING example.com (93.184.216.34) 56(84) bytes of data.\n"
            + "64 bytes from 93.184.216.34: icmp_seq=1 ttl=57 time=12.3 ms\n"
            + "64 bytes from 93.184.216.34: icmp_seq=3 ttl=57 time=15.1 ms\n"
            + "\n--- example.com ping statistics ---\n"
            + "3 packets transmitted, 2 received, 33.3333% packet loss, time 2003ms\n"
            + "rtt min/avg/max/mdev = 12.300/13.700/15.100/1.400 ms\n",
        // iputils, IPv6, no ttl in the reply line, a lost middle packet.
        "PING 2001:db8::1(2001:db8::1) 56 data bytes\n"
            + "64 bytes from 2001:db8::1: icmp_seq=1 ttl=64 time=1.05 ms\n"
            + "64 bytes from 2001:db8::1: icmp_seq=3 ttl=64 time=1.44 ms\n"
            + "\n--- 2001:db8::1 ping statistics ---\n"
            + "3 packets transmitted, 2 received, 33.3333% packet loss, time 2027ms\n"
            + "rtt min/avg/max/mdev = 1.050/1.245/1.440/0.195 ms\n",
        // busybox/toybox: zero-based sequence, `seq=` and totals on one line.
        "PING 1.1.1.1 (1.1.1.1): 56 data bytes\n"
            + "64 bytes from 1.1.1.1: seq=0 ttl=57 time=8.664 ms\n"
            + "64 bytes from 1.1.1.1: seq=1 ttl=57 time=9.100 ms\n"
            + "\n--- 1.1.1.1 ping statistics ---\n"
            + "2 packets transmitted, 2 packets received, 0% packet loss\n"
            + "round-trip min/avg/max = 8.664/8.882/9.100 ms\n",
        // No statistics block at all: the counts come from the reply lines.
        "64 bytes from 1.2.3.4: icmp_seq=1 ttl=57 time=12.5 ms\n"
            + "2 packets transmitted, 1 received, 50% packet loss\n",
        // Unparsable percentage and a missing `<n> received`.
        "64 bytes from 1.2.3.4: icmp_seq=2 ttl=57 time=20.0 ms\n"
            + "2 packets transmitted, 1.2.3% packet loss\n",
        // Every packet lost, and the RTT block says so.
        "PING 10.255.255.1 (10.255.255.1) 56(84) bytes of data.\n"
            + "\n--- 10.255.255.1 ping statistics ---\n"
            + "4 packets transmitted, 0 received, 100% packet loss, time 3070ms\n",
        // Duplicate sequence numbers keep the last line (`associateBy`).
        "64 bytes from 1.2.3.4: icmp_seq=1 ttl=57 time=10.0 ms\n"
            + "64 bytes from 1.2.3.4: icmp_seq=1 ttl=57 time=99.0 ms\n"
            + "2 packets transmitted, 2 received, 0% packet loss\n",
        // A reply line without `time=` is not a reply at all.
        "From 10.0.0.1 icmp_seq=1 Destination Host Unreachable\n"
            + "2 packets transmitted, 0 received, 100% packet loss\n",
        // No statistics line: the caller falls back to isReachable/TCP timing.
        "ping: unknown host nope.invalid\n",
        "",
    };

    private static final String[] TRACE_OUTPUTS = {
        "64 bytes from 1.1.1.1: icmp_seq=1 ttl=57 time=12.3 ms\n",
        "From 192.168.1.1 icmp_seq=1 Time to live exceeded\n",
        "From 10.0.0.1: icmp_seq=1 Destination Net Unreachable\n",
        "From 2001:db8::1 icmp_seq=1 Time exceeded: Hop limit\n",
        "PING x (1.2.3.4) 56 data bytes\n\n--- 1.2.3.4 ping statistics ---\n"
            + "1 packets transmitted, 0 received, 100% packet loss\n",
        "Usage: ping [-t ttl] destination\n",
        "ping: invalid option -- t\n",
        "connect: Network is unreachable\n",
        "",
    };

    private static final String[] HOSTS = {
        "  https://user:pw@dns.google:8443/dns-query?x=1#f  ",
        "dns.google",
        "dns.google:53",
        "dns.google:port",
        "example.com/path",
        "2001:db8::1",
        "[2001:db8::1]:53",
        "[2001:db8::1]",
        "[]",
        "[::1",
        "",
        "   ",
        "1.2.3.4",
        "010.0.0.1",
        "1.2.3",
        "1.2.3.4.5",
        "256.0.0.1",
        "::",
        "::1",
        "2001:4860:4860::8888",
        "dns.google:53",
        "1:2",
        ":1",
        "2001:db8::zz",
    };

    private static final Object[][] DNS_QUERIES = {
        {0xABCD, 0, "example.com"},
        {0xABCD, 1, "example.com."},
        {0, 0, ".com."},
        {1, 1, "a"},
        {0xFFFF, 0, "a.b.c.d.e"},
        {0x1234, 0, "ü.example"},
        {0, 0, "."},
        {0, 0, ""},
        {0, 0, "a..b"},
        {0, 0, repeat('a', 64)},
        {0, 0, repeat('a', 63)},
    };

    private static final double[][] LATENCY_SAMPLES = {
        {10.0, 20.0, 30.0},
        {1.0, 2.0},
        {0.2},
        {12.34},
        {},
        {100.5, 100.5, 100.5, 100.5},
    };

    private static String repeat(char value, int count) {
        StringBuilder text = new StringBuilder();
        for (int i = 0; i < count; i++) text.append(value);
        return text.toString();
    }

    /** Crafted replies; each entry is {ipv4, wire bytes}. */
    private static List<Object[]> dnsReplies() {
        List<Object[]> replies = new ArrayList<>();
        replies.add(new Object[] {true, reply(true, 0, 0x8100, List.of(
                record(1, 1, 300, new byte[] {1, 2, 3, 4})))});
        replies.add(new Object[] {false, reply(true, 0, 0x8100, List.of(
                record(28, 1, 60, ipv6("2001:db8::1"))))});
        replies.add(new Object[] {true, reply(true, 0, 0x8100, List.of(
                record(1, 1, 300, new byte[] {93, (byte) 184, (byte) 216, 34}),
                record(5, 1, 300, new byte[] {(byte) 0xC0, 0x0C}),
                record(1, 3, 300, new byte[] {5, 6, 7, 8}),
                record(1, 1, 300, new byte[] {1, 2, 3}),
                record(28, 1, 60, ipv6("::1"))))});
        replies.add(new Object[] {false, reply(true, 0, 0x8100, List.of(
                record(28, 1, 60, ipv6("fe80::abcd:ef01"))))});
        replies.add(new Object[] {false, reply(true, 0, 0x8100, List.of(
                record(28, 1, 60, ipv6("::ffff:1.2.3.4"))))});
        replies.add(new Object[] {true, reply(true, 3, 0x8103, List.of())});
        replies.add(new Object[] {true, reply(true, 5, 0x8105, List.of())});
        replies.add(new Object[] {true, reply(true, 2, 0x8102, List.of())});
        replies.add(new Object[] {true, reply(true, 0, 0x8102, List.of())}); // TC set
        replies.add(new Object[] {true, reply(true, 14, 0x810E, List.of())});
        replies.add(new Object[] {true, shortReply()});
        replies.add(new Object[] {true, noIdBitReply()});
        replies.add(new Object[] {true, extraAnswerCountReply()});
        replies.add(new Object[] {true, truncatedAnswerReply()});
        return replies;
    }

    private static byte[] shortReply() {
        byte[] wire = reply(true, 0, 0x8100, List.of());
        byte[] cut = new byte[11];
        System.arraycopy(wire, 0, cut, 0, cut.length);
        return cut;
    }

    private static byte[] noIdBitReply() {
        // The Kotlin gate reads response[0] (the ID high bit), not the QR flag.
        byte[] wire = reply(true, 0, 0x0100, List.of(record(1, 1, 60, new byte[] {1, 1, 1, 1})));
        return wire;
    }

    private static byte[] extraAnswerCountReply() {
        byte[] wire = reply(true, 0, 0x8100, List.of(record(1, 1, 60, new byte[] {1, 1, 1, 1})));
        wire[7] = 2; // ANCOUNT = 2, one record present
        return wire;
    }

    private static byte[] truncatedAnswerReply() {
        // ANCOUNT = 1, and the record's rdata is cut short: `readFully` hit EOF.
        byte[] wire = reply(true, 0, 0x8100, List.of(record(1, 1, 60, new byte[] {1, 1, 1, 1})));
        byte[] cut = new byte[wire.length - 2];
        System.arraycopy(wire, 0, cut, 0, cut.length);
        return cut;
    }

    private static byte[] ipv6(String text) {
        String[] halves = text.split("::", -1);
        List<Integer> groups = new ArrayList<>();
        List<String> head = halves[0].isEmpty() ? List.of() : List.of(halves[0].split(":"));
        List<String> tail = halves.length > 1 && !halves[1].isEmpty()
                ? List.of(halves[1].split(":")) : List.of();
        for (String group : head) {
            if (group.contains(".")) {
                String[] parts = group.split("\\.");
                int high = Integer.parseInt(parts[0]) * 256 + Integer.parseInt(parts[1]);
                int low = Integer.parseInt(parts[2]) * 256 + Integer.parseInt(parts[3]);
                groups.add(high);
                groups.add(low);
            } else {
                groups.add(Integer.parseInt(group, 16));
            }
        }
        int tailGroups = 0;
        for (String group : tail) {
            tailGroups += group.contains(".") ? 2 : 1;
        }
        for (int i = groups.size(); i < 8 - tailGroups; i++) groups.add(0);
        for (String group : tail) {
            if (group.contains(".")) {
                String[] parts = group.split("\\.");
                groups.add(Integer.parseInt(parts[0]) * 256 + Integer.parseInt(parts[1]));
                groups.add(Integer.parseInt(parts[2]) * 256 + Integer.parseInt(parts[3]));
            } else {
                groups.add(Integer.parseInt(group, 16));
            }
        }
        byte[] bytes = new byte[16];
        for (int i = 0; i < 8; i++) {
            bytes[i * 2] = (byte) (groups.get(i) >> 8);
            bytes[i * 2 + 1] = (byte) (int) (groups.get(i) & 0xFF);
        }
        return bytes;
    }

    private static byte[] record(int type, int klass, long ttl, byte[] rdata) {
        ByteArrayOutputStream out = new ByteArrayOutputStream();
        DataOutputStream data = new DataOutputStream(out);
        try {
            data.writeByte(0xC0);
            data.writeByte(0x0C); // owner name: pointer to the question name
            data.writeShort(type);
            data.writeShort(klass);
            data.writeInt((int) ttl);
            data.writeShort(rdata.length);
            data.write(rdata);
            data.flush();
        } catch (IOException error) {
            throw new IllegalStateException(error);
        }
        return out.toByteArray();
    }

    private static byte[] reply(boolean idHighBit, int rcode, int flags, List<byte[]> records) {
        ByteArrayOutputStream out = new ByteArrayOutputStream();
        DataOutputStream data = new DataOutputStream(out);
        try {
            data.writeByte(idHighBit ? 0x81 : 0x01);
            data.writeByte(0x34);
            data.writeShort(flags);
            data.writeShort(1); // QDCOUNT
            data.writeShort(records.size()); // ANCOUNT
            data.writeShort(0); // NSCOUNT
            data.writeShort(0); // ARCOUNT
            // q.example.com A IN
            data.write(new byte[] {1, 'q', 7, 'e', 'x', 'a', 'm', 'p', 'l', 'e', 3, 'c', 'o', 'm', 0});
            data.writeShort(1);
            data.writeShort(1);
            for (byte[] record : records) data.write(record);
            data.flush();
        } catch (IOException error) {
            throw new IllegalStateException(error);
        }
        return out.toByteArray();
    }

    // ---------------------------------------------------------------------------------------
    // Fixture emission
    // ---------------------------------------------------------------------------------------

    private static String escape(String value) {
        StringBuilder text = new StringBuilder();
        for (int i = 0; i < value.length(); i++) {
            char c = value.charAt(i);
            switch (c) {
                case '\\' -> text.append("\\\\");
                case '\n' -> text.append("\\n");
                case '\r' -> text.append("\\r");
                case '\t' -> text.append("\\t");
                default -> text.append(c);
            }
        }
        return text.toString();
    }

    private static String hex(byte[] bytes) {
        StringBuilder text = new StringBuilder();
        for (byte value : bytes) text.append(String.format("%02x", value & 0xFF));
        return text.toString();
    }

    private static void writeCorpus(Path directory) throws IOException {
        Files.createDirectories(directory);

        StringBuilder host = new StringBuilder();
        host.append("# input\tsanitized\tisIpLiteral\n");
        for (String value : HOSTS) {
            host.append(escape(value)).append('\t').append(escape(ProbeParsers.sanitize(value)))
                    .append('\t').append(ProbeParsers.isIpLiteral(value) ? 1 : 0).append('\n');
        }
        Files.writeString(directory.resolve("host.tsv"), host.toString(), StandardCharsets.UTF_8);

        StringBuilder query = new StringBuilder();
        query.append("# id\tqtype\tdomain\tqueryHex\n");
        for (Object[] entry : DNS_QUERIES) {
            int id = (Integer) entry[0];
            int qtype = (Integer) entry[1];
            String domain = (String) entry[2];
            byte[] built = ProbeParsers.buildQuery(id, qtype, domain);
            query.append(id).append('\t').append(qtype).append('\t').append(escape(domain))
                    .append('\t').append(built == null ? "-" : hex(built)).append('\n');
        }
        Files.writeString(directory.resolve("dns_query.tsv"), query.toString(), StandardCharsets.UTF_8);

        StringBuilder reply = new StringBuilder();
        reply.append("# ipv4\treplyHex\tpayloadHex\n");
        for (Object[] entry : dnsReplies()) {
            boolean ipv4 = (Boolean) entry[0];
            byte[] wire = (byte[]) entry[1];
            reply.append(ipv4 ? 1 : 0).append('\t').append(hex(wire)).append('\t')
                    .append(hex(ProbeParsers.parseServerReply(wire, ipv4))).append('\n');
        }
        Files.writeString(directory.resolve("dns_reply.tsv"), reply.toString(), StandardCharsets.UTF_8);

        StringBuilder ping = new StringBuilder();
        ping.append("# output\tpayloadHex\n");
        for (String output : PING_OUTPUTS) {
            ping.append(escape(output)).append('\t').append(hex(ProbeText.pingPayload(output))).append('\n');
        }
        Files.writeString(directory.resolve("ping.tsv"), ping.toString(), StandardCharsets.UTF_8);

        StringBuilder trace = new StringBuilder();
        trace.append("# resolved\ttext\tpayloadHex\n");
        for (String output : TRACE_OUTPUTS) {
            trace.append("1.2.3.4").append('\t').append(escape(output)).append('\t')
                    .append(hex(ProbeText.tracePayload("1.2.3.4", output))).append('\n');
        }
        Files.writeString(directory.resolve("trace.tsv"), trace.toString(), StandardCharsets.UTF_8);

        StringBuilder latency = new StringBuilder();
        latency.append("# samplesBits\tpayloadHex\n");
        for (double[] samples : LATENCY_SAMPLES) {
            StringBuilder bits = new StringBuilder();
            for (int i = 0; i < samples.length; i++) {
                if (i > 0) bits.append(',');
                bits.append(String.format("%016x", Double.doubleToRawLongBits(samples[i])));
            }
            latency.append(bits).append('\t').append(hex(ProbeText.latencyPayload(samples))).append('\n');
        }
        Files.writeString(directory.resolve("latency.tsv"), latency.toString(), StandardCharsets.UTF_8);

        // isSuccess has no payload: one hex reply per line plus the expected bit.
        StringBuilder success = new StringBuilder();
        success.append("# replyHex\tsuccess\n");
        for (Object[] entry : dnsReplies()) {
            byte[] wire = (byte[]) entry[1];
            success.append(hex(wire)).append('\t').append(ProbeParsers.isSuccess(wire) ? 1 : 0).append('\n');
        }
        Files.writeString(directory.resolve("dns_success.tsv"), success.toString(), StandardCharsets.UTF_8);

        System.out.println("wrote fixtures into " + directory);
    }

    public static void main(String[] arguments) throws Exception {
        if (arguments.length == 2 && arguments[0].equals("--corpus")) {
            writeCorpus(Path.of(arguments[1]));
            return;
        }
        System.err.println(
                "usage: javac -d /tmp/probe-ref rust/tools/probe-reference/*.java && "
                        + "java -cp /tmp/probe-ref ProbeReference --corpus <fixture-dir>");
        System.exit(2);
    }
}
