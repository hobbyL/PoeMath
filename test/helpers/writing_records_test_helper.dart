import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

List<String> writingRecordTexts(WidgetTester tester, String targetId) => [
  for (final text in tester.widgetList<Text>(
    find.descendant(
      of: find.byKey(ValueKey('writing-record-$targetId')),
      matching: find.byType(Text),
    ),
  ))
    text.data!,
];
