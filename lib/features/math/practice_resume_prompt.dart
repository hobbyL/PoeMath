import 'package:flutter/material.dart';

/// true 续练，false 明确开始新练习，null 取消进入且保留草稿。
Future<bool?> choosePracticeResume(BuildContext context, String subject) =>
    showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text('还有一组未完成的$subject'),
        content: const Text('继续上次题组，或放弃草稿后开始新的练习。已完成的答题记录会保留。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('开始新练习'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('继续上次'),
          ),
        ],
      ),
    );
