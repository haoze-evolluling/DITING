package com.haoze.dnssr.util

/** 按 id 递增的 keyset 分页遍历：固定页大小逐页拉取，直到取完为止。 */
suspend fun <T> forEachKeysetPage(
    pageSize: Int,
    fetchPage: suspend (lastId: Long, limit: Int) -> List<T>,
    idOf: (T) -> Long,
    consume: (T) -> Unit
) {
    var lastId = 0L
    while (true) {
        val page = fetchPage(lastId, pageSize)
        if (page.isEmpty()) return
        page.forEach(consume)
        lastId = idOf(page.last())
    }
}
