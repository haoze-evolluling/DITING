import java.util.Properties

plugins {
    id("com.android.application")
    id("dev.flutter.flutter-gradle-plugin")
}

val keystorePropertiesFile: File = rootProject.file("key.properties")
val keystoreProperties = Properties().apply {
    if (keystorePropertiesFile.exists()) {
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
    val fromPropDir = File(keystorePropertiesFile.parentFile, path)
    val fromAndroidRoot = rootProject.file(path)
    val fromAppDir = file(path)
    when {
        fromPropDir.exists() -> fromPropDir
        fromAndroidRoot.exists() -> fromAndroidRoot
        fromAppDir.exists() -> fromAppDir
        else -> null
    }
}

val hasReleaseSigning: Boolean = releaseKeystoreFile != null &&
    releaseKeystoreFile.exists() &&
    !releaseStorePassword.isNullOrBlank() &&
    !releaseKeyAlias.isNullOrBlank()

val signDebugWithRelease: Boolean =
    project.findProperty("signDebugWithRelease")?.toString()?.let {
      it.isBlank() || it == "true" || it == "1"
    } ?: true

val targetAbi: String = project.findProperty("ditingAbi")?.toString()?.lowercase() ?: ""

val compressNativeLibs: Boolean =
    project.findProperty("ditingCompressNativeLibs")?.toString()?.toBoolean() ?: true

val compressDex: Boolean =
    project.findProperty("ditingCompressDex")?.toString()?.toBoolean() ?: true

android {
    namespace = "com.haoze.diting"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.haoze.diting"
        minSdk = 28
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseSigning) {
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
                signingConfigs.findByName("release")?.let { signingConfig = it }
            }
        }
        release {
            signingConfig = if (hasReleaseSigning) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }
}

val abisToShip: Set<String> = setOf("arm64-v8a", "x86_64")

val targetPlatform: String =
    project.findProperty("target-platform")?.toString()?.trim() ?: ""

fun excludedJniAbis(variantName: String): List<String> {
    val kept = when {
        targetAbi == "x86_64" -> setOf("x86_64")
        targetAbi == "arm64" -> setOf("arm64-v8a")
        targetAbi == "all" -> abisToShip
        targetPlatform == "android-x64" -> setOf("x86_64")
        variantName == "release" -> setOf("arm64-v8a")
        else -> abisToShip
    }
    return listOf("armeabi-v7a", "x86") + (abisToShip - kept)
}

val splitPerAbi: Boolean =
    project.findProperty("split-per-abi")?.toString()?.toBoolean() ?: false

androidComponents {
    onVariants { variant ->
        if (!splitPerAbi) {
            variant.packaging.jniLibs.excludes.addAll(
                excludedJniAbis(variant.name).map { "**/$it/**" }
            )
        }
        variant.packaging.jniLibs.useLegacyPackaging.set(compressNativeLibs)
        if (variant.name == "release") {
            variant.packaging.dex.useLegacyPackaging.set(compressDex)
        }

        val capitalized = variant.name.replaceFirstChar { it.uppercase() }
        val expected = abisToShip - excludedJniAbis(variant.name).toSet()
        val requiredLibs = listOf("libditing_native.so")
        val checkNativeLibs = tasks.register("checkNativeLibs${capitalized}") {
            val libsDir = layout.projectDirectory.dir("src/main/jniLibs")
            val abis = expected
            doLast {
                val missing = abis
                    .sorted()
                    .flatMap { abi -> requiredLibs.map { "$abi/$it" } }
                    .filterNot { libsDir.file(it).asFile.exists() }
                if (missing.isNotEmpty()) {
                    throw GradleException(
                        "Missing native libraries: ${missing.joinToString(", ")}\n" +
                            "Build them with `python rust/build_android.py` (or run android/app/build_apk.bat, " +
                            "which does it for you); see docs/development/rust-engine-build.md"
                    )
                }
            }
        }
        tasks.matching { it.name == "pre${capitalized}Build" }.configureEach {
            dependsOn(checkNativeLibs)
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

val apkVersionName: String = project.findProperty("ditingApkVersionName")?.toString()
    ?: run {
        val pubspec = rootProject.file("../pubspec.yaml")
        val match = Regex("^version:\\s*([^+\\s]+)", RegexOption.MULTILINE)
            .find(pubspec.readText())
        match?.groupValues?.get(1) ?: "unknown"
    }
if (!splitPerAbi) {
    listOf("debug", "release").forEach { buildType ->
        val capitalized = buildType.replaceFirstChar { it.uppercase() }
        val copyTask = tasks.register<Copy>("copy${capitalized}ApkWithVersion") {
            from(layout.buildDirectory.dir("outputs/apk/$buildType")) {
                include("app-$buildType.apk")
            }
            rename { "DITING-$buildType-v$apkVersionName.apk" }
            into(layout.buildDirectory.dir("outputs/apk/versioned/$buildType"))
        }
        tasks.configureEach {
            if (name == "assemble$capitalized") {
                finalizedBy(copyTask)
            }
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    implementation("androidx.work:work-runtime-ktx:2.12.0")
}
