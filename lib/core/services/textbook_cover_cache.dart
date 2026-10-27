// lib/core/services/textbook_cover_cache.dart
//
// 层级：core/services（教材封面派生缓存）
// 职责：把 PDF 首页渲染结果缓存成 PNG，避免每次进入书籍管理页都重新
// 打开原书渲染封面。

import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:poemath/data/models/textbook.dart';

/// 封面 PNG 与原书派生缓存共用目录：
/// `<应用支持目录>/textbooks/cache/<sha256>/cover-v<版本>.png`。
///
/// 目录归属 `TextbookContentCache`：删除原书、文件校验失败导致缓存失效时
/// 整个目录会被递归清理，封面随之失效，不需要额外维护生命周期。
///
/// 磁盘缓存之外，另在会话内保留少量已解码位图：重新进入管理页时首帧
/// 就能直接出图，不必等 PNG 解码。缓存持有自己的 clone，调用方拿到的
/// 图像仍需自行释放。
class TextbookCoverCache {
  const TextbookCoverCache();

  /// 渲染参数（尺寸、格式）变化时递增，旧文件按新版本名自然失效。
  static const formatVersion = 1;

  static const _maxBytes = 8 * 1024 * 1024;

  /// 会话内位图缓存：再次进入管理页首帧直接出图，不再先闪占位。
  /// 768px 封面约 2.3 MB，6 本约 14 MB。
  static final _memory = <String, ui.Image>{};
  static const _maxMemoryImages = 6;

  /// 同步取出可独立释放的副本；没有则返回 null。
  ///
  /// 命中会刷新 LRU 顺序。返回的是 [ui.Image.clone]，调用方按既有约定
  /// 自行 dispose，不会影响缓存里的原图。
  ui.Image? take(String pdfPath) {
    final image = _memory.remove(pdfPath);
    if (image == null) return null;
    _memory[pdfPath] = image;
    if (image.debugDisposed) {
      _memory.remove(pdfPath);
      return null;
    }
    return image.clone();
  }

  /// 记住一份位图（内部保存 clone），供下次挂载首帧使用。
  void remember(String pdfPath, ui.Image image) {
    _memory.remove(pdfPath)?.dispose();
    _memory[pdfPath] = image.clone();
    while (_memory.length > _maxMemoryImages) {
      _memory.remove(_memory.keys.first)?.dispose();
    }
  }

  /// 封面失效（删除/重生成）时同步丢掉位图，避免继续显示旧封面。
  void forget(String pdfPath) {
    _memory.remove(pdfPath)?.dispose();
  }

  @visibleForTesting
  static void clearMemory() {
    for (final image in _memory.values) {
      image.dispose();
    }
    _memory.clear();
  }

  /// 由本机 PDF 路径推导缓存文件；路径不是 `<sha256>.pdf` 时不缓存。
  File? fileFor(String pdfPath) {
    final name = pdfPath.split(Platform.pathSeparator).last;
    if (!name.endsWith('.pdf')) return null;
    final id = name.substring(0, name.length - 4);
    if (!Textbook.isValidId(id)) return null;
    final parent = File(pdfPath).parent.path;
    return File(
      '$parent${Platform.pathSeparator}cache'
      '${Platform.pathSeparator}$id'
      '${Platform.pathSeparator}cover-v$formatVersion.png',
    );
  }

  /// 读取缓存；文件缺失、损坏或超限都返回 null 并清掉坏文件。
  Future<ui.Image?> read(String pdfPath) async {
    final file = fileFor(pdfPath);
    if (file == null) return null;
    try {
      if (!await file.exists()) return null;
      if (await file.length() > _maxBytes) {
        await file.delete();
        return null;
      }
      final codec = await ui.instantiateImageCodec(await file.readAsBytes());
      try {
        final frame = await codec.getNextFrame();
        return frame.image;
      } finally {
        codec.dispose();
      }
    } on Object {
      // 截断/损坏的缓存不能挡住封面：删掉后回退到重新渲染。
      try {
        if (await file.exists()) await file.delete();
      } on Object {
        // 删除失败只留下一个坏文件，下次读取仍会走这条兜底。
      }
      return null;
    }
  }

  /// 原子写入 PNG；空间不足等失败只损失缓存，不影响本次显示。
  Future<void> write(String pdfPath, ui.Image image) async {
    final file = fileFor(pdfPath);
    if (file == null) return;
    File? pending;
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null || data.lengthInBytes > _maxBytes) return;
      await file.parent.create(recursive: true);
      pending = File(
        '${file.path}.${Random.secure().nextInt(1 << 32)}.pending',
      );
      await pending.writeAsBytes(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        flush: true,
      );
      await pending.rename(file.path);
      pending = null;
    } on Object {
      // 写入失败不阻断显示。
    } finally {
      if (pending != null) {
        try {
          if (await pending.exists()) await pending.delete();
        } on Object {
          // 临时文件清理失败不影响后续。
        }
      }
    }
  }
}
