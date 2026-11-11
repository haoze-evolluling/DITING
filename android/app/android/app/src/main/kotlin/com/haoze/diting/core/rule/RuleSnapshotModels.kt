package com.haoze.diting.core.rule

/// Outcome of loading/compiling one trie file.
///
/// The tags are the kernel's (`snapshot::plan::Outcome`), and so are the derived questions —
/// "usable", "compiled", "settled" — because the stamp rule and the inline-row decision are made
/// there; the Kotlin side only reports which of the four happened. The order must not change.
internal enum class IndexOutcome(val tag: Int) {
    NOT_INDEXED(0),
    LOADED(1),
    COMPILED(2),
    FAILED(3),
}
