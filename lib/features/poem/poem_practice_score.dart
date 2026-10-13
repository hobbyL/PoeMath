// lib/features/poem/poem_practice_score.dart
//
// 层级：features/poem
// 职责：练习页 → 复习页的「一次性得分」侧信道。
//
// 为什么不扩展 PoemPracticeResult 枚举：全库仅 1 个
// push<PoemPracticeResult> 调用点（poem_review_page.dart），且 3 个
// 测试文件断言裸枚举值；背诵模式是完成制、无得分，包一层 outcome 会
// 让 recite 页与 2 个测试文件陪跑改动。得分是「读取即消费」的瞬态
// 数据，侧信道语义匹配。
//
// 使用纪律（双端防陈旧分数）：
// - 产出页（quiz / 听写）：进入时清空；pop 前写入本次最终得分。
// - 消费页（review）：pop 返回后读取，随即清空。
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 最近一次练习（测试 / 听写）的得分（0.0–1.0）；null = 无本次得分。
final lastPracticeScoreProvider = StateProvider<double?>((_) => null);
