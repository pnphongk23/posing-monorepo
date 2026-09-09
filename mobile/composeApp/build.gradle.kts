// composeApp/build.gradle.kts
import org.jetbrains.kotlin.gradle.plugin.mpp.NativeBuildType

plugins {
    alias(libs.plugins.kotlin.multiplatform)
    kotlin("plugin.serialization") version "2.0.0"
    alias(libs.plugins.compose)
    alias(libs.plugins.compose.compiler)
    id("org.jetbrains.kotlin.native.cocoapods")
}

kotlin {
    iosX64()
    iosArm64()
    iosSimulatorArm64()

    cocoapods {
        version = "1.0"
        summary = "AI Pose Compose shared UI"
        homepage = "https://github.com/pnphongk23/ai-pose"
        ios.deploymentTarget = "15.0"
        podfile = project.file("../iosApp/Podfile")
        // XcodeGen uses environment-qualified configurations; keep the
        // Kotlin/Native framework build type aligned with each one.
        xcodeConfigurationToNativeBuildType["Debug-Dev"] = NativeBuildType.DEBUG
        xcodeConfigurationToNativeBuildType["Debug-Prod"] = NativeBuildType.DEBUG
        xcodeConfigurationToNativeBuildType["Release-Dev"] = NativeBuildType.RELEASE
        xcodeConfigurationToNativeBuildType["Release-Prod"] = NativeBuildType.RELEASE
        // FEAT-010 / DEC-007: Firebase SDKs are resolved by the existing Podfile and
        // consumed from native Swift (AppDelegate.swift), which compiles with
        // Xcode/clang. The Kotlin side is a pure contract/test seam only
        // (EndpointPolicy.validate, AppStartupConfig.resolveEndpointValue /
        // applyEndpoint); Kotlin cinterop (pod()) is intentionally NOT declared
        // because the pinned Kotlin wrapper (1.9.20) cannot parse the Xcode 26.1 SDK modulemap. See
        // mobile/iosApp/FIREBASE_SETUP.md.
        framework {
            baseName = "ComposeApp"
            isStatic = true
            linkerOpts("-lsqlite3")
        }
    }

    listOf(iosX64(), iosArm64(), iosSimulatorArm64()).forEach { target ->
        target.binaries.framework {
            baseName = "ComposeApp"
            isStatic = true
        }
        target.binaries.all {
            linkerOpts("-lsqlite3")
        }
        target.compilations.all {
            kotlinOptions.freeCompilerArgs += listOf(
                "-Xopt-in=androidx.compose.ui.ExperimentalComposeUiApi",
                "-Xopt-in=org.jetbrains.compose.ExperimentalComposeApi"
            )
        }
    }

    sourceSets {
        commonMain.dependencies {
            implementation(compose.runtime)
            implementation(compose.foundation)
            implementation(compose.material3)
            implementation(compose.materialIconsExtended)
            implementation(compose.components.resources)
            implementation(libs.voyager.navigator)
            implementation(libs.voyager.tab.navigator)
            implementation(libs.voyager.koin)
            implementation(libs.koin.core)
            implementation(libs.koin.compose)
            implementation(libs.stately.common)
            implementation(libs.kotlinx.datetime)
            implementation(libs.coil.compose)
            implementation(libs.coil.network.ktor2)
            implementation(project(":shared"))
        }
        val commonTest by getting {
            dependencies {
                implementation(kotlin("test"))
                implementation(libs.coroutines.test)
                implementation(libs.ktor.client.mock)
            }
        }
        val iosSimulatorArm64Test by getting {
            dependencies {
                implementation(libs.sqldelight.native)
            }
        }
        all {
            languageSettings.optIn("androidx.compose.ui.ExperimentalComposeUiApi")
            languageSettings.optIn("org.jetbrains.compose.ExperimentalComposeApi")
        }
    }
}
