// composeApp/src/commonMain/kotlin/com/aipose/App.kt
package com.aipose

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import cafe.adriel.voyager.navigator.tab.CurrentTab
import cafe.adriel.voyager.navigator.tab.LocalTabNavigator
import cafe.adriel.voyager.navigator.tab.TabNavigator
import com.aipose.navigation.CameraTab
import com.aipose.navigation.LocalMainDockVisible
import com.aipose.navigation.MainDock
import com.aipose.navigation.PosesTab
import com.aipose.ui.theme.AiPoseTheme

@Composable
fun App() {
    AiPoseTheme {
        TabNavigator(tab = PosesTab) {
            val tabNavigator = LocalTabNavigator.current
            val mainDockVisible = LocalMainDockVisible.current
            val showMainDock = mainDockVisible && tabNavigator.current != CameraTab

            Box(modifier = Modifier.fillMaxSize()) {
                CurrentTab()
                if (showMainDock) {
                    MainDock(modifier = Modifier.align(Alignment.BottomCenter))
                }
            }
        }
    }
}
