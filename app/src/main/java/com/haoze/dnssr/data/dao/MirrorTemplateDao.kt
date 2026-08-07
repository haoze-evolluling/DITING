package com.haoze.dnssr.data.dao

import androidx.room.Dao
import androidx.room.Delete
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import androidx.room.Update
import com.haoze.dnssr.data.entity.MirrorTemplateEntity
import kotlinx.coroutines.flow.Flow

@Dao
interface MirrorTemplateDao {
    @Insert(onConflict = OnConflictStrategy.ABORT)
    suspend fun insert(template: MirrorTemplateEntity): Long
    @Update suspend fun update(template: MirrorTemplateEntity)
    @Delete suspend fun delete(template: MirrorTemplateEntity)
    @Query("SELECT * FROM mirror_template ORDER BY addedAt DESC")
    fun observeAll(): Flow<List<MirrorTemplateEntity>>
}
