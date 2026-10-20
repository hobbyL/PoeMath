// lib/data/hive/hive_registrar.dart
//
// 层级：data/hive
// 职责：注册所有 Hive TypeAdapter。
//       在 Hive.initFlutter() 后、打开 Box 前调用。

import 'package:hive/hive.dart';
import 'package:poemath/data/hive/hive_value_snapshot.dart';

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
import 'package:poemath/data/models/learning_activity.dart';
import 'package:poemath/data/models/llm_problem.dart';
import 'package:poemath/data/models/assistant_conversation.dart';
import 'package:poemath/data/models/assistant_message.dart';

bool _adaptersRegistered = false;

/// 注册所有 Hive TypeAdapter（幂等：仅首次调用生效）。
void registerHiveAdapters() {
  if (_adaptersRegistered) return;
  _adaptersRegistered = true;
  // 静态数据模型
  _register(PoemAdapter()); // typeId: 0
  _register(AuthorAdapter()); // typeId: 1
  _register(FormulaAdapter()); // typeId: 2
  _register(PoemAnnotationAdapter()); // typeId: 3
  _register(FormulaParamAdapter()); // typeId: 4

  // 动态数据模型
  _register(PoemProgressAdapter()); // typeId: 5
  _register(PoemFavoriteAdapter()); // typeId: 6
  _register(ReviewScheduleAdapter()); // typeId: 7
  _register(MathMistakeAdapter()); // typeId: 8
  _register(MathSessionAdapter()); // typeId: 9
  _register(FormulaFavoriteAdapter()); // typeId: 10
  _register(AchievementAdapter()); // typeId: 11
  _register(CheckInAdapter()); // typeId: 12
  _register(UserStatsAdapter()); // typeId: 13
  _register(ChallengeRecordAdapter()); // typeId: 14
  _register(LearningActivityAdapter()); // typeId: 15
  _register(LlmProblemAdapter()); // typeId: 16
  _register(ConversationAdapter()); // typeId: 17
  _register(MessageAdapter()); // typeId: 18

  // 枚举 Adapter
  _register(LearningStatusAdapter()); // typeId: 20
  _register(MessageRoleAdapter()); // typeId: 19
}

void _register<T>(TypeAdapter<T> adapter) {
  Hive.registerAdapter<T>(adapter);
  HiveValueSnapshot.registerAdapter<T>(adapter);
}
