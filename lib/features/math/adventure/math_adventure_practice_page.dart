import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:poemath/core/utils/profile_scope.dart';
import 'package:poemath/domain/math_adventure_catalog.dart';
import 'package:poemath/features/math/math_practice_page.dart';
import 'package:poemath/features/math/providers/math_providers.dart';
import 'package:poemath/math_engine/math_engine_api.dart';

/// 每条路由拥有独立答题状态，弹出后不会覆盖背后的普通练习。
class MathAdventurePracticePage extends StatelessWidget {
  const MathAdventurePracticePage({
    super.key,
    required this.node,
    this.resume = false,
    this.fromMap = false,
  });
  final MathAdventureNode node;
  final bool resume;
  final bool fromMap;
  @override
  Widget build(BuildContext context) => ProviderScope(
    key: ValueKey('${ProfileScope.currentId}:${node.scope}'),
    overrides: [
      mathProblemsProvider.overrideWith((ref) => <MathProblem>[]),
      mathCurrentIndexProvider.overrideWith((ref) => 0),
      mathCorrectCountProvider.overrideWith((ref) => 0),
      mathAnsweredCountProvider.overrideWith((ref) => 0),
      currentProblemProvider.overrideWith((ref) {
        final problems = ref.watch(mathProblemsProvider);
        final index = ref.watch(mathCurrentIndexProvider);
        return index >= 0 && index < problems.length ? problems[index] : null;
      }),
    ],
    child: MathPracticePage(
      adventureNode: node,
      resume: resume,
      fromMap: fromMap,
    ),
  );
}
