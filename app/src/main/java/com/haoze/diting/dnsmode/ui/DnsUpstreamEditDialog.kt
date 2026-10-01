package com.haoze.diting.dnsmode.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ErrorOutline
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.unit.dp
import com.haoze.diting.dnsmode.model.DnsModeProtocol
import com.haoze.diting.dnsmode.model.DnsUpstreamServer
import com.haoze.diting.dnsmode.model.DnsUpstreamValidator
import com.haoze.diting.ui.components.AppAlertDialog
import com.haoze.diting.ui.components.AppDialogButton
import com.haoze.diting.ui.components.SettingsCornerShape
import com.haoze.diting.ui.localizedText

/**
 * Add/edit dialog for user-defined upstream servers. Field-level errors come
 * from DnsUpstreamValidator; saving is only committed once every field passes.
 */
@Composable
fun DnsUpstreamEditDialog(
    title: String,
    initial: DnsUpstreamServer?,
    onDismiss: () -> Unit,
    onSave: (name: String, protocol: DnsModeProtocol, address: String, port: Int) -> Unit,
    onDelete: (() -> Unit)? = null
) {
    var name by remember { mutableStateOf(initial?.name ?: "") }
    var protocol by remember { mutableStateOf(initial?.protocol ?: DnsModeProtocol.UDP) }
    var address by remember { mutableStateOf(initial?.address ?: "") }
    var port by remember {
        mutableStateOf(
            initial?.takeIf { it.protocol != DnsModeProtocol.DOH }?.port?.toString()
                ?: DnsModeProtocol.UDP.defaultPort.toString()
        )
    }
    var nameError by remember { mutableStateOf<String?>(null) }
    var addressError by remember { mutableStateOf<String?>(null) }
    var portError by remember { mutableStateOf<String?>(null) }

    fun submit() {
        val currentNameError = DnsUpstreamValidator.validateName(name)
        val currentAddressError = DnsUpstreamValidator.validateAddress(protocol, address)
        val currentPortError = DnsUpstreamValidator.validatePort(port, protocol)
        nameError = currentNameError
        addressError = currentAddressError
        portError = currentPortError
        if (currentNameError == null && currentAddressError == null && currentPortError == null) {
            onSave(
                name.trim(),
                protocol,
                address.trim(),
                DnsUpstreamValidator.parsePort(port, protocol)
            )
        }
    }

    AppAlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(localizedText(title)) },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedTextField(
                    value = name,
                    onValueChange = {
                        name = it
                        nameError = null
                    },
                    label = { Text(localizedText("上游名称")) },
                    isError = nameError != null,
                    supportingText = { nameError?.let { Text(localizedText(it)) } },
                    keyboardOptions = KeyboardOptions(imeAction = ImeAction.Next),
                    shape = SettingsCornerShape,
                    modifier = Modifier.fillMaxWidth()
                )

                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    DnsModeProtocol.entries.forEach { candidate ->
                        FilterChip(
                            selected = protocol == candidate,
                            onClick = {
                                protocol = candidate
                                if (candidate != DnsModeProtocol.DOH) {
                                    port = candidate.defaultPort.toString()
                                    portError = null
                                }
                                addressError = null
                            },
                            label = { Text(candidate.label) }
                        )
                    }
                }

                OutlinedTextField(
                    value = address,
                    onValueChange = {
                        address = it
                        addressError = null
                    },
                    label = {
                        Text(
                            localizedText(
                                if (protocol == DnsModeProtocol.DOH) "DoH 解析地址" else "解析地址"
                            )
                        )
                    },
                    placeholder = {
                        Text(
                            localizedText(
                                if (protocol == DnsModeProtocol.DOH) {
                                    "https://example.com/dns-query"
                                } else {
                                    "1.1.1.1 或 example.com"
                                }
                            )
                        )
                    },
                    isError = addressError != null,
                    supportingText = { addressError?.let { Text(localizedText(it)) } },
                    keyboardOptions = KeyboardOptions(imeAction = ImeAction.Next),
                    shape = SettingsCornerShape,
                    modifier = Modifier.fillMaxWidth()
                )

                if (protocol != DnsModeProtocol.DOH) {
                    OutlinedTextField(
                        value = port,
                        onValueChange = {
                            port = it.filter { char -> char.isDigit() }
                            portError = null
                        },
                        label = { Text(localizedText("端口")) },
                        isError = portError != null,
                        supportingText = { portError?.let { Text(localizedText(it)) } },
                        keyboardOptions = KeyboardOptions(imeAction = ImeAction.Done),
                        shape = SettingsCornerShape,
                        modifier = Modifier.fillMaxWidth()
                    )
                }
            }
        },
        confirmButton = {
            Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                if (onDelete != null) {
                    AppDialogButton(label = "删除", onClick = onDelete, destructive = true)
                }
                AppDialogButton(label = "保存", onClick = ::submit)
            }
        },
        dismissButton = {
            AppDialogButton(label = "取消", onClick = onDismiss)
        }
    )
}
