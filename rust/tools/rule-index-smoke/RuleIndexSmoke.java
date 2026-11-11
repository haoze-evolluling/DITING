import com.haoze.diting.core.rule.RuleIndexNative;

import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.io.DataInputStream;
import java.io.DataOutputStream;
import java.io.IOException;
import java.nio.charset.StandardCharsets;

/// Host-JVM smoke test for the rule-index helper entries.
///
/// It proves the seven exported symbols match the signatures Kotlin declares (name and argument
/// order) and that every payload round trips. The semantics belong to the Rust tests; this only
/// checks the boundary, so it needs nothing but a JVM and `diting_rule_core.dll`/`.so`.
public final class RuleIndexSmoke {
    private static int checks;

    public static void main(String[] args) {
        System.load(args.length > 0 ? args[0] : "diting_rule_core");
        RuleIndexNative native_ = new RuleIndexNative();

        paths(native_);
        dtriValidation(native_);
        plan(native_);
        triePaths(native_);
        appAllowlist(native_);
        fingerprint(native_);
        rewriteRules(native_);

        System.out.println("rule-index smoke ok: " + checks + " checks");
    }

    /// The dataset tags: NORMAL (0), EXPRESS (1), DNS_MODE (2).
    private static void paths(RuleIndexNative native_) {
        Reader normal = new Reader(native_.paths(0));
        check(normal.string().equals("rule-index"), "normal root");
        check(normal.string().equals("domain"), "domain folder");
        check(normal.string().equals("hosts"), "hosts folder");
        check(normal.string().equals("block.trie"), "block trie");
        check(normal.string().equals("block.important.trie"), "important block trie");
        check(normal.string().equals("allow.trie"), "allow trie");
        check(normal.string().equals("allow.important.trie"), "important allow trie");

        Reader express = new Reader(native_.paths(1));
        check(express.string().equals("rule-index/express"), "express root");
        // Only the root differs, so the tails are shared.
        Reader normalTails = new Reader(native_.paths(0));
        normalTails.string();
        for (int index = 0; index < 6; index++) {
            check(express.string().equals(normalTails.string()), "express tail " + index);
        }

        Reader dnsMode = new Reader(native_.paths(2));
        check(dnsMode.string().equals("rule-index"), "dns mode shares the normal root");
        check(native_.paths(9) == null, "unknown dataset is rejected");
    }

    private static void dtriValidation(RuleIndexNative native_) {
        byte[] image = minimalImage();
        Reader ok = new Reader(native_.dtriValidate(validatePayload(image, image.length)));
        check(ok.u8() == 0, "a consistent image validates");
        check(ok.i64() == image.length, "the expected length is the file length");

        Reader sections = new Reader(native_.dtriValidate(validatePayload(image, image.length - 1)));
        check(sections.u8() == 4, "a short file is a section mismatch");
        check(sections.i64() == image.length, "the expected length comes back");

        Reader header = new Reader(native_.dtriValidate(validatePayload(new byte[8], 8)));
        check(header.u8() == 1, "a short header is rejected as a header");

        byte[] badMagic = image.clone();
        badMagic[3] = 'X';
        check(new Reader(native_.dtriValidate(validatePayload(badMagic, image.length))).u8() == 1,
                "a foreign magic is rejected");

        byte[] newer = image.clone();
        newer[7] = 2;
        check(new Reader(native_.dtriValidate(validatePayload(newer, image.length))).u8() == 2,
                "a newer version is not read");

        byte[] noNodes = image.clone();
        // nodes = 0
        noNodes[8] = 0;
        noNodes[9] = 0;
        noNodes[10] = 0;
        noNodes[11] = 0;
        check(new Reader(native_.dtriValidate(validatePayload(noNodes, image.length))).u8() == 3,
                "zero nodes is rejected");
    }

    /// A root-only DTRI header: magic, version 1, one node, no edges/sources, one bloom bit.
    private static byte[] minimalImage() {
        int header = 9 * 4;
        int bloomBytes = 1;
        int nodes = 1;
        int nodeSize = 12;
        byte[] image = new byte[header + bloomBytes + nodes * nodeSize];
        writeInt(image, 0, 0x44545249); // DTRI
        writeInt(image, 4, 1); // version
        writeInt(image, 8, nodes);
        writeInt(image, 12, 0); // edges
        writeInt(image, 16, 0); // sources
        writeInt(image, 20, 1); // bloomBits
        writeInt(image, 24, bloomBytes);
        writeInt(image, 28, 0); // labelsBytes
        writeInt(image, 32, 0); // sourcesBytes
        return image;
    }

    private static void writeInt(byte[] target, int offset, int value) {
        target[offset] = (byte) (value >>> 24);
        target[offset + 1] = (byte) (value >>> 16);
        target[offset + 2] = (byte) (value >>> 8);
        target[offset + 3] = (byte) value;
    }

    private static void plan(RuleIndexNative native_) {
        // block: compiled + loaded; allow: loaded + not indexed.
        byte[] packed = pack(out -> {
            out.writeByte(2);
            out.writeByte(1);
            out.writeByte(1);
            out.writeByte(0);
        });
        Reader plan = new Reader(native_.snapshotPlan(packed));
        check(plan.u8() == 1, "compiled flag");
        check(plan.u8() == 1, "settled flag");
        check(plan.u8() == 1, "block normal usable");
        check(plan.u8() == 1, "block important usable");
        check(plan.u8() == 1, "allow normal usable");
        check(plan.u8() == 0, "allow important not indexed");
        check(plan.u8() == 1, "block keeps only special rows");
        check(plan.u8() == 0, "allow keeps every row");

        byte[] failed = pack(out -> {
            out.writeByte(2);
            out.writeByte(1);
            out.writeByte(3);
            out.writeByte(1);
        });
        Reader failedPlan = new Reader(native_.snapshotPlan(failed));
        check(failedPlan.u8() == 1, "a failed half still counts as a compile");
        check(failedPlan.u8() == 0, "a failed half blocks the stamp");

        check(native_.snapshotPlan(new byte[] {0, 0, 0, 9}) == null, "an unknown tag is rejected");
    }

    private static void triePaths(RuleIndexNative native_) {
        byte[] packed = pack(out -> {
            out.writeByte(1);
            out.writeInt(4);
            writePath(out, "block.trie", true, 100);
            writePath(out, "block.important.trie", true, 0);
            writePath(out, "allow.trie", false, 0);
            writePath(out, "allow.important.trie", true, 7);
        });
        Reader paths = new Reader(native_.triePaths(packed));
        check(paths.u8() == 1 && paths.string().equals("block.trie"), "existing file exported");
        check(paths.u8() == 0, "an empty file is not exported");
        check(paths.u8() == 0, "a missing file is not exported");
        check(paths.u8() == 1 && paths.string().equals("allow.important.trie"), "last file exported");

        byte[] noDirectory = pack(out -> {
            out.writeByte(0);
            out.writeInt(4);
            writePath(out, "block.trie", true, 100);
            writePath(out, "block.important.trie", true, 1);
            writePath(out, "allow.trie", true, 1);
            writePath(out, "allow.important.trie", true, 1);
        });
        Reader none = new Reader(native_.triePaths(noDirectory));
        for (int index = 0; index < 4; index++) {
            check(none.u8() == 0, "no index directory exports nothing: " + index);
        }

        byte[] threeEntries = pack(out -> {
            out.writeByte(1);
            out.writeInt(3);
        });
        check(native_.triePaths(threeEntries) == null, "three entries is drift");
    }

    private static void appAllowlist(RuleIndexNative native_) {
        byte[] packed = pack(out -> {
            out.writeInt(3);
            writePackage(out, "com.a", " example.com ", "example.com", "   ");
            writePackage(out, "com.empty", "");
            writePackage(out, "com.b", "b.example", "a.example");
        });
        Reader packages = new Reader(native_.appAllowlist(packed));
        check(packages.count() == 2, "the empty package is dropped");
        check(packages.string().equals("com.a"), "first package");
        check(packages.count() == 1 && packages.string().equals("example.com"), "trimmed and deduplicated");
        check(packages.string().equals("com.b"), "second package");
        check(packages.count() == 2, "both domains kept");
        check(packages.string().equals("b.example"), "insertion order kept");
        check(packages.string().equals("a.example"), "insertion order kept");
    }

    private static void fingerprint(RuleIndexNative native_) {
        byte[] packed = pack(out -> {
            out.writeInt(2);
            writeString(out, "block_rule");
            out.writeByte(1);
            out.writeLong(10);
            out.writeLong(55);
            out.writeLong(9);
            writeString(out, "gone");
            out.writeByte(0);
        });
        check(new Reader(native_.ruleFingerprint(packed)).string()
                .equals("block_rule:10:55:9|gone:-"), "fingerprint text");

        byte[] drift = pack(out -> {
            out.writeInt(1);
            writeString(out, "block_rule");
            out.writeByte(2);
        });
        check(native_.ruleFingerprint(drift) == null, "an unknown presence byte is drift");
    }

    private static void rewriteRules(RuleIndexNative native_) {
        byte[] packed = pack(out -> {
            out.writeInt(4);
            writePair(out, " ads.example.com ", " 0.0.0.0 ");
            writePair(out, "ads.example.com", "1.1.1.1");
            writePair(out, "", "0.0.0.0");
            writePair(out, "b.example", "::");
        });
        Reader rows = new Reader(native_.rewriteRules(packed));
        check(rows.count() == 2, "duplicates and blanks dropped");
        check(rows.string().equals("ads.example.com"), "first pattern kept");
        check(rows.string().equals("0.0.0.0"), "oldest target wins");
        check(rows.string().equals("b.example"), "second pattern");
        check(rows.string().equals("::"), "second target");
    }

    // --- payload helpers --------------------------------------------------------------------

    private interface Writer {
        void write(DataOutputStream out) throws IOException;
    }

    private static byte[] pack(Writer writer) {
        ByteArrayOutputStream buffer = new ByteArrayOutputStream(256);
        try (DataOutputStream out = new DataOutputStream(buffer)) {
            writer.write(out);
        } catch (IOException error) {
            throw new IllegalStateException(error);
        }
        return buffer.toByteArray();
    }

    private static byte[] validatePayload(byte[] header, long fileLength) {
        return pack(out -> {
            out.writeInt(header.length);
            out.write(header);
            out.writeLong(fileLength);
        });
    }

    private static void writePath(DataOutputStream out, String path, boolean exists, long length)
            throws IOException {
        writeString(out, path);
        out.writeByte(exists ? 1 : 0);
        out.writeLong(length);
    }

    private static void writePackage(DataOutputStream out, String packageName, String... domains)
            throws IOException {
        writeString(out, packageName);
        out.writeInt(domains.length);
        for (String domain : domains) {
            writeString(out, domain);
        }
    }

    private static void writePair(DataOutputStream out, String pattern, String target) throws IOException {
        writeString(out, pattern);
        writeString(out, target);
    }

    private static void writeString(DataOutputStream out, String value) throws IOException {
        byte[] bytes = value.getBytes(StandardCharsets.UTF_8);
        out.writeInt(bytes.length);
        out.write(bytes);
    }

    private static final class Reader {
        private final DataInputStream in;

        Reader(byte[] payload) {
            this.in = new DataInputStream(new ByteArrayInputStream(payload));
        }

        int u8() {
            try {
                return in.readUnsignedByte();
            } catch (IOException error) {
                throw new IllegalStateException(error);
            }
        }

        int count() {
            try {
                return in.readInt();
            } catch (IOException error) {
                throw new IllegalStateException(error);
            }
        }

        long i64() {
            try {
                return in.readLong();
            } catch (IOException error) {
                throw new IllegalStateException(error);
            }
        }

        String string() {
            try {
                byte[] bytes = new byte[in.readInt()];
                in.readFully(bytes);
                return new String(bytes, StandardCharsets.UTF_8);
            } catch (IOException error) {
                throw new IllegalStateException(error);
            }
        }
    }

    private static void check(boolean condition, String what) {
        checks++;
        if (!condition) {
            throw new AssertionError("rule-index smoke failed: " + what);
        }
    }
}
