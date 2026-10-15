// test/features/provider_alias_consistency_test.dart
//
// 审计问题 13（C2）专项测试：`features/` 层曾各自再定义一份同类型的仓储
// Provider，与 `data/providers/repository_providers.dart` 的定义是**两个
// 不同实例**。测试里覆写其中一个，业务代码读另一个 —— 覆写看似生效实则
// 落空，测试因此可能在验证错误的对象。
//
// 别名化（`final a = b;`）后两个名字指向同一 Provider 实例，
// `overrideWith` 任一名都应被两条读取路径看到。

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:poemath/data/providers/repository_providers.dart';
import 'package:poemath/data/repositories/poem_progress_repository.dart';
import 'package:poemath/features/formula/providers/formula_providers.dart';
import 'package:poemath/features/math/providers/math_providers.dart';
import 'package:poemath/features/math/word_problem/word_problem_providers.dart';
import 'package:poemath/features/poem/providers/poem_providers.dart';

/// 返回值可辨认的假仓储，用于确认实际读到的是覆写后的实例。
class _FakePoemProgressRepo extends PoemProgressRepository {
  @override
  int get learnedCount => 4242;
}

void main() {
  group('仓储 Provider 别名指向同一实例', () {
    test('覆写数据层名，features 层别名读到覆写实例', () {
      final container = ProviderContainer(
        overrides: [
          poemProgressRepositoryProvider
              .overrideWith((ref) => _FakePoemProgressRepo()),
        ],
      );
      addTearDown(container.dispose);

      // 若二者是不同实例，这里会拿到真实仓储（learnedCount != 4242）。
      expect(container.read(poemProgressRepoProvider).learnedCount, 4242);
      expect(container.read(poemProgressRepositoryProvider).learnedCount, 4242);
    });

    test('覆写 features 层别名，数据层名同样生效（反向对称）', () {
      final container = ProviderContainer(
        overrides: [
          poemProgressRepoProvider
              .overrideWith((ref) => _FakePoemProgressRepo()),
        ],
      );
      addTearDown(container.dispose);

      expect(container.read(poemProgressRepositoryProvider).learnedCount, 4242);
      expect(container.read(poemProgressRepoProvider).learnedCount, 4242);
    });

    test('同一容器内两条路径是同一个实例', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(
        container.read(poemProgressRepositoryProvider),
        same(container.read(poemProgressRepoProvider)),
      );
      expect(
        container.read(poemRepositoryProvider),
        same(container.read(poemRepoProvider)),
      );
      expect(
        container.read(poemFavoriteRepositoryProvider),
        same(container.read(poemFavoriteRepoProvider)),
      );
      expect(
        container.read(reviewRepositoryProvider),
        same(container.read(reviewRepoProvider)),
      );
    });

    test('公式模块别名同样指向同一实例', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(
        container.read(formulaRepositoryProvider),
        same(container.read(formulaRepoProvider)),
      );
      expect(
        container.read(formulaFavoriteRepositoryProvider),
        same(container.read(formulaFavoriteRepoProvider)),
      );
    });

    test('口算模块别名同样指向同一实例', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(
        container.read(mathSessionRepositoryProvider),
        same(container.read(mathSessionRepoProvider)),
      );
      expect(
        container.read(mathMistakeRepositoryProvider),
        same(container.read(mathMistakeRepoProvider)),
      );
      expect(
        container.read(challengeRecordRepositoryProvider),
        same(container.read(challengeRecordRepoProvider)),
      );
    });

    test('应用题模块别名同样指向同一实例', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(
        container.read(llmProblemRepoDataProvider),
        same(container.read(llmProblemRepositoryProvider)),
      );
    });

    test('invalidate 别名即失效同一实例', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final before = container.read(poemProgressRepositoryProvider);
      container.invalidate(poemProgressRepoProvider);
      final after = container.read(poemProgressRepositoryProvider);

      expect(after, isNot(same(before)));
    });
  });
}
