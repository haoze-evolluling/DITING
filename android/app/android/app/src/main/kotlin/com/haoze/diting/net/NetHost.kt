package com.haoze.diting.net

/// Host text cleanup for every probe, backed by `rust/diting-probe-core` (`host.rs`).
///
/// Malformed input still passes through on purpose: the resolver is a better judge than a guessing
/// parser, which is why only the obvious decorations (scheme, path, userinfo, brackets, `:port`)
/// are removed.
internal object NetHost {

    fun sanitize(input: String): String = ProbeNative.sanitizeHost(input)
}
