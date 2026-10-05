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

/// 异常 → 用户可见中文文案；无匹配时返回 [fallback]。
String friendlyUpdateError(Object error, {required String fallback}) {
  if (error is UpdateConfigurationException) return '当前安装包未配置更新检查地址。';
  if (error is UpdateException) {
    if (error.statusCode == 404) return '更新信息不存在，请确认发布配置。';
    if (error.statusCode == 429) return '请求过于频繁，请稍后重试。';
    if ((error.statusCode ?? 0) >= 500) return '更新服务暂时不可用，请稍后重试。';
    if (error.message.isNotEmpty) return error.message;
  }
  if (error is UpdateInstallException) return error.message;
  return fallback;
}
