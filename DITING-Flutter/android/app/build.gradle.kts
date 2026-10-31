import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing: android/key.properties or the DITING_KEY* env vars in CI; neither is committed.
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

// Relative paths resolve against the key.properties dir, then the android root, then the app dir.
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

// Debug signed with the release key: else INSTALL_FAILED_UPDATE_INCOMPATIBLE over a release build.
val signDebugWithRelease: Boolean =
    project.findProperty("signDebugWithRelease")?.toString()?.let {
      it.isBlank() || it == "true" || it == "1"
    } ?: true

// --- APK size options ---------------------------------------------------
// Target ABI for single-architecture builds: empty (arm64 only, the historical
// default), "arm64" or "x86_64". Anything else falls back to the default.
val targetAbi: String = project.findProperty("ditingAbi")?.toString()?.lowercase() ?: ""

// Native libraries are stored uncompressed by default, which makes them mmap-able
// but leaves the APK ~20 MB (release) / ~90 MB (debug) larger. Compressing them
// (legacy packaging, extracted at install) shrinks the download without touching
// a single line of app code. Disable with -PditingCompressNativeLibs=false.
val compressNativeLibs: Boolean =
    project.findProperty("ditingCompressNativeLibs")?.toString()?.toBoolean() ?: true

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
        // The Go engine AAR is built with `-androidapi 28` (tunnel/build_aar.ps1), so the app
        // cannot run below Android 9.0. Overrides the Flutter default (24) on purpose.
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
            // R8 + resource shrinking: the Flutter/AGP defaults already shrink code,
            // this makes it explicit and drops unused framework resources too.
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }
}

// Tunnel AARs are single- or dual-ABI; drop the ABIs each build must not ship.
// abiFilters gets overwritten by the Flutter plugin, so jniLibs excludes are used instead.
//
// ABI policy:
//   ditingAbi unset  -> debug: arm64-v8a + x86_64 (dual-ABI tunnel-all.aar, runs on
//                       phones AND the x86_64 emulator); release: arm64-v8a only
//   ditingAbi=arm64  -> arm64-v8a only, debug and release
//   ditingAbi=x86_64 -> x86_64 only (emulator builds), debug and release
//   ditingAbi=all    -> arm64-v8a + x86_64 (universal build), debug and release
val splitPerAbi: Boolean =
    project.findProperty("split-per-abi")?.toString()?.toBoolean() ?: false
androidComponents {
    onVariants { variant ->
        val excludedByAbi = when {
            targetAbi == "x86_64" -> listOf("**/armeabi-v7a/**", "**/arm64-v8a/**")
            targetAbi == "arm64" -> listOf("**/armeabi-v7a/**", "**/x86_64/**")
            targetAbi == "all" -> listOf("**/armeabi-v7a/**", "**/x86/**")
            variant.name == "release" -> listOf("**/armeabi-v7a/**", "**/x86_64/**")
            else -> listOf("**/armeabi-v7a/**", "**/x86/**")
        }
        if (!splitPerAbi) {
            variant.packaging.jniLibs.excludes.addAll(excludedByAbi)
        }
        variant.packaging.jniLibs.useLegacyPackaging.set(compressNativeLibs)
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

// Copies each assembled APK to a versioned name, so releases do not overwrite the base one.
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

dependencies {
    // Go userspace tunnel (gomobile AAR). Picked per target ABI / build type:
    //   -PtunnelAar=<path>      explicit override (relative to app dir), all variants
    //   ditingAbi=x86_64        -> libs/tunnel-x64.aar   (x86_64 emulator)
    //   ditingAbi=all           -> libs/tunnel-all.aar   (dual ABI, universal)
    //   ditingAbi=arm64         -> libs/tunnel-arm64.aar
    //   ditingAbi unset         -> debug: libs/tunnel-all.aar so ONE debug APK runs on both
    //                              ARM devices and the x86_64 emulator; release/profile:
    //                              libs/tunnel-arm64.aar (committed)
    fun tunnelAar(relPath: String): File {
        val aarFile = file(relPath)
        if (!aarFile.exists()) {
            throw GradleException(
                "Tunnel AAR not found: $aarFile\n" +
                    "Build it from tunnel/build_aar.ps1 (no args for arm64, " +
                    "-Arch x64 / -Arch all for the others), see docs/development/aar-build-notes.md"
            )
        }
        println("Tunnel AAR [$relPath]: $aarFile")
        return aarFile
    }
    val explicitTunnelAar = project.findProperty("tunnelAar")?.toString()
    when {
        explicitTunnelAar != null ->
            implementation(files(tunnelAar(explicitTunnelAar)))
        targetAbi == "x86_64" ||
            project.findProperty("target-platform")?.toString() == "android-x64" ->
            implementation(files(tunnelAar("libs/tunnel-x64.aar")))
        targetAbi == "all" ->
            implementation(files(tunnelAar("libs/tunnel-all.aar")))
        targetAbi == "arm64" ->
            implementation(files(tunnelAar("libs/tunnel-arm64.aar")))
        else -> {
            add("debugImplementation", files(tunnelAar("libs/tunnel-all.aar")))
            add("releaseImplementation", files(tunnelAar("libs/tunnel-arm64.aar")))
            add("profileImplementation", files(tunnelAar("libs/tunnel-arm64.aar")))
        }
    }
}

flutter {
    source = "../.."
}
