# R8 / resource-shrinking keep rules for the DITING release build.
#
# The Flutter Gradle plugin already passes the rules the engine needs, and the
# app's Kotlin/SQLite/Firebase-free plugin set (sqlite3, path_provider, etc.)
# resolves reflectively only inside the plugin registrant, which R8 keeps via
# its generated references. Anything added here must be justified: an overly
# broad keep rule costs APK size, a missing one crashes at runtime.
#
# Native methods called from the Rust libraries (`libditing_*.so`) and the sqlite3 AAR are looked
# up by JNI, so keep the Java/Kotlin bridge classes they belong to.
-keepclasseswithmembernames,includedescriptorclasses class * {
    native <methods>;
}

# The Rust engine facade (`com.haoze.diting.engine`, libditing_engine.so). The class declares the
# natives, and its three callback interfaces are implemented by anonymous Kotlin objects whose method
# names Rust resolves by signature — R8 cannot see those references, so the whole package is kept.
# It is four small classes; the alternative is a NoSuchMethodError on a release build only.
-keep class com.haoze.diting.engine.** { *; }

# WorkManager (A7 scheduling) auto-initialises through `androidx.startup.InitializationProvider`,
# which looks up every `androidx.startup.Initializer` by the class name written in the merged
# manifest and instantiates it with `getDeclaredConstructor().newInstance()`. R8 full mode cannot
# see those reflective calls, so without these rules it strips the no-arg constructor and the app
# crashes before the first activity on release builds only:
#   RuntimeException: Unable to get provider androidx.startup.InitializationProvider:
#   java.lang.NoSuchMethodException: <init> []
-keep class androidx.startup.** { *; }
-keep class * implements androidx.startup.Initializer { *; }
# The WorkManager initializer itself is named as a manifest meta-data value, so keep the name too.
-keep class androidx.work.WorkManagerInitializer { *; }

# Workers are scheduled by class name and instantiated reflectively with (Context, WorkerParameters);
# keep the constructors or every enqueued work fails (and a corrupt queue can crash initialisation).
-keep class * extends androidx.work.ListenableWorker {
    <init>(android.content.Context, androidx.work.WorkerParameters);
}
-keep class com.haoze.diting.automation.ScheduleWork { *; }

# Room looks up its generated `*_Impl` database class by name and instantiates it through
# `getDeclaredConstructor().newInstance()`. WorkManager's WorkDatabase is the only Room database in
# this app; R8 keeps the class name but strips the empty constructor, so WorkManager's own
# initializer dies with `NoSuchMethodException: <init> []` before the first frame. This was the
# exact crash on the release build (`WorkManagerInitializer.create -> RoomDatabase`).
-keep class * extends androidx.room.RoomDatabase { <init>(); }
-keep class androidx.work.impl.WorkDatabase_Impl { *; }

# Keep annotations used for JSON (de)serialization in the update/member paths.
-keepattributes *Annotation*, Signature, InnerClasses, EnclosingMethod

# Do not keep line numbers / source files: saves a little dex size and strips
# stack-trace detail, which is acceptable because release crashes are reported
# through the app's own error reporting path.
-renamesourcefileattribute SourceFile
