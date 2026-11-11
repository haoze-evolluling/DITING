/// Reference implementation of the diagnostics parsers, lifted out of Kotlin so it can run on a
/// desktop JVM: no Kotlin toolchain, no device.
///
/// <p>This half is the host text and DNS wire work: {@code NetHost.sanitize},
/// {@code DnsLookupProbe.isIpLiteral}, the A/AAAA query builders, {@code DnsLatencyTester.isSuccess}
/// and {@code DnsServerProbe}'s answer walk. Each method is a line-for-line port of the Kotlin it
/// replaces, so the {@code DataInputStream} walk and the {@code Character} predicates are the same
/// Java library calls the app made.
///
/// <p>Compile the four files together and run the corpus generator:
///
/// <pre>
///   javac -d /tmp/probe-ref rust/tools/probe-reference/*.java
///   java -cp /tmp/probe-ref ProbeReference --corpus rust/diting-probe-core/tests/fixtures
/// </pre>

import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.io.DataInputStream;
import java.io.DataOutputStream;
import java.io.EOFException;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.List;

/// Host text and DNS wire parsers; package-private so {@code ProbeReference} can call them.
final class ProbeParsers {
    // ---------------------------------------------------------------------------------------
    // NetHost.sanitize
    // ---------------------------------------------------------------------------------------

    static String sanitize(String input) {
        String value = input.trim();
        if (value.isEmpty()) return value;
        int schemeIndex = value.indexOf("://");
        if (schemeIndex >= 0) value = value.substring(schemeIndex + 3);
        int cutIndex = indexOfAny(value, '/', '?', '#');
        if (cutIndex >= 0) value = value.substring(0, cutIndex);
        int atIndex = value.lastIndexOf('@');
        if (atIndex >= 0) value = value.substring(atIndex + 1);
        if (value.startsWith("[")) {
            int endIndex = value.indexOf(']');
            if (endIndex > 0) value = value.substring(1, endIndex);
            return value;
        }
        if (!value.contains("::") && countChar(value, ':') == 1) {
            String afterColon = value.substring(value.indexOf(':') + 1);
            boolean digits = !afterColon.isEmpty();
            for (int i = 0; i < afterColon.length() && digits; i++) {
                digits = Character.isDigit(afterColon.charAt(i));
            }
            if (digits) value = value.substring(0, value.indexOf(':'));
        }
        return value;
    }

    private static int indexOfAny(String value, char... needles) {
        for (int i = 0; i < value.length(); i++) {
            for (char needle : needles) {
                if (value.charAt(i) == needle) return i;
            }
        }
        return -1;
    }

    private static int countChar(String value, char needle) {
        int count = 0;
        for (int i = 0; i < value.length(); i++) {
            if (value.charAt(i) == needle) count++;
        }
        return count;
    }

    // ---------------------------------------------------------------------------------------
    // DnsLookupProbe.isIpLiteral
    // ---------------------------------------------------------------------------------------

    static boolean isIpLiteral(String value) {
        String text = value;
        if (text.startsWith("[")) text = text.substring(1);
        if (text.endsWith("]")) text = text.substring(0, text.length() - 1);
        if (text.isEmpty()) return false;
        String[] parts = text.split("\\.", -1);
        if (parts.length == 4 && !text.contains(":")) {
            for (String part : parts) {
                if (part.isEmpty() || part.length() > 3) return false;
                for (int i = 0; i < part.length(); i++) {
                    if (!Character.isDigit(part.charAt(i))) return false;
                }
                Integer parsed = toIntOrNull(part);
                if (parsed == null || parsed < 0 || parsed > 255) return false;
            }
            return true;
        }
        if (!text.contains(":")) return false;
        if (countChar(text, ':') < 2) return false;
        for (int i = 0; i < text.length(); i++) {
            char c = text.charAt(i);
            boolean ok = Character.isDigit(c)
                    || (c >= 'a' && c <= 'f')
                    || (c >= 'A' && c <= 'F')
                    || c == ':'
                    || c == '.';
            if (!ok) return false;
        }
        return true;
    }

    /// `String.toIntOrNull` / `String.toDoubleOrNull`: the Kotlin the probes called.
    static Integer toIntOrNull(String value) {
        if (value == null) return null;
        try {
            return Integer.parseInt(value);
        } catch (NumberFormatException error) {
            return null;
        }
    }

    static Double toDoubleOrNull(String value) {
        if (value == null) return null;
        try {
            return Double.parseDouble(value);
        } catch (NumberFormatException error) {
            return null;
        }
    }

    // ---------------------------------------------------------------------------------------
    // DnsServerProbe.buildQuery / DnsLatencyTester.buildQuery
    // ---------------------------------------------------------------------------------------

    /** Returns null when a label is empty or longer than 63 bytes (the Kotlin exception case). */
    static byte[] buildQuery(int id, int qtype, String domain) {
        String trimmed = domain;
        while (trimmed.startsWith(".")) trimmed = trimmed.substring(1);
        while (trimmed.endsWith(".")) trimmed = trimmed.substring(0, trimmed.length() - 1);
        ByteArrayOutputStream out = new ByteArrayOutputStream();
        DataOutputStream data = new DataOutputStream(out);
        try {
            data.writeShort(id);
            data.writeShort(0x0100);
            data.writeShort(1);
            data.writeShort(0);
            data.writeShort(0);
            data.writeShort(0);
            for (String label : trimmed.split("\\.", -1)) {
                byte[] bytes = label.getBytes(StandardCharsets.US_ASCII);
                if (bytes.length > 63 || bytes.length == 0) return null;
                data.writeByte(bytes.length);
                data.write(bytes);
            }
            data.writeByte(0);
            data.writeShort(qtype == 0 ? 1 : 28);
            data.writeShort(1);
            data.flush();
        } catch (IOException error) {
            throw new IllegalStateException(error);
        }
        return out.toByteArray();
    }

    // ---------------------------------------------------------------------------------------
    // DnsLatencyTester.isSuccess
    // ---------------------------------------------------------------------------------------

    static boolean isSuccess(byte[] response) {
        if (response.length < 12) return false;
        boolean qr = (response[2] & 0x80) != 0;
        int rcode = response[3] & 0x0F;
        return qr && rcode == 0;
    }

    // ---------------------------------------------------------------------------------------
    // DnsServerProbe.lookup's answer walk
    // ---------------------------------------------------------------------------------------

    static final class Record {
        final int kind; // 1 = A, 2 = AAAA
        final long ttl;
        final String value;

        Record(int kind, long ttl, String value) {
            this.kind = kind;
            this.ttl = ttl;
            this.value = value;
        }
    }

    /** Status 0 = ok, 1 = invalid, 2 = truncated, 3 = rcode, 4 = incomplete answer section. */
    static byte[] parseServerReply(byte[] response, boolean ipv4) {
        ProbeWriter writer = new ProbeWriter();
        if (response.length < 12 || (response[0] & 0x80) == 0) {
            writer.u8(1);
            return writer.bytes();
        }
        if ((response[2] & 0x02) != 0) {
            writer.u8(2);
            return writer.bytes();
        }
        int rcode = response[3] & 0x0F;
        if (rcode != 0) {
            writer.u8(3);
            writer.u8(rcode);
            return writer.bytes();
        }
        List<Record> records;
        try {
            records = parseAnswers(response, ipv4);
        } catch (EOFException error) {
            writer.u8(4);
            return writer.bytes();
        } catch (IOException error) {
            writer.u8(4);
            return writer.bytes();
        }
        writer.u8(0);
        writer.u32(records.size());
        for (Record record : records) {
            writer.u8(record.kind);
            writer.u32(record.ttl);
            writer.string(record.value);
        }
        return writer.bytes();
    }

    private static List<Record> parseAnswers(byte[] response, boolean ipv4) throws IOException {
        DataInputStream input = new DataInputStream(new ByteArrayInputStream(response));
        input.skipBytes(4);
        int questionCount = input.readUnsignedShort();
        int answerCount = input.readUnsignedShort();
        input.skipBytes(4);

        for (int i = 0; i < questionCount; i++) {
            skipName(input);
            input.skipBytes(4);
        }

        List<Record> records = new ArrayList<>();
        for (int i = 0; i < answerCount; i++) {
            skipName(input);
            int type = input.readUnsignedShort();
            int klass = input.readUnsignedShort();
            long ttl = input.readInt() & 0xFFFFFFFFL;
            int length = input.readUnsignedShort();
            byte[] payload = new byte[length];
            input.readFully(payload);
            if (klass != 1) continue;
            if (type == 1) {
                if (ipv4 && length == 4) records.add(new Record(1, ttl, formatIpv4(payload)));
            } else if (type == 28) {
                if (!ipv4 && length == 16) records.add(new Record(2, ttl, formatIpv6(payload)));
            }
        }
        return records;
    }

    private static void skipName(DataInputStream input) throws IOException {
        while (true) {
            int length = input.readUnsignedByte();
            if (length == 0) return;
            if ((length & 0xC0) == 0xC0) {
                input.skipBytes(1);
                return;
            }
            input.skipBytes(length);
        }
    }

    private static String formatIpv4(byte[] bytes) {
        StringBuilder text = new StringBuilder();
        for (int i = 0; i < 4; i++) {
            if (i > 0) text.append('.');
            text.append(bytes[i] & 0xFF);
        }
        return text.toString();
    }

    private static String formatIpv6(byte[] bytes) {
        int[] groups = new int[8];
        for (int i = 0; i < 8; i++) {
            groups[i] = ((bytes[i * 2] & 0xFF) << 8) | (bytes[i * 2 + 1] & 0xFF);
        }
        int bestStart = -1;
        int bestLength = 0;
        int index = 0;
        while (index < 8) {
            if (groups[index] != 0) {
                index++;
                continue;
            }
            int end = index;
            while (end < 8 && groups[end] == 0) end++;
            if (end - index > bestLength) {
                bestStart = index;
                bestLength = end - index;
            }
            index = end;
        }
        if (bestLength < 2) {
            StringBuilder text = new StringBuilder();
            for (int i = 0; i < 8; i++) {
                if (i > 0) text.append(':');
                text.append(Integer.toHexString(groups[i]));
            }
            return text.toString();
        }
        StringBuilder head = new StringBuilder();
        for (int i = 0; i < bestStart; i++) {
            if (i > 0) head.append(':');
            head.append(Integer.toHexString(groups[i]));
        }
        StringBuilder tail = new StringBuilder();
        for (int i = bestStart + bestLength; i < 8; i++) {
            if (i > bestStart + bestLength) tail.append(':');
            tail.append(Integer.toHexString(groups[i]));
        }
        return head + "::" + tail;
    }

}
