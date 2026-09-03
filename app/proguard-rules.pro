# 基础保留规则
-keepattributes Signature, InnerClasses, EnclosingMethod, *Annotation*

# Room 实体类（保险起见，避免被 R8 误删）
-keep class com.haoze.dnssr.data.entity.** { *; }

# 使用 org.json 手动序列化的数据类
-keepclassmembers class com.haoze.dnssr.vpn.DnsProvider { *; }
-keepclassmembers class com.haoze.dnssr.vpn.DnsProtocol { *; }

# Netty supports these JVM logging backends optionally. They are deliberately
# absent from the Android APK, where Netty falls back to its available logger.
-dontwarn org.apache.log4j.Level
-dontwarn org.apache.log4j.Logger
-dontwarn org.apache.log4j.Priority
-dontwarn org.apache.logging.log4j.LogManager
-dontwarn org.apache.logging.log4j.Logger
-dontwarn org.apache.logging.log4j.message.MessageFactory
-dontwarn org.apache.logging.log4j.spi.ExtendedLogger
-dontwarn org.apache.logging.log4j.spi.ExtendedLoggerWrapper
-dontwarn org.slf4j.ILoggerFactory
-dontwarn org.slf4j.Logger
-dontwarn org.slf4j.LoggerFactory
-dontwarn org.slf4j.Marker
-dontwarn org.slf4j.helpers.FormattingTuple
-dontwarn org.slf4j.helpers.MessageFormatter
-dontwarn org.slf4j.helpers.NOPLoggerFactory
-dontwarn org.slf4j.spi.LocationAwareLogger
