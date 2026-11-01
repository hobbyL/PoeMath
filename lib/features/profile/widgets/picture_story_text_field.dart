import 'package:flutter/material.dart';
import 'package:poemath/data/models/picture_story_editor_draft.dart';
import 'package:poemath/data/models/picture_story_prompt.dart';

/// 手动题目和 AI 候选使用相同字段、长度和可空规则。
class PictureStoryTextField extends StatelessWidget {
  const PictureStoryTextField({
    super.key,
    required this.field,
    required this.controller,
    required this.onChanged,
    this.enabled = true,
  });
  final PictureStoryEditorField field;
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final (label, maxLength, multiline, required) = switch (field) {
      PictureStoryEditorField.title => (
          '题目标题',
          PictureStoryPrompt.maxTitleLength,
          false,
          true
        ),
      PictureStoryEditorField.theme => (
          '主题（选填）',
          PictureStoryPrompt.maxThemeLength,
          false,
          false
        ),
      PictureStoryEditorField.questions => ('引导问题', null, true, true),
      PictureStoryEditorField.sceneFacts => ('观察提示（选填）', null, true, false),
      PictureStoryEditorField.goals => ('练习目标（选填）', null, true, false),
      PictureStoryEditorField.reference => (
          '参考表达（选填）',
          PictureStoryPrompt.maxReferenceLength,
          true,
          false
        ),
    };
    return TextFormField(
      key: ValueKey('picture-story-${field.name}'),
      controller: controller,
      enabled: enabled,
      minLines: multiline ? 3 : 1,
      maxLines: null,
      maxLength: maxLength,
      keyboardType: multiline ? TextInputType.multiline : TextInputType.text,
      textInputAction:
          multiline ? TextInputAction.newline : TextInputAction.next,
      decoration: InputDecoration(
        labelText: label,
        helperText: maxLength == null
            ? '每行一条，最多 ${PictureStoryPrompt.maxLines} 条'
            : null,
      ),
      onChanged: onChanged,
      validator: (value) {
        try {
          if (maxLength == null) {
            PictureStoryPrompt.checkedLines(
              (value ?? '').split('\n'),
              label: label,
              required: required,
            );
          } else {
            PictureStoryPrompt.checkedText(
              value ?? '',
              label: label,
              maxLength: maxLength,
              required: required,
            );
          }
          return null;
        } on FormatException catch (error) {
          return error.message;
        }
      },
    );
  }
}
