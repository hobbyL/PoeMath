import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poemath/core/widgets/app_widgets.dart';
import 'package:poemath/data/models/picture_story_practice_record.dart';
import 'package:poemath/features/chinese/expression/widgets/picture_story_takes_view.dart';

void main() {
  testWidgets('切换遍次配对各自文字点评和录音，比较时可展开原修订记录', (tester) async {
    final now = DateTime(2026, 11, 17);
    const firstSegment = PictureStorySegment(
      id: 'first-audio',
      position: 0,
      audioPath: '/first.wav',
      durationSeconds: 5,
      transcript: '第一遍原表达',
    );
    const secondSegment = PictureStorySegment(
      id: 'second-audio',
      position: 0,
      audioPath: '/second.wav',
      durationSeconds: 7,
      transcript: '第二遍原表达',
    );
    final first = PictureStoryTake(
      id: 'take-1',
      startedAt: now,
      completedAt: now,
      segments: [firstSegment],
      answerText: '第一遍修改后的表达',
      feedbackJson: '{"text":"第一遍点评"}',
      totalDurationSeconds: 5,
      usedHints: false,
      revisionsJson: jsonEncode([
        PictureStoryAnswerRevision(
          answer: '第一遍原表达',
          feedbackJson: '{"text":"第一遍原点评"}',
          createdAt: now,
        ).toJson(),
        PictureStoryAnswerRevision(
          answer: '第一遍修改后的表达',
          feedbackJson: '{"text":"第一遍修改点评"}',
          createdAt: now,
        ).toJson(),
      ]),
    );
    final record = PictureStoryPracticeRecord(
      id: 'practice',
      profileId: 'default',
      promptId: 'prompt',
      promptVersion: 1,
      startedAt: now,
      completedAt: now,
      status: 'completed',
      segmentsJson: '[]',
      feedbackJson: '{"text":"第二遍点评"}',
      revisionsJson: '[]',
    )..setSegments([secondSegment]);
    record.retellingStateJson = jsonEncode(
      PictureStoryRetellingState(
        archived: [first],
        currentId: 'take-2',
        currentStartedAt: now,
        currentCompletedAt: now,
      ).toJson(),
    );
    var changed = 0;
    PictureStorySegment? played;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            children: [
              ColoredCard(
                color: ThemeData().colorScheme.primary,
                child: PictureStoryTakesView(
                  record: record,
                  playingId: null,
                  onPlay: (segment) => played = segment,
                  onSelectionChanged: () => changed++,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.text('第二遍原表达'), findsOneWidget);
    expect(find.text('第二遍点评'), findsOneWidget);
    expect(find.text('第一遍修改后的表达'), findsNothing);
    await tester.tap(find.text('第 1 遍'));
    await tester.pumpAndSettle();
    expect(find.text('第一遍修改后的表达'), findsOneWidget);
    expect(find.text('第一遍点评'), findsOneWidget);
    expect(find.text('第 1 段录音'), findsOneWidget);
    expect(changed, 1);

    await tester.ensureVisible(find.text('第 1 段录音'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('第 1 段录音'));
    expect(played!.id, firstSegment.id);
    expect(played!.audioPath, firstSegment.audioPath);
    await tester.ensureVisible(find.text('比较两遍表达'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('比较两遍表达'));
    await tester.pumpAndSettle();
    expect(find.text('第一遍修改后的表达'), findsOneWidget);
    expect(find.text('第二遍原表达'), findsOneWidget);
    await tester.ensureVisible(find.text('这一遍的文字修改记录'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('这一遍的文字修改记录'));
    await tester.pumpAndSettle();
    expect(find.text('第一遍原表达'), findsOneWidget);
    expect(find.text('第一遍原点评'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
