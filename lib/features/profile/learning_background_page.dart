import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:poemath/core/theme/design_tokens.dart';
import 'package:poemath/core/widgets/learning_background_fields.dart';
import 'package:poemath/data/providers/repository_providers.dart';
import 'package:poemath/data/providers/provider_invalidation.dart';

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
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final settings = ref.read(settingsRepositoryProvider);
    _grade = settings.selectedGrade;
    _semester = settings.selectedSemester;
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await ref
          .read(settingsRepositoryProvider)
          .setLearningBackground(_grade, _semester);
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
