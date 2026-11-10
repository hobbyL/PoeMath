import 'dart:io';

/// Dart IO 的 DNS 错误前缀固定；只分类，不向日志/UI 传递可能含域名的原文。
bool isHostLookupFailure(SocketException error) =>
    error.message.startsWith('Failed host lookup:');
