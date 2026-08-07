package com.haoze.dnssr.ui

import android.graphics.BitmapFactory
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.animateDpAsState
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.haoze.dnssr.ui.components.SettingsSurfaceGroup

data class RecognitionMember(
    val name: String,
    val acknowledgement: String,
    val avatarFileName: String
)

@Composable
fun RecognitionList(
    members: List<RecognitionMember>,
    emptyText: String,
    avatarStates: Map<String, RecognitionAvatarState>
) {
    SettingsSurfaceGroup(
        content = if (members.isEmpty()) {
            listOf {
                Text(
                    text = localizedText(emptyText),
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 16.dp, vertical = 20.dp)
                )
            }
        } else {
            members.map { member ->
                {
                    RecognitionListItem(member, avatarStates[member.avatarFileName])
                }
            }
        }
    )
}

@Composable
private fun RecognitionListItem(member: RecognitionMember, avatarState: RecognitionAvatarState?) {
    val avatarFile = (avatarState as? RecognitionAvatarState.Available)?.file
    val avatar = remember(avatarFile) {
        avatarFile?.let { BitmapFactory.decodeFile(it.absolutePath)?.asImageBitmap() }
    }
    val hasAvatar = avatar != null
    val textStart by animateDpAsState(
        targetValue = if (hasAvatar) 60.dp else 0.dp,
        animationSpec = tween(durationMillis = 220),
        label = "recognitionTextStart"
    )

    Box(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 12.dp),
        contentAlignment = Alignment.CenterStart
    ) {
        Box(modifier = Modifier.size(48.dp)) {
            AnimatedVisibility(
                visible = hasAvatar,
                enter = fadeIn(animationSpec = tween(durationMillis = 160, delayMillis = 220)),
                exit = fadeOut(animationSpec = tween(durationMillis = 100))
            ) {
                avatar?.let {
                    Image(
                        bitmap = it,
                        contentDescription = localizedText("${member.name}的头像"),
                        contentScale = ContentScale.Crop,
                        modifier = Modifier
                            .size(48.dp)
                            .clip(CircleShape)
                    )
                }
            }
        }
        Column(modifier = Modifier.padding(start = textStart)) {
            Text(
                text = member.name,
                style = MaterialTheme.typography.bodyLarge,
                color = MaterialTheme.colorScheme.onSurface,
                fontWeight = FontWeight.Medium
            )
            Text(
                text = localizedText(member.acknowledgement),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
    }
}
