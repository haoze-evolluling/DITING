import java.io.ByteArrayOutputStream;
import java.io.DataOutputStream;
import java.io.IOException;
import java.nio.charset.StandardCharsets;

/// Reference payload writer: the fixed layouts documented in
/// {@code rust/diting-probe-core/src/api.rs}, written through `DataOutputStream` (big-endian).
///
/// <p>Package-private so both {@code ProbeParsers} (DNS replies) and {@code ProbeText}
/// (`ping` / `traceroute` / latency) pack their answers with it.
final class ProbeWriter {
    private final ByteArrayOutputStream out = new ByteArrayOutputStream();
    private final DataOutputStream data = new DataOutputStream(out);

    void u8(int value) {
        try {
            data.writeByte(value);
        } catch (IOException error) {
            throw new IllegalStateException(error);
        }
    }

    void u32(long value) {
        try {
            data.writeInt((int) value);
        } catch (IOException error) {
            throw new IllegalStateException(error);
        }
    }

    void i32(int value) {
        try {
            data.writeInt(value);
        } catch (IOException error) {
            throw new IllegalStateException(error);
        }
    }

    void i64(long value) {
        try {
            data.writeLong(value);
        } catch (IOException error) {
            throw new IllegalStateException(error);
        }
    }

    void f64(double value) {
        try {
            data.writeDouble(value);
        } catch (IOException error) {
            throw new IllegalStateException(error);
        }
    }

    void string(String value) {
        byte[] bytes = value.getBytes(StandardCharsets.UTF_8);
        u32(bytes.length);
        try {
            data.write(bytes);
        } catch (IOException error) {
            throw new IllegalStateException(error);
        }
    }

    byte[] bytes() {
        try {
            data.flush();
        } catch (IOException error) {
            throw new IllegalStateException(error);
        }
        return out.toByteArray();
    }
}
