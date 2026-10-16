import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/core/services/backup_service.dart';
import 'package:poemath/data/hive/hive_boxes.dart';
import 'package:poemath/data/hive/migrations/poem_identity_migration.dart';
import 'package:poemath/data/models/poem_progress.dart';
import 'package:poemath/data/models/poem_favorite.dart';
import 'package:poemath/data/models/review_schedule.dart';
import 'package:poemath/data/models/user_stats.dart';
import 'package:poemath/data/poem_identity.dart';
import 'package:poemath/data/repositories/poem_progress_repository.dart';
import 'package:poemath/data/repositories/poem_favorite_repository.dart';
import 'package:poemath/data/repositories/review_repository.dart';
import '../helpers/hive_test_helper.dart';

void main() {
  const alias = 'poem_exp_661';
  const canonical = 'poem_core_004';
  setUp(setUpHiveForTesting);
  tearDown(tearDownHiveForTesting);

  Future<void> seed() async {
    await HiveBoxes.poemProgress.put(
      'default_$canonical',
      PoemProgress(
        poemId: canonical,
        profileId: 'default',
        studyCount: 2,
        masteryLevel: 1,
        status: LearningStatus.learning,
        firstStudiedAt: DateTime(2025),
      ),
    );
    await HiveBoxes.poemProgress.put(
      'default_$alias',
      PoemProgress(
        poemId: alias,
        profileId: 'default',
        studyCount: 3,
        masteryLevel: 4,
        status: LearningStatus.reviewing,
        lastStudiedAt: DateTime(2026),
      ),
    );
    await HiveBoxes.poemProgress.put(
      'other_$alias',
      PoemProgress(poemId: alias, profileId: 'other', studyCount: 9),
    );
    await HiveBoxes.poemFavorites.put(
      'default_$alias',
      PoemFavorite(
        poemId: alias,
        profileId: 'default',
        createdAt: DateTime(2024),
      ),
    );
    await HiveBoxes.poemFavorites.put(
      'default_$canonical',
      PoemFavorite(
        poemId: canonical,
        profileId: 'default',
        createdAt: DateTime(2025),
      ),
    );
    await HiveBoxes.reviewSchedules.put(
      'default_$alias',
      ReviewSchedule(
        poemId: alias,
        profileId: 'default',
        currentRound: 2,
        nextReviewDate: DateTime(2027),
        lastReviewedAt: DateTime(2026),
        lastScore: 0.9,
      ),
    );
    await HiveBoxes.reviewSchedules.put(
      'default_$canonical',
      ReviewSchedule(
        poemId: canonical,
        profileId: 'default',
        currentRound: 1,
        nextReviewDate: DateTime(2025),
      ),
    );
    await HiveBoxes.userStats.put(
      'default',
      UserStats(profileId: 'default', poemsLearned: 2, totalStars: 20),
    );
  }

  test('同作品合并进度收藏复习，跨 profile 隔离且重复执行不累加', () async {
    await seed();
    await PoemIdentityMigration.run();
    await PoemIdentityMigration.run();
    final p = PoemProgressRepository().get(alias)!;
    expect(p.poemId, canonical);
    expect(p.studyCount, 5);
    expect(p.masteryLevel, 4);
    expect(p.status, LearningStatus.reviewing);
    expect(p.firstStudiedAt, DateTime(2025));
    expect(p.lastStudiedAt, DateTime(2026));
    expect(HiveBoxes.poemProgress.get('other_$canonical')!.studyCount, 9);
    expect(PoemFavoriteRepository().getAll().single.createdAt, DateTime(2024));
    final review = ReviewRepository().get(alias)!;
    expect(review.currentRound, 2);
    expect(review.nextReviewDate, DateTime(2027));
    expect(review.lastScore, 0.9);
    expect(HiveBoxes.userStats.get('default')!.poemsLearned, 1);
    expect(HiveBoxes.userStats.get('default')!.totalStars, 20);
    expect(await PoemFavoriteRepository().toggle(alias), false);
    expect(PoemFavoriteRepository().isFavorite(canonical), false);
  });

  test('目标已写入但别名未删除时，重放持久化计划不会再次累加', () async {
    await seed();
    final rows = HiveBoxes.poemProgress.values
        .where((p) => p.profileId == 'default')
        .map(PoemIdentity.progressMap)
        .toList();
    final result = PoemIdentity.merge('progress', rows).single;
    await HiveBoxes.meta.put(PoemIdentityMigration.pendingKey, {
      'kind': 'progress',
      'key': 'default_$canonical',
      'value': result,
      'delete': ['default_$alias'],
    });
    await HiveBoxes.poemProgress
        .put('default_$canonical', PoemIdentity.progress(result));
    await PoemIdentityMigration.run();
    expect(PoemProgressRepository().get(alias)!.studyCount, 5);
    expect(HiveBoxes.meta.containsKey(PoemIdentityMigration.pendingKey), false);
  });

  test('旧备份的双 ID 在恢复前合并，再次恢复仍为相同计数', () async {
    await seed();
    final backup = BackupService();
    final data = jsonDecode(await backup.exportToJson());
    final text = jsonEncode(data);
    await backup.restoreFromJson(text);
    await backup.restoreFromJson(text);
    expect(PoemProgressRepository().get(alias)!.studyCount, 5);
    expect(PoemFavoriteRepository().count, 1);
    expect(ReviewRepository().get(alias)!.currentRound, 2);
  });
}
