package com.haoze.dnssr.data.repository

import androidx.paging.PagingSource
import androidx.paging.PagingState
import androidx.sqlite.db.SimpleSQLiteQuery
import com.haoze.dnssr.data.DnsCacheQueryParams
import com.haoze.dnssr.data.dao.DnsCacheDao
import com.haoze.dnssr.data.entity.DnsCacheEntity

class DnsCacheRepository(private val dao: DnsCacheDao) {

    companion object {
        const val PAGE_SIZE = 50
    }

    fun cachePagingSource(params: DnsCacheQueryParams): PagingSource<Int, DnsCacheEntity> {
        return DnsCachePagingSource(params)
    }

    suspend fun deleteExpired(now: Long): Int {
        return dao.deleteExpired(now)
    }

    suspend fun recentEntries(now: Long, limit: Int): List<DnsCacheEntity> {
        return dao.getUnexpired(now, limit.coerceAtLeast(0))
    }

    private fun appendSearch(sql: StringBuilder, args: MutableList<Any>, params: DnsCacheQueryParams) {
        val trimmed = params.query.trim()
        if (trimmed.isNotEmpty()) {
            sql.append(" AND queryName LIKE ?")
            args.add("%${trimmed.lowercase()}%")
        }
    }

    private inner class DnsCachePagingSource(
        private val queryParams: DnsCacheQueryParams
    ) : PagingSource<Int, DnsCacheEntity>() {
        override suspend fun load(params: LoadParams<Int>): LoadResult<Int, DnsCacheEntity> {
            val offset = params.key ?: 0
            val limit = params.loadSize
            val args = mutableListOf<Any>(queryParams.asOfMillis)
            val sql = StringBuilder("SELECT * FROM dns_cache WHERE expiresAt > ?")
            appendSearch(sql, args, queryParams)
            sql.append(" ORDER BY COALESCE(lastHitAt, createdAt) DESC, createdAt DESC LIMIT $limit OFFSET $offset")
            val items = dao.queryList(SimpleSQLiteQuery(sql.toString(), args.toTypedArray()))
            return LoadResult.Page(
                data = items,
                prevKey = if (offset == 0) null else offset,
                nextKey = if (items.size < limit) null else offset + items.size
            )
        }

        override fun getRefreshKey(state: PagingState<Int, DnsCacheEntity>): Int? {
            return state.anchorPosition?.let { anchorPosition ->
                state.closestPageToPosition(anchorPosition)?.prevKey
            }
        }
    }
}
