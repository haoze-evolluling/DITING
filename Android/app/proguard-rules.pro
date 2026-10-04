# Room 实体类（保险起见，避免被 R8 误删）
-keep class com.haoze.diting.data.entity.** { *; }

# 使用 org.json 手动序列化的数据类
-keepclassmembers class com.haoze.diting.vpn.DnsProvider { *; }
-keepclassmembers class com.haoze.diting.vpn.DnsProtocol { *; }

# 优化 Release 日志：移除冗余的 Verbose / Debug 日志调用，减少无用字符串常量和字节码
-assumenosideeffects class android.util.Log {
    public static boolean isLoggable(java.lang.String, int);
    public static int v(...);
    public static int d(...);
}
