package com.haoze.dnssr.ui

import android.content.Context
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.platform.LocalContext
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope

class RecognitionAvatarLoader internal constructor(
    private val context: Context,
    members: List<RecognitionMember>
) {
    private val avatarFileNames = members.mapNotNull { it.avatarFileName }.distinct()
    private val mutableStates = mutableStateMapOf<String, RecognitionAvatarState>()
    val states: Map<String, RecognitionAvatarState> get() = mutableStates

    var isRefreshing by mutableStateOf(false)
        private set

    init {
        avatarFileNames.forEach { avatarFileName ->
            mutableStates[avatarFileName] = RecognitionAvatarRepository.cachedAvatar(context, avatarFileName)
                ?.let(RecognitionAvatarState::Available)
                ?: RecognitionAvatarState.Loading
        }
    }

    suspend fun loadMissing() = load(avatarFileNames.filter { avatarFileName ->
        mutableStates[avatarFileName] is RecognitionAvatarState.Loading
    })

    suspend fun retryMissingOrFailed(): AvatarRefreshResult {
        val targets = avatarFileNames.filter { avatarFileName ->
            mutableStates[avatarFileName] !is RecognitionAvatarState.Available
        }
        if (targets.isEmpty()) return AvatarRefreshResult(0, 0)
        load(targets)
        return AvatarRefreshResult(
            refreshedCount = targets.count { mutableStates[it] is RecognitionAvatarState.Available },
            failedCount = targets.count { mutableStates[it] is RecognitionAvatarState.Failed }
        )
    }

    private suspend fun load(avatarFileNames: List<String>) {
        if (avatarFileNames.isEmpty()) return
        isRefreshing = true
        try {
            avatarFileNames.forEach { mutableStates[it] = RecognitionAvatarState.Loading }
            coroutineScope {
                avatarFileNames.map { avatarFileName ->
                    async {
                        val file = RecognitionAvatarRepository.loadAvatar(context, avatarFileName)
                        mutableStates[avatarFileName] = file?.let(RecognitionAvatarState::Available)
                            ?: RecognitionAvatarState.Failed
                    }
                }.awaitAll()
            }
        } finally {
            isRefreshing = false
        }
    }
}

data class AvatarRefreshResult(val refreshedCount: Int, val failedCount: Int)

@Composable
fun rememberRecognitionAvatarLoader(members: List<RecognitionMember>): RecognitionAvatarLoader {
    val context = LocalContext.current.applicationContext
    val loader = remember(context, members) { RecognitionAvatarLoader(context, members) }
    LaunchedEffect(loader) {
        loader.loadMissing()
    }
    return loader
}
