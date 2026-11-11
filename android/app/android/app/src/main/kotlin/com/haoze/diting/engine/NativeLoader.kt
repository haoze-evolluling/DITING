package com.haoze.diting.engine

/// Loads `libditing_engine.so` exactly once, and remembers a failure.
///
/// The Rust engine is one shared library (`libditing_engine.so`). Loading it is explicit rather
/// than a static initialiser so the failure surfaces where the caller can show it:
/// the DNS server service reports `DNS 服务启动失败：…` instead of the process dying with an
/// `UnsatisfiedLinkError` inside a class initialiser.
///
/// A failure is remembered on purpose: a missing `.so` (a stale `jniLibs` directory, an ABI the
/// build did not include) cannot be fixed by retrying, and the second attempt would only hide the
/// first stack trace.
internal object NativeLoader {
    private var loaded = false
    private var failure: Throwable? = null

    @Synchronized
    fun ensureLoaded() {
        if (loaded) return
        failure?.let { throw IllegalStateException("libditing_engine 加载失败", it) }
        try {
            System.loadLibrary(LIBRARY)
            loaded = true
        } catch (error: Throwable) {
            failure = error
            throw IllegalStateException(
                "libditing_engine 加载失败：${error.message ?: error.javaClass.simpleName}",
                error,
            )
        }
    }

    /// `System.loadLibrary` resolves `libditing_engine.so` from the APK's `lib/<abi>/`.
    private const val LIBRARY = "diting_engine"
}
