// lib/data/hive/hive_boxes.dart
//
// 层级：data/hive
// 职责：Box 打开与全局访问入口。
//       通过 HiveBoxes.init() 打开所有 Box，
//       通过 HiveBoxes.xxx 静态属性访问。

import 'package:hive/hive.dart';

import 'package:poemath/core/constants/hive_keys.dart';
import 'package:poemath/data/models/poem.dart';
import 'package:poemath/data/models/author.dart';
import 'package:poemath/data/models/formula.dart';
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

class HiveBoxes {
  const HiveBoxes._();

  // ============ 静态数据 Box ============
  static late Box<Poem> poems;
  static late Box<Author> authors;
  static late Box<Formula> formulas;

  // ============ 动态数据 Box ============
  static late Box<PoemProgress> poemProgress;
  static late Box<PoemFavorite> poemFavorites;
  static late Box<ReviewSchedule> reviewSchedules;
  static late Box<MathMistake> mathMistakes;
  static late Box<MathSession> mathSessions;
  static late Box<FormulaFavorite> formulaFavorites;
  static late Box<Achievement> achievements;
  static late Box<CheckIn> checkIns;
  static late Box<UserStats> userStats;
  static late Box<ChallengeRecord> challengeRecords;
  static late Box<LearningActivity> learningActivities;

  // ============ KV Box ============
  static late Box<dynamic> settings;
  static late Box<dynamic> meta;

  /// 打开所有 Box。必须在 registerHiveAdapters() 之后调用。
  static Future<void> init() async {
    // 静态数据
    poems = await Hive.openBox<Poem>(HiveKeys.poemBox);
    authors = await Hive.openBox<Author>(HiveKeys.authorBox);
    formulas = await Hive.openBox<Formula>(HiveKeys.formulaBox);

    // 动态数据
    poemProgress = await Hive.openBox<PoemProgress>(HiveKeys.progressBox);
    poemFavorites = await Hive.openBox<PoemFavorite>(HiveKeys.poemFavoriteBox);
    reviewSchedules = await Hive.openBox<ReviewSchedule>(HiveKeys.reviewBox);
    mathMistakes = await Hive.openBox<MathMistake>(HiveKeys.mistakeBox);
    mathSessions = await Hive.openBox<MathSession>(HiveKeys.mathSessionBox);
    formulaFavorites =
        await Hive.openBox<FormulaFavorite>(HiveKeys.formulaFavoriteBox);
    achievements = await Hive.openBox<Achievement>(HiveKeys.achievementBox);
    checkIns = await Hive.openBox<CheckIn>(HiveKeys.checkInBox);
    userStats = await Hive.openBox<UserStats>(HiveKeys.userStatsBox);
    challengeRecords =
        await Hive.openBox<ChallengeRecord>(HiveKeys.challengeRecordBox);
    learningActivities =
        await Hive.openBox<LearningActivity>(HiveKeys.learningActivityBox);

    // KV
    settings = await Hive.openBox(HiveKeys.settingsBox);
    meta = await Hive.openBox(HiveKeys.metaBox);
  }

  /// 关闭所有 Box（通常在 App 退出时调用）。
  static Future<void> close() async {
    await Hive.close();
  }
}
