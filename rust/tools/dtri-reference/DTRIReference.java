import java.io.ByteArrayOutputStream;
import java.io.DataOutputStream;
import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.util.ArrayList;
import java.util.Collections;
import java.util.HashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Random;
import java.util.TreeSet;

/**
 * Reference writer for the DTRI subscription-rule index.
 *
 * <p>This is the Kotlin {@code MappedSubscriptionRuleIndex.compile} algorithm lifted out of Android
 * so it can run on a desktop JVM: no Kotlin toolchain, no device, and it can be diffed byte for
 * byte against the Rust port in {@code rust/diting-rule-core/src/dtri.rs}. The committed fixtures
 * under {@code rust/diting-rule-core/tests/fixtures/} are produced with this file.
 *
 * <pre>
 *   java rust/tools/dtri-reference/DTRIReference.java rules.txt out.dtri
 *   java rust/tools/dtri-reference/DTRIReference.java --pack rules.txt out.pack
 *   java rust/tools/dtri-reference/DTRIReference.java --generate 100000 rules.txt
 * </pre>
 *
 * <p>--pack writes the JNI payload `RustRuleIndexCompiler.pack` builds, so the packed format is
 * pinned by committed fixtures instead of only by the Android build.
 *
 * <p>Corpus format: one rule per line, tab separated, fields in this order:
 * pattern, source, important, appScope, appInverted, isWildcard, denyallow, isRegex, dnsType.
 * Booleans are {@code 1}/{@code 0}; a field of {@code ~} is null and {@code =} is the empty string
 * (the trie filter treats those differently: {@code isNullOrEmpty} skips only a non-empty value).
 * Trailing fields may be omitted.
 */
public final class DTRIReference {
    private static final int MAGIC = 0x44545249; // DTRI
    private static final int VERSION = 1;
    private static final int BLOOM_HASHES = 7;

    private DTRIReference() {}

    public static void main(String[] args) throws Exception {
        if (args.length == 3 && args[0].equals("--generate")) {
            generate(new File(args[2]), Integer.parseInt(args[1]));
            return;
        }
        if (args.length == 3 && args[0].equals("--pack")) {
            writePacked(new File(args[1]), new File(args[2]));
            return;
        }
        if (args.length != 2) {
            System.err.println("usage: DTRIReference <rules.txt> <out.dtri>");
            System.err.println("       DTRIReference --pack <rules.txt> <out.pack>");
            System.err.println("       DTRIReference --generate <count> <rules.txt>");
            System.exit(2);
        }
        List<Rule> rules = readCorpus(new File(args[0]));
        long started = System.nanoTime();
        byte[] image = compile(rules);
        double millis = (System.nanoTime() - started) / 1_000_000.0;
        try (FileOutputStream out = new FileOutputStream(args[1])) {
            out.write(image);
        }
        System.out.printf(
                Locale.ROOT, "rules=%d bytes=%d compileMs=%.1f%n", rules.size(), image.length, millis);
    }

    static final class Rule {
        String pattern = "";
        String source = "";
        boolean important;
        String appScope;
        boolean appInverted;
        boolean isWildcard;
        String denyallow;
        boolean isRegex;
        String dnsType;
    }

    static List<Rule> readCorpus(File file) throws IOException {
        List<Rule> rules = new ArrayList<>();
        for (String line : Files.readAllLines(file.toPath(), StandardCharsets.UTF_8)) {
            if (line.isEmpty()) {
                continue;
            }
            String[] fields = line.split("\t", -1);
            Rule rule = new Rule();
            rule.pattern = field(fields, 0, "");
            rule.source = field(fields, 1, "");
            rule.important = bool(field(fields, 2, "0"));
            rule.appScope = nullable(fields, 3);
            rule.appInverted = bool(field(fields, 4, "0"));
            rule.isWildcard = bool(field(fields, 5, "0"));
            rule.denyallow = nullable(fields, 6);
            rule.isRegex = bool(field(fields, 7, "0"));
            rule.dnsType = nullable(fields, 8);
            rules.add(rule);
        }
        return rules;
    }

    private static String field(String[] fields, int index, String fallback) {
        return index < fields.length ? fields[index] : fallback;
    }

    /** {@code ~} is null, {@code =} is the empty string, anything else is itself. */
    private static String nullable(String[] fields, int index) {
        String value = field(fields, index, "~");
        if (value.equals("~")) {
            return null;
        }
        return value.equals("=") ? "" : value;
    }

    private static boolean bool(String value) {
        return value.equals("1") || value.equalsIgnoreCase("true");
    }

    /** The JNI payload: no filtering, the writer applies the Kotlin compile filter itself. */
    static void writePacked(File corpus, File target) throws IOException {
        List<Rule> rules = readCorpus(corpus);
        ByteArrayOutputStream buffer = new ByteArrayOutputStream();
        DataOutputStream out = new DataOutputStream(buffer);
        out.writeInt(rules.size());
        for (Rule rule : rules) {
            writeString(out, rule.pattern);
            writeString(out, rule.source);
            int flags = 0;
            if (rule.isWildcard) flags |= 1;
            if (rule.appInverted) flags |= 2;
            if (rule.isRegex) flags |= 4;
            out.writeByte(flags);
            writeOptional(out, rule.appScope);
            writeOptional(out, rule.denyallow);
            writeOptional(out, rule.dnsType);
        }
        out.flush();
        Files.write(target.toPath(), buffer.toByteArray());
    }

    private static void writeString(DataOutputStream out, String value) throws IOException {
        byte[] bytes = value.getBytes(StandardCharsets.UTF_8);
        out.writeInt(bytes.length);
        out.write(bytes);
    }

    private static void writeOptional(DataOutputStream out, String value) throws IOException {
        if (value == null) {
            out.writeInt(-1);
        } else {
            writeString(out, value);
        }
    }

    static byte[] compile(List<Rule> rules) throws IOException {
        BuildNode root = new BuildNode();
        TreeSet<String> sources = new TreeSet<>();
        int ruleCount = 0;
        for (Rule rule : rules) {
            if (rule.isWildcard
                    || rule.pattern.contains("*")
                    || (rule.appScope != null && !rule.appScope.isEmpty())
                    || rule.appInverted
                    || rule.isRegex
                    || (rule.denyallow != null && !rule.denyallow.isEmpty())
                    || (rule.dnsType != null && !rule.dnsType.isEmpty())) {
                continue;
            }
            BuildNode node = root;
            String pattern = trimEndDots(rule.pattern.toLowerCase(Locale.ROOT));
            int end = pattern.length();
            while (end > 0) {
                int dot = pattern.lastIndexOf('.', end - 1);
                String label = pattern.substring(dot + 1, end);
                BuildNode child = node.children.get(label);
                if (child == null) {
                    child = new BuildNode();
                    node.children.put(label, child);
                }
                node = child;
                end = dot;
            }
            if (node.source == null || rule.source.compareTo(node.source) < 0) {
                node.source = rule.source;
            }
            node.pattern = pattern;
            sources.add(rule.source);
            ruleCount++;
        }

        List<BuildNode> nodes = new ArrayList<>();
        assign(root, nodes);

        Map<String, Integer> sourceIds = new HashMap<>();
        int nextSourceId = 0;
        for (String source : sources) {
            sourceIds.put(source, nextSourceId++);
        }

        ByteArrayOutputStream labels = new ByteArrayOutputStream();
        List<int[]> edges = new ArrayList<>(); // labelOffset, labelLength, child
        List<int[]> flatNodes = new ArrayList<>(); // source, firstEdge, edgeCount
        for (BuildNode node : nodes) {
            int firstEdge = edges.size();
            for (Map.Entry<String, BuildNode> entry : sortedChildren(node)) {
                byte[] bytes = entry.getKey().getBytes(StandardCharsets.UTF_8);
                edges.add(new int[] {labels.size(), bytes.length, entry.getValue().index});
                labels.write(bytes);
            }
            int source = node.source == null ? -1 : sourceIds.get(node.source);
            flatNodes.add(new int[] {source, firstEdge, edges.size() - firstEdge});
        }

        int bloomBits = Math.max(64, ruleCount * 10);
        byte[] bloom = new byte[(bloomBits + 7) / 8];
        collectBloom(root, bloom, bloomBits);

        int sourceBytes = 0;
        for (String source : sources) {
            sourceBytes += 4 + source.getBytes(StandardCharsets.UTF_8).length;
        }

        ByteArrayOutputStream buffer = new ByteArrayOutputStream();
        DataOutputStream out = new DataOutputStream(buffer);
        for (int value : new int[] {
            MAGIC,
            VERSION,
            flatNodes.size(),
            edges.size(),
            sources.size(),
            bloomBits,
            bloom.length,
            labels.size(),
            sourceBytes
        }) {
            out.writeInt(value);
        }
        out.write(bloom);
        for (int[] node : flatNodes) {
            out.writeInt(node[0]);
            out.writeInt(node[1]);
            out.writeInt(node[2]);
        }
        for (int[] edge : edges) {
            out.writeInt(edge[0]);
            out.writeInt(edge[1]);
            out.writeInt(edge[2]);
        }
        out.write(labels.toByteArray());
        for (String source : sources) {
            byte[] bytes = source.getBytes(StandardCharsets.UTF_8);
            out.writeInt(bytes.length);
            out.write(bytes);
        }
        out.flush();
        return buffer.toByteArray();
    }

    private static void assign(BuildNode node, List<BuildNode> nodes) {
        node.index = nodes.size();
        nodes.add(node);
        for (Map.Entry<String, BuildNode> entry : sortedChildren(node)) {
            assign(entry.getValue(), nodes);
        }
    }

    private static List<Map.Entry<String, BuildNode>> sortedChildren(BuildNode node) {
        List<Map.Entry<String, BuildNode>> entries = new ArrayList<>(node.children.entrySet());
        Collections.sort(entries, (left, right) -> left.getKey().compareTo(right.getKey()));
        return entries;
    }

    private static void collectBloom(BuildNode node, byte[] bloom, int bloomBits) {
        if (node.pattern != null) {
            addBloom(node.pattern, bloom, bloomBits);
        }
        for (BuildNode child : node.children.values()) {
            collectBloom(child, bloom, bloomBits);
        }
    }

    private static void addBloom(String value, byte[] bloom, int bloomBits) {
        long[] hashes = hashes(value);
        for (int index = 0; index < BLOOM_HASHES; index++) {
            long sum = hashes[0] + index * hashes[1];
            int bit = (int) positiveMod(sum, bloomBits);
            bloom[bit / 8] = (byte) (bloom[bit / 8] | (1 << (bit % 8)));
        }
    }

    private static long[] hashes(String value) {
        long h1 = -3750763034362895579L;
        long h2 = h1;
        for (int index = 0; index < value.length(); index++) {
            long b = value.charAt(index) & 0xff;
            h1 = (h1 ^ b) * 1099511628211L;
            h2 = h2 * 1099511628211L ^ b;
        }
        return new long[] {h1, h2 | 1L};
    }

    private static long positiveMod(long value, long modulus) {
        return (value % modulus + modulus) % modulus;
    }

    private static String trimEndDots(String value) {
        int end = value.length();
        while (end > 0 && value.charAt(end - 1) == '.') {
            end--;
        }
        return value.substring(0, end);
    }

    private static final class BuildNode {
        final Map<String, BuildNode> children = new HashMap<>();
        String source;
        String pattern;
        int index = -1;
    }

    /** Synthetic corpus for the benchmark: realistic nested domains with mixed sources. */
    private static void generate(File target, int count) throws IOException {
        Random random = new Random(20261105L);
        String[] second = {"ads", "track", "metrics", "cdn", "static", "promo", "beacon", "api"};
        String[] tld = {"com", "net", "org", "io", "cn"};
        StringBuilder builder = new StringBuilder(count * 40);
        for (int index = 0; index < count; index++) {
            String host =
                    "||"
                            + second[random.nextInt(second.length)]
                            + (index % 977)
                            + "."
                            + second[random.nextInt(second.length)]
                            + (index % 53)
                            + "."
                            + tld[random.nextInt(tld.length)]
                            + "^";
            builder.append(host)
                    .append('\t')
                    .append("sub_").append(1 + random.nextInt(8))
                    .append('\t').append(index % 7 == 0 ? '1' : '0')
                    .append("\t~\t0\t0\t~\t0\t~\n");
        }
        try (FileOutputStream out = new FileOutputStream(target)) {
            out.write(builder.toString().getBytes(StandardCharsets.UTF_8));
        }
    }
}
