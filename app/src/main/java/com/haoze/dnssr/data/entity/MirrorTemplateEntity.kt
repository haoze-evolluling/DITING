package com.haoze.dnssr.data.entity

import androidx.room.Entity
import androidx.room.Index
import androidx.room.PrimaryKey

@Entity(tableName = "mirror_template", indices = [Index(value = ["name"], unique = true)])
data class MirrorTemplateEntity(
    @PrimaryKey(autoGenerate = true) val id: Long = 0,
    val name: String,
    val template: String,
    val addedAt: Long = System.currentTimeMillis()
)
