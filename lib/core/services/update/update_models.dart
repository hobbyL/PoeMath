// lib/core/services/update/update_models.dart
//
// 层级：core/services/update
// 职责：应用版本信息与更新描述模型。

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
