import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:poemath/core/theme/design_tokens.dart';
import 'package:poemath/core/widgets/learning_background_fields.dart';
import 'package:poemath/data/providers/repository_providers.dart';
import 'package:poemath/data/providers/provider_invalidation.dart';
import 'package:poemath/domain/math_entry_kind.dart';

class LearningBackgroundPage extends ConsumerStatefulWidget {
  const LearningBackgroundPage({super.key});

  @override
  ConsumerState<LearningBackgroundPage> createState() =>
      _LearningBackgroundPageState();
}

class _LearningBackgroundPageState
    extends ConsumerState<LearningBackgroundPage> {
  late int _grade;
  late String _semester;
  late Set<MathEntryKind> _kinds;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final settings = ref.read(settingsRepositoryProvider);
    _grade = settings.selectedGrade;
    _semester = settings.selectedSemester;
    _kinds = settings.mathEntryKinds;
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final settings = ref.read(settingsRepositoryProvider);
      await settings.setLearningBackground(_grade, _semester);
      await settings.setMathEntryKinds(_kinds);
      if (!mounted) return;
      invalidateLearningBackground(ref.invalidate);
      Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('学习背景保存失败，请重试')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('学习背景')),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(SpacingTokens.lg),
            children: [
              LearningBackgroundFields(
                grade: _grade,
                semester: _semester,
                onChanged: _saving
                    ? (grade, semester) {}
                    : (grade, semester) => setState(() {
                          _grade = grade;
                          _semester = semester;
                        }),
                kinds: _kinds,
                // 取消最后一项在组件内已被拦（空集合无意义）；此处仍做
                // 防御性判断，避免任何路径构造出空集合后写盘。
                onKindsChanged: _saving
                    ? (kinds) {}
                    : (kinds) {
                        if (kinds.isEmpty) return;
                        setState(() => _kinds = kinds);
                      },
              ),
              const SizedBox(height: SpacingTokens.lg),
              FilledButton(
                onPressed: _saving ? null : _save,
                child: Text(_saving ? '保存中…' : '保存学习背景'),
              ),
            ],
          ),
        ),
      );
}
