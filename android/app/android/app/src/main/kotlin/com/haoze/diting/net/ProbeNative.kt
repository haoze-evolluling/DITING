package com.haoze.diting.net

import java.io.ByteArrayOutputStream
import java.io.DataOutputStream
import java.nio.ByteBuffer

/// Native diagnostics kernel, the JNI face of `rust/diting-probe-core`.
///
/// The payload layouts are documented in `rust/diting-probe-core/src/api.rs`; every request is one
/// packed `ByteArray` and every answer is one packed `ByteArray`, both big-endian. The library is
/// required: a build that forgot `python rust/build_android.py` fails the probe with an
/// [IllegalStateException] instead of running a second parser in Kotlin.
internal class ProbeNative private constructor() {
    external fun sanitizeHost(input: String): String?
    external fun isIpLiteral(input: String): Boolean
    external fun traceResponseLine(line: String): Boolean
    external fun dohEndpoint(url: String, host: String): String?
    external fun buildDnsQuery(packed: ByteArray): ByteArray?
    external fun dnsResponseSucceeded(response: ByteArray): Boolean
    external fun parseDnsServerReply(packed: ByteArray): ByteArray?
    external fun pingSummary(packed: ByteArray): ByteArray?
    external fun latencyStats(packed: ByteArray): ByteArray?
    external fun traceHop(packed: ByteArray): ByteArray?

    companion object {
        private val instance: ProbeNative by lazy {
            try {
                System.loadLibrary("diting_kernels")
                ProbeNative()
            } catch (error: Throwable) {
                throw IllegalStateException(
                    "native diagnostics kernel unavailable; build it with " +
                        "`python rust/build_android.py`",
                    error,
                )
            }
        }

        /// `NetHost.sanitize`; never null.
        fun sanitizeHost(input: String): String =
            requireNotNull(instance.sanitizeHost(input)) { "native sanitize returned no value" }

        /// `DnsLookupProbe.isIpLiteral`.
        fun isIpLiteral(input: String): Boolean = instance.isIpLiteral(input)

        /// `TraceProbe`'s streaming stamp: `time=` anywhere or a `From ` prefix.
        fun isResponseLine(line: String): Boolean = instance.traceResponseLine(line)

        /// `DnsLatencyTester`'s DoH endpoint.
        fun dohEndpoint(url: String, host: String): String =
            requireNotNull(instance.dohEndpoint(url, host)) { "native DoH endpoint returned no value" }

        /// One A/AAAA query wire image; null when a label was empty or longer than 63 bytes.
        fun buildDnsQueryOrNull(id: Int, ipv4: Boolean, domain: String): ByteArray? =
            instance.buildDnsQuery(ProbePayload.query(id, ipv4, domain))

        /// `DnsLatencyTester.isSuccess`.
        fun dnsResponseSucceeded(response: ByteArray): Boolean =
            instance.dnsResponseSucceeded(response)

        /// The custom resolver's answer walk.
        fun parseDnsServerReply(response: ByteArray, ipv4: Boolean): ProbeDnsReply =
            decodeDnsReply(
                requireNotNull(instance.parseDnsServerReply(ProbePayload.reply(response, ipv4))) {
                    "native DNS reply decoder rejected the payload"
                },
            )

        /// `PingProbe.parseSummary`; null means the output carried no `N% packet loss` line.
        ///
        /// A null *payload* is different: the kernel rejected the request, which is a hard error.
        fun pingSummary(output: String): ProbePingSummary? {
            val payload = requireNotNull(instance.pingSummary(ProbePayload.text(output))) {
                "native ping summary rejected the payload"
            }
            val reader = ProbePayload.Reader(payload)
            return when (reader.u8()) {
                0 -> {
                    val transmitted = reader.i32()
                    val received = reader.i32()
                    val lossPercent = reader.f64()
                    val stats = reader.optionals()
                    val replies = List(reader.count()) {
                        val sequence = reader.i32()
                        val flags = reader.u8()
                        val elapsed = reader.f64()
                        val ttl = reader.i32()
                        val timeout = reader.u8() != 0
                        ProbeReplyRow(
                            sequence = sequence,
                            elapsedMs = if (flags and 1 != 0) elapsed else null,
                            ttl = if (flags and 2 != 0) ttl else null,
                            timeout = timeout,
                        )
                    }
                    ProbePingSummary(
                        transmitted = transmitted,
                        received = received,
                        lossPercent = lossPercent,
                        minMs = stats.minMs,
                        avgMs = stats.avgMs,
                        maxMs = stats.maxMs,
                        jitterMs = stats.jitterMs,
                        replies = replies,
                    )
                }
                1 -> null
                else -> throw IllegalStateException("native ping summary returned an unknown status")
            }
        }

        /// Min/avg/max/jitter of the probe samples plus the rounded millisecond value.
        fun latencyStats(samples: List<Double>): ProbeLatencyStats {
            val reader = ProbePayload.Reader(
                requireNotNull(instance.latencyStats(ProbePayload.samples(samples))) {
                    "native latency statistics rejected the payload"
                },
            )
            val stats = reader.optionals()
            return ProbeLatencyStats(
                minMs = stats.minMs,
                avgMs = stats.avgMs,
                maxMs = stats.maxMs,
                jitterMs = stats.jitterMs,
                roundedAverageMs = reader.i64(),
            )
        }

        /// One hop of a `ping -t <ttl>` run.
        fun traceHop(resolved: String, text: String): ProbeHop =
            decodeHop(
                requireNotNull(instance.traceHop(ProbePayload.hop(resolved, text))) {
                    "native trace hop decoder rejected the payload"
                },
            )
    }
}

/// One row of `PingSummary.replies`.
internal data class ProbeReplyRow(
    val sequence: Int,
    val elapsedMs: Double?,
    val ttl: Int?,
    val timeout: Boolean,
)

/// The parsed half of a `PingSummary`.
internal data class ProbePingSummary(
    val transmitted: Int,
    val received: Int,
    val lossPercent: Double,
    val minMs: Double?,
    val avgMs: Double?,
    val maxMs: Double?,
    val jitterMs: Double?,
    val replies: List<ProbeReplyRow>,
)

/// Sample statistics shared by the latency tester and the TCP fallback.
internal data class ProbeLatencyStats(
    val minMs: Double?,
    val avgMs: Double?,
    val maxMs: Double?,
    val jitterMs: Double?,
    val roundedAverageMs: Long,
)

/// One A/AAAA answer of a custom resolver.
internal data class ProbeDnsAnswer(val ipv4: Boolean, val ttl: Long, val value: String)

/// Outcome of reading one custom resolver's reply; the failure kinds print different messages.
internal sealed interface ProbeDnsReply {
    data class Ok(val answers: List<ProbeDnsAnswer>) : ProbeDnsReply
    data object Invalid : ProbeDnsReply
    data object Truncated : ProbeDnsReply
    data class Rcode(val code: Int) : ProbeDnsReply
    data object Incomplete : ProbeDnsReply
}

/// What one hop's output means, mirroring `trace::Hop`.
internal sealed interface ProbeHop {
    data class Reached(val address: String?, val elapsedMs: Double?) : ProbeHop
    data class Answered(val address: String, val unreachable: Boolean) : ProbeHop
    data object NetUnreachable : ProbeHop
    data object NoMatch : ProbeHop
    data object Unsupported : ProbeHop
}

private fun decodeDnsReply(payload: ByteArray): ProbeDnsReply {
    val reader = ProbePayload.Reader(payload)
    return when (reader.u8()) {
        0 -> ProbeDnsReply.Ok(
            List(reader.count()) {
                ProbeDnsAnswer(
                    ipv4 = reader.u8() == 1,
                    ttl = reader.u32(),
                    value = reader.string(),
                )
            },
        )
        1 -> ProbeDnsReply.Invalid
        2 -> ProbeDnsReply.Truncated
        3 -> ProbeDnsReply.Rcode(reader.u8())
        4 -> ProbeDnsReply.Incomplete
        else -> throw IllegalStateException("native DNS reply decoder returned an unknown status")
    }
}

private fun decodeHop(payload: ByteArray): ProbeHop {
    val reader = ProbePayload.Reader(payload)
    return when (reader.u8()) {
        0 -> {
            val flags = reader.u8()
            val address = if (flags and 1 != 0) reader.string() else null
            val elapsed = reader.f64()
            ProbeHop.Reached(address, if (flags and 2 != 0) elapsed else null)
        }
        1 -> {
            val flags = reader.u8()
            ProbeHop.Answered(reader.string(), flags and 4 != 0)
        }
        2 -> ProbeHop.NetUnreachable
        3 -> ProbeHop.NoMatch
        4 -> ProbeHop.Unsupported
        else -> throw IllegalStateException("native trace hop decoder returned an unknown status")
    }
}

/// Payload builders and the big-endian reader the decoders share.
private object ProbePayload {
    fun query(id: Int, ipv4: Boolean, domain: String): ByteArray = pack { out ->
        out.writeShort(id)
        out.writeByte(if (ipv4) 0 else 1)
        writeString(out, domain)
    }

    fun reply(response: ByteArray, ipv4: Boolean): ByteArray = pack { out ->
        out.writeByte(if (ipv4) 1 else 0)
        out.writeInt(response.size)
        out.write(response)
    }

    fun text(text: String): ByteArray = pack { out -> writeString(out, text) }

    fun hop(resolved: String, text: String): ByteArray = pack { out ->
        writeString(out, resolved)
        writeString(out, text)
    }

    fun samples(samples: List<Double>): ByteArray = pack { out ->
        out.writeInt(samples.size)
        samples.forEach(out::writeDouble)
    }

    private fun writeString(out: DataOutputStream, value: String) {
        val bytes = value.toByteArray(Charsets.UTF_8)
        out.writeInt(bytes.size)
        out.write(bytes)
    }

    private fun pack(write: (DataOutputStream) -> Unit): ByteArray {
        val buffer = ByteArrayOutputStream(64)
        val out = DataOutputStream(buffer)
        write(out)
        out.flush()
        return buffer.toByteArray()
    }

    class Reader(payload: ByteArray) {
        private val buffer: ByteBuffer = ByteBuffer.wrap(payload)

        fun u8(): Int = buffer.get().toInt() and 0xFF

        fun i32(): Int = buffer.int

        fun u32(): Long = buffer.int.toLong() and 0xFFFFFFFFL

        fun i64(): Long = buffer.long

        fun f64(): Double = buffer.double

        fun count(): Int = u32().toInt()

        fun string(): String {
            val length = count()
            val bytes = ByteArray(length)
            buffer.get(bytes)
            return String(bytes, Charsets.UTF_8)
        }

        /// `u8` presence bits followed by four `Double`s; a clear bit means the value is padding.
        fun optionals(): ProbeOptionals {
            val flags = u8()
            val values = List(4) { f64() }
            return ProbeOptionals(
                minMs = if (flags and 1 != 0) values[0] else null,
                avgMs = if (flags and 2 != 0) values[1] else null,
                maxMs = if (flags and 4 != 0) values[2] else null,
                jitterMs = if (flags and 8 != 0) values[3] else null,
            )
        }
    }
}

/// The four optional latencies one presence byte describes.
internal data class ProbeOptionals(
    val minMs: Double?,
    val avgMs: Double?,
    val maxMs: Double?,
    val jitterMs: Double?,
)
