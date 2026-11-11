import com.haoze.diting.engine.Engine;

import java.io.ByteArrayOutputStream;
import java.net.DatagramPacket;
import java.net.DatagramSocket;
import java.net.InetAddress;
import java.net.InetSocketAddress;
import java.nio.file.Files;
import java.net.Socket;
import java.nio.charset.StandardCharsets;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.atomic.AtomicReference;

/// Host-JVM smoke test for the engine's JNI boundary.
///
/// It proves three things the Rust tests cannot:
///
/// 1. the exported symbols match the names and argument orders the Kotlin facade declares;
/// 2. the callbacks are called from engine threads into a real JVM object, with the gomobile
///    argument list intact (thirteen arguments for the race log, eight for bootstrap);
/// 3. the standalone server answers a real UDP and a real TCP client, end to end, with a fake
///    upstream written here in Java.
///
/// The semantics (policy walk, cache TTLs, JSON documents) belong to the Rust tests; this only
/// checks the boundary.
public final class EngineSmoke {
    static int checks;

    public static void main(String[] args) throws Exception {
        System.load(args.length > 0 ? args[0] : "diting_engine");

        FakeUpstream upstream = FakeUpstream.start();
        try {
            lifecycle(upstream);
        } finally {
            upstream.close();
        }
        System.out.println("engine smoke ok: " + checks + " checks");
    }

    /// One engine's whole life: config, rules, server, queries, documents, stop, free.
    private static void lifecycle(FakeUpstream upstream) throws Exception {
        Engine engine = new Engine();
        check(engine.handle() != 0, "engine handle");
        check(!engine.isRunning(), "not running before start");

        String configError = engine.applyDNSConfig(upstream.config());
        check(configError == null, "applyDNSConfig accepted: " + configError);

        String snapshotError = engine.applyRuleSnapshot(
                "{\"filterEnabled\":true,\"globalBlock\":[\"blocked.test\"],"
                        + "\"globalAllow\":[],\"globalImportant\":[]}");
        check(snapshotError.isEmpty(), "applyRuleSnapshot accepted: " + snapshotError);

        engine.setRewriteRules("{\"rewrite.test\":\"9.8.7.6\"}");
        engine.setBlockResponseType("NXDOMAIN");
        engine.setFilterDNS(true);

        AtomicInteger batches = new AtomicInteger();
        AtomicReference<String> batch = new AtomicReference<>();
        AtomicReference<String> race = new AtomicReference<>();
        CountDownLatch logged = new CountDownLatch(1);
        CountDownLatch raced = new CountDownLatch(1);
        engine.setBatchLogCallback(json -> {
            batch.set(json);
            batches.incrementAndGet();
            logged.countDown();
        });
        engine.setRaceLogCallback(
                (queryName, queryType, strategy, providerCount, success, elapsedMs,
                        selectedProviderID, selectedElapsedMs, winnerProviderID, winnerElapsedMs,
                        fallbackUsed, fallbackSuccess, errorMessage) -> {
                    race.set(queryName + "|" + queryType + "|" + strategy + "|" + success + "|"
                            + selectedProviderID + "|" + fallbackUsed);
                    raced.countDown();
                });
        engine.setBootstrapLogCallback(
                (ipID, ipName, ip, host, success, elapsedMs, fallbackUsed, errorMessage) -> {
                    throw new IllegalStateException("no bootstrap event is expected in stage 1");
                });

        String startError = engine.startStandalone(0);
        check(startError == null, "startStandalone accepted: " + startError);
        check(engine.isRunning(), "running after start");

        // A UDP query: forwarded upstream, answered, logged, and raced.
        byte[] query = query("forward.test", 11);
        byte[] answer = udp(port(engine), query);
        check(answer.length > 12, "udp answer received");
        check(answer[0] == 0 && answer[1] == 11, "udp answer carries the client id");
        check((answer[3] & 0x0f) == 0, "udp answer is NOERROR (rcode=" + (answer[3] & 0x0f)
                + ", length=" + answer.length + ")");

        check(logged.await(3, TimeUnit.SECONDS), "batch log delivered");
        check(batches.get() >= 1, "one batch delivered");
        String batchJson = batch.get();
        check(batchJson.contains("\"d\":\"forward.test\""), "batch row carries the domain");
        check(batchJson.contains("\"i\":\"1.2.3.4\""), "batch row carries the addresses");
        check(raced.await(3, TimeUnit.SECONDS), "race log delivered");
        check(race.get().startsWith("forward.test|1|single|true|p1|"), "race row: " + race.get());

        // The cache answers the second query without a second upstream round trip.
        udp(port(engine), query("forward.test", 12));
        check(upstream.count() == 1, "the cache served the repeat: " + upstream.count());

        // A policy block and a rewrite, both without touching the upstream.
        byte[] blocked = udp(port(engine), query("blocked.test", 13));
        check((blocked[3] & 0x0f) == 3, "blocked answer is NXDOMAIN");
        byte[] rewritten = udp(port(engine), query("rewrite.test", 14));
        check((rewritten[3] & 0x0f) == 0, "rewrite answer is NOERROR");
        check(rewritten[rewritten.length - 4] == 9, "rewrite answer is the configured address");
        check(upstream.count() == 1, "blocked and rewritten queries stayed local");

        // TCP carries the same answer with the 2-byte frame.
        byte[] overTcp = tcp(port(engine), query("tcp.test", 15));
        check(overTcp[0] == 0 && overTcp[1] == 15, "tcp answer carries the client id");

        // The documents the UI reads.
        String stats = engine.getStats();
        check(stats.contains("\"total\":"), "stats document: " + stats);
        check(stats.contains("\"dropped_logs\":"), "stats document carries the drop counter");
        String cacheStats = engine.getDNSCacheStats();
        check(cacheStats.contains("\"totalHits\":"), "cache stats: " + cacheStats);
        check(cacheStats.contains("\"evictionCount\":"), "cache stats carries evictions");
        String entries = engine.getDNSCacheEntries(10);
        check(entries.startsWith("["), "cache entries: " + entries);
        check(entries.contains("\"queryName\""), "cache entry carries the query name");
        check(entries.contains("\"originalTtlSeconds\""), "cache entry carries the TTL");
        String resolved = engine.resolveDomain("example.test", true);
        check(resolved.contains("\"source\":\"upstream\""), "resolveDomain: " + resolved);
        String empty = engine.resolveDomain("", true);
        check(empty.contains("\"error\":\"empty domain\""), "resolveDomain error: " + empty);

        engine.clearDNSCache();
        check(engine.getDNSCacheEntries(10).equals("[]"), "the cache is empty after clear");

        // ---- stage 3: the TUN facade and the protect-before-dial rule -----------------------

        AtomicInteger protects = new AtomicInteger();
        AtomicInteger lastFd = new AtomicInteger(-1);
        AtomicInteger trafficTicks = new AtomicInteger();
        engine.setSocketProtector(fd -> {
            protects.incrementAndGet();
            lastFd.set((int) fd);
            return true;
        });
        engine.setUIDResolver((protocol, localIP, localPort, remoteIP, remotePort) -> {
            check(localIP.equals("10.0.0.2"), "uid resolver sees the app endpoint: " + localIP);
            return 10123L;
        });
        engine.setAppUidResolver(uid -> uid == 10123L ? "com.test.app" : "");
        engine.setTrafficCallback(json -> trafficTicks.incrementAndGet());
        engine.setBlockedUIDs("10123, 20234,bogus");
        engine.setFilterHttp3(true);
        engine.setBlockEncryptedDns(true);
        engine.setTickIntervalMs(500);

        // The protector is consulted for the upstream dial of the next query; the descriptor is the
        // long gomobile generated, not a truncated int.
        udp(port(engine), query("protected.test", 21));
        check(protects.get() >= 1, "protect called before the upstream dial: " + protects.get());
        check(lastFd.get() >= 0 || System.getProperty("os.name").startsWith("Windows"),
                "protect received a descriptor: " + lastFd.get());

        // Starting a TUN on a descriptor that cannot be duplicated fails through the facade with the
        // engine's text, and leaves nothing running.
        try {
            engine.startFull(-1, null);
            check(false, "startFull on an invalid descriptor must fail");
        } catch (IllegalStateException expected) {
            check(expected.getMessage() != null && expected.getMessage().contains("TUN fd"),
                    "startFull error: " + expected.getMessage());
        }
        check(!engine.isFullRunning(), "no TUN session after a failed start");
        check(!engine.getStats().contains("\"tun\""), "no tun object without a session");
        engine.stopFull();
        engine.releaseTun();
        check(trafficTicks.get() == 0, "no traffic tick without a running session");

        // Clearing every stage 3 callback is a no-op, not a crash.
        engine.setSocketProtector(null);
        engine.setUIDResolver(null);
        engine.setAppUidResolver(null);
        engine.setTrafficCallback(null);

        // ---- stage 4a: the outbound proxy facade ------------------------------------------

        String badProxy = engine.configureOutboundProxy(
                "{\"enabled\":true,\"protocol\":\"ftp\",\"host\":\"127.0.0.1\",\"port\":1080}");
        check(badProxy.contains("unsupported outbound proxy protocol"),
                "proxy config error: " + badProxy);
        check(engine.configureOutboundProxy("").isEmpty(), "a blank config disables the proxy");
        String goodProxy = engine.configureOutboundProxy(
                "{\"enabled\":true,\"protocol\":\"socks5\",\"host\":\"127.0.0.1\","
                        + "\"port\":1080,\"scope\":\"all\"}");
        check(goodProxy.isEmpty(), "a valid proxy config is accepted: " + goodProxy);
        AtomicInteger proxyEvents = new AtomicInteger();
        engine.setOutboundProxyStatusCallback((state, message) -> proxyEvents.incrementAndGet());
        engine.setOutboundProxyStatusCallback(null);
        check(proxyEvents.get() == 0, "no status before a tunnel starts");

        // ---- stage 4b: the MITM facade ---------------------------------------------------

        String certDir = Files.createTempDirectory("diting-mitm").toString();
        String caPem = engine.startStackMitm(certDir);
        check(caPem.contains("BEGIN CERTIFICATE"), "startStackMitm hands back the root CA");
        check(engine.isMitmActive(), "MITM is active after start");
        check(engine.getMitmCACert(certDir).equals(caPem), "the live CA is the one reported");
        engine.setMitmAllowedUIDs("10123, 20234");
        engine.setHttpsBypassRules("bank.test");
        engine.setExtraPassthroughSuffixes("bank.test");
        engine.setCosmeticRules("{\"globalHide\":[\"#ad\"],\"globalException\":[],\"domains\":{}}");
        engine.setRequestRules("[{\"pattern\":\"https://ads.test/p\",\"kind\":\"block\"}]");
        AtomicInteger httpEvents = new AtomicInteger();
        engine.setHttpLogCallback((packageName, authority, protocol, outcome, rule) ->
                httpEvents.incrementAndGet());
        check(engine.getMitmBlacklistCount() == 0, "a fresh session has no blacklist entries");
        engine.clearMitmBlacklist();
        engine.setHttpLogCallback(null);
        engine.stopStackMitm();
        check(!engine.isMitmActive(), "MITM stopped");
        check(engine.getMitmCACert(certDir).contains("BEGIN CERTIFICATE"),
                "the root survives stopStackMitm");
        check(httpEvents.get() == 0, "no HTTP events without a relayed flow");

        engine.stopStandalone();
        check(!engine.isRunning(), "stopped");
        engine.stop();
        engine.free();
        check(engine.handle() == 0, "handle released");

        // A released engine must not crash the process; the facade reports it instead.
        try {
            engine.getStats();
            check(false, "a released engine refuses calls");
        } catch (IllegalStateException expected) {
            check(true, "released engine reported");
        }

        // A malformed config is reported, not fatal.
        Engine second = new Engine();
        try {
            String error = second.applyDNSConfig("{\"mode\":\"nope\"}");
            check(error != null && error.contains("mode"), "config error reported: " + error);
            String missing = second.startStandalone(1);
            check(missing == null || missing.contains("bind"), "start on a privileged port: " + missing);
        } finally {
            second.stop();
            second.free();
        }
    }

    // ---- helpers ---------------------------------------------------------------------------

    private static void check(boolean condition, String message) {
        checks++;
        if (!condition) {
            throw new IllegalStateException("check failed: " + message);
        }
    }

    private static byte[] question(String name) {
        ByteArrayOutputStream out = new ByteArrayOutputStream();
        for (String label : name.split("\\.")) {
            out.write(label.length());
            out.writeBytes(label.getBytes(StandardCharsets.US_ASCII));
        }
        out.write(0);
        out.writeBytes(new byte[] {0, 1, 0, 1});
        return out.toByteArray();
    }

    static byte[] query(String name, int id) {
        ByteArrayOutputStream out = new ByteArrayOutputStream();
        out.writeBytes(new byte[] {(byte) (id >> 8), (byte) id, 0x01, 0x00, 0, 1, 0, 0, 0, 0, 0, 0});
        out.writeBytes(question(name));
        return out.toByteArray();
    }

    /// The fake upstream's answer: the query echoed, plus one A record.
    static byte[] answer(byte[] query, int[] address) {
        byte[] response = query.clone();
        response[2] = (byte) 0x81;
        response[3] = (byte) 0x80;
        response[7] = 1;
        ByteArrayOutputStream out = new ByteArrayOutputStream();
        out.writeBytes(response);
        out.writeBytes(new byte[] {(byte) 0xc0, 0x0c, 0, 1, 0, 1, 0, 0, 0, 60, 0, 4});
        for (int octet : address) {
            out.write(octet);
        }
        return out.toByteArray();
    }

    /// The port the engine's standalone server picked (`startStandalone(0)` means "any").
    private static int port(Engine engine) {
        long port = engine.standalonePort();
        check(port > 0, "server reports its port");
        return (int) port;
    }

    private static byte[] udp(int port, byte[] query) throws Exception {
        try (DatagramSocket socket = new DatagramSocket()) {
            socket.setSoTimeout(3000);
            InetAddress loopback = InetAddress.getByName("127.0.0.1");
            socket.send(new DatagramPacket(query, query.length, loopback, port));
            byte[] buffer = new byte[4096];
            DatagramPacket packet = new DatagramPacket(buffer, buffer.length);
            socket.receive(packet);
            byte[] response = new byte[packet.getLength()];
            System.arraycopy(packet.getData(), 0, response, 0, response.length);
            return response;
        }
    }

    private static byte[] tcp(int port, byte[] query) throws Exception {
        try (Socket socket = new Socket("127.0.0.1", port)) {
            socket.setSoTimeout(3000);
            socket.getOutputStream().write(new byte[] {(byte) (query.length >> 8), (byte) query.length});
            socket.getOutputStream().write(query);
            socket.getOutputStream().flush();
            byte[] length = socket.getInputStream().readNBytes(2);
            int size = ((length[0] & 0xff) << 8) | (length[1] & 0xff);
            return socket.getInputStream().readNBytes(size);
        }
    }

    /// A tiny DNS upstream: answers every query with 1.2.3.4 and counts the queries.
    static final class FakeUpstream {
        private final DatagramSocket socket;
        private final AtomicInteger queries = new AtomicInteger();
        private final Thread thread;

        private FakeUpstream(DatagramSocket socket) {
            this.socket = socket;
            this.thread = new Thread(this::loop, "fake-dns-upstream");
            this.thread.setDaemon(true);
            this.thread.start();
        }

        static FakeUpstream start() throws Exception {
            DatagramSocket socket = new DatagramSocket(new InetSocketAddress("127.0.0.1", 0));
            socket.setSoTimeout(200);
            return new FakeUpstream(socket);
        }

        String config() {
            return "{\"mode\":\"single\",\"providers\":[{\"id\":\"p1\",\"protocol\":\"PLAIN\","
                    + "\"server\":\"127.0.0.1:" + socket.getLocalPort() + "\",\"url\":\"\",\"weight\":1}],"
                    + "\"blockResponse\":\"NXDOMAIN\","
                    + "\"dynamicResponse\":{\"enabled\":false,\"requestThreshold\":0,"
                    + "\"windowSeconds\":0,\"nxDomainDurationSeconds\":0},"
                    + "\"cache\":{\"enabled\":true,\"mode\":\"limit_max_ttl\",\"maxTtlSeconds\":600},"
                    + "\"bootstrap\":{\"enabled\":false,\"ips\":[]}}";
        }

        int count() {
            return queries.get();
        }

        private void loop() {
            byte[] buffer = new byte[4096];
            while (!socket.isClosed()) {
                try {
                    DatagramPacket packet = new DatagramPacket(buffer, buffer.length);
                    socket.receive(packet);
                    byte[] query = new byte[packet.getLength()];
                    System.arraycopy(packet.getData(), 0, query, 0, query.length);
                    queries.incrementAndGet();
                    byte[] response = answer(query, new int[] {1, 2, 3, 4});
                    socket.send(new DatagramPacket(response, response.length, packet.getAddress(),
                            packet.getPort()));
                } catch (Exception ignored) {
                    // A read timeout or a closed socket is how this thread ends.
                }
            }
        }

        void close() {
            socket.close();
        }
    }
}
