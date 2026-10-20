import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';

import 'package:poemath/app.dart';
import 'package:poemath/core/constants/app_constants.dart';
import 'package:poemath/core/constants/hive_keys.dart';
import 'package:poemath/core/services/hive_encryption_key_resolver.dart';
import 'package:poemath/core/services/hive_encryption_key_provider.dart';
import 'package:poemath/core/services/notification_service.dart';
import 'package:poemath/core/services/parent_access_service.dart';
import 'package:poemath/core/services/speech/legacy_speech_cleanup.dart';
import 'package:poemath/core/theme/app_theme.dart';
import 'package:poemath/core/theme/design_tokens.dart';
import 'package:poemath/core/utils/logger.dart';
import 'package:poemath/core/widgets/app_widgets.dart';
import 'package:poemath/data/hive/hive_boxes.dart';
import 'package:poemath/data/hive/hive_registrar.dart';
import 'package:poemath/data/hive/migrations/math_mistake_key_migration.dart';
import 'package:poemath/data/hive/migrations/poem_identity_migration.dart';
import 'package:poemath/data/repositories/settings_repository.dart';

typedef AppInitializer = Future<void> Function();

Future<void> initializeCoreStorage() async {
  await Hive.initFlutter();

  // Hive 的数据目录就是 `getApplicationDocumentsDirectory()`（hive_flutter
  // 的 `initFlutter` 内部如此定位，且未传 subDir）。这里自己取一次，因为
  // 加密迁移要按文件路径直接读写 `.hive` / `.lock`。
  //
  // 不用 `package:path` 的 `join`：它不是本项目的直接依赖，为一个固定拼接
  // 引入依赖不划算（且 Hive 自身也用 '/' 拼接）。
  final boxDir = (await getApplicationDocumentsDirectory()).path;

  registerHiveAdapters();

  // 决定本次启动用哪把 cipher，并完成「明文 → 密文」的一次性迁移。
  //
  // 暂时读取失败或迁移写入失败交给 AppBootstrap 显示可重试界面。
  final resolved = await HiveEncryptionKeyResolver.resolve(boxDir: boxDir);
  final plaintext = HiveEncryptionKeyResolver.isPlaintext(resolved.cipher);

  await HiveBoxes.init(cipher: plaintext ? null : resolved.cipher);

  // 标记要写进已打开的 meta box，因此放在 init 之后。
  // 明文模式（迁移失败退路）下不写：那时没有可用密钥状态可言。
  if (!plaintext) await _markKeyRecoveredIfNeeded(resolved.status);

  await MathMistakeKeyMigration.run();
  await PoemIdentityMigration.run();
  try {
    await ParentAccessService.instance.initialize();
  } on Object catch (error) {
    AppLogger.e('家长保护安全存储不可用，家长区保持锁定', tag: 'Startup', error: error);
  }
  // 历史 commit 的配置写入会把明文凭据落进 Hive（凭据本就只应存在于
  // secure storage）。迁移自身已逐条捕获失败（写失败保留原值），这里再整体
  // 兜底一层，确保凭据问题不阻断启动。
  try {
    await _settingsRepository().migratePlaintextWebDavCredentials();
  } on Object catch (error) {
    AppLogger.e(
      'WebDAV 凭据整体迁移失败，明文凭据保留在 Hive',
      tag: 'Startup',
      error: error,
    );
  }
}

Future<void> initializeOptionalServices() async {
  await NotificationService.instance.initialize();
  // 清理移除本地语音识别后的遗留模型与设置键；失败不影响启动。
  await LegacySpeechCleanup.run();
}

/// 迁移用的 `SettingsRepository`：惰性单例，须在 Hive 初始化之后调用
/// （构造本身不读存储，`migratePlaintextWebDavCredentials` 会）。
SettingsRepository _settingsRepository() => _settingsRepositoryInstance;

final SettingsRepository _settingsRepositoryInstance = SettingsRepository();

/// 密钥丢失降级时在 meta 里留一个标记，供 UI 展示一次性提示。
///
/// 标记写在 Hive 打开**之后** —— 它本身要落进已加密的 meta box。
/// 只在 `recoveredEmpty` 时写：`ok` 是正常路径，`newInstall` 是全新安装，
/// 两者都不该打扰用户。
///
/// 写失败只记日志：提示是尽力而为的附加信息，不能反过来阻断启动。
Future<void> _markKeyRecoveredIfNeeded(HiveKeyStatus status) async {
  if (status != HiveKeyStatus.recoveredEmpty) return;
  try {
    await HiveBoxes.meta.put(HiveKeys.metaHiveKeyRecovered, true);
  } on Object catch (error) {
    AppLogger.e(
      '写入「Hive 密钥丢失」标记失败，用户不会看到提示',
      tag: 'Startup',
      error: error,
    );
  }
}

/// 在 Flutter UI 启动后初始化核心存储，并为失败提供重试入口。
class AppBootstrap extends StatefulWidget {
  const AppBootstrap({
    super.key,
    this.coreInitializer,
    this.optionalInitializer,
    this.readyChild = const App(),
  });

  final AppInitializer? coreInitializer;
  final AppInitializer? optionalInitializer;
  final Widget readyChild;

  @override
  State<AppBootstrap> createState() => _AppBootstrapState();
}

class _AppBootstrapState extends State<AppBootstrap> {
  bool _isInitializing = false;
  bool _isReady = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    if (_isInitializing) return;
    setState(() {
      _isInitializing = true;
    });

    try {
      await (widget.coreInitializer ?? initializeCoreStorage)();
      if (!mounted) return;
      setState(() {
        _isInitializing = false;
        _isReady = true;
      });
      unawaited(_initializeOptionalServices());
    } catch (error) {
      AppLogger.e(
        '核心存储初始化失败',
        tag: 'Startup',
        error: error,
      );
      if (!mounted) return;
      setState(() {
        _isInitializing = false;
        _error = error;
      });
    }
  }

  Future<void> _initializeOptionalServices() async {
    try {
      await (widget.optionalInitializer ?? initializeOptionalServices)();
    } catch (error) {
      AppLogger.e(
        '可选服务初始化失败，应用继续启动',
        tag: 'Startup',
        error: error,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isReady) return widget.readyChild;

    return MaterialApp(
      title: AppConstants.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.resolve(
        subject: AppSubject.poem,
        brightness: Brightness.light,
      ),
      darkTheme: AppTheme.resolve(
        subject: AppSubject.poem,
        brightness: Brightness.dark,
      ),
      home: Scaffold(
        body: _error != null
            ? StartupFailureView(
                message: _error is HiveKeyUnavailable
                    ? _error.toString()
                    : '本地数据暂时无法打开，原有文件已保留。请检查设备存储空间后重试。',
                onRetry: _initialize,
                isRetrying: _isInitializing,
              )
            : const _StartupLoadingView(),
      ),
    );
  }
}

class _StartupLoadingView extends StatelessWidget {
  const _StartupLoadingView();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.auto_stories_rounded,
              size: 56,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: SpacingTokens.lg),
            const CircularProgressIndicator(),
            const SizedBox(height: SpacingTokens.md),
            const Text('正在准备${AppConstants.appName}…'),
          ],
        ),
      ),
    );
  }
}
