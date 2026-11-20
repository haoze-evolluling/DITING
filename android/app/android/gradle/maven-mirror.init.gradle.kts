val mavenMirrors = listOf(
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
