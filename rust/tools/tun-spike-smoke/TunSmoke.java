import com.haoze.diting.engine.TunSession;

import java.io.InputStream;
import java.net.InetAddress;
import java.net.ServerSocket;
import java.net.Socket;
import java.util.Collections;
import java.util.LinkedHashSet;
import java.util.Set;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.atomic.AtomicLong;

public final class TunSmoke {
    static int checks;

    public static void main(String[] args) throws Exception {
        System.load(args.length > 0 ? args[0] : "diting_tun_spike");

        try (Drain drain = Drain.start()) {
            happyPath(drain);
            throwingCallback(drain);
            refusedProtect(drain);
            stopThenFeed(drain);
            freeWhileRunning(drain);
        }
        System.out.println("tun spike smoke ok: " + checks + " checks");
    }

    private static void happyPath(Drain drain) {
        TunSession session = new TunSession();
        check(session.handle() != 0, "session handle");

        AtomicLong protectedFd = new AtomicLong(-1);
        AtomicInteger protectCalls = new AtomicInteger();
        session.setProtector(fd -> {
            protectCalls.incrementAndGet();
            protectedFd.set(fd);
            return true;
        });

        AtomicInteger packets = new AtomicInteger();
        Set<String> threads = Collections.synchronizedSet(new LinkedHashSet<>());
        session.setCallback(json -> {
            packets.incrementAndGet();
            threads.add(Thread.currentThread().getName());
        });

        String error = session.start("127.0.0.1:" + drain.port());
        check(error == null, "start accepted: " + error);

        String twice = session.start("127.0.0.1:" + drain.port());
        check(twice != null && twice.contains("already running"), "a second start is refused: " + twice);

        session.feed(1000);
        check(session.waitForCallbacks(1000, 10_000), "1000 callbacks arrived: " + session.getStats());
        check(packets.get() == 1000, "callback count " + packets.get());
        check(protectCalls.get() == 1, "protect runs once per connection: " + protectCalls.get());
        check(protectedFd.get() > 0, "protect received a real descriptor: " + protectedFd.get());
        check(threads.size() == 1, "all callbacks on one thread: " + threads);
        String stats = session.getStats();
        check(stats.contains("\"thread\":\"diting-tun-callback\""),
                "the callback thread is the dedicated one: " + stats);
        check(stats.contains("\"delivered\":1000"), "stats delivered: " + stats);
        check(stats.contains("\"beforeConnect\":true"), "protect ordered before connect: " + stats);
        check(stats.contains("\"connects\":1"), "one protected connection: " + stats);
        check(stats.contains("\"connected\":true"), "stats reports the connection: " + stats);
        check(stats.contains("\"dropped\":0"), "no packet dropped: " + stats);
        check(stats.contains("\"denied\":0"), "no protect refused: " + stats);

        session.stop();
        int stopped = packets.get();
        session.feed(50);
        sleep(150);
        check(packets.get() == stopped, "no callback after stop: " + packets.get());
        check(session.getStats().contains("\"connected\":false"), "stopped session is disconnected");
        session.close();
    }

    private static void throwingCallback(Drain drain) {
        TunSession session = new TunSession();
        session.setProtector(fd -> true);

        AtomicInteger calls = new AtomicInteger();
        AtomicInteger delivered = new AtomicInteger();
        session.setCallback(json -> {
            delivered.incrementAndGet();
            if (calls.incrementAndGet() == 1) {
                throw new IllegalStateException("the app's callback threw");
            }
        });

        String error = session.start("127.0.0.1:" + drain.port());
        check(error == null, "start accepted with a throwing callback: " + error);
        session.feed(60);
        check(session.waitForCallbacks(60, 10_000), "callbacks continue after a Java exception");
        check(delivered.get() == 60, "every callback ran: " + delivered.get());
        check(session.getStats().contains("\"panics\":0"), "stats call still works after the exception");
        session.stop();
        session.close();
    }

    private static void refusedProtect(Drain drain) {
        TunSession session = new TunSession();
        int acceptedBefore = drain.accepted.get();
        AtomicInteger calls = new AtomicInteger();
        session.setProtector(fd -> {
            calls.incrementAndGet();
            return false;
        });
        session.setCallback(json -> {});

        String error = session.start("127.0.0.1:" + drain.port());
        check(error == null, "start accepted before the refusal: " + error);
        session.feed(10);

        String stats = waitForStats(session, "\"denied\":1", 5_000);
        check(stats.contains("\"denied\":1"), "the refusal is recorded: " + stats);
        check(stats.contains("\"connects\":0"), "no connection was made: " + stats);
        check(stats.contains("protect refused"), "the error names protect: " + stats);
        sleep(150);
        check(drain.accepted.get() == acceptedBefore,
                "the upstream saw no connection: " + drain.accepted.get());
        check(calls.get() == 1, "one protect attempt: " + calls.get());
        session.stop();
        session.close();
    }

    private static void stopThenFeed(Drain drain) {
        TunSession session = new TunSession();
        AtomicInteger delivered = new AtomicInteger();
        session.setProtector(fd -> true);
        session.setCallback(json -> delivered.incrementAndGet());
        check(session.start("127.0.0.1:" + drain.port()) == null, "start accepted");
        session.feed(10);
        check(session.waitForCallbacks(10, 10_000), "the ten packets arrived");
        session.stop();
        session.stop();
        int before = delivered.get();
        session.feed(10);
        sleep(150);
        check(delivered.get() == before, "nothing arrives after stop: " + delivered.get());
        session.close();
    }

    private static void freeWhileRunning(Drain drain) {
        TunSession session = new TunSession();
        session.setProtector(fd -> true);
        session.setCallback(json -> {});
        check(session.start("127.0.0.1:" + drain.port()) == null, "start accepted");
        session.feed(200);
        long stale = session.handle();
        session.close();
        check(TunSession.statsForRawHandle(stale).equals("{}"),
                "a released handle answers {}");

        check(session.handle() == 0, "close() zeroed the handle");
        TunSession survivor = new TunSession();
        check(survivor.getStats().contains("\"live\":1"), "only the survivor is registered");
        survivor.close();
    }

    private static String waitForStats(TunSession session, String needle, long timeoutMs) {
        long deadline = System.currentTimeMillis() + timeoutMs;
        String stats = session.getStats();
        while (!stats.contains(needle) && System.currentTimeMillis() < deadline) {
            sleep(10);
            stats = session.getStats();
        }
        return stats;
    }

    private static void sleep(long millis) {
        try {
            Thread.sleep(millis);
        } catch (InterruptedException interrupted) {
            Thread.currentThread().interrupt();
        }
    }

    static void check(boolean condition, String label) {
        checks++;
        if (!condition) {
            throw new AssertionError("check failed: " + label);
        }
    }

    static final class Drain implements AutoCloseable {
        final AtomicInteger accepted = new AtomicInteger();
        private final ServerSocket server;
        private final AtomicBoolean running = new AtomicBoolean(true);
        private final Thread thread;

        private Drain(ServerSocket server) {
            this.server = server;
            this.thread = new Thread(() -> {
                while (running.get()) {
                    try {
                        Socket socket = server.accept();
                        accepted.incrementAndGet();
                        Thread reader = new Thread(() -> drain(socket));
                        reader.setDaemon(true);
                        reader.start();
                    } catch (Exception stopped) {
                        return;
                    }
                }
            }, "tun-smoke-upstream");
            this.thread.setDaemon(true);
            this.thread.start();
        }

        static Drain start() throws Exception {
            return new Drain(new ServerSocket(0, 8, InetAddress.getByName("127.0.0.1")));
        }

        int port() {
            return server.getLocalPort();
        }

        private static void drain(Socket socket) {
            try (Socket open = socket; InputStream input = socket.getInputStream()) {
                byte[] buffer = new byte[4096];
                while (input.read(buffer) >= 0) {
                }
            } catch (Exception ignored) {
            }
        }

        @Override
        public void close() throws Exception {
            running.set(false);
            server.close();
        }
    }
}
