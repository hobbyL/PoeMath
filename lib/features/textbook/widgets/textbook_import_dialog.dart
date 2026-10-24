import 'package:flutter/material.dart';
import 'package:poemath/core/theme/spacing_tokens.dart';
import 'package:poemath/data/models/textbook.dart';

class TextbookImportDetails {
  const TextbookImportDetails({
    required this.title,
    required this.grade,
    required this.semester,
    required this.publisher,
    required this.editionNote,
  });
  final String title;
  final int grade;
  final String semester;
  final String publisher;
  final String editionNote;
}

class TextbookImportDialog extends StatefulWidget {
  const TextbookImportDialog({super.key, required this.fileName});
  final String fileName;
  @override
  State<TextbookImportDialog> createState() => _TextbookImportDialogState();
}

class _TextbookImportDialogState extends State<TextbookImportDialog> {
  final _form = GlobalKey<FormState>();
  late final _title = TextEditingController(
    text: widget.fileName
        .replaceFirst(RegExp(r'\.pdf$', caseSensitive: false), ''),
  );
  final _publisher = TextEditingController();
  final _edition = TextEditingController();
  int? _grade;
  String? _semester;
  @override
  void dispose() {
    _title.dispose();
    _publisher.dispose();
    _edition.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('登记教材'),
        content: SingleChildScrollView(
          child: Form(
            key: _form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '请按手中教材填写册次。导入后可查看原书，核对版权页和目录。',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: SpacingTokens.md),
                TextFormField(
                  controller: _title,
                  maxLength: 100,
                  decoration: const InputDecoration(labelText: '书名'),
                  validator: (value) =>
                      value == null || value.trim().isEmpty ? '请填写书名' : null,
                ),
                const SizedBox(height: SpacingTokens.sm),
                DropdownButtonFormField<int>(
                  decoration: const InputDecoration(labelText: '年级'),
                  items: [
                    for (final entry in Textbook.gradeLabels.entries)
                      DropdownMenuItem(
                        value: entry.key,
                        child: Text(entry.value),
                      ),
                  ],
                  onChanged: (value) => _grade = value,
                  validator: (value) => value == null ? '请选择年级' : null,
                ),
                const SizedBox(height: SpacingTokens.md),
                DropdownButtonFormField<String>(
                  decoration: const InputDecoration(labelText: '学期'),
                  items: const [
                    DropdownMenuItem(value: '上', child: Text('上册')),
                    DropdownMenuItem(value: '下', child: Text('下册')),
                  ],
                  onChanged: (value) => _semester = value,
                  validator: (value) => value == null ? '请选择学期' : null,
                ),
                const SizedBox(height: SpacingTokens.md),
                TextFormField(
                  controller: _publisher,
                  maxLength: 80,
                  decoration: const InputDecoration(labelText: '出版社（选填）'),
                ),
                const SizedBox(height: SpacingTokens.sm),
                TextFormField(
                  controller: _edition,
                  maxLength: 160,
                  decoration: const InputDecoration(
                    labelText: '版次 / 印次（选填）',
                    hintText: '例如：2024 年第 1 版',
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              if (!_form.currentState!.validate()) return;
              Navigator.pop(
                context,
                TextbookImportDetails(
                  title: _title.text.trim(),
                  grade: _grade!,
                  semester: _semester!,
                  publisher: _publisher.text.trim(),
                  editionNote: _edition.text.trim(),
                ),
              );
            },
            child: const Text('导入教材'),
          ),
        ],
      );
}
