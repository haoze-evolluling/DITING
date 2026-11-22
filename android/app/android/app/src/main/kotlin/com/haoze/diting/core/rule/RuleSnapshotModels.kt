package com.haoze.diting.core.rule

internal enum class IndexOutcome(val tag: Int) {
    NOT_INDEXED(0),
    LOADED(1),
    COMPILED(2),
    FAILED(3),
}
