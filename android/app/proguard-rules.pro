# R8 / ProGuard 规则 —— 韵算 (PoeMath) release 构建
#
# 目标：release APK 启用 minifyEnabled + shrinkResources 后仍能正常运行。
#
# 维护原则（见 .trellis/tasks/10-18-security-hardening/design.md §4.1）：
#   1. 本文件只保留「R8 无法自行证明安全」的入口。每条规则都必须写明保留理由。
#   2. 规则宁可多留也不能漏 —— 漏掉一条的后果是 release 包一进相关页面就崩，
#      而 debug 包完全不复现（debug 不跑 R8）。
#   3. 新增依赖或新增平台通道后，若 release 真机路径（更新 / TTS / ASR / 通知 /
#      WebDAV）出现崩溃，按崩溃堆栈在此补 keep 规则并记录原因。
#
# 注意：Dart 侧代码（含 Hive TypeAdapter、MethodChannel 名、更新 URL）由
# Dart AOT 编译，不经过 R8，本文件对它们不产生任何影响。

# ---------------------------------------------------------------------------
# Flutter 引擎与嵌入层
# ---------------------------------------------------------------------------
# Flutter 的 Java 嵌入层由引擎通过反射与 JNI 调起（platform view、plugin
# 注册、deferred component 等），类名/方法名被混淆后会在运行期抛
# NoSuchMethodError / ClassNotFoundException。
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# 注解、泛型签名、内部类、封闭方法必须保留：
#   - *Annotation*   ：R8 依据注解做入口推导的前提；注解被剥掉后部分框架的
#                      运行期查找会静默失效。
#   - Signature      ：泛型签名，反射读取参数化类型时必需。
#   - InnerClasses / EnclosingMethod：内部类与 encloser 的对应关系，
#                      反射构造内部类实例时必需。
-keepattributes *Annotation*, Signature, InnerClasses, EnclosingMethod

# ---------------------------------------------------------------------------
# 本项目原生入口
# ---------------------------------------------------------------------------
# MainActivity 由 AndroidManifest 以**类名字符串**声明（android:name=".MainActivity"），
# 被混淆后系统无法实例化，应用直接起不来 —— 故类名必须保留。
#
# 但**只保留类名，不保留成员**：`{ *; }` 会把全部私有方法名留在 DEX 里，
# 实测 `resolveUpdateApk` / `installedSignatures` / `apkSignatures` 都因此明文
# 可读，等于把签名闸门的实现细节白送给逆向者。通道分发走
# `when (call.method)` 的**字符串比较**（MainActivity.kt:31-40），方法名是纯
# 内部符号，R8 改写它不影响任何运行期行为。
-keep,allowoptimization class com.poemath.app.MainActivity
-keepclassmembers class com.poemath.app.MainActivity {
    <init>(...);   # Android 框架按无参构造实例化 Activity
}

# ---------------------------------------------------------------------------
# 依赖反射 / 平台入口的插件（仅列实际使用的）
# ---------------------------------------------------------------------------

# flutter_local_notifications —— 通过 Gson 反序列化「已排定通知」的持久化记录，
# 依赖字段名与类名不被改写（scheduled_notifications.json 的运行时恢复路径）。
# gson 保留整个包：注解属性已在上面统一保留，此处无需再叠一层
# `@SerializedName` 字段规则 —— 全保留与精细保留二选一，同时写会互相覆盖。
-keep class com.dexterous.** { *; }
-keep class com.google.gson.** { *; }

# file_picker —— 插件在 android 侧通过反射构造 FilePickerPlugin 回调，
# 并保留与被选取文件类型相关的常量字段。
-keep class com.mr.flutter.plugin.filepicker.** { *; }

# share_plus —— 通过 FileProvider authority 与 Intent 传递 content:// URI，
# 插件内 ThumbnailProvider/FileProvider 子类由 manifest 按类名声明。
-keep class dev.fluttercommunity.plus.share.** { *; }

# record（语音识别音频采集）—— AudioRecord 相关插件类在 manifest 中按类名
# 声明为前台服务，混淆后服务无法启动。
-keep class com.llfbandit.record.** { *; }

# package_info_plus —— 通过 PackageManager 与嵌入层回调读取版本信息。
-keep class dev.fluttercommunity.plus.packageinfo.** { *; }

# path_provider / flutter_secure_storage / flutter_tts / audioplayers
# 均通过 MethodChannel 直接调用，无反射入口，不需要 keep。

# ---------------------------------------------------------------------------
# AndroidX 与 Kotlin 运行时
# ---------------------------------------------------------------------------
# androidx.core 的 FileProvider 由 manifest 的 <provider> 按类名实例化；
# R8 默认保留 manifest 中声明的类，这里显式保留以防 manifest 合并后
# provider 被 shrinkResources 判为未引用。
-keep class androidx.core.content.FileProvider { *; }

# Kotlin 元数据（suspend 函数、默认参数合成桥接、协程挂起点）依赖
# @Metadata 注解；被剥离后 Kotlin 反射与部分协程路径会失败。
-keep class kotlin.Metadata { *; }
-keepattributes RuntimeVisibleParameterAnnotations

# ---------------------------------------------------------------------------
# 抑制无法解析的可选依赖警告
# ---------------------------------------------------------------------------
# 各插件对可选后端（如 gson 的部分扩展、Play Core 的动态交付）声明了
# compileOnly 依赖，R8 在打包时找不到对应类属预期情况。
-dontwarn com.google.gson.**
-dontwarn com.google.android.play.core.**
-dontwarn io.flutter.embedding.engine.deferredcomponents.**
