import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// --- Release signing ----------------------------------------------------
// Credentials come from android/key.properties or the DITING_KEY* env vars in
// CI; neither is committed. Relative keystore paths are resolved against the
// key.properties dir, then the android root, then the app dir.
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

// Debug builds also use the release key; otherwise installing a debug build
// over a release build fails with INSTALL_FAILED_UPDATE_INCOMPATIBLE.
val signDebugWithRelease: Boolean =
    project.findProperty("signDebugWithRelease")?.toString()?.let {
      it.isBlank() || it == "true" || it == "1"
    } ?: true

// --- Packaging options --------------------------------------------------
// Target ABI for single-architecture builds: empty (arm64 only, the historical
// default), "arm64", "x86_64" or "all". Unrecognized values fall back to the default.
val targetAbi: String = project.findProperty("ditingAbi")?.toString()?.lowercase() ?: ""

// Native libraries are uncompressed by default (mmap-able, but ~20 MB larger for
// release / ~90 MB for debug). Compressing them shrinks the download without any
// app-code change. Disable with -PditingCompressNativeLibs=false.
val compressNativeLibs: Boolean =
    project.findProperty("ditingCompressNativeLibs")?.toString()?.toBoolean() ?: true

// Release keeps classes.dex compressed (legacy packaging, extracted at install)
// to save ~0.55 MB; debug stays uncompressed so `flutter run` is not slowed.
// Disable with -PditingCompressDex=false.
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
        // The merged Rust library (libditing_native.so, built for API 28 by
        // rust/build_android.py) owns the data plane, so the app cannot run below
        // Android 9.0. Overrides the Flutter default (24) on purpose.
        minSdk = 28
        targetSdk = flutter.targetSdkVersion
        // Version code from pubspec.yaml; split APKs add 1000 * ABI_VERSION unless overridden.
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
            // Release key when available, else debug so `flutter run --release` works.
            signingConfig = if (hasReleaseSigning) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
            // Explicit R8 + resource shrinking on top of the Flutter/AGP defaults.
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }
}

// --- ABI selection & native-library checks ------------------------------
// Every packaged `.so` is built for both supported ABIs by rust/build_android.py;
// each build drops the ones it must not ship. `abiFilters` gets overwritten by the
// Flutter plugin, so jniLibs excludes are used instead.
//
// ABI policy:
//   ditingAbi unset  -> debug: arm64-v8a + x86_64; release: arm64-v8a only
//   ditingAbi=arm64  -> arm64-v8a only, debug and release
//   ditingAbi=x86_64 -> x86_64 only (emulator builds), debug and release
//   ditingAbi=all    -> arm64-v8a + x86_64 (universal build), debug and release
val abisToShip: Set<String> = setOf("arm64-v8a", "x86_64")

// `flutter build apk --target-platform android-x64` must not fall back to the
// release default (arm64-v8a) when `-PditingAbi` was not given: the emulator
// cannot load that APK.
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
    // armeabi-v7a / x86 are never built, so they are always excluded.
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
        // Deflate classes.dex for release only (see compressDex above).
        if (variant.name == "release") {
            variant.packaging.dex.useLegacyPackaging.set(compressDex)
        }

        // `libditing_native.so` carries the engine, UI kernels and server
        // runtime; `libditing_server.so` is the launcher that starts server
        // mode in its own process. Missing either breaks the matching mode at
        // runtime. Checked per variant at execution time, so `gradlew clean`
        // still works on a fresh clone.
        val capitalized = variant.name.replaceFirstChar { it.uppercase() }
        val expected = abisToShip - excludedJniAbis(variant.name).toSet()
        val requiredLibs = listOf(
            "libditing_native.so",
            "libditing_server.so",
        )
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

// --- Versioned APK output -----------------------------------------------
// Copy each assembled APK to a versioned name so releases do not overwrite the
// base artifact.
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
    // No AAR dependency: the merged native library ships as libditing_native.so under
    // src/main/jniLibs/<abi>/ (no Go/gomobile step in the build).
    // 自动化定时（A7）：一次性兜底任务 + 周期心跳任务。
    implementation("androidx.work:work-runtime-ktx:2.10.1")
}
