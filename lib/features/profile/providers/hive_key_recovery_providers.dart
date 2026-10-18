// lib/features/profile/providers/hive_key_recovery_providers.dart
//
// 层级：features/profile/providers
// 职责：「Hive 加密密钥丢失、已重建空数据」的一次性提示状态。
//
// 为什么必须提示（design.md §7.4）：密钥丢失时 App 会删掉解不开的密文、
// 用新密钥建空 box 继续启动。用户看到的是「学习记录全没了」。静默重建
// 等于把一次数据丢失事故伪装成「本来就没有」—— 用户既不知道发生了什么，
// 也无从判断是不是自己误操作。所以要如实告诉他：数据不见了，原因是
// 设备安全存储里的密钥没了。
//
// 提示只在**首次进入页面时读一次**，读到即清（见 [markHiveKeyRecoveryShown]）。
// 不清的话它会在每次进「我的」页时重复出现，从「提醒」变成「噪音」。

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:poemath/core/constants/hive_keys.dart';
import 'package:poemath/core/utils/logger.dart';
import 'package:poemath/data/hive/hive_boxes.dart';

const String _tag = 'HiveKeyRecovery';

/// 是否应展示「本地数据已因密钥丢失而重建」提示。
///
/// 标记由启动流程在降级时写入（`app_bootstrap.dart` 的
/// `_markKeyRecoveredIfNeeded`）。非 `true` 一律视为「无需提示」，
/// 读取异常也返回 false —— 提示是附加信息，不能反过来打断页面构建。
final hiveKeyRecoveredProvider = Provider<bool>((ref) {
  try {
    return HiveBoxes.meta.get(HiveKeys.metaHiveKeyRecovered) == true;
  } on Object catch (error) {
    AppLogger.e('读取「Hive 密钥丢失」标记失败，本次不提示', tag: _tag, error: error);
    return false;
  }
});

/// 清除标记，使提示只出现一次。
///
/// 只在 UI 真的展示了提示之后调用 —— 页面构建阶段（例如 build 里、
/// `addPostFrameCallback` 之前）就清掉的话，一次未渲染成的 build 会把
/// 提示永久吞掉，用户永远不知道数据丢过。
///
/// 清除失败只记日志：最坏结果是下次进页面再提示一遍，比反过来安全。
Future<void> markHiveKeyRecoveryShown() async {
  try {
    await HiveBoxes.meta.delete(HiveKeys.metaHiveKeyRecovered);
  } on Object catch (error) {
    AppLogger.e('清除「Hive 密钥丢失」标记失败，下次仍会提示', tag: _tag, error: error);
  }
}
