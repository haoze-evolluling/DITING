import com.haoze.diting.log.LogNative;

import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.io.DataInputStream;
import java.io.DataOutputStream;
import java.io.IOException;
import java.nio.charset.StandardCharsets;

/// Host-JVM smoke test for the log kernel's JNI boundary.
///
/// It proves the 50 exported symbols match the signatures Kotlin declares (name and argument
/// order) and that every payload round trips. The semantics belong to the Rust tests; this only
/// checks the boundary, so it needs nothing but a JVM and `diting_log_core.dll`/`.so`.
public final class LogSmoke {
    static int checks;

    public static void main(String[] args) {
        System.load(args.length > 0 ? args[0] : "diting_log_core");
        LogNative native_ = new LogNative();
        long now = 1_700_000_000_000L;

        stats(native_, now);
        rows(native_, now);
        retention(native_, now);
        crash(native_);
        traffic(native_, now);
        health(native_, now);
        attr(native_, now);
        queue(native_, now);
        RuntimeSmoke.run(native_, now);

        System.out.println("log smoke ok: " + checks + " checks");
    }

    private static void stats(LogNative native_, long now) {
        long handle = native_.statsNew();
        check(handle != 0, "stats handle");
        byte[] batch = dnsBatch("Example.com", 1, false, "", "", false, "com.app", "1.2.3.4", 5);
        byte[] answer = native_.dnsBatch(handle, 0, batch, now);
        check(answer != null, "dns batch answered");
        Reader rows = new Reader(answer);
        check(rows.count() == 1, "one dns row");
        // `u32 count | rows(u32 length | bytes)`: Kotlin hands each blob to the SQL writer.
        Reader row = new Reader(rows.blob());
        check(row.i64() == now, "timestamp falls back to now");
        check(row.string().equals("example.com"), "query name folded");
        check(row.i32() == 1, "query type");
        check(row.string().equals("PASSED"), "result");
        check(row.optional().equals("app=com.app, resolved=1.2.3.4, elapsed=5ms"), "message");
        check(row.u8() == 0, "not cached");
        check(row.optional() == null, "no subscription id");
        check(row.optional().equals("com.app"), "package name");
        check(!rows.remaining(), "the batch carried one row");

        Reader snapshot = new Reader(native_.statsSnapshot(handle));
        check(snapshot.i64() == 1, "total counted");
        check(snapshot.i64() == 1, "passed counted");
        check(snapshot.i64() == 0, "nothing filtered");
        check(snapshot.i64() == 0, "nothing cached");
        check(snapshot.i64() == 0, "nothing rewritten");
        check(snapshot.i64() == 0, "nothing failed");

        // An off-mode batch still counts but answers no rows.
        byte[] off = native_.dnsBatch(handle, 2, batch, now);
        check(off != null && off.length == 0, "mode off answers nothing");
        Reader afterOff = new Reader(native_.statsSnapshot(handle));
        check(afterOff.i64() == 2, "mode off still counts");

        native_.rateTick(handle, 100, 200, now);
        native_.rateTick(handle, 1_100, 2_100, now + 1_000);
        // The rate is this tick's delta over the real interval, not a difference of the two ticks.
        Reader rate = new Reader(native_.rateSnapshot(handle, now + 1_000));
        check(rate.i64() == 1_100, "tx rate");
        check(rate.i64() == 2_100, "rx rate");
        native_.statsRateReset(handle);
        Reader reset = new Reader(native_.rateSnapshot(handle, now + 1_000));
        check(reset.i64() == 0 && reset.i64() == 0, "rate reset");

        native_.statsRequestReset(handle);
        check(new Reader(native_.statsSnapshot(handle)).i64() == 0, "request reset");
        native_.statsFree(handle);
    }

    private static void rows(LogNative native_, long now) {
        long stats = native_.statsNew();
        byte[] allowed = pack(out -> {
            writeString(out, "");
            writeString(out, "");
            writeString(out, "");
            writeString(out, "allowed");
            writeString(out, "");
        });
        byte[] hidden = native_.httpEvent(stats, 1, allowed, now);
        check(hidden != null && hidden.length == 0, "pass-through hidden");
        byte[] http = native_.httpEvent(stats, 0, allowed, now);
        check(http != null && http.length > 0, "http row answered");
        Reader httpReader = new Reader(http);
        check(httpReader.i64() == now, "http timestamp");
        check(httpReader.string().equals("unknown"), "blank package becomes unknown");
        check(httpReader.optional() == null, "blank authority is null");
        check(httpReader.string().equals(""), "protocol passes through");
        check(httpReader.string().equals("allowed"), "outcome");
        check(httpReader.optional() == null, "blank rule is null");
        check(!httpReader.remaining(), "http row fully read");

        byte[] race = pack(out -> {
            writeString(out, " Example.COM ");
            out.writeInt(28);
            writeString(out, "smart_prediction");
            out.writeInt(3);
            out.writeByte(1);
            out.writeLong(40);
            writeString(out, "p1");
            out.writeLong(0);
            writeString(out, "");
            out.writeLong(12);
            out.writeByte(0);
            out.writeByte(0);
            writeString(out, "");
        });
        Reader raceRow = new Reader(native_.raceRow(race, now));
        check(raceRow.i64() == now, "race timestamp");
        check(raceRow.string().equals(" example.com "), "race query name");
        check(raceRow.i32() == 28, "race query type");
        check(raceRow.string().equals("smart_prediction"), "race strategy");
        check(raceRow.i32() == 3, "race provider count");
        check(raceRow.u8() == 1, "race success");
        check(raceRow.i64() == 40, "race elapsed");
        check(raceRow.optional().equals("p1"), "selected provider");
        check(raceRow.optional() == null, "zero selected elapsed is null");
        check(raceRow.optional() == null, "blank winner id is null");
        check(raceRow.optionalLong() == 12, "winner elapsed");
        check(raceRow.u8() == 0 && raceRow.u8() == 0, "fallback flags");
        check(raceRow.optional() == null, "blank message is null");

        byte[] blankRace = pack(out -> {
            writeString(out, "  ");
            out.writeInt(1);
            writeString(out, "");
            out.writeInt(0);
            out.writeByte(0);
            out.writeLong(0);
            writeString(out, "");
            out.writeLong(0);
            writeString(out, "");
            out.writeLong(0);
            out.writeByte(0);
            out.writeByte(0);
            writeString(out, "");
        });
        check(native_.raceRow(blankRace, now).length == 0, "blank race answers nothing");

        byte[] bootstrap = pack(out -> {
            writeString(out, "");
            writeString(out, "Cloudflare");
            writeString(out, "1.1.1.1");
            writeString(out, "DNS.Google");
            out.writeByte(1);
            out.writeLong(7);
            out.writeByte(0);
            writeString(out, "");
        });
        Reader bootstrapRow = new Reader(native_.bootstrapRow(bootstrap, now));
        check(bootstrapRow.i64() == now, "bootstrap timestamp");
        check(bootstrapRow.string().equals("unknown"), "blank ip id becomes unknown");
        check(bootstrapRow.string().equals("Cloudflare"), "ip name kept");
        check(bootstrapRow.string().equals("1.1.1.1"), "ip kept");
        check(bootstrapRow.string().equals("dns.google"), "host folded");
        check(bootstrapRow.u8() == 1, "bootstrap success");
        check(bootstrapRow.i64() == 7, "bootstrap elapsed");
        check(bootstrapRow.u8() == 0, "fallback flag");
        check(bootstrapRow.optional() == null, "bootstrap message");
        native_.statsFree(stats);
    }

    private static void retention(LogNative native_, long now) {
        byte[] request = pack(out -> {
            out.writeByte(0);
            out.writeInt(0);
            out.writeByte(1);
            out.writeInt(60);
            out.writeLong(now);
        });
        Reader plan = new Reader(native_.retentionPlan(request));
        check(plan.i32() == 7, "default log window");
        check(plan.i64() == now - 7L * 86_400_000L, "log cutoff");
        check(plan.i32() == 60, "traffic window");
        check(plan.i64() == now - 60L * 86_400_000L, "traffic cutoff");
        check(plan.count() == 4, "four pruned tables");
        check(plan.string().equals("dns_log"), "first table");
        check(plan.string().equals("http_request_log"), "second table");
        check(plan.string().equals("dns_race_log"), "third table");
        check(plan.string().equals("bootstrap_log"), "fourth table");
        check(plan.string().equals("app_traffic_daily"), "traffic table");
        check(plan.i64() == 5_000, "batch rows");
    }

    private static void crash(LogNative native_) {
        byte[] request = pack(out -> {
            writeString(out, "com.haoze.diting");
            out.writeInt(3);
            writeString(out, "keep com.haoze.diting");
            writeString(out, "--------- beginning of crash");
            writeString(out, "drop com.other.app");
        });
        Reader selected = new Reader(native_.crashSelect(request));
        check(selected.count() == 1, "one crash block");
        check(selected.string().equals("keep com.haoze.diting"), "kept line");
    }

    private static void traffic(LogNative native_, long now) {
        long handle = native_.trafficNew();
        byte[] tick = pack(out -> {
            writeString(out, "2026-01-01");
            out.writeInt(2);
            out.writeInt(10001);
            out.writeLong(100);
            out.writeLong(200);
            writeString(out, "com.a");
            out.writeInt(10002);
            out.writeLong(0);
            out.writeLong(0);
            writeString(out, "com.b");
        });
        Reader outcome = new Reader(native_.trafficOnTick(handle, tick));
        int flags = outcome.u8();
        check(flags == 0, "no flush, nothing dropped");
        check(outcome.i64() == 100, "tick tx");
        check(outcome.i64() == 200, "tick rx");
        check(outcome.string().isEmpty(), "no dropped date");
        check(outcome.count() == 0, "no dropped packages");

        byte[] taken = native_.trafficTake(handle);
        Reader batches = new Reader(taken);
        check(batches.count() == 1, "one date bucket");
        check(batches.string().equals("2026-01-01"), "bucket date");
        check(batches.count() == 1, "one package bucket");
        check(batches.string().equals("com.a"), "bucket package");
        check(batches.i64() == 100 && batches.i64() == 200, "bucket delta");
        check(native_.trafficRequeue(handle, taken), "requeue accepted");
        check(native_.trafficClear(handle) == 1, "clear reports the lost row");

        check(!native_.trafficInBackoff(handle, now), "not backing off yet");
        check(native_.trafficBackoff(handle, now) == 2_000, "first backoff");
        check(native_.trafficInBackoff(handle, now), "inside the window");
        native_.trafficResetBackoff(handle);
        check(!native_.trafficInBackoff(handle, now), "backoff reset");
        native_.trafficFree(handle);
    }

    private static void health(LogNative native_, long now) {
        long handle = native_.healthNew();
        byte[] dropped = pack(out -> {
            out.writeInt(3);
            out.writeByte(1);
            writeString(out, "dns_log");
        });
        Reader line = new Reader(native_.healthDropped(handle, dropped, now));
        check(line.u8() == 1, "first warning reported");
        check(line.string().equals("dropped 3 row(s) from dns_log (tableMissing)"), "warning text");

        Reader again = new Reader(native_.healthDropped(handle, dropped, now + 1_000));
        check(again.u8() == 0, "second warning suppressed");
        Reader openFailure = new Reader(
                native_.healthOpenFailure(handle, "diting_database", "IOException: gone", now + 2_000));
        check(openFailure.u8() == 0, "open failure suppressed");
        Reader warn = new Reader(native_.healthWarn(handle, "stuck", "", now + 3_000));
        check(warn.u8() == 0, "warn suppressed");

        Reader snapshot = new Reader(native_.healthSnapshot(handle));
        check(snapshot.i64() == 6, "dropped rows counted");
        check(snapshot.string().equals("overflow") && snapshot.i64() == 0, "overflow count");
        check(snapshot.string().equals("tableMissing") && snapshot.i64() == 6, "missing count");
        check(snapshot.string().equals("noDatabase") && snapshot.i64() == 0, "no-database count");
        check(snapshot.string().equals("closed") && snapshot.i64() == 0, "closed count");
        check(snapshot.string().equals("dns_log:tableMissing"), "last drop");
        check(snapshot.i64() == 1, "open failures");
        check(snapshot.i64() == 3, "suppressed");
        check(snapshot.string().equals("IOException: gone"), "last cause");
        native_.healthFree(handle);
    }

    private static void attr(LogNative native_, long now) {
        long handle = native_.attrNew();
        byte[] key = pack(out -> {
            out.writeLong(6);
            writeString(out, "10.0.0.2");
            out.writeLong(51_000);
            writeString(out, "1.2.3.4");
            out.writeLong(443);
        });
        Reader miss = new Reader(native_.attrUidLookup(handle, key, now));
        check(miss.u8() == 0, "unknown flow misses");
        check(native_.attrUidStore(handle, key, 10_001, now), "uid stored");
        Reader hit = new Reader(native_.attrUidLookup(handle, key, now + 1_000));
        check(hit.u8() == 1 && hit.i32() == 10_001, "uid hit");
        Reader expired = new Reader(native_.attrUidLookup(handle, key, now + 11_000));
        check(expired.u8() == 0, "uid expired after ten seconds");

        Reader notKnown = new Reader(native_.attrPackageLookup(handle, -1));
        check(notKnown.u8() == 2, "invalid uid is not asked about");
        Reader packageMiss = new Reader(native_.attrPackageLookup(handle, 10_001));
        check(packageMiss.u8() == 0, "package miss");
        native_.attrPackageStore(handle, 10_001, "com.example");
        Reader packageHit = new Reader(native_.attrPackageLookup(handle, 10_001));
        check(packageHit.u8() == 1 && packageHit.string().equals("com.example"), "package hit");
        native_.attrClear(handle);
        Reader cleared = new Reader(native_.attrPackageLookup(handle, 10_001));
        check(cleared.u8() == 0, "caches cleared");
        native_.attrFree(handle);
    }

    private static void queue(LogNative native_, long now) {
        long handle = native_.queueNew(0);
        check(handle != 0, "log-table queue");
        byte[] row = pack(out -> writeString(out, "row"));
        Reader first = new Reader(native_.queueSubmit(handle, row, now));
        check(first.u8() == 1, "row accepted");
        check(first.count() == 0, "no overflow");
        check(first.u8() == 0, "batch not full");
        check(first.i64() == 1_000, "flush in one second");

        for (int index = 1; index < 199; index++) {
            native_.queueSubmit(handle, row, now);
        }
        Reader full = new Reader(native_.queueSubmit(handle, row, now));
        check(full.u8() == 1 && full.count() == 0, "accepted");
        check(full.u8() == 1, "batch full");
        check(full.i64() == 0, "flush now");
        check(native_.queuePendingLen(handle) == 200, "200 rows queued");

        byte[] taken = native_.queueTake(handle);
        Reader batch = new Reader(taken);
        check(batch.u8() == 1, "take answered a batch");
        check(batch.count() == 200, "whole batch taken");
        check(native_.queuePendingLen(handle) == 0, "queue drained");
        check(native_.queueTake(handle)[0] == 0, "empty take");

        check(native_.queueRequeue(handle, asRequeue(taken)) == 0, "requeue without overflow");
        check(native_.queuePendingLen(handle) == 200, "rows back in the queue");

        check(!native_.queueMissingLatched(handle, now), "no latch yet");
        native_.queueLatchMissing(handle, now);
        check(native_.queueMissingLatched(handle, now + 29_000), "latched for thirty seconds");
        check(!native_.queueMissingLatched(handle, now + 30_000), "latch expired");

        check(native_.queueBackoff(handle, now) == 1_000, "first queue backoff");
        check(native_.queueInBackoff(handle, now), "inside the queue window");
        check(native_.queueRetryWait(handle, now) == 1_000, "retry wait");
        native_.queueResetBackoff(handle);
        check(native_.queueRetryWait(handle, now) == 0, "retry wait cleared");

        native_.queueMarkClosed(handle);
        check(native_.queueIsClosed(handle), "marked closed");
        Reader rejected = new Reader(native_.queueSubmit(handle, row, now));
        check(rejected.u8() == 0, "closed queue refuses rows");
        check(native_.queueClose(handle) == 200, "closed reports the tail");
        native_.queueFree(handle);

        long http = native_.queueNew(1);
        check(http != 0, "http queue");
        for (int index = 0; index < 9; index++) {
            native_.queueSubmit(http, row, now);
        }
        Reader httpFull = new Reader(native_.queueSubmit(http, row, now));
        check(httpFull.u8() == 1, "http row accepted");
        check(httpFull.count() == 0, "no http overflow");
        check(httpFull.u8() == 1, "http batch of ten");
        check(httpFull.i64() == 0, "http flush now");
        native_.queueLatchMissing(http, now);
        check(!native_.queueMissingLatched(http, now), "http never latches");
        native_.queueFree(http);

        check(native_.queueNew(2) == 0, "unknown settings tag is rejected");
    }

    // --- payload helpers --------------------------------------------------------------------

    interface Writer {
        void write(DataOutputStream out) throws IOException;
    }

    static byte[] pack(Writer writer) {
        ByteArrayOutputStream buffer = new ByteArrayOutputStream(256);
        try (DataOutputStream out = new DataOutputStream(buffer)) {
            writer.write(out);
        } catch (IOException error) {
            throw new IllegalStateException(error);
        }
        return buffer.toByteArray();
    }

    static void writeString(DataOutputStream out, String value) throws IOException {
        byte[] bytes = value.getBytes(StandardCharsets.UTF_8);
        out.writeInt(bytes.length);
        out.write(bytes);
    }

    static byte[] dnsBatch(
            String domain,
            int queryType,
            boolean blocked,
            String blockedBy,
            String error,
            boolean cached,
            String app,
            String resolved,
            long elapsedMs) {
        return pack(out -> {
            out.writeInt(1);
            out.writeLong(0);
            writeString(out, domain);
            out.writeInt(queryType);
            out.writeByte(blocked ? 1 : 0);
            writeString(out, blockedBy);
            writeString(out, error);
            out.writeByte(cached ? 1 : 0);
            writeString(out, app);
            writeString(out, resolved);
            out.writeLong(elapsedMs);
        });
    }

    static final class Reader {
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

        int i32() {
            try {
                return in.readInt();
            } catch (IOException error) {
                throw new IllegalStateException(error);
            }
        }

        int count() {
            return i32();
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

        byte[] blob() {
            try {
                byte[] bytes = new byte[in.readInt()];
                in.readFully(bytes);
                return bytes;
            } catch (IOException error) {
                throw new IllegalStateException(error);
            }
        }

        String optional() {
            int present = u8();
            return present == 0 ? null : string();
        }

        Long optionalLong() {
            int present = u8();
            return present == 0 ? null : i64();
        }

        boolean remaining() {
            try {
                return in.available() > 0;
            } catch (IOException error) {
                throw new IllegalStateException(error);
            }
        }
    }

    /// `queueTake` answers `u8 hasBatch | u32 count | blobs`; `queueRequeue` takes the rows alone.
    static byte[] asRequeue(byte[] take) {
        Reader reader = new Reader(take);
        check(reader.u8() == 1, "take answered a batch");
        int count = reader.count();
        return pack(out -> {
            out.writeInt(count);
            for (int index = 0; index < count; index++) {
                byte[] row = reader.blob();
                out.writeInt(row.length);
                out.write(row);
            }
        });
    }

    static void check(boolean condition, String what) {
        checks++;
        if (!condition) {
            throw new AssertionError("log smoke failed: " + what);
        }
    }
}
