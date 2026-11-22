package com.haoze.diting.core.rule;

public final class RuleIndexNative {
    public native byte[] paths(int datasetTag);

    public native byte[] dtriValidate(byte[] packed);

    public native byte[] snapshotPlan(byte[] packed);

    public native byte[] triePaths(byte[] packed);

    public native byte[] appAllowlist(byte[] packed);

    public native byte[] ruleFingerprint(byte[] packed);

    public native byte[] rewriteRules(byte[] packed);
}
