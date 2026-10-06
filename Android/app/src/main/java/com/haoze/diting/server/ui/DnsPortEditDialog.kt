package com.haoze.diting.server.ui

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import com.haoze.diting.server.model.DnsListenPortValidator
import com.haoze.diting.ui.components.AppAlertDialog
import com.haoze.diting.ui.components.AppDialogButton
import com.haoze.diting.ui.components.SettingsCornerShape
import com.haoze.diting.ui.localizedText

/**
 * Edit dialog for the DNS mode local listen port. Validation comes from
 * DnsListenPortValidator; saving is only committed once the value passes.
 */
@Composable
fun DnsPortEditDialog(
    initialPort: Int,
    onDismiss: () -> Unit,
    onSave: (port: Int) -> Unit
) {
    var port by remember { mutableStateOf(initialPort.toString()) }
    var portError by remember { mutableStateOf<String?>(null) }

    fun submit() {
        val currentError = DnsListenPortValidator.validate(port)
        portError = currentError
        if (currentError == null) {
            onSave(DnsListenPortValidator.parse(port))
        }
    }

    AppAlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(localizedText("本地监听端口")) },
        text = {
            Column {
                OutlinedTextField(
                    value = port,
                    onValueChange = {
                        port = it.filter { char -> char.isDigit() }
                        portError = null
                    },
                    label = { Text(localizedText("端口")) },
                    isError = portError != null,
                    supportingText = {
                        Text(
                            localizedText(
                                portError
                                    ?: "范围 ${DnsListenPortValidator.MIN_PORT}-${DnsListenPortValidator.MAX_PORT}，默认 ${DnsListenPortValidator.DEFAULT_PORT}"
                            )
                        )
                    },
                    keyboardOptions = KeyboardOptions(
                        keyboardType = KeyboardType.Number,
                        imeAction = ImeAction.Done
                    ),
                    shape = SettingsCornerShape,
                    modifier = Modifier.fillMaxWidth()
                )
            }
        },
        confirmButton = {
            AppDialogButton(label = "保存", onClick = ::submit)
        },
        dismissButton = {
            AppDialogButton(label = "取消", onClick = onDismiss)
        }
    )
}
