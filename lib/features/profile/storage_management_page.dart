import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:poemath/core/services/cache_activity.dart';
import 'package:poemath/core/services/storage_management_service.dart';
import 'package:poemath/core/theme/spacing_tokens.dart';
import 'package:poemath/core/utils/format_bytes.dart';
import 'package:poemath/core/utils/logger.dart';
import 'package:poemath/core/utils/responsive_layout.dart';
import 'package:poemath/core/widgets/app_widgets.dart';
import 'package:poemath/core/widgets/parent_access_boundary.dart';
import 'package:poemath/features/profile/storage_management_provider.dart';
import 'package:poemath/features/textbook/providers/textbook_providers.dart';

class StorageManagementPage extends ConsumerStatefulWidget {
  const StorageManagementPage({super.key});

  @override
  ConsumerState<StorageManagementPage> createState() =>
      _StorageManagementPageState();
}

class _StorageManagementPageState extends ConsumerState<StorageManagementPage> {
  StorageCacheSnapshot? _snapshot;
  bool _loading = false;
  bool _loadFailed = false;
  StorageCacheKind? _busy;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _loadFailed = false;
    });
    try {
      final snapshot = await ref.read(storageManagementServiceProvider).scan();
      if (!mounted) return;
      setState(() => _snapshot = snapshot);
    } on Object catch (error, stackTrace) {
      AppLogger.e(
        '存储清单加载失败',
        tag: 'StorageManagement',
        error: error,
        stackTrace: stackTrace,
      );
      if (mounted) setState(() => _loadFailed = true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _clear(StorageCacheKind kind) async {
    if (_busy != null || _loading) return;
    setState(() => _busy = kind);
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialog) => AlertDialog(
          title: Text('清理${kind.label}？'),
          content: Text(kind.clearDescription),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialog, true),
              child: const Text('清理缓存'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
      assertParentAccess(context);
      await ref.read(storageManagementServiceProvider).clear(kind);
      if (!mounted) return;
      if (kind == StorageCacheKind.textbookContent) {
        ref.invalidate(textbookReadingContentProvider);
      }
      _showMessage('已清理${kind.label}');
      await _load();
    } on CacheInUseException {
      if (mounted) _showMessage('缓存正在使用，请在操作完成后重试');
    } on Object catch (error, stackTrace) {
      AppLogger.e(
        '缓存清理失败',
        tag: 'StorageManagement',
        error: error,
        stackTrace: stackTrace,
      );
      if (!mounted) return;
      _showMessage('清理未完成，请刷新后重试');
      await _load();
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final snapshot = _snapshot;
    final entries = snapshot?.entries ??
        [
          for (final kind in StorageCacheKind.values)
            if (kind != StorageCacheKind.legacySpeechModels)
              StorageCacheEntry(kind: kind),
        ];
    return Scaffold(
      appBar: AppBar(
        title: const Text('存储管理'),
        actions: [
          IconButton(
            tooltip: '刷新存储占用',
            onPressed: _loading || _busy != null ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: AnimatedPageBody(
          padding: const EdgeInsets.symmetric(
            horizontal: SpacingTokens.md,
            vertical: SpacingTokens.sm,
          ),
          children: [
            ColoredCard(
              color: theme.colorScheme.primary,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_loading) ...[
                    const Text('正在统计存储…'),
                    const SizedBox(height: SpacingTokens.sm),
                    const LinearProgressIndicator(),
                  ] else if (snapshot != null) ...[
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            '磁盘占用 ${formatBytes(snapshot.diskBytes)}',
                          ),
                        ),
                        const SizedBox(width: SpacingTokens.md),
                        Expanded(
                          child: Text(
                            '内存缓存 ${formatBytes(snapshot.memoryBytes)}',
                            textAlign: TextAlign.end,
                          ),
                        ),
                      ],
                    ),
                  ],
                  if (_loadFailed || snapshot?.hasErrors == true) ...[
                    const SizedBox(height: SpacingTokens.sm),
                    Text(
                      _loadFailed ? '暂时无法读取存储，请刷新重试。' : '部分存储暂时无法统计，以上为已统计占用。',
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: SpacingTokens.md),
            LayoutBuilder(
              builder: (context, constraints) {
                final fontSize = theme.textTheme.titleSmall?.fontSize;
                final textScale = fontSize == null
                    ? 1.0
                    : MediaQuery.textScalerOf(context).scale(fontSize) /
                        fontSize;
                return MasonryLayout(
                  columnCount: ResponsiveLayout.columns(
                    constraints.maxWidth /
                        textScale.clamp(1.0, double.infinity),
                  ),
                  gap: SpacingTokens.sm,
                  children: [
                    for (final entry in entries)
                      AppTile(
                        icon: entry.kind.icon,
                        iconColor: theme.colorScheme.primary,
                        title: entry.kind.label,
                        titleSuffix: _loading
                            ? '正在统计…'
                            : entry.usage == null
                                ? '统计失败，请刷新重试'
                                : '${entry.usage!.entries}${entry.kind.isMemory ? '项' : '个文件'} · ${formatBytes(entry.usage!.bytes)}',
                        titleSuffixInline: true,
                        subtitle: entry.kind.description,
                        trailing: entry.kind.canClear
                            ? Tooltip(
                                message: '清理${entry.kind.label}',
                                child: TextButton(
                                  style: TextButton.styleFrom(
                                    minimumSize: const Size(
                                      SpacingTokens.minTapTarget,
                                      SpacingTokens.minTapTarget,
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: SpacingTokens.xs,
                                    ),
                                    alignment: AlignmentDirectional.centerEnd,
                                  ),
                                  onPressed: _loading ||
                                          _busy != null ||
                                          entry.usage == null ||
                                          entry.usage!.entries == 0
                                      ? null
                                      : () => _clear(entry.kind),
                                  child:
                                      Text(_busy == entry.kind ? '清理中…' : '清理'),
                                ),
                              )
                            : null,
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

extension _StorageCacheLabels on StorageCacheKind {
  String get label => switch (this) {
        StorageCacheKind.textbookCovers => '教材封面',
        StorageCacheKind.textbookContent => '教材解析',
        StorageCacheKind.textbookAudio => '教材朗读',
        StorageCacheKind.cloudAudio => '云朗读',
        StorageCacheKind.images => '图片显示',
        StorageCacheKind.pictureStoryImages => '看图说话题图',
        StorageCacheKind.updates => '更新安装包',
        StorageCacheKind.pickers => '文件与图片选择',
        StorageCacheKind.sharing => '分享与导出临时文件',
        StorageCacheKind.systemTts => '系统朗读临时文件',
        StorageCacheKind.legacySpeechModels => '旧版语音模型',
      };

  IconData get icon => switch (this) {
        StorageCacheKind.textbookCovers ||
        StorageCacheKind.images ||
        StorageCacheKind.pictureStoryImages =>
          Icons.image_outlined,
        StorageCacheKind.textbookContent => Icons.menu_book_outlined,
        StorageCacheKind.textbookAudio ||
        StorageCacheKind.cloudAudio ||
        StorageCacheKind.systemTts =>
          Icons.volume_up_outlined,
        StorageCacheKind.updates => Icons.system_update_outlined,
        StorageCacheKind.pickers => Icons.folder_open_outlined,
        StorageCacheKind.sharing => Icons.ios_share_outlined,
        StorageCacheKind.legacySpeechModels => Icons.mic_none_outlined,
      };

  String get description => switch (this) {
        StorageCacheKind.textbookCovers => '原书首页生成的封面图片',
        StorageCacheKind.textbookContent => '目录、逐页文字与页面布局',
        StorageCacheKind.textbookAudio => '系统或云端生成的教材音频及校验文件',
        StorageCacheKind.cloudAudio => '本次使用中复用的云端朗读音频',
        StorageCacheKind.images => '用于加快图片显示的闲置解码图片',
        StorageCacheKind.pictureStoryImages => '删除题目时清理无引用题图，历史和草稿使用的图片会保留',
        StorageCacheKind.updates => '已下载的更新包及未完成副本',
        StorageCacheKind.pickers => '导入文件、相册选图和拍照的临时副本',
        StorageCacheKind.sharing => '分享产生的副本与导出临时文件',
        StorageCacheKind.systemTts => '系统语音合成留下的临时音频',
        StorageCacheKind.legacySpeechModels => '旧版本遗留的本地识别模型',
      };

  String get clearDescription => switch (this) {
        StorageCacheKind.textbookAudio ||
        StorageCacheKind.cloudAudio =>
          '清理后再次朗读会重新生成音频；使用云端生成时可能消耗云额度。教材和学习记录会保留。',
        StorageCacheKind.updates => '清理后需要重新下载更新安装包，当前应用版本会保留。',
        StorageCacheKind.pickers => '清理文件选择、相册和相机产生的临时副本，已导入的教材和题目配图会保留。',
        StorageCacheKind.sharing => '清理应用内的分享副本和导出临时文件，已另存的备份与本机备份快照会保留。',
        _ => '清理后再次使用会重新生成缓存，教材、题库、学习记录和设置会保留。',
      };
}
