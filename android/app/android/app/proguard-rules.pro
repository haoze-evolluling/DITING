# R8 / resource-shrinking keep rules for the DITING release build.
#
# The Flutter Gradle plugin already passes the rules the engine needs, and the
# app's Kotlin/SQLite/Firebase-free plugin set (sqlite3, path_provider, etc.)
# resolves reflectively only inside the plugin registrant, which R8 keeps via
# its generated references. Anything added here must be justified: an overly
# broad keep rule costs APK size, a missing one crashes at runtime.
#
# Native methods called from the Go tunnel AAR and the sqlite3 AAR are looked
# up by JNI, so keep the Java/Kotlin bridge classes they belong to.
-keepclasseswithmembernames,includedescriptorclasses class * {
    native <methods>;
}

# Keep annotations used for JSON (de)serialization in the update/member paths.
-keepattributes *Annotation*, Signature, InnerClasses, EnclosingMethod

# Do not keep line numbers / source files: saves a little dex size and strips
# stack-trace detail, which is acceptable because release crashes are reported
# through the app's own error reporting path.
-renamesourcefileattribute SourceFile
