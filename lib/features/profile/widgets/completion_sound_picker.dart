import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:poemath/core/services/sound_service.dart';
import 'package:poemath/core/theme/design_tokens.dart';
import 'package:poemath/core/utils/logger.dart';
import 'package:poemath/core/widgets/app_widgets.dart';
import 'package:poemath/data/providers/repository_providers.dart';
import 'package:poemath/domain/completion_sound.dart';

class CompletionSoundPicker extends ConsumerStatefulWidget {
  const CompletionSoundPicker({super.key, this.previewService});

  /// 试听使用独立播放器，关闭面板即释放；可注入以验证真实交互。
  final SoundService? previewService;

  @override
  ConsumerState<CompletionSoundPicker> createState() =>
      _CompletionSoundPickerState();
}

class _CompletionSoundPickerState extends ConsumerState<CompletionSoundPicker> {
  late final SoundService _preview;
  bool _saving = false;
  bool _startingPreview = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _preview = widget.previewService ??
        SoundService(ref.read(settingsRepositoryProvider));
  }

  @override
  void dispose() {
    _preview.dispose();
    super.dispose();
  }

  Future<void> _select(CompletionSound? sound) async {
    if (sound == null || _saving) return;
    final settings = ref.read(settingsRepositoryProvider);
    if (sound == settings.completionSound) return;
    // ProviderContainer 的寿命覆盖面板，关闭面板后保存完成仍刷新设置页。
    final container = ProviderScope.containerOf(context, listen: false);
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await settings.setCompletionSound(sound);
      container.invalidate(settingsRepositoryProvider);
    } on Object catch (error, stackTrace) {
      AppLogger.e(
        '完成提示音设置保存失败',
        tag: 'Settings',
        error: error,
        stackTrace: stackTrace,
      );
      if (mounted) setState(() => _error = '保存失败，请重试');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _listen(CompletionSound sound) async {
    if (_startingPreview) return;
    setState(() {
      _startingPreview = true;
      _error = null;
    });
    final success = await _preview.previewCompletion(sound);
    if (!mounted) return;
    setState(() {
      _startingPreview = false;
      if (!success) _error = '暂时无法试听，请重试';
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settings = ref.watch(settingsRepositoryProvider);
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(SpacingTokens.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '完成提示音',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: SpacingTokens.md),
            if (_error != null) ...[
              Text(
                _error!,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.error),
              ),
              const SizedBox(height: SpacingTokens.md),
            ],
            RadioGroup<CompletionSound>(
              groupValue: settings.completionSound,
              onChanged: _saving ? (_) {} : _select,
              child: Column(
                children: [
                  for (final sound in CompletionSound.values) ...[
                    AppTile(
                      iconColor: theme.colorScheme.tertiary,
                      title: sound.label,
                      subtitle: sound.description,
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Semantics(
                            label: '使用${sound.label}',
                            child: Radio<CompletionSound>(
                              value: sound,
                              enabled: !_saving,
                            ),
                          ),
                          IconButton(
                            tooltip: '试听${sound.label}',
                            onPressed:
                                _startingPreview ? null : () => _listen(sound),
                            icon: const Icon(Icons.play_arrow_rounded),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: SpacingTokens.sm),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
