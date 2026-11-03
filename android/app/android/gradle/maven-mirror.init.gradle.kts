// Maven mirror for this machine: Maven Central answers 403 here.
//
// Install by copying it to $GRADLE_USER_HOME/init.d/ (on Windows
// %USERPROFILE%\.gradle\init.d\), or run any build with
//   -I <path-to-this-file>
//
// It has to be an init script rather than a settings.gradle.kts block: the Flutter Gradle plugin
// (`includeBuild($flutterSdkPath/packages/flutter_tools/gradle)`) is a separate build whose own
// settings script declares Central-only repositories with FAIL_ON_PROJECT_REPOS, so repositories
// declared by the app build never reach it. `beforeSettings` in an init script fires for every
// Settings object in the composite build, including that one.
val mavenMirrors = listOf(
    // Fastest from this network (serves both Maven Central and Google's Android repo).
    "https://repo.huaweicloud.com/repository/maven/",
    "https://mirrors.cloud.tencent.com/nexus/repository/maven-public/",
)

beforeSettings {
    pluginManagement.repositories {
        mavenMirrors.forEach { maven(it) }
        google()
        mavenCentral()
        gradlePluginPortal()
    }
    dependencyResolutionManagement.repositories {
        mavenMirrors.forEach { maven(it) }
        google()
        mavenCentral()
    }
}

allprojects {
    buildscript.repositories {
        mavenMirrors.forEach { maven(it) }
    }
}
