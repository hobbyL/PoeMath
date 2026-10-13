// lib/features/profile/widgets/sync_conflict_dialog.dart
//
// 层级：features/profile/widgets
// 职责：跨设备同步覆盖确认框。
//       云端备份顶层带 exportedAt（导出时刻），本机记录上次成功同步时刻。
//       两者比对可判断「云端是否在本机之后被其他设备写过」——
//       直接覆盖会让对方的新数据消失，因此必须先让用户知情。
//
// 两个方向共用本组件：
//   - 下载：云端比本机新 → 覆盖本地会丢本机进度；
//   - 上传：本机比云端新 → 覆盖云端会丢云端进度。
//       措辞与按钮文案由 [SyncConflictDirection] 决定。

import 'package:flutter/material.dart';

import 'package:poemath/core/theme/design_tokens.dart';

/// 覆盖方向：决定文案指向「会被覆盖的一方」。
enum SyncConflictDirection {
  /// 从云端下载：本地当前数据将被云端备份覆盖。
  download,

  /// 上传到云端：云端现有备份将被本机数据覆盖。
  upload,
}

/// 展示时间线差异并请用户确认覆盖。
///
/// 返回约定：`true` = 用户确认继续；`false` / `null` = 取消
/// （调用方须中止操作，保证两端数据零变更）。
Future<bool?> showSyncConflictDialog(
  BuildContext context, {
  required SyncConflictDirection direction,
  required DateTime remoteExportedAt,
  required DateTime localSyncedAt,
}) {
  return showDialog<bool>(
    context: context,
    builder: (_) => _SyncConflictDialog(
      direction: direction,
      remoteExportedAt: remoteExportedAt,
      localSyncedAt: localSyncedAt,
    ),
  );
}

class _SyncConflictDialog extends StatelessWidget {
  const _SyncConflictDialog({
    required this.direction,
    required this.remoteExportedAt,
    required this.localSyncedAt,
  });

  final SyncConflictDirection direction;
  final DateTime remoteExportedAt;
  final DateTime localSyncedAt;

  bool get _isDownload => direction == SyncConflictDirection.download;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('⚠️ 云端数据比本机新'),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _isDownload
                  ? '云端备份由其他设备更新过，比本机上次同步的时间更晚。'
                      '继续下载会用云端数据覆盖本机，本机上的学习记录将丢失。'
                  : '本机数据比云端备份更新。继续上传会用本机数据覆盖云端，'
                      '其他设备上次同步的内容将丢失。',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: SpacingTokens.lg),
            _TimestampRow(
              label: _isDownload ? '云端备份时间' : '本机数据时间',
              value: remoteExportedAt,
              color: theme.colorScheme.error,
            ),
            const SizedBox(height: SpacingTokens.xs),
            _TimestampRow(
              label: _isDownload ? '本机上次同步' : '云端备份时间',
              value: localSyncedAt,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: SpacingTokens.lg),
            Text(
              '若你不确定哪一份是最新的，请先取消，确认另一台设备的状态后再操作。',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          style: FilledButton.styleFrom(
            backgroundColor: theme.colorScheme.error,
          ),
          child: Text(_isDownload ? '仍然下载覆盖' : '仍然上传覆盖'),
        ),
      ],
    );
  }
}

/// 时间行：标签 + `yyyy-MM-dd HH:mm` 本地时间。
class _TimestampRow extends StatelessWidget {
  const _TimestampRow({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final DateTime value;
  final Color color;

  /// 只展示到分钟：秒级差异对用户无意义，反而增加阅读负担。
  static String _format(DateTime time) {
    final local = time.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodyMedium;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          // 固定标签列宽，让两个时间左对齐便于比对。
          width: 96,
          child: Text(
            '$label：',
            style: style?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Expanded(
          child: Text(
            _format(value),
            style: style?.copyWith(color: color, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}
