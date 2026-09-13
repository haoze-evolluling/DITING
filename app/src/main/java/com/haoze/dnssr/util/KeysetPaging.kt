package com.haoze.dnssr.util

/** Keyset pagination over incrementing ids: fetches fixed-size pages until the source is exhausted. */
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
