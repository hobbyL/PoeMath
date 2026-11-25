import 'package:flutter/material.dart';

/// Count visible characters, including punctuation, without spaces/newlines.
/// Grapheme clusters keep a supplementary Han character or emoji as one.
int pictureStoryTextLength(String text) =>
    text.characters.where((character) => character.trim().isNotEmpty).length;

/// Shared editing surface for recognized speech and later answer revisions.
class PictureStoryTextArea extends StatelessWidget {
  const PictureStoryTextArea({
    super.key,
    required this.controller,
    required this.onChanged,
    this.label = '识别文字（可修改）',
    this.readOnly = false,
    this.maxLength,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final String label;
  final bool readOnly;
  final int? maxLength;

  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    readOnly: readOnly,
    minLines: 5,
    maxLines: null,
    maxLength: maxLength,
    keyboardType: TextInputType.multiline,
    textInputAction: TextInputAction.newline,
    textAlignVertical: TextAlignVertical.top,
    style: Theme.of(context).textTheme.bodyLarge,
    decoration: InputDecoration(
      labelText: label,
      alignLabelWithHint: true,
      floatingLabelBehavior: FloatingLabelBehavior.always,
      counter: ValueListenableBuilder<TextEditingValue>(
        valueListenable: controller,
        builder: (context, value, _) => Text(
          '${pictureStoryTextLength(value.text)} 字',
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
      ),
    ),
    onChanged: onChanged,
  );
}
