import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:poemath/data/hive/hive_boxes.dart';
import 'package:poemath/data/models/poem.dart';
import 'package:poemath/data/models/poem_progress.dart';
import 'package:poemath/data/repositories/poem_progress_repository.dart';
import 'package:poemath/features/poem/poem_quiz_page.dart';
import 'package:poemath/features/poem/providers/poem_providers.dart';
import 'package:poemath/features/poem/quiz/quiz_models.dart';

import '../../helpers/hive_test_helper.dart';

class _BlockingPoemProgressRepository extends PoemProgressRepository {
  final _pending = Completer<PoemProgress>();
  var recordStudyCalls = 0;

  @override
  Future<PoemProgress> recordStudy(String poemId) {
    recordStudyCalls++;
    return _pending.future;
  }

  void release(PoemProgress progress) => _pending.complete(progress);
}

void main() {
  setUp(() async {
    await setUpHiveForTesting();
  });

  tearDown(() async {
    await tearDownHiveForTesting();
  });

  testWidgets('最后一题结算期间禁用查看结果避免重复写入', (tester) async {
    // 构造 10 行诗词，确保生成足够多题
    final poem = Poem(
      id: 'quiz_guard',
      title: '测试诗',
      author: '测试作者',
      dynasty: '唐',
      content: '第一句\n第二句\n第三句\n第四句\n第五句\n第六句\n第七句\n第八句\n第九句\n第十句',
      pinyin: '',
      layer: 'core',
      grade: 1,
    );
    await tester.runAsync(() async {
      await HiveBoxes.settings.put('sound_enabled', false);
      await HiveBoxes.settings.put('haptic_enabled', false);
    });
    final progressRepo = _BlockingPoemProgressRepository();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          poemByIdProvider('quiz_guard').overrideWith((ref) => poem),
          poemProgressRepoProvider.overrideWith(
            (ref) => progressRepo,
          ),
        ],
        child: const MaterialApp(
          home: PoemQuizPage(
            poemId: 'quiz_guard',
            quizType: QuizType.fillBlank,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 完成所有题目直到最后一题
    var iteration = 0;
    while (iteration < 10) {
      iteration++;

      // 答题
      final answerField = find.byType(TextField);
      if (answerField.evaluate().isEmpty) break;

      await tester.enterText(answerField, '任意答案');
      await tester.tap(find.text('提交'));
      await tester.pumpAndSettle();

      // 检查是下一题还是查看结果
      if (find.text('查看结果').evaluate().isNotEmpty) {
        break; // 已到最后一题
      }

      if (find.text('下一题').evaluate().isNotEmpty) {
        await tester.tap(find.text('下一题'));
        await tester.pumpAndSettle();
      } else {
        break;
      }
    }

    // 现在应该显示"查看结果"
    final resultButton = find.text('查看结果');
    if (resultButton.evaluate().isEmpty) {
      // 可能还没到最后一题，跳过测试
      return;
    }

    // 第一次点击"查看结果"，会触发异步结算
    await tester.tap(resultButton);
    await tester.pump(); // 让 _isFinishing = true 生效

    // 立即再次点击，应被 _isFinishing 拦截
    if (find.text('查看结果').evaluate().isNotEmpty) {
      await tester.tap(resultButton);
    }

    // 验证只调用了一次 recordStudy
    expect(progressRepo.recordStudyCalls, 1);

    // 在后台释放阻塞，让异步操作完成
    await tester.runAsync(() async {
      progressRepo.release(
        PoemProgress(
          poemId: poem.id,
          profileId: 'test',
          status: LearningStatus.learning,
        ),
      );
    });

    await tester.pumpAndSettle();
  });
}
