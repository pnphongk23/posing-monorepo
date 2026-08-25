// composeApp/src/commonMain/kotlin/com/aipose/App.kt
package com.aipose

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import cafe.adriel.voyager.navigator.tab.CurrentTab
import cafe.adriel.voyager.navigator.tab.TabNavigator
import coil3.ImageLoader
import coil3.compose.setSingletonImageLoaderFactory
import coil3.disk.DiskCache
import coil3.memory.MemoryCache
import coil3.network.ktor2.KtorNetworkFetcherFactory
import coil3.util.DebugLogger
import com.aipose.navigation.MatchedImageOverlay
import com.aipose.navigation.PosesTab
import com.aipose.ui.components.communityDiskCacheDirectory
import com.aipose.ui.theme.AiPoseTheme
import okio.Path.Companion.toPath

@Composable
fun App() {
    setSingletonImageLoaderFactory { context ->
        ImageLoader.Builder(context)
            .components {
                add(KtorNetworkFetcherFactory())
            }
            // Single, bounded memory + disk caches. Community media (and other remote
            // images) are cached here instead of per-card local staging: the disk
            // cache avoids re-downloading thumbnails across launches/scroll, and the
            // memory cache is capped so it can never exhaust device memory.
            .memoryCache {
                MemoryCache.Builder()
                    .maxSizePercent(context, 0.15)
                    .build()
            }
            .diskCache {
                DiskCache.Builder()
                    .directory(communityDiskCacheDirectory().toPath())
                    .maxSizeBytes(50L * 1024L * 1024L)
                    .build()
            }
            .logger(DebugLogger())
            .build()
    }
    AiPoseTheme {
        Box(modifier = Modifier.fillMaxSize()) {
            TabNavigator(tab = PosesTab) {
                // Each list-root owns its dock. This keeps nested Voyager detail screens
                // full-screen instead of relying on a child CompositionLocal to mutate
                // this parent composition.
                Box(modifier = Modifier.fillMaxSize()) {
                    CurrentTab()
                }
            }
            MatchedImageOverlay()
        }
    }
}
