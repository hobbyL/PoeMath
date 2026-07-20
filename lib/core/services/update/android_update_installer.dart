// lib/core/services/update/android_update_installer.dart
//
// 层级：core/services/update
// 职责：通过 MethodChannel 调用 Android 原生安装器。

import 'dart:io';

import 'package:flutter/services.dart';

import 'package:poemath/core/services/update/update_models.dart';

/// Android 原生安装异常。
class UpdateInstallException implements Exception {
  const UpdateInstallException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Android 应用安装器（MethodChannel 桥接）。
///
/// 仅在 Android 平台可用。提供以下功能：
/// - 获取当前应用版本信息
/// - 读取 APK 文件的版本信息
/// - 检查未知来源安装权限
/// - 调用系统安装器安装 APK
class AndroidUpdateInstaller {
  AndroidUpdateInstaller({
    MethodChannel channel = const MethodChannel('com.poemath.app/app_update'),
    bool? isAndroid,
  })  : _channel = channel,
        _isAndroid = isAndroid ?? Platform.isAndroid;

  final MethodChannel _channel;
  final bool _isAndroid;

  /// 当前平台是否支持应用内安装。
  bool get isSupported => _isAndroid;

  /// 获取当前安装的应用版本信息。
  Future<AppVersionInfo> getCurrentVersion() async {
    if (!isSupported) {
      throw const UpdateInstallException('当前平台不支持应用内安装更新');
    }
    final value = await _invokeRequired<Map<dynamic, dynamic>>('getAppVersion');
    return AppVersionInfo.fromMap(value);
  }

  /// 读取 APK 文件的版本信息。
  Future<AppVersionInfo?> inspectApk(String path) async {
    if (!isSupported) {
      throw const UpdateInstallException('当前平台不支持读取安装包信息');
    }
    final value = await _invokeNullable<Object>('inspectApk', {'path': path});
    if (value == null) return null;
    if (value is Map<dynamic, dynamic>) return AppVersionInfo.fromMap(value);
    throw const UpdateInstallException('安装包信息格式不正确');
  }

  /// 是否有安装未知来源应用的权限（Android 8+）。
  Future<bool> canRequestPackageInstalls() async {
    if (!isSupported) return false;
    return _invokeRequired<bool>('canRequestPackageInstalls');
  }

  /// 打开系统的安装权限设置页面。
  Future<void> openInstallPermissionSettings() async {
    if (!isSupported) {
      throw const UpdateInstallException('当前平台不支持安装权限设置');
    }
    await _invokeVoid('openInstallPermissionSettings');
  }

  /// 调用系统安装器安装 APK。
  Future<void> installApk(String path) async {
    if (!isSupported) {
      throw const UpdateInstallException('当前平台不支持应用内安装更新');
    }
    await _invokeVoid('installApk', {'path': path});
  }

  Future<T> _invokeRequired<T>(String method, [Object? arguments]) async {
    try {
      final value = await _channel.invokeMethod<T>(method, arguments);
      if (value == null) {
        throw const UpdateInstallException('Android 返回了空结果');
      }
      return value;
    } on PlatformException catch (error) {
      throw _installExceptionFromPlatform(error);
    }
  }

  Future<T?> _invokeNullable<T>(String method, [Object? arguments]) async {
    try {
      return await _channel.invokeMethod<T>(method, arguments);
    } on PlatformException catch (error) {
      throw _installExceptionFromPlatform(error);
    }
  }

  Future<void> _invokeVoid(String method, [Object? arguments]) async {
    try {
      await _channel.invokeMethod<void>(method, arguments);
    } on PlatformException catch (error) {
      throw _installExceptionFromPlatform(error);
    }
  }

  UpdateInstallException _installExceptionFromPlatform(
    PlatformException error,
  ) {
    final message = error.message;
    if (message != null && message.isNotEmpty) {
      return UpdateInstallException(message);
    }
    return UpdateInstallException(error.code);
  }
}
