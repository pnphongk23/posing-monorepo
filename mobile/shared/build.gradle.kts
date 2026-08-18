// shared/build.gradle.kts
plugins {
    alias(libs.plugins.kotlin.multiplatform)
    alias(libs.plugins.sqldelight)
    kotlin("plugin.serialization") version "2.0.0"
}

kotlin {
    iosX64()
    iosArm64()
    iosSimulatorArm64()

    sourceSets {
        commonMain.dependencies {
            api(libs.sqldelight.runtime)
            implementation(libs.sqldelight.coroutines)
            implementation(libs.coroutines.core)
            implementation(libs.ktor.client.core)
            implementation(libs.ktor.client.content.negotiation)
            implementation(libs.ktor.serialization.kotlinx.json)
            implementation(libs.kotlinx.serialization.json)
            implementation(libs.kotlinx.datetime)
        }
        iosMain.dependencies {
            implementation(libs.sqldelight.native)
            implementation(libs.ktor.client.darwin)
        }
        val iosSimulatorArm64Test by getting {
            dependencies {
                implementation(libs.ktor.client.mock)
                implementation(libs.coroutines.test)
            }
        }
    }
}

sqldelight {
    databases {
        create("AiPoseDatabase") {
            packageName.set("com.aipose.data")
        }
    }
}
