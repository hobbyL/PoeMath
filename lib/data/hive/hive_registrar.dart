// lib/data/hive/hive_registrar.dart
//
// 层级：data/hive
// 职责：注册所有 Hive TypeAdapter。
//       在 Hive.initFlutter() 后、打开 Box 前调用。

import 'package:hive/hive.dart';

import 'package:poemath/data/models/poem.dart';
import 'package:poemath/data/models/poem_annotation.dart';
import 'package:poemath/data/models/author.dart';
import 'package:poemath/data/models/formula.dart';
import 'package:poemath/data/models/formula_param.dart';
import 'package:poemath/data/models/poem_progress.dart';
import 'package:poemath/data/models/poem_favorite.dart';
import 'package:poemath/data/models/review_schedule.dart';
import 'package:poemath/data/models/math_mistake.dart';
import 'package:poemath/data/models/math_session.dart';
import 'package:poemath/data/models/formula_favorite.dart';
import 'package:poemath/data/models/achievement.dart';
import 'package:poemath/data/models/check_in.dart';
import 'package:poemath/data/models/user_stats.dart';
import 'package:poemath/data/models/challenge_record.dart';

bool _adaptersRegistered = false;

/// 注册所有 Hive TypeAdapter（幂等：仅首次调用生效）。
void registerHiveAdapters() {
  if (_adaptersRegistered) return;
  _adaptersRegistered = true;
  // 静态数据模型
  Hive.registerAdapter(PoemAdapter());               // typeId: 0
  Hive.registerAdapter(AuthorAdapter());              // typeId: 1
  Hive.registerAdapter(FormulaAdapter());             // typeId: 2
  Hive.registerAdapter(PoemAnnotationAdapter());      // typeId: 3
  Hive.registerAdapter(FormulaParamAdapter());        // typeId: 4

  // 动态数据模型
  Hive.registerAdapter(PoemProgressAdapter());        // typeId: 5
  Hive.registerAdapter(PoemFavoriteAdapter());        // typeId: 6
  Hive.registerAdapter(ReviewScheduleAdapter());      // typeId: 7
  Hive.registerAdapter(MathMistakeAdapter());         // typeId: 8
  Hive.registerAdapter(MathSessionAdapter());         // typeId: 9
  Hive.registerAdapter(FormulaFavoriteAdapter());     // typeId: 10
  Hive.registerAdapter(AchievementAdapter());         // typeId: 11
  Hive.registerAdapter(CheckInAdapter());             // typeId: 12
  Hive.registerAdapter(UserStatsAdapter());           // typeId: 13
  Hive.registerAdapter(ChallengeRecordAdapter());     // typeId: 14

  // 枚举 Adapter
  Hive.registerAdapter(LearningStatusAdapter());      // typeId: 20
}
