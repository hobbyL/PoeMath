// lib/core/services/update/update_models.dart
//
// 层级：core/services/update
// 职责：应用版本信息与更新描述模型，及更新链路共享的
//       校验/文案纯函数（UpdatePage 与更新弹窗共用）。

import 'package:poemath/core/services/update/android_update_installer.dart';
import 'package:poemath/core/services/update/update_client.dart';

/// 当前安装的应用版本信息（由 Android MethodChannel 返回）。
class AppVersionInfo {
  const AppVersionInfo({
    required this.packageName,
    required this.versionName,
    required this.versionCode,
  });

  final String packageName;
  final String versionName;
  final int versionCode;

  factory AppVersionInfo.fromMap(Map<dynamic, dynamic> map) {
    return AppVersionInfo(
      packageName: _stringOf(map['packageName']),
      versionName: _stringOf(map['versionName']),
      versionCode: _intOf(map['versionCode']),
    );
  }
}

/// 远程 release.json 中的更新描述信息。
class AppUpdateInfo {
  const AppUpdateInfo({
    required this.packageName,
    required this.versionName,
    required this.versionCode,
    required this.tagName,
    required this.channel,
    required this.apkUrl,
    required this.apkSha256,
    required this.apkSize,
    required this.mandatory,
    required this.notes,
  });

  final String packageName;
  final String versionName;
  final int versionCode;
  final String tagName;
  final String channel;
  final String apkUrl;
  final String apkSha256;
  final int apkSize;
  final bool mandatory;
  final String notes;

  factory AppUpdateInfo.fromJson(Map<String, dynamic> json) {
    return AppUpdateInfo(
      packageName: _stringOf(json['packageName']),
      versionName: _stringOf(json['versionName']),
      versionCode: _intOf(json['versionCode']),
      tagName: _stringOf(json['tagName']),
      channel: _stringOf(json['channel']),
      apkUrl: _stringOf(json['apkUrl']),
      apkSha256: _stringOf(json['apkSha256']).toLowerCase(),
      apkSize: _intOf(json['apkSize']),
      mandatory: _boolOf(json['mandatory']),
      notes: _stringOf(json['notes']),
    );
  }

  /// 是否比 [current] 版本更新。
  bool isNewerThan(AppVersionInfo current) {
    return packageName == current.packageName &&
        versionCode > current.versionCode;
  }
}

String _stringOf(Object? value) {
  if (value == null) return '';
  return value.toString().trim();
}

int _intOf(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value.trim()) ?? 0;
  return 0;
}

bool _boolOf(Object? value) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  if (value is String) {
    final text = value.trim().toLowerCase();
    return text == 'true' || text == '1' || text == 'yes';
  }
  return false;
}

/// `history.json` 中的一条历史版本记录。
///
/// 由发版 CI 从 git tag + commit 历史生成（见 `.github/workflows/
/// android-build.yml`），只含展示所需的最小字段。
class AppVersionHistoryEntry {
  const AppVersionHistoryEntry({
    required this.versionName,
    required this.versionCode,
    required this.tagName,
    required this.notes,
  });

  final String versionName;
  final int versionCode;
  final String tagName;

  /// 该版本面向用户的中文说明；可能为空（该版无面向用户的变更）。
  final String notes;

  factory AppVersionHistoryEntry.fromJson(Map<String, dynamic> json) {
    return AppVersionHistoryEntry(
      versionName: _stringOf(json['versionName']),
      versionCode: _intOf(json['versionCode']),
      tagName: _stringOf(json['tagName']),
      notes: _stringOf(json['notes']),
    );
  }
}

/// APK 元数据与远端/本地版本三方一致性校验；返回 null 表示通过。
String? apkCompatibilityError({
  required AppUpdateInfo latest,
  required AppVersionInfo current,
  required AppVersionInfo? apk,
}) {
  if (apk == null) return '无法读取安装包信息，已阻止安装。';
  if (apk.packageName != current.packageName) {
    return '安装包名 ${apk.packageName} 与当前应用 ${current.packageName} 不一致。';
  }
  if (apk.packageName != latest.packageName) {
    return '安装包名 ${apk.packageName} 与更新信息 ${latest.packageName} 不一致。';
  }
  if (apk.versionCode != latest.versionCode) {
    return '安装包版本号 ${apk.versionCode} 与更新信息 ${latest.versionCode} 不一致。';
  }
  if (apk.versionCode <= current.versionCode) {
    return '安装包版本不高于当前版本，已阻止安装。';
  }
  return null;
}

/// APK 签名指纹比对；返回 null 表示通过，否则返回面向用户的中文原因。
///
/// 信任锚是**当前已安装版本**的签名证书（原生侧动态读取，不写入源码常量），
/// 因为 `latest.json` 同时提供 `apkUrl` 与 `apkSha256` —— 单一更新源被劫持时
/// 两者可被一起替换，SHA256 校验形同虚设；签名证书是唯一的独立锚点。
///
/// 判据是**集合交集非空**而非全等：多签名者或 v1+v2+v3 混合签名时，只要存在
/// 至少一个共同的可信证书即认为同源，避免误拒正常更新。
///
/// 这是 Dart 侧的前置闸门（给用户明确原因）；原生 `installApk` 内部会再比对
/// 一次，通道可直接调用，故 Dart 侧判断不构成安全边界。
String? apkSignatureError({
  required List<String> installed,
  required List<String> incoming,
}) {
  if (installed.isEmpty || incoming.isEmpty) {
    return '无法读取签名信息，已阻止安装。';
  }
  final installedSet = installed.map((value) => value.toLowerCase()).toSet();
  final hasCommon = incoming
      .map((value) => value.toLowerCase())
      .any(installedSet.contains);
  if (!hasCommon) return '安装包签名与当前应用不一致，已阻止安装。';
  return null;
}

/// 异常 → 用户可见中文文案；无匹配时返回 [fallback]。
String friendlyUpdateError(Object error, {required String fallback}) {
  if (error is UpdateConfigurationException) {
    // message 非空 = 「配了但不合法」（如明文 HTTP 被拒），需原样透出；
    // 为空才是「完全没配」。
    final message = error.message?.trim();
    if (message != null && message.isNotEmpty) return message;
    return '当前安装包未配置更新检查地址。';
  }
  if (error is UpdateException) {
    if (error.statusCode == 404) return '更新信息不存在，请确认发布配置。';
    if (error.statusCode == 429) return '请求过于频繁，请稍后重试。';
    if ((error.statusCode ?? 0) >= 500) return '更新服务暂时不可用，请稍后重试。';
    if (error.message.isNotEmpty) return error.message;
  }
  if (error is UpdateInstallException) return error.message;
  return fallback;
}

// ---------- 更新说明清洗 ----------

/// 行首 markdown 标题标记（`#` ~ `######`）。
final RegExp _notesHeading = RegExp(r'^#{1,6}\s*');

/// 行首列表标记：`- ` / `* ` / `+ ` / `• ` / `1. ` / `1) ` / `1、`。
///
/// `.` 与 `)` 要求后随空格，避免把 `1.5 倍速` 当成序号列表；中文顿号写法
/// 惯例不带空格（`2、修复`），故 `、` 后空格可省。
final RegExp _notesBullet = RegExp(r'^(?:[-*+•]\s+|\d+[.)]\s+|\d+、\s*)');

/// 剥离标记后只剩孤立列表符号的行（如 `-` / `•` / `1.`），无实际内容。
final RegExp _notesBareMarker = RegExp(r'^([-*+•]|\d+[.、)])$');

/// 行内加粗标记 `**x**` / `__x__`（仅剥标记，保留文本）。
final RegExp _notesEmphasis = RegExp(r'\*\*|__');

/// 行内 markdown 链接 `[text](url)` → `text`。
final RegExp _notesLink = RegExp(r'\[([^\]]*)\]\([^)]*\)');

/// 更新说明 → 可逐行渲染的纯文本行。
///
/// `notes` 可能来自人工撰写的 GitHub Release body（markdown），弹窗不引入
/// markdown 渲染库，故在此做纯文本清洗：丢弃空行与 code fence 代码块、剥离
/// 标题与加粗标记、把各式列表前缀统一为 `• `，避免原样渲染出 `#` / `**` 残留。
///
/// 返回空列表表示「无可展示的更新内容」（调用方据此只提示有新版本）。
List<String> updateNotesLines(String raw) {
  final lines = <String>[];
  // code fence 整块丢弃（块内多为命令/代码示例，对用户无意义）；
  // 未闭合的围栏按 markdown 语义吞至结尾。
  var inFence = false;
  for (final rawLine in raw.split('\n')) {
    var line = rawLine.trim();
    if (line.startsWith('```') || line.startsWith('~~~')) {
      inFence = !inFence;
      continue;
    }
    if (inFence || line.isEmpty) continue;

    line = line.replaceAllMapped(_notesLink, (m) => m.group(1) ?? '');
    line = line.replaceAll(_notesEmphasis, '');
    line = line.replaceFirst(_notesHeading, '').trim();
    // 列表前缀统一为 `• `：标题行剥完井号后可能才暴露列表标记，故在其后处理。
    final bullet = _notesBullet.firstMatch(line);
    if (bullet != null) {
      final content = line.substring(bullet.end).trim();
      if (content.isEmpty) continue;
      line = '• $content';
    } else if (_notesBareMarker.hasMatch(line)) {
      continue;
    }

    if (line.isEmpty) continue;
    lines.add(line);
  }
  return lines;
}
