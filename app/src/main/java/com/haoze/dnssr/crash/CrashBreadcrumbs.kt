package com.haoze.dnssr.crash

import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * 低开销内存环形缓冲区，用于记录崩溃前关键生命周期和运行事件（Breadcrumbs）。
 * 整个生命周期常驻内存，固定最大容量，无磁盘 I/O、无定时器与后台线程，对性能和电量零负荷。
 */
object CrashBreadcrumbs {
    private const val MAX_BREADCRUMBS = 150

    data class Breadcrumb(
        val timestamp: Long,
        val tag: String,
        val message: String,
        val level: String = "INFO"
    ) {
        fun format(dateFormat: SimpleDateFormat): String {
            return "${dateFormat.format(Date(timestamp))} [$level] [$tag] $message"
        }
    }

    private val lock = Any()
    private val buffer = Array<Breadcrumb?>(MAX_BREADCRUMBS) { null }
    private var head = 0
    private var size = 0

    fun record(tag: String, message: String, level: String = "INFO") {
        val entry = Breadcrumb(
            timestamp = System.currentTimeMillis(),
            tag = tag,
            message = message,
            level = level
        )
        synchronized(lock) {
            buffer[head] = entry
            head = (head + 1) % MAX_BREADCRUMBS
            if (size < MAX_BREADCRUMBS) {
                size++
            }
        }
    }

    fun getBreadcrumbs(): List<Breadcrumb> {
        val result = ArrayList<Breadcrumb>(size)
        synchronized(lock) {
            if (size == 0) return emptyList()
            val start = if (size < MAX_BREADCRUMBS) 0 else head
            for (i in 0 until size) {
                val index = (start + i) % MAX_BREADCRUMBS
                buffer[index]?.let { result.add(it) }
            }
        }
        return result
    }

    fun formatAll(): String {
        val list = getBreadcrumbs()
        if (list.isEmpty()) return "(None)"
        val dateFormat = SimpleDateFormat("yyyy-MM-dd HH:mm:ss.SSS", Locale.getDefault())
        val sb = StringBuilder()
        for (item in list) {
            sb.append(item.format(dateFormat)).append("\n")
        }
        return sb.toString().trimEnd()
    }
}
