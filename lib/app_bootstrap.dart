import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:poemath/app.dart';
import 'package:poemath/core/constants/app_constants.dart';
import 'package:poemath/core/services/notification_service.dart';
import 'package:poemath/core/theme/app_theme.dart';
import 'package:poemath/core/theme/design_tokens.dart';
import 'package:poemath/core/utils/logger.dart';
import 'package:poemath/core/widgets/app_widgets.dart';
import 'package:poemath/data/hive/hive_boxes.dart';
import 'package:poemath/data/hive/hive_registrar.dart';

typedef AppInitializer = Future<void> Function();

Future<void> initializeCoreStorage() async {
  await Hive.initFlutter();
  registerHiveAdapters();
  await HiveBoxes.init();
}

Future<void> initializeOptionalServices() async {
  await NotificationService.instance.initialize();
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
                message: '本地数据暂时无法打开，请检查设备存储空间后重试。',
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
