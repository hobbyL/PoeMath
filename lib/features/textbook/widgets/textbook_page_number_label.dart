import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:poemath/core/services/textbook_page_number_service.dart';
import 'package:poemath/data/models/textbook_page_numbers.dart';

String asyncTextbookPageLabel(AsyncValue<int?> page) {
  if (page.isLoading) return '正在读取页码';
  if (page.hasError) return '页码读取失败';
  return textbookPrintedPageLabel(page.valueOrNull);
}

/// 各入口共用加载/失败/未编号状态，future 只随服务或物理页面变化。
class TextbookPageNumberLabel extends StatefulWidget {
  const TextbookPageNumberLabel({
    super.key,
    required this.service,
    required this.pages,
    required this.builder,
    this.fallbackLabel,
  });

  final TextbookPageNumberService? service;
  final List<int> pages;
  final String? fallbackLabel;
  final Widget Function(BuildContext context, String label) builder;

  @override
  State<TextbookPageNumberLabel> createState() =>
      _TextbookPageNumberLabelState();
}

class _TextbookPageNumberLabelState extends State<TextbookPageNumberLabel> {
  Future<TextbookPageNumbers>? _future;

  @override
  void initState() {
    super.initState();
    _future = widget.service?.load(widget.pages);
  }

  @override
  void didUpdateWidget(covariant TextbookPageNumberLabel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.service != widget.service ||
        !listEquals(oldWidget.pages, widget.pages)) {
      _future = widget.service?.load(widget.pages);
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<TextbookPageNumbers>(
    future: _future,
    builder: (context, snapshot) {
      final service = widget.service;
      final label = service == null
          ? widget.fallbackLabel ?? '正在读取页码'
          : snapshot.connectionState == ConnectionState.done
          ? snapshot.hasError
                ? '页码读取失败'
                : snapshot.data!.labelForPages(widget.pages)
          : service.numbers.labelForPages(widget.pages);
      return widget.builder(context, label);
    },
  );
}
