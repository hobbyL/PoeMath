// lib/features/assistant/assistant_enabled_provider.dart
//
// 层级：features/assistant（Riverpod Provider）
// 职责：AI 助手悬浮气泡开关状态 —— 初值从 Hive 读取，变更时自动回写。
//       MainShell 据此决定是否挂载 DraggableAssistantBubble。
// 依赖：Riverpod / Hive settings box。
//
// 模式对齐 core/theme/theme_providers.dart 的 ThemeModeNotifier：
//   NotifierProvider + listenSelf 自动持久化，写入经 Zone.root 调度
//   （规避 Flutter 测试 FakeAsync zone 无法完成 I/O Future 的卡死）。

import 'dart:async' show Zone;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:poemath/data/hive/hive_boxes.dart';

/// AI 助手悬浮气泡开关 Notifier —— 初值从 Hive 读取，变更时经 Zone.root 回写。
///
/// 默认关闭（opt-in）：无存储值时返回 false，气泡不挂载；新老用户升级后
/// 均需在「AI 设置」中手动开启。
class AssistantEnabledNotifier extends Notifier<bool> {
  /// Hive settings box 内的持久化 key。
  static const String storageKey = 'assistant_enabled';

  @override
  bool build() {
    final stored = HiveBoxes.settings.get(
      storageKey,
      defaultValue: false,
    ) as bool;

    // 监听后续变更，自动持久化到 Hive（根 Zone 执行 I/O，避免测试卡死）。
    listenSelf((prev, next) {
      if (prev != null && prev != next) {
        Zone.root.run(() {
          HiveBoxes.settings.put(storageKey, next);
        });
      }
    });

    return stored;
  }

  /// 设置开关状态（true = 显示悬浮气泡）。
  void setEnabled(bool enabled) {
    state = enabled;
  }
}

/// AI 助手悬浮气泡开关（默认关闭）。
final assistantEnabledProvider =
    NotifierProvider<AssistantEnabledNotifier, bool>(
  AssistantEnabledNotifier.new,
);
