import java.io.File
import java.util.Properties

plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.compose)
    id("com.google.devtools.ksp") version "2.3.10"
}

// ==============================================================================
// 1. 应用版本配置 (App Version Configuration)
// ==============================================================================
// 应用内部版本号（整数，用于系统版本对比及应用升级判断）
val appVersionCode = 24

// 应用展示版本号（对外版本名称，供界面展示及说明使用）
val appVersionName = "1.2.10"

// 应用产物显示版本号（用于 APK 输出重命名等归档标识）
val apkVersionName = appVersionName

// ==============================================================================
// 2. 签名密钥与构建参数解析 (Signing Properties & Keystore Resolution)
// ==============================================================================
val keystorePropertiesFile: File? = listOf(
    rootProject.file("DITING-keystore/keystore.properties"),
    rootProject.file("keystore/keystore.properties"),
    rootProject.file("keystore.properties"),
    rootProject.file("../DITING-keystore/keystore.properties"),
    rootProject.file("../keystore/keystore.properties"),
    rootProject.file("../keystore.properties")
).firstOrNull { it.exists() }

val keystoreProperties = Properties().apply {
    if (keystorePropertiesFile != null && keystorePropertiesFile.exists()) {
        keystorePropertiesFile.inputStream().use { load(it) }
    }
}

val releaseStoreFilePath: String? = keystoreProperties.getProperty("storeFile")
    ?: System.getenv("DITING_KEYSTORE_FILE")
val releaseStorePassword: String? = keystoreProperties.getProperty("storePassword")
    ?: System.getenv("DITING_KEYSTORE_PASSWORD")
val releaseKeyAlias: String? = keystoreProperties.getProperty("keyAlias")
    ?: System.getenv("DITING_KEY_ALIAS")
val releaseKeyPassword: String? = keystoreProperties.getProperty("keyPassword")
    ?: System.getenv("DITING_KEY_PASSWORD")

val releaseKeystoreFile: File? = releaseStoreFilePath?.let { path ->
    val fromPropDir = keystorePropertiesFile?.parentFile?.let { File(it, path) }
    val fromRoot = rootProject.file(path)
    val fromApp = file(path)
    val fromRepoRoot = rootProject.file("..").resolve(path)
    when {
        fromPropDir != null && fromPropDir.exists() -> fromPropDir
        fromRoot.exists() -> fromRoot
        fromApp.exists() -> fromApp
        fromRepoRoot.exists() -> fromRepoRoot
        else -> null
    }
}

val signDebugWithRelease = project.findProperty("signDebugWithRelease") in listOf("true", "1", "")

// ==============================================================================
// 3. Android 构建与编译配置 (Android Configuration)
// ==============================================================================
android {
    namespace = "com.haoze.diting"
    compileSdk {
        version = release(36) {
            minorApiLevel = 1
        }
    }

    defaultConfig {
        applicationId = "com.haoze.diting"
        minSdk = 24
        targetSdk = 36
        versionCode = appVersionCode
        versionName = appVersionName
        ndk {
            abiFilters += "arm64-v8a"
        }
    }

    androidResources {
        localeFilters += listOf("zh", "en", "zh-rCN")
    }

    signingConfigs {
        if (releaseKeystoreFile != null && releaseKeystoreFile.exists() &&
            !releaseStorePassword.isNullOrBlank() && !releaseKeyAlias.isNullOrBlank()
        ) {
            create("release") {
                storeFile = releaseKeystoreFile
                storePassword = releaseStorePassword
                keyAlias = releaseKeyAlias
                keyPassword = releaseKeyPassword ?: releaseStorePassword
                enableV1Signing = true
                enableV2Signing = true
                enableV3Signing = true
            }
        }
    }

    buildTypes {
        debug {
            if (signDebugWithRelease) {
                signingConfigs.findByName("release")?.let { releaseSigningConfig ->
                    signingConfig = releaseSigningConfig
                }
            }
        }
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            signingConfigs.findByName("release")?.let { releaseSigningConfig ->
                signingConfig = releaseSigningConfig
            }
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    buildFeatures {
        buildConfig = true
        compose = true
    }

    packaging {
        resources {
            excludes += setOf(
                "META-INF/INDEX.LIST",
                "META-INF/DEPENDENCIES",
                "META-INF/LICENSE*",
                "META-INF/license*",
                "META-INF/**/LICENSE*",
                "META-INF/**/license*",
                "META-INF/NOTICE*",
                "META-INF/notice*",
                "META-INF/**/NOTICE*",
                "META-INF/**/notice*",
                "META-INF/ASL2.0",
                "META-INF/AL2.0",
                "META-INF/LGPL2.1",
                "META-INF/*.version",
                "META-INF/**/*.version",
                "META-INF/version-control-info.textproto",
                "META-INF/app-metadata.properties",
                "DebugProbesKt.bin",
                "**/*.kotlin_builtins"
            )
        }
        jniLibs {
            useLegacyPackaging = true
        }
        dex {
            useLegacyPackaging = true
        }
    }

    lint {
        checkReleaseBuilds = false
        abortOnError = false
    }
}

// ==============================================================================
// 4. 构建产物归档与命名任务 (Artifact Archiving Tasks)
// ==============================================================================
listOf("debug", "release").forEach { buildType ->
    val capitalizedBuildType = buildType.replaceFirstChar { it.uppercase() }
    val apkOutputDirectory = layout.buildDirectory.dir("outputs/apk/$buildType")
    val versionedApkOutputDirectory = layout.buildDirectory.dir("outputs/apk/versioned/$buildType")

    val copyApkTask = tasks.register<Copy>("copy${capitalizedBuildType}ApkWithVersion") {
        dependsOn("assemble$capitalizedBuildType")
        from(apkOutputDirectory)
        include("app-$buildType.apk")
        rename("app-$buildType.apk", "DITING-$buildType-v$apkVersionName.apk")
        into(versionedApkOutputDirectory)
    }

    tasks.configureEach {
        if (name == "assemble$capitalizedBuildType") {
            finalizedBy(copyApkTask)
        }
    }
}

// ==============================================================================
// 5. 依赖项配置 (Dependencies)
// ==============================================================================
dependencies {
    // GPL-3.0 userspace TCP/IP stack used by the opt-in HTTPS inspection mode.
    implementation(files("libs/tunnel.aar"))

    // Jetpack Compose 相关依赖
    implementation(platform(libs.androidx.compose.bom))
    implementation(libs.androidx.activity.compose)
    implementation(libs.androidx.compose.material3)
    implementation(libs.androidx.compose.material.icons.extended)
    implementation(libs.androidx.compose.ui)
    implementation(libs.androidx.compose.ui.graphics)
    implementation(libs.androidx.lifecycle.viewmodel.compose)
    implementation(libs.androidx.lifecycle.runtime.compose)

    // AndroidX 核心库与架构组件
    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.core.splashscreen)
    implementation(libs.androidx.lifecycle.runtime.ktx)
    implementation(libs.androidx.paging.runtime)
    implementation(libs.androidx.paging.compose)
    implementation(libs.androidx.work.runtime.ktx)

    // 本地持久化 (Room)
    implementation(libs.androidx.room.runtime)
    implementation(libs.androidx.room.ktx)
    ksp(libs.androidx.room.compiler)

    // 网络与三方组件
    implementation(libs.okhttp)
    implementation(libs.accompanist.drawablepainter)

    // 单元测试
    testImplementation(libs.junit)
    testImplementation(libs.json)
}
