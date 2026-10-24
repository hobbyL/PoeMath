import 'package:flutter/material.dart';

class TextbookPageDialog extends StatefulWidget {
  const TextbookPageDialog({
    super.key,
    required this.page,
    required this.pageCount,
  });

  final int page;
  final int pageCount;

  @override
  State<TextbookPageDialog> createState() => _TextbookPageDialogState();
}

class _TextbookPageDialogState extends State<TextbookPageDialog> {
  final _form = GlobalKey<FormState>();
  late final _input = TextEditingController(text: '${widget.page}');

  void _submit() {
    if (_form.currentState!.validate()) {
      Navigator.pop(context, int.parse(_input.text.trim()));
    }
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('跳转到 PDF 页'),
        scrollable: true,
        content: Form(
          key: _form,
          child: TextFormField(
            controller: _input,
            autofocus: true,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.go,
            onFieldSubmitted: (_) => _submit(),
            decoration: InputDecoration(labelText: '页码（1–${widget.pageCount}）'),
            validator: (value) {
              final number = int.tryParse(value?.trim() ?? '');
              return number == null || number < 1 || number > widget.pageCount
                  ? '请填写有效页码'
                  : null;
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(onPressed: _submit, child: const Text('跳转')),
        ],
      );
}
