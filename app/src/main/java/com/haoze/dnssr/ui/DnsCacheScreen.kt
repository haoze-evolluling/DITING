package com.haoze.dnssr.ui

import com.haoze.dnssr.ui.dashboard.formatDuration
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.repeatOnLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.paging.LoadState
import androidx.paging.compose.collectAsLazyPagingItems
import androidx.paging.compose.itemContentType
import com.haoze.dnssr.data.entity.DnsCacheEntity
import com.haoze.dnssr.ui.components.SettingsCornerShape
import com.haoze.dnssr.ui.components.SettingsItemSpacing
import com.haoze.dnssr.ui.components.SettingsScaffold
import com.haoze.dnssr.ui.components.SettingsSurfaceItem
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import kotlin.math.max
import kotlinx.coroutines.delay

private val cacheTimeFormatter = SimpleDateFormat("MM-dd HH:mm:ss", Locale.getDefault())
@Composable
fun DnsCacheScreen(
    onBack: () -> Unit
) {
    val viewModel: DnsCacheViewModel = viewModel()
    val params by viewModel.params.collectAsStateWithLifecycle()
    val nowMillis by viewModel.nowMillis.collectAsStateWithLifecycle()
    val entries = viewModel.entries.collectAsLazyPagingItems()
    var isSearchActive by remember { mutableStateOf(false) }
    val lifecycleOwner = LocalLifecycleOwner.current

    NavigationSettledEffect {
        viewModel.activate()
        viewModel.refreshCacheList()
    }

    LaunchedEffect(lifecycleOwner) {
        lifecycleOwner.lifecycle.repeatOnLifecycle(Lifecycle.State.STARTED) {
            while (true) {
                delay(1_000L)
                viewModel.updateClock()
            }
        }
    }

    SettingsScaffold(
        titleContent = {
            // Keep the title slot at a stable width so toggling search does not animate its expansion.
            Box(modifier = Modifier.fillMaxWidth()) {
                if (isSearchActive) {
                    OutlinedTextField(
                        value = params.query,
                        onValueChange = viewModel::onSearchQueryChange,
                        placeholder = { Text(localizedText("搜索缓存域名...")) },
                        singleLine = true,
                        shape = RoundedCornerShape(28.dp),
                        modifier = Modifier.fillMaxWidth()
                    )
                } else {
                    Text(localizedText("DNS 缓存"))
                }
            }
        },
        onBack = onBack,
        actions = {
            if (isSearchActive) {
                IconButton(
                    onClick = {
                        if (params.query.isNotEmpty()) {
                            viewModel.onSearchQueryChange("")
                        } else {
                            isSearchActive = false
                        }
                    }
                ) {
                    Icon(Icons.Default.Close, contentDescription = localizedText("关闭搜索"))
                }
            } else {
                IconButton(onClick = { isSearchActive = true }) {
                    Icon(Icons.Default.Search, contentDescription = localizedText("搜索"))
                }
            }
            IconButton(
                onClick = {
                    viewModel.refreshCacheList()
                    entries.refresh()
                }
            ) {
                Icon(Icons.Default.Refresh, contentDescription = localizedText("刷新"))
            }
        }
    ) { innerPadding ->
        Box(
            modifier = Modifier
                .fillMaxSize()
                .padding(innerPadding)
        ) {
            LazyColumn(
                modifier = Modifier.fillMaxSize(),
                contentPadding = PaddingValues(16.dp),
                verticalArrangement = Arrangement.spacedBy(SettingsItemSpacing)
            ) {
                items(
                    count = entries.itemCount,
                    contentType = entries.itemContentType { "DnsCacheEntity" }
                ) { index ->
                    entries[index]?.let { entry ->
                        SettingsSurfaceItem(
                            index = index,
                            itemCount = entries.itemCount
                        ) {
                            DnsCacheItem(
                                entry = entry,
                                nowMillis = nowMillis
                            )
                        }
                    }
                }

                if (entries.loadState.append is LoadState.Loading) {
                    item {
                        Box(
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(16.dp),
                            contentAlignment = Alignment.Center
                        ) {
                            CircularProgressIndicator()
                        }
                    }
                }
            }

            when {
                entries.loadState.refresh is LoadState.Loading && entries.itemCount == 0 -> {
                    CircularProgressIndicator(modifier = Modifier.align(Alignment.Center))
                }
                entries.loadState.refresh is LoadState.NotLoading && entries.itemCount == 0 -> {
                    Text(
                        text = localizedText("暂无 DNS 缓存"),
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.align(Alignment.Center)
                    )
                }
            }
        }
    }
}

@Composable
private fun DnsCacheItem(
    entry: DnsCacheEntity,
    nowMillis: Long
) {
    val remaining = max(0L, (entry.expiresAt - nowMillis + 999L) / 1000L)
    val expirationText = if (remaining == 0L) {
        "已过期"
    } else {
        "${formatDuration(remaining)} 后过期"
    }
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 12.dp),
        verticalArrangement = Arrangement.spacedBy(6.dp)
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = entry.queryName,
                    style = MaterialTheme.typography.bodyLarge
                )
                Text(
                    text = localizedText("${dnsTypeName(entry.queryType)} · $expirationText"),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }
        Text(
            text = localizedText("原始 TTL ${formatDuration(entry.originalTtlSeconds)} · 命中 ${entry.hitCount} 次 · ${entry.responseSize} B"),
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
        Text(
            text = localizedText("最后命中 ${entry.lastHitAt?.let { cacheTimeFormatter.format(Date(it)) } ?: "无"}"),
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
    }
}

private fun dnsTypeName(type: Int): String {
    return when (type) {
        1 -> "A"
        28 -> "AAAA"
        5 -> "CNAME"
        15 -> "MX"
        16 -> "TXT"
        2 -> "NS"
        12 -> "PTR"
        255 -> "ANY"
        else -> "TYPE$type"
    }
}
