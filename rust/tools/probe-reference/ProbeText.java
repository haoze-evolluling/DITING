/// Reference implementation of the `ping` / `traceroute` output parsers and the latency arithmetic,
/// lifted out of Kotlin so it can run on a desktop JVM.
///
/// <p>Each method is a line-for-line port of the Kotlin it replaces
/// ({@code PingProbe.parseSummary}, {@code TraceProbe.trace}'s per-hop parse,
/// {@code DnsLatencyTester.probeAverage}'s average). The regular expressions,
/// {@code toIntOrNull} / {@code toDoubleOrNull}, {@code average()}, {@code Math.round} and
/// {@code jitterOf} are therefore the <em>same Java library calls</em> the app made.
///
/// <p>Compile the four files together and run the corpus generator:
///
/// <pre>
///   javac -d /tmp/probe-ref rust/tools/probe-reference/*.java
///   java -cp /tmp/probe-ref ProbeReference --corpus rust/diting-probe-core/tests/fixtures
/// </pre>

import java.io.ByteArrayOutputStream;
import java.io.DataOutputStream;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/// The text parsers and the payload writer their results are packed with.
final class ProbeText {
    // ---------------------------------------------------------------------------------------
    // PingProbe.parseSummary
    // ---------------------------------------------------------------------------------------

    private static final Pattern REPLY = Pattern.compile(
            "from\\s+(\\S+):\\s+(?:icmp_seq|seq)=(\\d+)(?:.*?ttl=(\\d+))?.*?time=([0-9.]+)\\s*ms");
    private static final Pattern LOSS = Pattern.compile("([0-9.]+)% packet loss");
    private static final Pattern TRANSMITTED = Pattern.compile("(\\d+) packets? transmitted");
    private static final Pattern RECEIVED = Pattern.compile("(\\d+) (?:packets? )?received");
    private static final Pattern RTT = Pattern.compile(
            "=\\s*([0-9.]+)/([0-9.]+)/([0-9.]+)(?:/([0-9.]+))?\\s*ms");

    static final class ReplyRow {
        Integer sequence;
        Double elapsedMs;
        Integer ttl;
        boolean timeout;

        ReplyRow(Integer sequence, Double elapsedMs, Integer ttl) {
            this.sequence = sequence;
            this.elapsedMs = elapsedMs;
            this.ttl = ttl;
        }

        ReplyRow(int sequence) {
            this.sequence = sequence;
            this.timeout = true;
        }
    }

    /** Status 1 = no `N% packet loss` line (the Kotlin null), 0 = a full summary. */
    static byte[] pingPayload(String output) {
        ProbeWriter writer = new ProbeWriter();
        Matcher loss = LOSS.matcher(output);
        if (!loss.find()) {
            writer.u8(1);
            return writer.bytes();
        }

        List<ReplyRow> parsed = new ArrayList<>();
        Matcher replies = REPLY.matcher(output);
        while (replies.find()) {
            parsed.add(new ReplyRow(
                    ProbeParsers.toIntOrNull(replies.group(2)),
                    ProbeParsers.toDoubleOrNull(replies.group(4)),
                    ProbeParsers.toIntOrNull(replies.group(3))));
        }

        Integer transmittedValue = null;
        Matcher transmittedMatcher = TRANSMITTED.matcher(output);
        if (transmittedMatcher.find()) transmittedValue = ProbeParsers.toIntOrNull(transmittedMatcher.group(1));
        int transmitted = transmittedValue != null ? transmittedValue : Math.max(parsed.size(), 1);

        Integer receivedValue = null;
        Matcher receivedMatcher = RECEIVED.matcher(output);
        if (receivedMatcher.find()) receivedValue = ProbeParsers.toIntOrNull(receivedMatcher.group(1));
        int receivedCount = 0;
        for (ReplyRow row : parsed) {
            if (row.elapsedMs != null) receivedCount++;
        }
        int received = receivedValue != null ? receivedValue : receivedCount;

        Double lossValue = ProbeParsers.toDoubleOrNull(loss.group(1));
        double lossPercent = lossValue != null
                ? lossValue
                : (transmitted > 0 ? (transmitted - received) * 100.0 / transmitted : 100.0);

        Matcher rtt = RTT.matcher(output);
        boolean hasRtt = rtt.find();

        Map<Integer, ReplyRow> bySequence = new LinkedHashMap<>();
        for (ReplyRow row : parsed) {
            bySequence.put(row.sequence != null ? row.sequence : -1, row);
        }
        int base = bySequence.containsKey(0) ? 0 : 1;
        List<ReplyRow> rows = new ArrayList<>();
        for (int sequence = base; sequence < base + transmitted; sequence++) {
            ReplyRow row = bySequence.get(sequence);
            rows.add(row != null ? row : new ReplyRow(sequence));
        }

        List<Double> samples = new ArrayList<>();
        for (ReplyRow row : parsed) {
            if (row.elapsedMs != null) samples.add(row.elapsedMs);
        }

        Double minMs = hasRtt ? ProbeParsers.toDoubleOrNull(rtt.group(1)) : null;
        if (minMs == null) minMs = minOf(samples);
        Double avgMs = hasRtt ? ProbeParsers.toDoubleOrNull(rtt.group(2)) : null;
        if (avgMs == null) avgMs = samples.isEmpty() ? null : average(samples);
        Double maxMs = hasRtt ? ProbeParsers.toDoubleOrNull(rtt.group(3)) : null;
        if (maxMs == null) maxMs = maxOf(samples);
        Double jitterMs = null;
        if (hasRtt) {
            String group = rtt.group(4);
            if (group != null) jitterMs = ProbeParsers.toDoubleOrNull(group);
        }
        if (jitterMs == null) jitterMs = jitterOf(samples);

        writer.u8(0);
        writer.i32(transmitted);
        writer.i32(received);
        writer.f64(lossPercent);
        writer.u8((minMs != null ? 1 : 0) | (avgMs != null ? 2 : 0)
                | (maxMs != null ? 4 : 0) | (jitterMs != null ? 8 : 0));
        writer.f64(minMs != null ? minMs : 0.0);
        writer.f64(avgMs != null ? avgMs : 0.0);
        writer.f64(maxMs != null ? maxMs : 0.0);
        writer.f64(jitterMs != null ? jitterMs : 0.0);
        writer.u32(rows.size());
        for (ReplyRow row : rows) {
            writer.i32(row.sequence);
            writer.u8((row.elapsedMs != null ? 1 : 0) | (row.ttl != null ? 2 : 0));
            writer.f64(row.elapsedMs != null ? row.elapsedMs : 0.0);
            writer.i32(row.ttl != null ? row.ttl : 0);
            writer.u8(row.timeout ? 1 : 0);
        }
        return writer.bytes();
    }

    // ---------------------------------------------------------------------------------------
    // jitterOf / latency sample arithmetic
    // ---------------------------------------------------------------------------------------

    /** Flags + min/avg/max/jitter + `average().roundToLong().coerceAtLeast(1)`. */
    static byte[] latencyPayload(double[] samples) {
        Double min = null;
        Double max = null;
        double sum = 0.0;
        for (double sample : samples) {
            min = min == null ? sample : Math.min(min, sample);
            max = max == null ? sample : Math.max(max, sample);
            sum += sample;
        }
        Double average = samples.length == 0 ? null : sum / samples.length;
        Double jitter = jitterOf(samples);
        long rounded = average == null ? 0L : Math.round(average);
        if (rounded < 1L) rounded = 1L;

        ProbeWriter writer = new ProbeWriter();
        writer.u8((min != null ? 1 : 0) | (average != null ? 2 : 0)
                | (max != null ? 4 : 0) | (jitter != null ? 8 : 0));
        writer.f64(min != null ? min : 0.0);
        writer.f64(average != null ? average : 0.0);
        writer.f64(max != null ? max : 0.0);
        writer.f64(jitter != null ? jitter : 0.0);
        writer.i64(rounded);
        return writer.bytes();
    }

    private static Double jitterOf(List<Double> samples) {
        if (samples.size() < 2) return null;
        double mean = average(samples);
        double sum = 0.0;
        for (double sample : samples) sum += Math.abs(sample - mean);
        return sum / samples.size();
    }

    private static Double jitterOf(double[] samples) {
        List<Double> values = new ArrayList<>();
        for (double sample : samples) values.add(sample);
        return jitterOf(values);
    }

    private static double average(List<Double> samples) {
        double sum = 0.0;
        for (double sample : samples) sum += sample;
        return sum / samples.size();
    }

    private static Double minOf(List<Double> samples) {
        Double min = null;
        for (double sample : samples) min = min == null ? sample : Math.min(min, sample);
        return min;
    }

    private static Double maxOf(List<Double> samples) {
        Double max = null;
        for (double sample : samples) max = max == null ? sample : Math.max(max, sample);
        return max;
    }

    // ---------------------------------------------------------------------------------------
    // TraceProbe's per-hop parse
    // ---------------------------------------------------------------------------------------

    private static final Pattern TRACE_REPLY = Pattern.compile(
            "from\\s+(\\S+):\\s+(?:icmp_seq|seq)=\\d+.*?time=([0-9.]+)\\s*ms");
    private static final Pattern TRACE_FROM = Pattern.compile(
            "From\\s+(.+?)\\s*:??\\s*icmp_seq=\\d+\\s+(.*)");

    static byte[] tracePayload(String resolved, String text) {
        ProbeWriter writer = new ProbeWriter();
        if (text.contains("Usage:") || text.contains("invalid option")) {
            writer.u8(4);
            return writer.bytes();
        }
        Matcher reply = TRACE_REPLY.matcher(text);
        if (reply.find()) {
            String address = reply.group(1);
            if (address.isEmpty()) address = resolved;
            Double elapsed = ProbeParsers.toDoubleOrNull(reply.group(2));
            writer.u8(0);
            writer.u8((address != null ? 1 : 0) | (elapsed != null ? 2 : 0));
            writer.string(address);
            writer.f64(elapsed != null ? elapsed : 0.0);
            return writer.bytes();
        }
        Matcher from = TRACE_FROM.matcher(text);
        if (from.find()) {
            boolean unreachable = from.group(2).toLowerCase(Locale.ROOT).contains("unreach");
            writer.u8(1);
            writer.u8(1 | (unreachable ? 4 : 0));
            writer.string(from.group(1));
            return writer.bytes();
        }
        if (text.toLowerCase(Locale.ROOT).contains("unreach")) {
            writer.u8(2);
            return writer.bytes();
        }
        writer.u8(3);
        return writer.bytes();
    }

    // ---------------------------------------------------------------------------------------
}
