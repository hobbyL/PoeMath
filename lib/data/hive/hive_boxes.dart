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
import 'package:poemath/data/models/llm_problem.dart';
import 'package:poemath/data/models/assistant_conversation.dart';
import 'package:poemath/data/models/assistant_message.dart';

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
  static late Box<LlmProblem> llmProblems;
  static late Box<Conversation> conversations;
  static late Box<Message> messages;

  // ============ KV Box ============
  static late Box<dynamic> settings;
  static late Box<dynamic> meta;

  /// 打开所有 Box。必须在 registerHiveAdapters() 之后调用。
  ///
  /// [cipher] 为 **null 等价于不加密**，只用于测试
  /// （`test/helpers/hive_test_helper.dart` 等）。
  /// **生产路径必须传 cipher** —— 见 `database-guidelines.md` 的
  /// 「Hive 加密」一节；漏传会让全部用户数据以明文 JSON 落盘。
  ///
  /// 19 处 `openBox` 逐处显式写 `crashRecovery: false, encryptionCipher: cipher`，**故意不抽
  /// 辅助函数**：机械重复反而让「哪一个 box 漏加了 cipher」在 review 时
  /// 一眼可见；抽成 `open<T>(name)` 会把这种遗漏藏进一行里。
  static Future<void> init({HiveCipher? cipher}) async {
    // 静态数据
    poems = await Hive.openBox<Poem>(
      HiveKeys.poemBox,
      crashRecovery: false,
      encryptionCipher: cipher,
    );
    authors = await Hive.openBox<Author>(
      HiveKeys.authorBox,
      crashRecovery: false,
      encryptionCipher: cipher,
    );
    formulas = await Hive.openBox<Formula>(
      HiveKeys.formulaBox,
      crashRecovery: false,
      encryptionCipher: cipher,
    );

    // 动态数据
    poemProgress = await Hive.openBox<PoemProgress>(
      HiveKeys.progressBox,
      crashRecovery: false,
      encryptionCipher: cipher,
    );
    poemFavorites = await Hive.openBox<PoemFavorite>(
      HiveKeys.poemFavoriteBox,
      crashRecovery: false,
      encryptionCipher: cipher,
    );
    reviewSchedules = await Hive.openBox<ReviewSchedule>(
      HiveKeys.reviewBox,
      crashRecovery: false,
      encryptionCipher: cipher,
    );
    mathMistakes = await Hive.openBox<MathMistake>(
      HiveKeys.mistakeBox,
      crashRecovery: false,
      encryptionCipher: cipher,
    );
    mathSessions = await Hive.openBox<MathSession>(
      HiveKeys.mathSessionBox,
      crashRecovery: false,
      encryptionCipher: cipher,
    );
    formulaFavorites = await Hive.openBox<FormulaFavorite>(
      HiveKeys.formulaFavoriteBox,
      crashRecovery: false,
      encryptionCipher: cipher,
    );
    achievements = await Hive.openBox<Achievement>(
      HiveKeys.achievementBox,
      crashRecovery: false,
      encryptionCipher: cipher,
    );
    checkIns = await Hive.openBox<CheckIn>(
      HiveKeys.checkInBox,
      crashRecovery: false,
      encryptionCipher: cipher,
    );
    userStats = await Hive.openBox<UserStats>(
      HiveKeys.userStatsBox,
      crashRecovery: false,
      encryptionCipher: cipher,
    );
    challengeRecords = await Hive.openBox<ChallengeRecord>(
      HiveKeys.challengeRecordBox,
      crashRecovery: false,
      encryptionCipher: cipher,
    );
    learningActivities = await Hive.openBox<LearningActivity>(
      HiveKeys.learningActivityBox,
      crashRecovery: false,
      encryptionCipher: cipher,
    );
    llmProblems = await Hive.openBox<LlmProblem>(
      HiveKeys.llmProblemBox,
      crashRecovery: false,
      encryptionCipher: cipher,
    );
    conversations = await Hive.openBox<Conversation>(
      HiveKeys.conversationBox,
      crashRecovery: false,
      encryptionCipher: cipher,
    );
    messages = await Hive.openBox<Message>(
      HiveKeys.messageBox,
      crashRecovery: false,
      encryptionCipher: cipher,
    );

    // KV
    settings = await Hive.openBox(
      HiveKeys.settingsBox,
      crashRecovery: false,
      encryptionCipher: cipher,
    );
    meta = await Hive.openBox(
      HiveKeys.metaBox,
      crashRecovery: false,
      encryptionCipher: cipher,
    );
  }

  /// 关闭所有 Box（通常在 App 退出时调用）。
  static Future<void> close() async {
    await Hive.close();
  }
}
