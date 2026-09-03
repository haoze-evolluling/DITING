package com.haoze.dnssr.ui

import android.content.Context
import com.haoze.dnssr.ui.transfer.ConfigExporter
import com.haoze.dnssr.ui.transfer.ConfigImporter
import com.haoze.dnssr.ui.transfer.ConfigTransferParser

class ConfigTransferManager(private val context: Context) {
    private val exporter = ConfigExporter(context)
    private val importer = ConfigImporter(context)

    suspend fun export(selection: ConfigExportSelection): String {
        return exporter.export(selection)
    }

    suspend fun import(
        content: String,
        onProgress: (ConfigImportProgress) -> Unit = {}
    ): ConfigImportResult {
        val config = ConfigTransferParser.parseAndValidate(content)
        return importer.import(config, onProgress)
    }
}
