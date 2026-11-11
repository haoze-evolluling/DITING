package com.haoze.diting.core.rule;

/// Host-JVM copy of the `RuleIndexNative` declarations, used only by `RuleIndexSmoke` to prove that
/// the exported JNI symbols match the signatures Kotlin declares (name *and* argument order).
///
/// The Kotlin file is the real contract; this one is checked against it by `python rust/verify.py
/// --smoke`, because `cargo test` cannot see the `Java_...` symbol names.
public final class RuleIndexNative {
    public native byte[] paths(int datasetTag);

    public native byte[] dtriValidate(byte[] packed);

    public native byte[] snapshotPlan(byte[] packed);

    public native byte[] triePaths(byte[] packed);

    public native byte[] appAllowlist(byte[] packed);

    public native byte[] ruleFingerprint(byte[] packed);

    public native byte[] rewriteRules(byte[] packed);
}
