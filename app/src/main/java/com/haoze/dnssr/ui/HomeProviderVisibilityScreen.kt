package com.haoze.dnssr.ui

import android.app.Application
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material3.TriStateCheckbox
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.state.ToggleableState
import androidx.compose.ui.unit.dp
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.lifecycle.viewModelScope
import com.haoze.dnssr.ui.components.SettingsCheckboxItem
import com.haoze.dnssr.ui.components.SettingsGroupTitle
import com.haoze.dnssr.ui.components.SettingsInfoText
import com.haoze.dnssr.ui.components.SettingsItem
import com.haoze.dnssr.ui.components.SettingsLoadingContent
import com.haoze.dnssr.ui.components.SettingsScaffold
import com.haoze.dnssr.ui.components.SettingsSurfaceGroup
import com.haoze.dnssr.vpn.DnsProtocol
import com.haoze.dnssr.vpn.DnsProvider
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

@Composable
fun HomeProviderVisibilityScreen(
    onBack: () -> Unit,
    title: String,
    viewModel: HomeProviderVisibilityViewModel = viewModel()
) {
    val providers by viewModel.providers.collectAsStateWithLifecycle()
    val visibility by viewModel.visibility.collectAsStateWithLifecycle()
    val initialLoading by viewModel.initialLoading.collectAsStateWithLifecycle()

    NavigationSettledEffect {
        viewModel.activate()
    }

    SettingsScaffold(title = localizedText(title), onBack = onBack) { innerPadding ->
        if (initialLoading) {
            SettingsLoadingContent(modifier = Modifier.padding(innerPadding))
        } else {
            LazyColumn(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(innerPadding),
                verticalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                item {
                    SettingsInfoText(
                        localizedText("关闭竞速模式时，首页解析服务下拉框仅显示这里选中的服务。当前正在使用的服务会始终保留。"),
                        modifier = Modifier.padding(top = 8.dp)
                    )
                }
                DnsProtocol.MANAGED_PROTOCOLS.forEach { protocol ->
                    val protocolProviders = providers.filter { it.protocol == protocol }
                    val selectedCount = protocolProviders.count(visibility::isVisible)
                    val state = when {
                        protocolProviders.isEmpty() && protocol in visibility.visibleProtocols -> ToggleableState.On
                        selectedCount == 0 -> ToggleableState.Off
                        selectedCount == protocolProviders.size -> ToggleableState.On
                        else -> ToggleableState.Indeterminate
                    }

                    item {
                        SettingsGroupTitle(localizedText("${protocol.label} 服务"))
                    }
                    item {
                        val surfaceItems = mutableListOf<@Composable () -> Unit>()
                        surfaceItems += {
                            SettingsItem(
                                title = localizedText("全部 ${protocol.label} 服务"),
                                subtitle = when (state) {
                                    ToggleableState.On -> localizedText("显示该类型的全部服务")
                                    ToggleableState.Off -> localizedText("不显示该类型的服务")
                                    ToggleableState.Indeterminate -> localizedText("已选择 $selectedCount 个服务")
                                },
                                onClick = { viewModel.setProtocolVisible(protocol, state != ToggleableState.On) }
                            ) {
                                TriStateCheckbox(
                                    state = state,
                                    onClick = { viewModel.setProtocolVisible(protocol, state != ToggleableState.On) }
                                )
                            }
                        }
                        protocolProviders.forEach { provider ->
                            surfaceItems += {
                                SettingsCheckboxItem(
                                    title = localizedText(provider.name),
                                    subtitle = provider.endpointLabel(),
                                    checked = visibility.isVisible(provider),
                                    onCheckedChange = { checked ->
                                        viewModel.setProviderVisible(provider, checked)
                                    }
                                )
                            }
                        }
                        SettingsSurfaceGroup(
                            content = surfaceItems
                        )
                    }
                }
            }
        }
    }
}

class HomeProviderVisibilityViewModel(application: Application) : AndroidViewModel(application) {
    private val _providers = MutableStateFlow<List<DnsProvider>>(emptyList())
    val providers: StateFlow<List<DnsProvider>> = _providers.asStateFlow()

    private val _visibility = MutableStateFlow(HomeProviderVisibility())
    val visibility: StateFlow<HomeProviderVisibility> = _visibility.asStateFlow()

    private val _initialLoading = MutableStateFlow(true)
    val initialLoading: StateFlow<Boolean> = _initialLoading.asStateFlow()

    private var activated = false

    fun activate() {
        if (activated) return
        activated = true
        viewModelScope.launch(Dispatchers.IO) {
            val context = getApplication<Application>()
            val providers = DnsProvider.loadRuntimeProviders(context)
            val visibility = AppSettings.getHomeProviderVisibility(context)
            withContext(Dispatchers.Main) {
                _providers.value = providers
                _visibility.value = visibility
                _initialLoading.value = false
            }
        }
    }

    fun setProtocolVisible(protocol: DnsProtocol, visible: Boolean) {
        updateVisibility { current ->
            val protocolProviderIds = _providers.value
                .filter { it.protocol == protocol }
                .map { it.id }
                .toSet()
            current.copy(
                visibleProtocols = current.visibleProtocols.toMutableSet().apply {
                    if (visible) add(protocol) else remove(protocol)
                },
                hiddenProviderIds = current.hiddenProviderIds - protocolProviderIds,
                visibleProviderIds = current.visibleProviderIds - protocolProviderIds
            )
        }
    }

    fun setProviderVisible(provider: DnsProvider, visible: Boolean) {
        updateVisibility { current ->
            if (provider.protocol in current.visibleProtocols) {
                current.copy(
                    hiddenProviderIds = current.hiddenProviderIds.toMutableSet().apply {
                        if (visible) remove(provider.id) else add(provider.id)
                    },
                    visibleProviderIds = current.visibleProviderIds - provider.id
                )
            } else {
                current.copy(
                    hiddenProviderIds = current.hiddenProviderIds - provider.id,
                    visibleProviderIds = current.visibleProviderIds.toMutableSet().apply {
                        if (visible) add(provider.id) else remove(provider.id)
                    }
                )
            }
        }
    }

    private fun updateVisibility(transform: (HomeProviderVisibility) -> HomeProviderVisibility) {
        val updated = transform(_visibility.value)
        _visibility.value = updated
        viewModelScope.launch(Dispatchers.IO) {
            AppSettings.setHomeProviderVisibility(getApplication(), updated)
        }
    }
}
