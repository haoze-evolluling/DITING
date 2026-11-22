package com.haoze.diting.engine

internal object NativeLoader {
    private var loaded = false
    private var failure: Throwable? = null

    @Synchronized
    fun ensureLoaded() {
        if (loaded) return
        failure?.let { throw IllegalStateException("libditing_native 加载失败", it) }
        try {
            System.loadLibrary(LIBRARY)
            loaded = true
        } catch (error: Throwable) {
            failure = error
            throw IllegalStateException(
                "libditing_native 加载失败：${error.message ?: error.javaClass.simpleName}",
                error,
            )
        }
    }

    private const val LIBRARY = "diting_native"
}
