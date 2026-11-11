import com.haoze.diting.log.LogNative;

import java.io.DataOutputStream;
import java.io.IOException;

/// The runtime-log capture group of the smoke test: the file listing, the export document, the
/// `logcat` plan, the per-file budget and the `dns_cache` projection.
///
/// Split out of `LogSmoke` to keep both files short; it shares the payload helpers there.
public final class RuntimeSmoke {
    /// The runtime-log capture group: the file listing, the export document, the `logcat` plan,
    /// the per-file budget and the `dns_cache` projection.
    public static void run(LogNative native_, long now) {
    byte[] listing = LogSmoke.pack(out -> {
        out.writeInt(4);
        writeStoreFile(out, "runtime-20260101-000000.log", 10, 100);
        writeStoreFile(out, ".capture", 99, 3);
        writeStoreFile(out, "runtime-20260103-000000.log", 30, 300);
        writeStoreFile(out, "notes.txt", 50, 7);
    });
    LogSmoke.Reader index = new LogSmoke.Reader(native_.storeIndex(listing));
    LogSmoke.check(index.count() == 2, "two log files kept");
    LogSmoke.check(index.count() == 2, "both survive the trim");
    LogSmoke.check(index.string().equals("runtime-20260103-000000.log"), "newest first");
    LogSmoke.check(index.i64() == 30, "last modified");
    LogSmoke.check(index.i64() == 300, "length");
    LogSmoke.check(index.string().equals("runtime-20260101-000000.log"), "oldest last");
    LogSmoke.check(index.i64() == 10, "last modified");
    LogSmoke.check(index.i64() == 100, "length");
    LogSmoke.check(!index.remaining(), "listing fully read");

    byte[] empty = LogSmoke.pack(out -> {
        out.writeInt(0);
        LogSmoke.writeString(out, "");
        LogSmoke.writeString(out, "2026-01-01 00:00:00");
    });
    LogSmoke.check(new LogSmoke.Reader(native_.storeDocument(empty)).u8() == 0, "nothing to export");

    byte[] document = LogSmoke.pack(out -> {
        out.writeInt(2);
        LogSmoke.writeString(out, "runtime-1.log");
        out.writeByte(1);
        LogSmoke.writeString(out, "body");
        LogSmoke.writeString(out, "runtime-2.log");
        out.writeByte(0);
        LogSmoke.writeString(out, "*** *** ***\npid: 1");
        LogSmoke.writeString(out, "2026-01-02 03:04:05");
    });
    LogSmoke.Reader exported = new LogSmoke.Reader(native_.storeDocument(document));
    LogSmoke.check(exported.u8() == 1, "document answered");
    String text = exported.string();
    LogSmoke.check(text.contains("(2 FILE(S))"), "file count in the header");
    LogSmoke.check(text.contains("---- runtime-1.log ----\nbody"), "first section");
    LogSmoke.check(text.contains("(无法读取该文件)"), "unreadable marker");
    LogSmoke.check(text.endsWith("---- 系统 crash 缓冲区 ----\n*** *** ***\npid: 1"), "crash section");

    byte[] plan = native_.capturePlan(4242);
    LogSmoke.Reader capturePlan = new LogSmoke.Reader(plan);
    LogSmoke.check(capturePlan.i64() == 1_000, "watchdog cadence");
    LogSmoke.check(capturePlan.count() == 2, "two logcat attempts");
    LogSmoke.check(capturePlan.count() == 5, "pid attempt has five parts");
    for (String expected : new String[] {"logcat", "-v", "time", "--pid", "4242"}) {
        LogSmoke.check(capturePlan.string().equals(expected), "pid attempt part: " + expected);
    }
    LogSmoke.check(capturePlan.count() == 3, "fallback has three parts");
    for (String expected : new String[] {"logcat", "-v", "time"}) {
        LogSmoke.check(capturePlan.string().equals(expected), "fallback part: " + expected);
    }

    long budget = native_.captureSessionNew();
    LogSmoke.check(budget != 0, "capture session");
    LogSmoke.Reader first = new LogSmoke.Reader(native_.captureLine(budget, LogSmoke.pack(out -> LogSmoke.writeString(out, "hello"))));
    LogSmoke.check(first.i64() == 6, "line cost");
    LogSmoke.check(first.u8() == 0, "not full yet");
    LogSmoke.Reader second = new LogSmoke.Reader(native_.captureLine(budget, LogSmoke.pack(out -> LogSmoke.writeString(out, ""))));
    LogSmoke.check(second.i64() == 7, "empty line costs its newline");
    native_.captureSessionFree(budget);
    LogSmoke.Reader mirrorLayout = new LogSmoke.Reader(native_.mirrorLayout());
    LogSmoke.check(mirrorLayout.i64() == 200, "mirror row cap");
    LogSmoke.check(mirrorLayout.i64() == 5_000, "mirror initial delay");
    LogSmoke.check(mirrorLayout.i64() == 10_000, "mirror interval");

    byte[] snapshot = LogSmoke.pack(out -> {
        out.writeInt(1);
        LogSmoke.writeString(out, "10|example.com|1");
        LogSmoke.writeString(out, "example.com");
        out.writeInt(1);
        out.writeInt(1);
        out.writeLong(1_000);
        out.writeLong(301_000);
        out.writeLong(2_000);
        out.writeLong(7);
        out.writeLong(300);
        out.writeInt(45);
    });
    LogSmoke.Reader mirrorRows = new LogSmoke.Reader(native_.mirrorRows(snapshot));
    LogSmoke.check(mirrorRows.count() == 1, "one mirrored row");
    // `u32 count | rows(u32 length | bytes)`: DnsCacheMirror binds one blob per row.
    LogSmoke.Reader mirrorRow = new LogSmoke.Reader(mirrorRows.blob());
    LogSmoke.check(mirrorRow.string().equals("10|example.com|1"), "cache key");
    LogSmoke.check(mirrorRow.string().equals("example.com"), "query name");
    LogSmoke.check(mirrorRow.i32() == 1, "query type");
    LogSmoke.check(mirrorRow.i32() == 1, "query class");
    LogSmoke.check(mirrorRow.i64() == 1_000, "created at");
    LogSmoke.check(mirrorRow.i64() == 301_000, "expires at");
    LogSmoke.check(mirrorRow.i64() == 2_000, "last hit at");
    LogSmoke.check(mirrorRow.i64() == 7, "hit count");
    LogSmoke.check(mirrorRow.i64() == 300, "original ttl");
    LogSmoke.check(mirrorRow.string().isEmpty(), "ttl offsets stay empty");
    LogSmoke.check(mirrorRow.blob().length == 0, "response bytes stay empty");
    LogSmoke.check(mirrorRow.i32() == 45, "response size");
    LogSmoke.check(!mirrorRows.remaining(), "the answer carried one row");
}

    private static void writeStoreFile(
            DataOutputStream out, String name, long lastModified, long length) throws IOException {
    LogSmoke.writeString(out, name);
    out.writeLong(lastModified);
    out.writeLong(length);
}
}
