// lib/core/services/backup_service.dart
//
// 层级：core/services
// 职责：数据备份与恢复服务。
//       导出所有用户动态数据为 JSON，或从 JSON 恢复。
//       静态数据（诗词、作者、公式）由 asset 加载，不参与备份。

import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'package:poemath/data/hive/hive_boxes.dart';
import 'package:poemath/data/models/achievement.dart';
import 'package:poemath/data/models/check_in.dart';
import 'package:poemath/data/models/formula_favorite.dart';
import 'package:poemath/data/models/math_mistake.dart';
import 'package:poemath/data/models/math_session.dart';
import 'package:poemath/data/models/learning_activity.dart';
import 'package:poemath/data/models/llm_problem.dart';
import 'package:poemath/data/models/llm_provider_config.dart';
import 'package:poemath/data/models/poem_favorite.dart';
import 'package:poemath/data/models/poem_progress.dart';
import 'package:poemath/data/models/review_schedule.dart';
import 'package:poemath/data/models/user_stats.dart';
import 'package:poemath/data/models/challenge_record.dart';
import 'package:poemath/data/repositories/activity_settlement_ledger.dart';
import 'package:poemath/domain/learning_reward_calculator.dart';
import 'package:poemath/core/services/backup_credentials_cipher.dart';
import 'package:poemath/core/services/secure_credential_store.dart';
import 'package:poemath/core/services/speech/speech_recognition_models.dart';
import 'package:poemath/math_engine/math_engine_api.dart';
import 'package:poemath/math_engine/validators/expression_evaluator.dart';

/// 备份数据版本号，用于兼容性检查。
const int _backupVersion = 1;

/// 允许随备份迁移的 settings key 及其类型契约（key → 期望类型标签）。
///
/// 导出只写白名单内的 key；恢复只删/写白名单内的 key，白名单外一律跳过、
/// 类型不符跳过该 key（不毁整个恢复）。恢复不再 `box.clear()`：本机的
/// 排除 key（如 webdav_configs）原值保留，防止攻击者借恶意备份清空设备配置。
///
/// 排除项及理由（设备绑定、换机重配，与凭据不随备份明文迁移的既有设计一致）：
/// - webdav_configs / llm_providers / llm_active_provider_id /
///   llm_base_url / llm_model / tts_cloud_base_url /
///   tts_cloud_enabled / tts_cloud_voice / tts_cloud_style：
///   指向外部服务的端点或开关（llm_providers 含 baseUrl/model，
///   llm_active_provider_id 依赖其存在），注入即成为凭据外泄端点（P1）；
/// - llm_provider_word_problem / llm_provider_poem_explain /
///   llm_provider_math_explain：场景级厂商绑定（LlmScenario.settingsKey），
///   值为 llm_providers 条目 id，跨机迁移必然悬空；
/// - tencent_asr_credential_fingerprint / tencent_asr_verified_at /
///   worker_tts_verified_fingerprint：与凭据绑定的验证状态，凭据不随备份
///   走，指纹/时间戳单独迁移会误导验证状态。
///
/// 新增 settings key 时必须同步登记本白名单（并注明类型），否则不会随备份迁移。
const Map<String, String> _settingsValueType = <String, String>{
  'theme_mode': 'string', // 外观模式 system/light/dark
  'active_subject': 'string', // 当前主题 poem/math
  'sound_enabled': 'bool', // 音效开关
  'haptic_enabled': 'bool', // 触觉反馈开关
  'selected_grade': 'int', // 选中年级
  'tts_speed': 'double', // TTS 语速
  'tts_voice': 'string', // TTS 音色 JSON 字符串
  'pinyin_visible': 'bool', // 拼音显示开关
  'daily_poem_goal': 'int', // 每日诗词背诵目标
  'daily_math_goal': 'int', // 每日口算做题目标
  'math_batch_size': 'int', // 每组题目数量
  'math_difficulty': 'string', // 练习难度 easy/medium/hard
  'math_practice_mode': 'string', // 练习模式（综合或 ProblemMode.name）
  'llm_provider_name': 'string', // LLM 供应商名称（纯展示，非敏感）
  'has_onboarded': 'bool', // 是否完成引导
  // 通知设置（notification_service 直读写，随备份迁移，见其 key 常量区）。
  'reminder_enabled': 'bool', // 每日提醒开关
  'reminder_hour': 'int', // 每日提醒小时（24h 制）
  'reminder_minute': 'int', // 每日提醒分钟
  'weekly_report_enabled': 'bool', // 周报开关
  // AI 讲解提示词用户覆盖（纯文本、非凭据、不指向外部服务，随备份迁移
  // 换机不丢；与设备绑定的 llm_providers / 场景绑定 key 不同类）。
  'llm_poem_explain_prompt': 'string', // 诗词讲解 system prompt 覆盖
  'llm_math_explain_prompt': 'string', // 口算解析 system prompt 覆盖
  'llm_assistant_prompt': 'string', // AI 助手 system prompt 覆盖
};

class BackupService {
  BackupService({SecureCredentialStore? secureStore})
      : _secureStore = secureStore ?? SecureCredentialStore();

  final SecureCredentialStore _secureStore;

  /// 导出所有用户数据为 JSON 字符串。
  ///
  /// [passphrase] 非空且安全存储中存在凭据时，凭据以
  /// PBKDF2 + AES-256-GCM 加密写入 `credentials` 节；否则省略该节。
  Future<String> exportToJson({String? passphrase}) async {
    final data = <String, dynamic>{
      'version': _backupVersion,
      'exportedAt': DateTime.now().toIso8601String(),
      'poemProgress': _exportPoemProgress(),
      'poemFavorites': _exportPoemFavorites(),
      'reviewSchedules': _exportReviewSchedules(),
      'mathMistakes': _exportMathMistakes(),
      'mathSessions': _exportMathSessions(),
      'formulaFavorites': _exportFormulaFavorites(),
      'achievements': _exportAchievements(),
      'checkIns': _exportCheckIns(),
      'userStats': _exportUserStats(),
      'challengeRecords': _exportChallengeRecords(),
      'learningActivities': _exportLearningActivities(),
      'llmProblems': _exportLlmProblems(),
      'activitySettlements': ActivitySettlementLedger.completedKeys,
      'settings': _exportSettings(),
    };
    final credentials = await _exportCredentials(passphrase);
    if (credentials != null) {
      data['credentials'] = credentials;
    }
    return const JsonEncoder.withIndent('  ').convert(data);
  }

  /// 读取安全存储凭据并加密；无口令、无凭据或读取失败时返回 `null`
  /// （导出静默降级为不含凭据节）。
  Future<Map<String, dynamic>?> _exportCredentials(String? passphrase) async {
    final normalized = passphrase?.trim() ?? '';
    if (normalized.isEmpty) return null;
    try {
      final payload = <String, String>{};
      final tencent = await _secureStore.readTencentAsrCredentials();
      if (tencent != null) {
        payload['tencent_asr_secret_id'] = tencent.secretId;
        payload['tencent_asr_secret_key'] = tencent.secretKey;
      }
      final workerApiKey = await _secureStore.readWorkerTtsApiKey();
      if (workerApiKey != null && workerApiKey.isNotEmpty) {
        payload['worker_tts_api_key'] = workerApiKey;
      }
      final llmApiKey = await _readActiveLlmApiKey();
      if (llmApiKey != null && llmApiKey.isNotEmpty) {
        payload['llm_api_key'] = llmApiKey;
        // 归属提示（host|model，非敏感）：恢复端凭它在本机 llm_providers
        // 中找回 key 的归属配置，防止导出后本机切换 active 导致 key 写
        // 进错误槽位。只进加密凭据节，明文备份任何位置不得出现。
        payload['llm_api_key_hint'] = _activeLlmKeyHint();
      }
      if (payload.isEmpty) return null;
      return await encryptCredentials(payload, normalized);
    } on Object {
      return null;
    }
  }

  /// 导出并保存到临时文件，返回文件路径。
  Future<String> exportToFile({String? passphrase}) async {
    final json = await exportToJson(passphrase: passphrase);
    final dir = await getTemporaryDirectory();
    final timestamp =
        DateTime.now().toIso8601String().replaceAll(':', '-').split('.').first;
    final file = File('${dir.path}/poemath_backup_$timestamp.json');
    await file.writeAsString(json);
    return file.path;
  }

  /// 探测备份 JSON 是否含 `credentials` 节（决定导入/下载前是否弹口令框）。
  static bool jsonHasCredentials(String jsonString) {
    try {
      final decoded = jsonDecode(jsonString);
      return decoded is Map && decoded.containsKey('credentials');
    } on FormatException {
      return false;
    }
  }

  /// 从 JSON 字符串恢复数据。
  ///
  /// 返回恢复的记录总数。
  /// 如果版本不兼容，抛出 [FormatException]。
  /// 备份含 `credentials` 节时：口令留空跳过凭据、口令错误在写入前
  /// 抛 [FormatException]，均不影响其余数据；口令正确则在末尾把凭据
  /// 写入安全存储。
  /// 恢复失败时自动回滚到恢复前的数据状态（回滚只还原 Hive 数据，
  /// 不触碰安全存储）。
  Future<int> restoreFromJson(String jsonString, {String? passphrase}) async {
    final data = _decodeAndValidate(jsonString);

    // 凭据解密在快照与任何写入之前完成：口令错误时数据零变更。
    Map<String, String>? plainCredentials;
    if (data.containsKey('credentials')) {
      final normalized = passphrase?.trim() ?? '';
      if (normalized.isNotEmpty) {
        plainCredentials = await decryptCredentials(
          data['credentials'] as Map<String, dynamic>,
          normalized,
        );
      }
    }

    // 恢复前先快照当前数据（不含凭据节），失败时用于回滚
    final snapshot = await exportToJson();

    try {
      final count = await _doRestore(data);
      if (plainCredentials != null) {
        await _restoreCredentials(plainCredentials);
      }
      return count;
    } on Object catch (error, stackTrace) {
      // 恢复失败，回滚到快照
      try {
        final rollback = _decodeAndValidate(snapshot);
        await _doRestore(rollback);
      } on Object catch (rollbackError) {
        throw BackupRestoreException(
          '恢复失败，且回滚失败，请检查数据完整性',
          cause: error,
          rollbackError: rollbackError,
        );
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  /// 把解密后的凭据写入安全存储（覆盖式）。
  Future<void> _restoreCredentials(Map<String, String> credentials) async {
    final secretId = credentials['tencent_asr_secret_id'];
    final secretKey = credentials['tencent_asr_secret_key'];
    if (secretId != null && secretKey != null) {
      await _secureStore.saveTencentAsrCredentials(
        TencentAsrCredentials(secretId: secretId, secretKey: secretKey),
      );
    }
    final apiKey = credentials['worker_tts_api_key'];
    if (apiKey != null && apiKey.isNotEmpty) {
      await _secureStore.saveWorkerTtsApiKey(apiKey);
    }
    // legacy 备份无 llm_api_key 字段 → null，跳过（不覆盖现有值）。
    // LLM 配置设备绑定（url/model 不随备份迁移），key 必须找到本机的
    // 归属配置才能落到正确槽位（llm_api_key_{configId}）：
    // - 有 llm_api_key_hint（新备份）：按 host|model 在本机 llm_providers
    //   中匹配，key 写回**匹配配置**的槽位——防止导出后本机切换 active
    //   造成「A 的 key 写进 B 槽位」；本机无匹配配置则丢弃（与
    //   url/model 不迁移纪律一致）。
    // - 无 hint（旧备份）：维持现行为——写本机当前生效配置的键位；
    //   本机无生效配置则丢弃（兼容不倒退）。
    final llmApiKey = credentials['llm_api_key'];
    if (llmApiKey != null && llmApiKey.isNotEmpty) {
      final hint = credentials['llm_api_key_hint'];
      if (hint != null && hint.isNotEmpty) {
        final matchedId = _matchLlmProviderByHint(hint);
        if (matchedId != null) {
          await _secureStore.saveLlmApiKeyFor(matchedId, llmApiKey);
        }
      } else {
        final activeId = HiveBoxes.settings.get('llm_active_provider_id')
            as String?;
        if (activeId != null && activeId.isNotEmpty) {
          await _secureStore.saveLlmApiKeyFor(activeId, llmApiKey);
        }
      }
    }
  }

  /// 在本机 llm_providers 中按 hint（host|model）匹配配置；
  /// 找不到返回 null（恢复时丢弃该 key）。同 host+model 多条取第一条
  /// （同址同模型的 key 可互换，无实害）。
  String? _matchLlmProviderByHint(String hint) {
    final providers = LlmProviderConfig.decodeList(
      HiveBoxes.settings.get('llm_providers') as String?,
    );
    for (final config in providers) {
      if (_llmKeyHintOf(config.baseUrl, config.model) == hint) {
        return config.id;
      }
    }
    return null;
  }

  /// 当前生效 LLM 配置的 key 归属提示（host|model）；无生效配置返回
  /// 空串（导出端与 active key 同时判断，空串不会写入凭据节）。
  String _activeLlmKeyHint() {
    final activeId =
        HiveBoxes.settings.get('llm_active_provider_id') as String?;
    if (activeId == null || activeId.isEmpty) return '';
    final providers = LlmProviderConfig.decodeList(
      HiveBoxes.settings.get('llm_providers') as String?,
    );
    for (final config in providers) {
      if (config.id == activeId) {
        return _llmKeyHintOf(config.baseUrl, config.model);
      }
    }
    return '';
  }

  /// 配置的归属提示：host 取 baseUrl 解析出的 host（解析失败回退原串），
  /// 与 model 以「|」连接。非敏感（加密节内已含各 API key，host|model
  /// 不新增暴露面）。
  static String _llmKeyHintOf(String baseUrl, String model) {
    final host = Uri.tryParse(baseUrl)?.host ?? '';
    return '${host.isEmpty ? baseUrl : host}|$model';
  }

  /// 读取当前生效 LLM 配置的 API Key（llm_api_key_{activeId}）；
  /// 无生效配置返回 null。
  Future<String?> _readActiveLlmApiKey() async {
    final activeId =
        HiveBoxes.settings.get('llm_active_provider_id') as String?;
    if (activeId == null || activeId.isEmpty) return null;
    return _secureStore.readLlmApiKeyFor(activeId);
  }

  /// 执行实际的数据恢复，返回记录总数。
  Future<int> _doRestore(Map<String, dynamic> data) async {
    var count = 0;

    count += await _restorePoemProgress(
      data['poemProgress'] as List<dynamic>? ?? [],
    );
    count += await _restorePoemFavorites(
      data['poemFavorites'] as List<dynamic>? ?? [],
    );
    count += await _restoreReviewSchedules(
      data['reviewSchedules'] as List<dynamic>? ?? [],
    );
    count += await _restoreMathMistakes(
      data['mathMistakes'] as List<dynamic>? ?? [],
    );
    count += await _restoreMathSessions(
      data['mathSessions'] as List<dynamic>? ?? [],
    );
    count += await _restoreFormulaFavorites(
      data['formulaFavorites'] as List<dynamic>? ?? [],
    );
    count += await _restoreAchievements(
      data['achievements'] as List<dynamic>? ?? [],
    );
    count += await _restoreCheckIns(
      data['checkIns'] as List<dynamic>? ?? [],
    );
    count += await _restoreUserStats(
      data['userStats'] as List<dynamic>? ?? [],
    );
    count += await _restoreChallengeRecords(
      data['challengeRecords'] as List<dynamic>? ?? [],
    );
    count += await _restoreLearningActivities(
      data['learningActivities'] as List<dynamic>? ?? [],
    );
    count += await _restoreLlmProblems(
      data['llmProblems'] as List<dynamic>? ?? [],
    );
    if (data.containsKey('activitySettlements')) {
      await ActivitySettlementLedger.replaceCompletedKeys(
        (data['activitySettlements'] as List<dynamic>).cast<String>(),
      );
    }
    if (data.containsKey('settings')) {
      await _restoreSettings(data['settings'] as Map<String, dynamic>);
    }

    return count;
  }

  /// 从文件路径恢复。
  Future<int> restoreFromFile(String filePath, {String? passphrase}) async {
    final file = File(filePath);
    if (!file.existsSync()) {
      throw const FormatException('备份文件不存在');
    }
    final json = await file.readAsString();
    return restoreFromJson(json, passphrase: passphrase);
  }

  // ============ 导出 ============

  List<Map<String, dynamic>> _exportPoemProgress() {
    return HiveBoxes.poemProgress.values.map((p) {
      return <String, dynamic>{
        'poemId': p.poemId,
        'profileId': p.profileId,
        'status': p.status.index,
        'masteryLevel': p.masteryLevel,
        'studyCount': p.studyCount,
        'lastStudiedAt': p.lastStudiedAt?.toIso8601String(),
        'firstStudiedAt': p.firstStudiedAt?.toIso8601String(),
        'stars': p.stars,
      };
    }).toList();
  }

  List<Map<String, dynamic>> _exportPoemFavorites() {
    return HiveBoxes.poemFavorites.values.map((f) {
      return <String, dynamic>{
        'poemId': f.poemId,
        'profileId': f.profileId,
        'createdAt': f.createdAt.toIso8601String(),
      };
    }).toList();
  }

  List<Map<String, dynamic>> _exportReviewSchedules() {
    return HiveBoxes.reviewSchedules.values.map((r) {
      return <String, dynamic>{
        'poemId': r.poemId,
        'profileId': r.profileId,
        'currentRound': r.currentRound,
        'nextReviewDate': r.nextReviewDate.toIso8601String(),
        'lastReviewedAt': r.lastReviewedAt?.toIso8601String(),
        'isCompleted': r.isCompleted,
      };
    }).toList();
  }

  List<Map<String, dynamic>> _exportMathMistakes() {
    return HiveBoxes.mathMistakes.values.map((m) {
      return <String, dynamic>{
        'id': m.id,
        'profileId': m.profileId,
        'problemText': m.problemText,
        'correctAnswer': m.correctAnswer,
        'userAnswer': m.userAnswer,
        'problemType': m.problemType,
        'grade': m.grade,
        'errorType': m.errorType,
        'solutionStepsJson': m.solutionStepsJson,
        'createdAt': m.createdAt.toIso8601String(),
        'isResolved': m.isResolved,
        'retryCount': m.retryCount,
      };
    }).toList();
  }

  List<Map<String, dynamic>> _exportMathSessions() {
    return HiveBoxes.mathSessions.values.map((s) {
      return <String, dynamic>{
        'id': s.id,
        'profileId': s.profileId,
        'grade': s.grade,
        'problemType': s.problemType,
        'totalProblems': s.totalProblems,
        'correctCount': s.correctCount,
        'durationSeconds': s.durationSeconds,
        'starsEarned': s.starsEarned,
        'startedAt': s.startedAt.toIso8601String(),
        'finishedAt': s.finishedAt?.toIso8601String(),
        'semester': s.semester,
        'difficulty': s.difficulty,
        'problemsJson': s.problemsJson,
      };
    }).toList();
  }

  List<Map<String, dynamic>> _exportFormulaFavorites() {
    return HiveBoxes.formulaFavorites.values.map((f) {
      return <String, dynamic>{
        'formulaId': f.formulaId,
        'profileId': f.profileId,
        'createdAt': f.createdAt.toIso8601String(),
      };
    }).toList();
  }

  List<Map<String, dynamic>> _exportAchievements() {
    return HiveBoxes.achievements.values.map((a) {
      return <String, dynamic>{
        'id': a.id,
        'profileId': a.profileId,
        'title': a.title,
        'description': a.description,
        'iconName': a.iconName,
        'isUnlocked': a.isUnlocked,
        'unlockedAt': a.unlockedAt?.toIso8601String(),
        'progress': a.progress,
      };
    }).toList();
  }

  List<Map<String, dynamic>> _exportCheckIns() {
    return HiveBoxes.checkIns.values.map((c) {
      return <String, dynamic>{
        'profileId': c.profileId,
        'date': c.date,
        'poemCount': c.poemCount,
        'mathTotalCount': c.mathTotalCount,
        'mathCorrectCount': c.mathCorrectCount,
        'starsEarned': c.starsEarned,
        'durationSeconds': c.durationSeconds,
        'isCheckedIn': c.isCheckedIn,
        'activitySources': c.activitySources,
      };
    }).toList();
  }

  List<Map<String, dynamic>> _exportUserStats() {
    return HiveBoxes.userStats.values.map((s) {
      return <String, dynamic>{
        'profileId': s.profileId,
        'totalStars': s.totalStars,
        'currentStreak': s.currentStreak,
        'longestStreak': s.longestStreak,
        'poemsLearned': s.poemsLearned,
        'poemsMastered': s.poemsMastered,
        'mathTotalProblems': s.mathTotalProblems,
        'mathTotalCorrect': s.mathTotalCorrect,
        'level': s.level,
        'createdAt': s.createdAt.toIso8601String(),
        'mathBestStreak': s.mathBestStreak,
      };
    }).toList();
  }

  List<Map<String, dynamic>> _exportChallengeRecords() {
    return HiveBoxes.challengeRecords.values.map((r) {
      return <String, dynamic>{
        'id': r.id,
        'profileId': r.profileId,
        'mode': r.mode,
        'score': r.score,
        'totalAnswered': r.totalAnswered,
        'correctCount': r.correctCount,
        'bestCombo': r.bestCombo,
        'grade': r.grade,
        'semester': r.semester,
        'difficulty': r.difficulty,
        'durationSeconds': r.durationSeconds,
        'createdAt': r.createdAt.toIso8601String(),
        'starsEarned': r.starsEarned,
      };
    }).toList();
  }

  List<Map<String, dynamic>> _exportLearningActivities() {
    return HiveBoxes.learningActivities.values.map((activity) {
      return <String, dynamic>{
        'id': activity.id,
        'profileId': activity.profileId,
        'activityType': activity.activityType,
        'totalItems': activity.totalItems,
        'successfulItems': activity.successfulItems,
        'poemId': activity.poemId,
        'starsEarned': activity.starsEarned,
        'durationSeconds': activity.durationSeconds,
        'completedAt': activity.completedAt.toIso8601String(),
      };
    }).toList();
  }

  List<Map<String, dynamic>> _exportLlmProblems() {
    return HiveBoxes.llmProblems.values.map((p) {
      return <String, dynamic>{
        'id': p.id,
        'profileId': p.profileId,
        'questionText': p.questionText,
        'unit': p.unit,
        'operands': p.operands,
        'operators': p.operators,
        'answer': p.answer,
        'explanation': p.explanation,
        'batchId': p.batchId,
        'createdAt': p.createdAt.toIso8601String(),
        'grade': p.grade,
        'semester': p.semester,
        'topic': p.topic,
        'difficulty': p.difficulty,
        'done': p.done,
        'attempts': p.attempts,
        'correctCount': p.correctCount,
        'lastDoneAt': p.lastDoneAt?.toIso8601String(),
      };
    }).toList();
  }

  Map<String, dynamic> _exportSettings() {
    final box = HiveBoxes.settings;
    final result = <String, dynamic>{};
    // 只导白名单 key：排除 key（外部服务端点、凭据绑定状态）留在本机，
    // 备份文件干净且不误导「配置会同步」。
    for (final key in box.keys) {
      final name = key.toString();
      if (!_settingsValueType.containsKey(name)) continue;
      result[name] = box.get(key);
    }
    return result;
  }

  // ============ 恢复 ============

  Future<int> _restorePoemProgress(List<dynamic> items) async {
    final box = HiveBoxes.poemProgress;
    await box.clear();
    for (final item in items) {
      final m = item as Map<String, dynamic>;
      final obj = PoemProgress(
        poemId: m['poemId'] as String,
        profileId: m['profileId'] as String,
        status: LearningStatus.values[m['status'] as int? ?? 0],
        masteryLevel: m['masteryLevel'] as int? ?? 0,
        studyCount: m['studyCount'] as int? ?? 0,
        lastStudiedAt: _parseDateTime(m['lastStudiedAt']),
        firstStudiedAt: _parseDateTime(m['firstStudiedAt']),
        stars: m['stars'] as int? ?? 0,
      );
      await box.put('${obj.profileId}_${obj.poemId}', obj);
    }
    return items.length;
  }

  Future<int> _restorePoemFavorites(List<dynamic> items) async {
    final box = HiveBoxes.poemFavorites;
    await box.clear();
    for (final item in items) {
      final m = item as Map<String, dynamic>;
      final obj = PoemFavorite(
        poemId: m['poemId'] as String,
        profileId: m['profileId'] as String,
        createdAt: _parseDateTime(m['createdAt']),
      );
      await box.put('${obj.profileId}_${obj.poemId}', obj);
    }
    return items.length;
  }

  Future<int> _restoreReviewSchedules(List<dynamic> items) async {
    final box = HiveBoxes.reviewSchedules;
    await box.clear();
    for (final item in items) {
      final m = item as Map<String, dynamic>;
      final obj = ReviewSchedule(
        poemId: m['poemId'] as String,
        profileId: m['profileId'] as String,
        currentRound: m['currentRound'] as int? ?? 0,
        nextReviewDate: _parseDateTime(m['nextReviewDate']) ?? DateTime.now(),
        lastReviewedAt: _parseDateTime(m['lastReviewedAt']),
        isCompleted: m['isCompleted'] as bool? ?? false,
      );
      await box.put('${obj.profileId}_${obj.poemId}', obj);
    }
    return items.length;
  }

  Future<int> _restoreMathMistakes(List<dynamic> items) async {
    final box = HiveBoxes.mathMistakes;
    await box.clear();
    for (final item in items) {
      final m = item as Map<String, dynamic>;
      final obj = MathMistake(
        id: m['id'] as String,
        profileId: m['profileId'] as String,
        problemText: m['problemText'] as String,
        correctAnswer: m['correctAnswer'] as String,
        userAnswer: m['userAnswer'] as String,
        problemType: m['problemType'] as String,
        grade: m['grade'] as int,
        errorType: m['errorType'] as String?,
        solutionStepsJson: m['solutionStepsJson'] as String?,
        createdAt: _parseDateTime(m['createdAt']),
        isResolved: m['isResolved'] as bool? ?? false,
        retryCount: m['retryCount'] as int? ?? 0,
      );
      await box.put('${obj.profileId}_${obj.id}', obj);
    }
    return items.length;
  }

  Future<int> _restoreMathSessions(List<dynamic> items) async {
    final box = HiveBoxes.mathSessions;
    await box.clear();
    for (final item in items) {
      final m = item as Map<String, dynamic>;
      final obj = MathSession(
        id: m['id'] as String,
        profileId: m['profileId'] as String,
        grade: m['grade'] as int,
        problemType: m['problemType'] as String,
        totalProblems: m['totalProblems'] as int,
        correctCount: m['correctCount'] as int? ?? 0,
        durationSeconds: m['durationSeconds'] as int? ?? 0,
        starsEarned: m['starsEarned'] as int? ?? 0,
        startedAt: _parseDateTime(m['startedAt']),
        finishedAt: _parseDateTime(m['finishedAt']),
        semester: m['semester'] as String?,
        difficulty: m['difficulty'] as String?,
        problemsJson: m['problemsJson'] as String?,
      );
      await box.put('${obj.profileId}_${obj.id}', obj);
    }
    return items.length;
  }

  Future<int> _restoreFormulaFavorites(List<dynamic> items) async {
    final box = HiveBoxes.formulaFavorites;
    await box.clear();
    for (final item in items) {
      final m = item as Map<String, dynamic>;
      final obj = FormulaFavorite(
        formulaId: m['formulaId'] as String,
        profileId: m['profileId'] as String,
        createdAt: _parseDateTime(m['createdAt']),
      );
      await box.put('${obj.profileId}_${obj.formulaId}', obj);
    }
    return items.length;
  }

  Future<int> _restoreAchievements(List<dynamic> items) async {
    final box = HiveBoxes.achievements;
    await box.clear();
    for (final item in items) {
      final m = item as Map<String, dynamic>;
      final obj = Achievement(
        id: m['id'] as String,
        profileId: m['profileId'] as String,
        title: m['title'] as String,
        description: m['description'] as String? ?? '',
        iconName: m['iconName'] as String? ?? 'trophy',
        isUnlocked: m['isUnlocked'] as bool? ?? false,
        unlockedAt: _parseDateTime(m['unlockedAt']),
        progress: (m['progress'] as num?)?.toDouble() ?? 0.0,
      );
      await box.put('${obj.profileId}_${obj.id}', obj);
    }
    return items.length;
  }

  Future<int> _restoreCheckIns(List<dynamic> items) async {
    final box = HiveBoxes.checkIns;
    await box.clear();
    for (final item in items) {
      final m = item as Map<String, dynamic>;
      final obj = CheckIn(
        profileId: m['profileId'] as String,
        date: m['date'] as String,
        poemCount: m['poemCount'] as int? ?? 0,
        mathTotalCount: m['mathTotalCount'] as int? ?? 0,
        mathCorrectCount: m['mathCorrectCount'] as int? ?? 0,
        starsEarned: m['starsEarned'] as int? ?? 0,
        durationSeconds: m['durationSeconds'] as int? ?? 0,
        isCheckedIn: m['isCheckedIn'] as bool? ?? true,
        activitySources: m['activitySources'] as int? ?? 0,
      );
      await box.put('${obj.profileId}_${obj.date}', obj);
    }
    return items.length;
  }

  Future<int> _restoreUserStats(List<dynamic> items) async {
    final box = HiveBoxes.userStats;
    await box.clear();
    for (final item in items) {
      final m = item as Map<String, dynamic>;
      final obj = UserStats(
        profileId: m['profileId'] as String,
        totalStars: m['totalStars'] as int? ?? 0,
        currentStreak: m['currentStreak'] as int? ?? 0,
        longestStreak: m['longestStreak'] as int? ?? 0,
        poemsLearned: m['poemsLearned'] as int? ?? 0,
        poemsMastered: m['poemsMastered'] as int? ?? 0,
        mathTotalProblems: m['mathTotalProblems'] as int? ?? 0,
        mathTotalCorrect: m['mathTotalCorrect'] as int? ?? 0,
        level: m['level'] as int? ?? 0,
        createdAt: _parseDateTime(m['createdAt']),
        mathBestStreak: m['mathBestStreak'] as int? ?? 0,
      );
      await box.put('${obj.profileId}_stats', obj);
    }
    return items.length;
  }

  Future<int> _restoreChallengeRecords(List<dynamic> items) async {
    final box = HiveBoxes.challengeRecords;
    await box.clear();
    for (final item in items) {
      final m = item as Map<String, dynamic>;
      final obj = ChallengeRecord(
        id: m['id'] as String,
        profileId: m['profileId'] as String,
        mode: m['mode'] as String,
        score: m['score'] as int,
        totalAnswered: m['totalAnswered'] as int,
        correctCount: m['correctCount'] as int,
        bestCombo: m['bestCombo'] as int? ?? 0,
        grade: m['grade'] as int,
        semester: m['semester'] as String,
        difficulty: m['difficulty'] as String,
        durationSeconds: m['durationSeconds'] as int? ?? 0,
        createdAt: _parseDateTime(m['createdAt']),
        starsEarned: m['starsEarned'] as int? ?? 0,
      );
      await box.put('${obj.profileId}_${obj.id}', obj);
    }
    return items.length;
  }

  Future<int> _restoreLearningActivities(List<dynamic> items) async {
    final box = HiveBoxes.learningActivities;
    await box.clear();
    for (final item in items) {
      final m = item as Map<String, dynamic>;
      final activity = LearningActivity(
        id: m['id'] as String,
        profileId: m['profileId'] as String,
        activityType: m['activityType'] as String,
        totalItems: m['totalItems'] as int,
        successfulItems: m['successfulItems'] as int,
        poemId: m['poemId'] as String?,
        starsEarned: m['starsEarned'] as int,
        durationSeconds: m['durationSeconds'] as int,
        completedAt: DateTime.parse(m['completedAt'] as String),
      );
      await box.put('${activity.profileId}_${activity.id}', activity);
    }
    return items.length;
  }

  Future<int> _restoreLlmProblems(List<dynamic> items) async {
    final box = HiveBoxes.llmProblems;
    await box.clear();
    for (final item in items) {
      final m = item as Map<String, dynamic>;
      final obj = LlmProblem(
        id: m['id'] as String,
        profileId: m['profileId'] as String,
        questionText: m['questionText'] as String,
        unit: m['unit'] as String,
        operands: (m['operands'] as List<dynamic>).cast<int>(),
        operators: (m['operators'] as List<dynamic>).cast<String>(),
        answer: m['answer'] as int,
        explanation: m['explanation'] as String? ?? '',
        batchId: m['batchId'] as String,
        createdAt: _parseDateTime(m['createdAt']) ?? DateTime.now(),
        grade: m['grade'] as int,
        semester: m['semester'] as String,
        topic: m['topic'] as String,
        difficulty: m['difficulty'] as int,
        done: m['done'] as bool? ?? false,
        attempts: m['attempts'] as int? ?? 0,
        correctCount: m['correctCount'] as int? ?? 0,
        lastDoneAt: _parseDateTime(m['lastDoneAt']),
      );
      await box.put('${obj.profileId}_${obj.id}', obj);
    }
    return items.length;
  }

  Future<void> _restoreSettings(Map<String, dynamic> items) async {
    final box = HiveBoxes.settings;
    // 只删并重写白名单 key：排除 key（如本机 webdav_configs）原值保留，
    // 恶意备份既不能注入外部服务端点，也不能借恢复清空设备配置。
    for (final key in _settingsValueType.keys) {
      await box.delete(key);
    }
    for (final entry in items.entries) {
      final expected = _settingsValueType[entry.key];
      if (expected == null) continue; // 白名单外：跳过
      final value = _normalizeSettingValue(entry.value, expected);
      if (value == null) continue; // 类型不符：跳过该 key，不毁整个恢复
      await box.put(entry.key, value);
    }
  }

  /// 按白名单类型契约规范化 settings 值；类型不符返回 null（跳过该 key）。
  ///
  /// - 'string'：仅接受 String；
  /// - 'bool'：仅接受 bool；
  /// - 'int'：仅接受 int（JSON 的 1.5 解出 double → 拒绝）；
  /// - 'double'：接受任意 num 并 `toDouble()`（JSON 整数 1 合法化为 1.0）。
  Object? _normalizeSettingValue(Object? value, String expected) {
    switch (expected) {
      case 'string':
        return value is String ? value : null;
      case 'bool':
        return value is bool ? value : null;
      case 'int':
        return value is int ? value : null;
      case 'double':
        return value is num ? value.toDouble() : null;
    }
    return null;
  }

  // ============ 工具 ============

  Map<String, dynamic> _decodeAndValidate(String jsonString) {
    final Object? decoded;
    try {
      decoded = jsonDecode(jsonString);
    } on FormatException {
      throw const FormatException('无效的备份文件格式');
    }

    if (decoded is! Map<Object?, Object?>) {
      throw const FormatException('备份文件顶层必须是 JSON 对象');
    }

    final data = <String, dynamic>{};
    for (final entry in decoded.entries) {
      if (entry.key is! String) {
        throw const FormatException('备份文件包含无效的顶层键');
      }
      data[entry.key as String] = entry.value;
    }

    final version = data['version'];
    if (version != null && (version is! int || version < 0)) {
      throw const FormatException('备份文件版本号无效');
    }
    if (version is int && version > _backupVersion) {
      throw FormatException('备份文件版本 ($version) 高于当前支持版本');
    }
    _validateOptionalDate(data, 'exportedAt', 'top-level');

    _validateList(data, 'poemProgress', _validatePoemProgress);
    _validateList(data, 'poemFavorites', _validatePoemFavorite);
    _validateList(data, 'reviewSchedules', _validateReviewSchedule);
    _validateList(data, 'mathMistakes', _validateMathMistake);
    _validateList(data, 'mathSessions', _validateMathSession);
    _validateList(data, 'formulaFavorites', _validateFormulaFavorite);
    _validateList(data, 'achievements', _validateAchievement);
    _validateList(data, 'checkIns', _validateCheckIn);
    _validateList(data, 'userStats', _validateUserStats);
    _validateList(data, 'challengeRecords', _validateChallengeRecord);
    _validateList(data, 'learningActivities', _validateLearningActivity);
    _validateList(data, 'llmProblems', _validateLlmProblem);
    _validateUniqueLearningActivityIds(data);
    _validateActivitySettlements(data);

    if (data.containsKey('settings')) {
      final settings = data['settings'];
      if (settings is! Map<Object?, Object?>) {
        _invalidField('settings', '必须是 JSON 对象');
      }
      _validateJsonObject(settings, 'settings');
    }

    if (data.containsKey('credentials')) {
      final credentials = data['credentials'];
      if (credentials is! Map<Object?, Object?>) {
        _invalidField('credentials', '必须是 JSON 对象');
      }
    }

    return data;
  }

  void _validateActivitySettlements(Map<String, dynamic> data) {
    if (!data.containsKey('activitySettlements')) return;
    final value = data['activitySettlements'];
    if (value is! List<Object?>) {
      _invalidField('activitySettlements', '必须是 JSON 数组');
    }

    final keys = <String>{};
    for (var index = 0; index < value.length; index++) {
      final key = value[index];
      if (key is! String || !ActivitySettlementLedger.isSettlementKey(key)) {
        _invalidField('activitySettlements[$index]', '不是有效的活动结算标记');
      }
      if (!keys.add(key)) {
        _invalidField('activitySettlements[$index]', '活动结算标记重复');
      }
    }
  }

  void _validateList(
    Map<String, dynamic> data,
    String key,
    void Function(Map<String, dynamic> item, String path) validator,
  ) {
    if (!data.containsKey(key)) return;
    final value = data[key];
    if (value is! List<Object?>) {
      _invalidField(key, '必须是 JSON 数组');
    }

    for (var index = 0; index < value.length; index++) {
      final rawItem = value[index];
      if (rawItem is! Map<Object?, Object?>) {
        _invalidField('$key[$index]', '必须是 JSON 对象');
      }
      final item = <String, dynamic>{};
      for (final entry in rawItem.entries) {
        if (entry.key is! String) {
          _invalidField('$key[$index]', '包含无效字段名');
        }
        item[entry.key as String] = entry.value;
      }
      validator(item, '$key[$index]');
    }
  }

  void _validatePoemProgress(Map<String, dynamic> item, String path) {
    _requiredString(item, 'poemId', path);
    _requiredString(item, 'profileId', path);
    _optionalInt(
      item,
      'status',
      path,
      min: 0,
      max: LearningStatus.values.length - 1,
    );
    _optionalInt(item, 'masteryLevel', path, min: 0, max: 5);
    _optionalNonNegativeInt(item, 'studyCount', path);
    _optionalNonNegativeInt(item, 'stars', path);
    _validateOptionalDate(item, 'lastStudiedAt', path);
    _validateOptionalDate(item, 'firstStudiedAt', path);
  }

  void _validatePoemFavorite(Map<String, dynamic> item, String path) {
    _requiredString(item, 'poemId', path);
    _requiredString(item, 'profileId', path);
    _validateOptionalDate(item, 'createdAt', path);
  }

  void _validateReviewSchedule(Map<String, dynamic> item, String path) {
    _requiredString(item, 'poemId', path);
    _requiredString(item, 'profileId', path);
    _optionalInt(
      item,
      'currentRound',
      path,
      min: 0,
      max: ReviewSchedule.intervals.length,
    );
    _validateOptionalDate(item, 'nextReviewDate', path);
    _validateOptionalDate(item, 'lastReviewedAt', path);
    _optionalBool(item, 'isCompleted', path);
  }

  void _validateMathMistake(Map<String, dynamic> item, String path) {
    for (final key in <String>[
      'id',
      'profileId',
      'problemText',
      'correctAnswer',
      'userAnswer',
      'problemType',
    ]) {
      _requiredString(item, key, path);
    }
    _requiredInt(item, 'grade', path);
    _optionalNullableString(item, 'errorType', path);
    _optionalNullableString(item, 'solutionStepsJson', path);
    _validateOptionalDate(item, 'createdAt', path);
    _optionalBool(item, 'isResolved', path);
    _optionalNonNegativeInt(item, 'retryCount', path);
  }

  void _validateMathSession(Map<String, dynamic> item, String path) {
    for (final key in <String>['id', 'profileId', 'problemType']) {
      _requiredString(item, key, path);
    }
    _requiredInt(item, 'grade', path);
    _requiredNonNegativeInt(item, 'totalProblems', path);
    _optionalNonNegativeInt(item, 'correctCount', path);
    _optionalNonNegativeInt(item, 'durationSeconds', path);
    _optionalNonNegativeInt(item, 'starsEarned', path);
    _validateOptionalDate(item, 'startedAt', path);
    _validateOptionalDate(item, 'finishedAt', path);
    _optionalNullableString(item, 'semester', path);
    _optionalNullableString(item, 'difficulty', path);
    if (item['semester'] != null) {
      _optionalEnumString(
        item,
        'semester',
        path,
        const <String>{'上', '下'},
      );
    }
    if (item['difficulty'] != null) {
      _optionalEnumString(
        item,
        'difficulty',
        path,
        const <String>{'easy', 'medium', 'hard'},
      );
    }
    _optionalNullableString(item, 'problemsJson', path);
  }

  void _validateFormulaFavorite(Map<String, dynamic> item, String path) {
    _requiredString(item, 'formulaId', path);
    _requiredString(item, 'profileId', path);
    _validateOptionalDate(item, 'createdAt', path);
  }

  void _validateAchievement(Map<String, dynamic> item, String path) {
    _requiredString(item, 'id', path);
    _requiredString(item, 'profileId', path);
    _requiredString(item, 'title', path);
    _optionalNullableString(item, 'description', path);
    _optionalNullableString(item, 'iconName', path);
    _optionalBool(item, 'isUnlocked', path);
    _validateOptionalDate(item, 'unlockedAt', path);
    final progress = item['progress'];
    if (progress != null &&
        (progress is! num || progress < 0 || progress > 1)) {
      _invalidField('$path.progress', '必须是 0 到 1 之间的数字');
    }
  }

  void _validateCheckIn(Map<String, dynamic> item, String path) {
    _requiredString(item, 'profileId', path);
    _requiredString(item, 'date', path);
    for (final key in <String>[
      'poemCount',
      'mathTotalCount',
      'mathCorrectCount',
      'starsEarned',
      'durationSeconds',
    ]) {
      _optionalNonNegativeInt(item, key, path);
    }
    _optionalBool(item, 'isCheckedIn', path);
    final sources = item['activitySources'];
    if (sources != null &&
        (sources is! int || sources < 0 || (sources & ~3) != 0)) {
      _invalidField('$path.activitySources', '包含未知来源标记');
    }
  }

  void _validateUserStats(Map<String, dynamic> item, String path) {
    _requiredString(item, 'profileId', path);
    for (final key in <String>[
      'totalStars',
      'currentStreak',
      'longestStreak',
      'poemsLearned',
      'poemsMastered',
      'mathTotalProblems',
      'mathTotalCorrect',
      'mathBestStreak',
    ]) {
      _optionalNonNegativeInt(item, key, path);
    }
    _optionalInt(
      item,
      'level',
      path,
      min: 0,
      max: UserStats.levelNames.length - 1,
    );
    _validateOptionalDate(item, 'createdAt', path);
  }

  void _validateChallengeRecord(Map<String, dynamic> item, String path) {
    for (final key in <String>[
      'id',
      'profileId',
      'mode',
      'semester',
      'difficulty',
    ]) {
      _requiredString(item, key, path);
    }
    _optionalEnumString(
      item,
      'mode',
      path,
      const <String>{'fixed', 'extending'},
    );
    _optionalEnumString(item, 'semester', path, const <String>{'上', '下'});
    _optionalEnumString(
      item,
      'difficulty',
      path,
      const <String>{'easy', 'medium', 'hard'},
    );
    for (final key in <String>[
      'score',
      'totalAnswered',
      'correctCount',
      'bestCombo',
      'grade',
      'durationSeconds',
    ]) {
      _requiredNonNegativeInt(item, key, path);
    }
    _optionalNonNegativeInt(item, 'starsEarned', path);
    _validateOptionalDate(item, 'createdAt', path);
  }

  void _validateLearningActivity(Map<String, dynamic> item, String path) {
    _requiredString(item, 'id', path);
    _requiredString(item, 'profileId', path);
    final activityType = _requiredString(item, 'activityType', path);
    final allowedTypes =
        LearningActivityType.values.map((type) => type.name).toSet();
    if (!allowedTypes.contains(activityType)) {
      _invalidField('$path.activityType', '不是受支持的枚举值');
    }

    final totalItems = _requiredInt(item, 'totalItems', path);
    final successfulItems = _requiredInt(item, 'successfulItems', path);
    final starsEarned = _requiredInt(item, 'starsEarned', path);
    final durationSeconds = _requiredInt(item, 'durationSeconds', path);
    if (totalItems < 0) {
      _invalidField('$path.totalItems', '不能为负数');
    }
    if (successfulItems < 0 || successfulItems > totalItems) {
      _invalidField('$path.successfulItems', '必须介于 0 和总数之间');
    }
    if (starsEarned < 0 || starsEarned > 3) {
      _invalidField('$path.starsEarned', '必须介于 0 和 3 之间');
    }
    if (durationSeconds < 0) {
      _invalidField('$path.durationSeconds', '不能为负数');
    }

    _optionalNullableString(item, 'poemId', path);
    final poemId = item['poemId'];
    if (poemId is String && poemId.isEmpty) {
      _invalidField('$path.poemId', '不能是空字符串');
    }
    final requiresPoem =
        activityType == LearningActivityType.poemRecitation.name ||
            activityType == LearningActivityType.poemQuiz.name ||
            activityType == LearningActivityType.readAlong.name;
    if (requiresPoem && poemId is! String) {
      _invalidField('$path.poemId', '诗词活动必须提供诗词 ID');
    }

    final completedAt = item['completedAt'];
    if (completedAt is! String || DateTime.tryParse(completedAt) == null) {
      _invalidField('$path.completedAt', '必须是有效的 ISO 日期字符串');
    }
  }

  void _validateLlmProblem(Map<String, dynamic> item, String path) {
    for (final key in <String>[
      'id',
      'profileId',
      'questionText',
      'unit',
      'batchId',
      'semester',
      'topic',
    ]) {
      _requiredString(item, key, path);
    }
    final answer = _requiredInt(item, 'answer', path);
    _requiredInt(item, 'grade', path);
    _requiredInt(item, 'difficulty', path);
    _optionalNonNegativeInt(item, 'attempts', path);
    _optionalNonNegativeInt(item, 'correctCount', path);
    _optionalBool(item, 'done', path);
    _validateOptionalDate(item, 'createdAt', path);
    _validateOptionalDate(item, 'lastDoneAt', path);

    // 运算符类型检查：非空字符串数组
    final operators = item['operators'];
    if (operators is! List<Object?> ||
        operators.any((op) => op is! String || op.isEmpty)) {
      _invalidField('$path.operators', '必须是非空字符串数组');
    }
    // 操作数类型检查：非负整数
    final operands = item['operands'];
    if (operands is! List<Object?> ||
        operands.any((v) => v is! int || v < 0)) {
      _invalidField('$path.operands', '必须是非负整数数组');
    }

    // ---- 语义校验：与生成侧 WordProblemValidator 同一信任标准 ----
    // 校验失败抛 FormatException，发生在任何 Box clear 之前。
    // 运算符白名单：symbol → Operator 映射，白名单即 Operator.symbol
    //（+、-、×、÷），映射不到即拒。
    final bySymbol = <String, Operator>{
      for (final op in Operator.values) op.symbol: op,
    };
    final mappedOperators = <Operator>[];
    for (final symbol in operators.cast<String>()) {
      final mapped = bySymbol[symbol];
      if (mapped == null) {
        _invalidField('$path.operators', '包含未知运算符: $symbol');
      }
      mappedOperators.add(mapped);
    }
    // 结构约束：operands 非空且数量 = 运算符数 + 1
    //（消除 expressionText 直接取 operands.first/[i+1] 的越界数据面风险）。
    final operandValues = operands.cast<int>();
    if (operandValues.isEmpty ||
        operandValues.length != mappedOperators.length + 1) {
      _invalidField('$path.operands', '与运算符数量不匹配');
    }
    // answer 非负：骨架全为非负整数，负 answer 是脏数据
    //（如 [4,12] + '-' 求值恰为 -8，仅靠求值一致性拦不住显式负数）。
    if (answer < 0) {
      _invalidField('$path.answer', '不能为负数');
    }
    // 求值一致性：ExpressionEvaluator 复算必须等于 answer（整数结果）。
    final evaluated = ExpressionEvaluator.evaluate(
      operandValues.map(NumberValue.fromInt).toList(),
      mappedOperators,
    );
    if (evaluated == null ||
        !evaluated.isInteger ||
        evaluated.asInteger != answer) {
      _invalidField('$path.answer', '与算式求值不一致');
    }
  }

  void _validateUniqueLearningActivityIds(Map<String, dynamic> data) {
    final activities = data['learningActivities'];
    if (activities is! List<Object?>) return;

    final keys = <String>{};
    for (var index = 0; index < activities.length; index++) {
      final activity = activities[index] as Map<Object?, Object?>;
      final key = '${activity['profileId']}\u0000${activity['id']}';
      if (!keys.add(key)) {
        _invalidField(
          'learningActivities[$index].id',
          '同一用户下活动 ID 重复',
        );
      }
    }
  }

  void _validateJsonObject(Map<Object?, Object?> object, String path) {
    for (final entry in object.entries) {
      if (entry.key is! String) {
        _invalidField(path, '包含无效字段名');
      }
      _validateJsonValue(entry.value, '$path.${entry.key}');
    }
  }

  void _validateJsonValue(Object? value, String path) {
    if (value == null || value is String || value is num || value is bool) {
      return;
    }
    if (value is List<Object?>) {
      for (var index = 0; index < value.length; index++) {
        _validateJsonValue(value[index], '$path[$index]');
      }
      return;
    }
    if (value is Map<Object?, Object?>) {
      _validateJsonObject(value, path);
      return;
    }
    _invalidField(path, '不是有效的 JSON 值');
  }

  String _requiredString(
    Map<String, dynamic> item,
    String key,
    String path,
  ) {
    final value = item[key];
    if (value is! String || value.isEmpty) {
      _invalidField('$path.$key', '必须是非空字符串');
    }
    return value;
  }

  void _optionalNullableString(
    Map<String, dynamic> item,
    String key,
    String path,
  ) {
    final value = item[key];
    if (value != null && value is! String) {
      _invalidField('$path.$key', '必须是字符串或 null');
    }
  }

  int _requiredInt(Map<String, dynamic> item, String key, String path) {
    final value = item[key];
    if (value is! int) _invalidField('$path.$key', '必须是整数');
    return value;
  }

  void _requiredNonNegativeInt(
    Map<String, dynamic> item,
    String key,
    String path,
  ) {
    final value = _requiredInt(item, key, path);
    if (value < 0) _invalidField('$path.$key', '不能为负数');
  }

  void _optionalNonNegativeInt(
    Map<String, dynamic> item,
    String key,
    String path,
  ) {
    final value = item[key];
    if (value == null) return;
    if (value is! int || value < 0) {
      _invalidField('$path.$key', '必须是非负整数');
    }
  }

  void _optionalInt(
    Map<String, dynamic> item,
    String key,
    String path, {
    int? min,
    int? max,
  }) {
    final value = item[key];
    if (value == null) return;
    if (value is! int ||
        (min != null && value < min) ||
        (max != null && value > max)) {
      _invalidField('$path.$key', '整数超出允许范围');
    }
  }

  void _optionalBool(
    Map<String, dynamic> item,
    String key,
    String path,
  ) {
    final value = item[key];
    if (value != null && value is! bool) {
      _invalidField('$path.$key', '必须是布尔值');
    }
  }

  void _optionalEnumString(
    Map<String, dynamic> item,
    String key,
    String path,
    Set<String> allowed,
  ) {
    final value = item[key];
    if (value is! String || !allowed.contains(value)) {
      _invalidField('$path.$key', '不是受支持的枚举值');
    }
  }

  void _validateOptionalDate(
    Map<String, dynamic> item,
    String key,
    String path,
  ) {
    final value = item[key];
    if (value == null) return;
    if (value is! String || DateTime.tryParse(value) == null) {
      _invalidField('$path.$key', '必须是有效的 ISO 日期字符串或 null');
    }
  }

  Never _invalidField(String path, String reason) {
    throw FormatException('备份字段 $path 无效：$reason');
  }

  DateTime? _parseDateTime(dynamic value) {
    if (value == null) return null;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }
}

/// 恢复写入失败；[rollbackError] 非 null 表示回滚也失败。
class BackupRestoreException implements Exception {
  const BackupRestoreException(
    this.message, {
    this.cause,
    this.rollbackError,
  });

  final String message;
  final Object? cause;
  final Object? rollbackError;

  bool get rollbackFailed => rollbackError != null;

  @override
  String toString() => 'BackupRestoreException: $message';
}
