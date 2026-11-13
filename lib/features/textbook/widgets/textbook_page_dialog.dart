import 'dart:async';

import 'package:flutter/material.dart';
import 'package:poemath/core/services/textbook_page_number_service.dart';
import 'package:poemath/core/theme/spacing_tokens.dart';
import 'package:poemath/core/widgets/app_widgets.dart';
import 'package:poemath/data/models/textbook_page_numbers.dart';

class TextbookPageDialog extends StatefulWidget {
  const TextbookPageDialog({
    super.key,
    required this.page,
    required this.pageCount,
    this.pageNumbers,
  });

  final int page;
  final int pageCount;
  final TextbookPageNumberService? pageNumbers;

  @override
  State<TextbookPageDialog> createState() => _TextbookPageDialogState();
}

class _TextbookPageDialogState extends State<TextbookPageDialog> {
  final _form = GlobalKey<FormState>();
  late final _input = TextEditingController(
    text: widget.pageNumbers?.numbers.pages[widget.page]?.toString() ?? '',
  );
  StreamSubscription<TextbookPageNumberProgress>? _scan;
  bool _pdfMode = false;
  bool _busy = false;
  int _generation = 0;
  int _scanned = 0;
  String? _error;
  List<int> _targets = const [];

  void _cancelScan() {
    _generation++;
    unawaited(_scan?.cancel());
    _scan = null;
  }

  void _switchMode(bool pdfMode) {
    if (_pdfMode == pdfMode) return;
    _cancelScan();
    setState(() {
      _pdfMode = pdfMode;
      _busy = false;
      _error = null;
      _targets = const [];
      _input.text = pdfMode
          ? '${widget.page}'
          : widget.pageNumbers?.numbers.pages[widget.page]?.toString() ?? '';
    });
  }

  void _changed(String _) {
    _cancelScan();
    setState(() {
      _busy = false;
      _error = null;
      _targets = const [];
    });
  }

  void _submit() {
    if (_busy || !_form.currentState!.validate()) return;
    final number = int.parse(_input.text.trim());
    if (_pdfMode) {
      Navigator.pop(context, number);
      return;
    }
    final service = widget.pageNumbers;
    if (service == null) {
      setState(() => _error = '书页码暂未就绪，可切换到 PDF 页');
      return;
    }
    _cancelScan();
    final generation = _generation;
    if (service.numbers.complete) {
      _resolve(service.numbers, number);
      return;
    }
    setState(() {
      _busy = true;
      _scanned = 0;
      _error = null;
      _targets = const [];
    });
    _scan = service.scan().listen(
      (progress) {
        if (mounted && generation == _generation) {
          setState(() => _scanned = progress.scanned);
        }
      },
      onError: (Object error) {
        if (mounted && generation == _generation) {
          setState(() {
            _busy = false;
            _error = '书页码读取失败，请重试或使用 PDF 页';
          });
        }
      },
      onDone: () {
        if (mounted && generation == _generation && _error == null) {
          _resolve(service.numbers, number);
        }
      },
      cancelOnError: true,
    );
  }

  void _resolve(TextbookPageNumbers numbers, int number) {
    final targets = numbers.targets(number);
    if (numbers.complete && targets.length == 1) {
      Navigator.pop(context, targets.single);
      return;
    }
    setState(() {
      _busy = false;
      _targets = targets;
      _error = targets.isEmpty ? '没有找到书页 $number，可使用 PDF 页' : null;
    });
  }

  @override
  void dispose() {
    _cancelScan();
    _input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('跳转页码'),
    scrollable: true,
    content: Form(
      key: _form,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: SpacingTokens.sm,
            children: [
              ChoiceChip(
                label: const Text('书页'),
                selected: !_pdfMode,
                onSelected: (_) => _switchMode(false),
              ),
              ChoiceChip(
                label: const Text('PDF 页'),
                selected: _pdfMode,
                onSelected: (_) => _switchMode(true),
              ),
            ],
          ),
          const SizedBox(height: SpacingTokens.sm),
          TextFormField(
            key: ValueKey(_pdfMode),
            controller: _input,
            autofocus: true,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.go,
            onChanged: _changed,
            onFieldSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              labelText: _pdfMode ? 'PDF 页（1–${widget.pageCount}）' : '书上印刷的页码',
            ),
            validator: (value) {
              final number = int.tryParse(value?.trim() ?? '');
              return number == null ||
                      number < 1 ||
                      (_pdfMode && number > widget.pageCount)
                  ? '请填写有效页码'
                  : null;
            },
          ),
          if (_busy) ...[
            const SizedBox(height: SpacingTokens.md),
            LinearProgressIndicator(value: _scanned / widget.pageCount),
            const SizedBox(height: SpacingTokens.xs),
            const Text('正在查找书页，可取消或使用 PDF 页'),
          ],
          if (_error != null) ...[
            const SizedBox(height: SpacingTokens.sm),
            Semantics(
              liveRegion: true,
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          ],
          if (_targets.length > 1) ...[
            const SizedBox(height: SpacingTokens.sm),
            const Text('多个页面使用此书页码，请选择：'),
            for (final page in _targets)
              AppTile(
                flat: true,
                iconColor: Theme.of(context).colorScheme.primary,
                title: 'PDF 第 $page 页',
                subtitle: '',
                onTap: () => Navigator.pop(context, page),
              ),
          ],
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(onPressed: _busy ? null : _submit, child: const Text('跳转')),
    ],
  );
}
