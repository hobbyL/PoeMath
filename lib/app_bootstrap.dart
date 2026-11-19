import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';

import 'package:poemath/app.dart';
import 'package:poemath/core/constants/app_constants.dart';
import 'package:poemath/core/constants/hive_keys.dart';
import 'package:poemath/core/routing/app_router.dart';
import 'package:poemath/core/routing/app_routes.dart';
import 'package:poemath/core/services/hive_encryption_key_resolver.dart';
import 'package:poemath/core/services/hive_encryption_key_provider.dart';
import 'package:poemath/core/services/notification_service.dart';
import 'package:poemath/core/services/parent_access_service.dart';
import 'package:poemath/core/services/picture_story_editor_service.dart';
import 'package:poemath/core/services/speech/legacy_speech_cleanup.dart';
import 'package:poemath/core/theme/app_theme.dart';
import 'package:poemath/core/theme/design_tokens.dart';
import 'package:poemath/core/utils/logger.dart';
import 'package:poemath/core/widgets/app_widgets.dart';
import 'package:poemath/data/hive/bootstrap.dart';
import 'package:poemath/data/hive/hive_boxes.dart';
import 'package:poemath/data/hive/hive_registrar.dart';
import 'package:poemath/data/hive/migrations/math_mistake_key_migration.dart';
import 'package:poemath/data/hive/migrations/poem_identity_migration.dart';
import 'package:poemath/data/providers/repository_providers.dart';
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
    await _settingsRepository().migratePictureStoryFeedbackSelection();
  } on Object {
    AppLogger.e('AI 点评配置迁移暂未完成，下次读取时重试', tag: 'Startup');
  }
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
    AppLogger.e('WebDAV 凭据整体迁移失败，明文凭据保留在 Hive', tag: 'Startup', error: error);
  }
}

Future<void> initializeOptionalServices({
  AppInitializer? notificationInitializer,
  AppInitializer? speechCleanup,
  AppInitializer? pictureStoryRecovery,
}) async {
  final services = <({String name, AppInitializer initialize})>[
    (
      name: '通知',
      initialize:
          notificationInitializer ?? NotificationService.instance.initialize,
    ),
    (name: '遗留语音清理', initialize: speechCleanup ?? LegacySpeechCleanup.run),
    (
      name: '看图说话选图恢复',
      initialize:
          pictureStoryRecovery ??
          PictureStoryEditorService.instance.recoverLostImage,
    ),
  ];
  // 可选初始化独立处理失败，通知异常也不能跳过 Android 丢失选图恢复。
  for (final service in services) {
    try {
      await service.initialize();
    } on Object catch (error, stackTrace) {
      AppLogger.e(
        '${service.name}初始化失败，应用继续启动',
        tag: 'Startup',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }
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
    AppLogger.e('写入「Hive 密钥丢失」标记失败，用户不会看到提示', tag: 'Startup', error: error);
  }
}

typedef StartupDataInitializer = Future<bool> Function(
  BootstrapProgressCallback onProgress,
);
typedef StartupIndexBuilder = Future<void> Function();

/// 初始化存储和静态学习资料，准备完成后直接进入首页或首次引导。
class AppBootstrap extends ConsumerStatefulWidget {
  const AppBootstrap({
    super.key,
    this.coreInitializer,
    this.optionalInitializer,
    this.dataInitializer,
    this.indexBuilder,
    this.readyChild,
  });

  final AppInitializer? coreInitializer;
  final AppInitializer? optionalInitializer;
  final StartupDataInitializer? dataInitializer;
  final StartupIndexBuilder? indexBuilder;
  final Widget? readyChild;

  @override
  ConsumerState<AppBootstrap> createState() => _AppBootstrapState();
}

enum _StartupPhase { coreStorage, learningData }

class _AppBootstrapState extends ConsumerState<AppBootstrap> {
  bool _isInitializing = false;
  bool _coreReady = false;
  bool _optionalServicesStarted = false;
  bool _isReady = false;
  bool _isImporting = false;
  double _progress = 0;
  String _statusText = '正在准备韵算…';
  String? _errorMessage;
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
      _isImporting = false;
      _progress = 0;
      _statusText = '正在准备韵算…';
      _error = null;
      _errorMessage = null;
    });

    var phase = _StartupPhase.coreStorage;
    try {
      if (!_coreReady) {
        await (widget.coreInitializer ?? initializeCoreStorage)();
        if (!mounted) return;
        _coreReady = true;
        if (!_optionalServicesStarted) {
          _optionalServicesStarted = true;
          unawaited(_initializeOptionalServices());
        }
      }

      phase = _StartupPhase.learningData;
      setState(() {
        _statusText = '正在加载学习资料…';
      });
      final didImport = widget.dataInitializer != null
          ? await widget.dataInitializer!(_updateProgress)
          : await DataBootstrap.ensureInitialized(onProgress: _updateProgress);
      if (!mounted) return;

      if (didImport) {
        setState(() {
          _statusText = '正在整理诗词索引…';
        });
      }

      if (widget.indexBuilder != null) {
        await widget.indexBuilder!();
      } else {
        await ref.read(poemRepositoryProvider).buildIndices();
      }

      if (!mounted) return;
      if (widget.readyChild == null) {
        final hasOnboarded = ref.read(settingsRepositoryProvider).hasOnboarded;
        ref.read(appStartupLocationProvider.notifier).state = hasOnboarded
            ? AppRoutes.home
            : AppRoutes.onboarding;
      }
      setState(() {
        _isReady = true;
      });
    } catch (error) {
      AppLogger.e(
        phase == _StartupPhase.coreStorage ? '核心存储初始化失败' : '静态学习资料初始化失败',
        tag: 'Startup',
        error: error,
      );
      if (!mounted) return;
      setState(() {
        _error = error;
        _errorMessage = phase == _StartupPhase.coreStorage
            ? '本地数据暂时无法打开，原有文件已保留。请检查设备存储空间后重试。'
            : '学习资料加载失败，请重试。';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isInitializing = false;
        });
      }
    }
  }

  void _updateProgress(double progress) {
    if (!mounted) return;
    setState(() {
      _progress = progress;
      _isImporting = true;
      if (progress < 0.3) {
        _statusText = '正在加载诗词数据…';
      } else if (progress < 0.6) {
        _statusText = '正在整理古诗…';
      } else if (progress < 0.8) {
        _statusText = '正在加载作者资料…';
      } else if (progress < 0.95) {
        _statusText = '正在加载数学公式…';
      } else {
        _statusText = '即将完成…';
      }
    });
  }

  Future<void> _initializeOptionalServices() async {
    try {
      await (widget.optionalInitializer ?? initializeOptionalServices)();
    } catch (error) {
      AppLogger.e('可选服务初始化失败，应用继续启动', tag: 'Startup', error: error);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isReady) return widget.readyChild ?? const App();

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
        backgroundColor: _error == null ? ColorTokens.startupPaper : null,
        body: _error != null
            ? StartupFailureView(
                message: _error is HiveKeyUnavailable
                    ? _error.toString()
                    : _errorMessage ?? '启动失败，请重试。',
                onRetry: _initialize,
                isRetrying: _isInitializing,
              )
            : _StartupLoadingView(
                progress: _progress,
                statusText: _statusText,
                isImporting: _isImporting,
              ),
      ),
    );
  }
}

class _StartupLoadingView extends StatelessWidget {
  const _StartupLoadingView({
    required this.progress,
    required this.statusText,
    required this.isImporting,
  });

  final double progress;
  final String statusText;
  final bool isImporting;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Image.asset(
          'assets/images/splash_art.png',
          fit: BoxFit.contain,
          alignment: Alignment.center,
          excludeFromSemantics: true,
        ),
        SafeArea(
          child: Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                SpacingTokens.xl,
                SpacingTokens.md,
                SpacingTokens.xl,
                SpacingTokens.xl,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(
                      SpacingTokens.radiusSmall,
                    ),
                    child: LinearProgressIndicator(
                      value: isImporting ? progress : null,
                      minHeight: SpacingTokens.xs,
                      backgroundColor: ColorTokens.poemPaperDeep,
                      valueColor: const AlwaysStoppedAnimation<Color>(
                        ColorTokens.poemGreen,
                      ),
                    ),
                  ),
                  const SizedBox(height: SpacingTokens.md),
                  Text(
                    statusText,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium
                        ?.copyWith(color: ColorTokens.poemInk),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
