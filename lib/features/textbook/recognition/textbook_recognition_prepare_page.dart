import 'dart:async';
import 'package:flutter/material.dart';
import 'package:poemath/core/services/parent_access_service.dart';
import 'package:poemath/core/theme/spacing_tokens.dart';
import 'package:poemath/core/widgets/app_widgets.dart';
import 'package:poemath/core/widgets/parent_access_boundary.dart';
import 'package:poemath/data/models/textbook_course.dart';
import 'package:poemath/data/models/textbook_course_review.dart';
import 'package:poemath/data/models/textbook_recognition_progress.dart';
import 'package:poemath/domain/textbook_recognition_content.dart';
import 'package:poemath/domain/textbook_recognition_session.dart';
import 'package:poemath/features/textbook/providers/textbook_providers.dart';
import 'package:poemath/features/textbook/recognition/recognition_page_state.dart';
import 'package:poemath/features/textbook/textbook_course_editor_page.dart';
import 'package:poemath/features/textbook/textbook_source_page.dart';
import 'package:poemath/features/textbook/widgets/textbook_course_content.dart';

class TextbookRecognitionPreparePage extends RecognitionPage {
  const TextbookRecognitionPreparePage({
    super.key,
    required super.bookId,
    required super.lessonId,
    super.routeObserver,
  });
  @override
  RecognitionPageState<TextbookRecognitionPreparePage> createState() =>
      _PrepareState();
}

class _PrepareState
    extends RecognitionPageState<TextbookRecognitionPreparePage> {
  final selected = <String>{};
  final chosen = <String, String>{};
  bool scopeChecked = false;
  String? playingKey;
  List<RecognitionTarget> get preview => pack == null || lesson == null
      ? []
      : recognitionTargets(pack!, lesson!, preview: true);
  RecognitionCue? _cue(RecognitionTarget t) =>
      t.cues.where((c) => c.key == chosen[t.id]).firstOrNull ??
      t.cues.where((c) => c.nodeId != t.id).firstOrNull ??
      t.cues.firstOrNull;
  Future<void> _source(TextbookCourseNode node) async {
    if (!await ensureParentAccess(context) ||
        !current ||
        node.sources.isEmpty) {
      return;
    }
    await stopAudio();
    if (!mounted || !current) return;
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            TextbookCourseSourcePage(book: book!, sources: node.sources),
      ),
    );
  }

  Future<void> _edit(TextbookCourseNode node) async {
    if (!await ensureParentAccess(context) || !current) return;
    await stopAudio();
    if (!mounted || !current) return;
    await Navigator.push<TextbookCoursePack>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            TextbookCourseEditorPage(book: book!, pack: pack!, node: node),
      ),
    );
    if (!current) return;
    selected.clear();
    chosen.clear();
    scopeChecked = false;
    playingKey = null;
    ref.invalidate(textbookCourseProvider(widget.bookId));
    await reload();
  }

  Future<void> _approve() async {
    if (busy ||
        !scopeChecked ||
        selected.isEmpty ||
        !await ensureParentAccess(context) ||
        !current) {
      return;
    }
    final previous = pack!,
        b = book!,
        courses = ref.read(textbookCourseRepositoryProvider);
    final ids = <String>{lesson!.id};
    for (final t in preview.where((t) => selected.contains(t.id))) {
      ids.add(t.id);
      final c = _cue(t);
      if (c != null) ids.add(c.nodeId);
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      var json = previous.toJson();
      final at = DateTime.now();
      for (final node in previous.nodes.where((n) => ids.contains(n.id))) {
        if (node.isApproved) continue;
        json = reviewTextbookCourse(
          input: json,
          nodeId: node.id,
          reviewer: '本机家长',
          decision: 'approved',
          checks: node.requiredChecks,
          notes: '已对照原书核对本课归属、认字范围及选定生字/示范',
          at: at,
        );
      }
      await courses.save(
        b,
        TextbookCoursePack.fromJson(json),
        previous: previous,
        authorize: ParentAccessService.instance.assertAllowed,
      );
      if (!current) return;
      ref.invalidate(textbookCourseProvider(widget.bookId));
      await reload();
    } on Object catch (e) {
      if (current) setState(() => error = message(e));
    } finally {
      if (current) setState(() => busy = false);
    }
  }

  void _confirmAudio(RecognitionTarget t, RecognitionCue c) {
    if (!heard || heardIdentity == null || playingKey != c.key || busy) return;
    final identity = heardIdentity!,
        p = progress!,
        repo = repository!,
        fp = fingerprint;
    final op = 'audio/${t.fingerprint}/${c.key}/${identity.signature}';
    unawaited(
      runWrite(
        () => repo.change(
          lessonId: widget.lessonId,
          fingerprint: fp,
          operationId: op,
          expectedRevision: p.revision,
          authorize: ParentAccessService.instance.assertAllowed,
          reduce: (latest, _) => latest.copy(
            audio: {
              ...latest.audio,
              c.key: RecognitionAudioApproval(
                fingerprint: t.fingerprint,
                cueKey: c.key,
                identity: identity,
              ),
            },
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[
      const Text('先对照原书核对。可以只准备确定的几个字；准备内容不计入孩子的学习成绩。'),
      const SizedBox(height: SpacingTokens.md),
      if (lesson != null)
        AppTile(
          iconColor: Theme.of(context).colorScheme.primary,
          subtitle: '',
          icon: Icons.menu_book_outlined,
          title: lesson!.title,
          onTap:
              lesson!.sources.isEmpty || busy ? null : () => _source(lesson!),
        ),
      Material(
        type: MaterialType.transparency,
        child: CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          value: scopeChecked,
          onChanged:
              busy ? null : (v) => setState(() => scopeChecked = v ?? false),
          title: const Text('已确认课目归属、来源页和本课认字范围'),
        ),
      ),
      for (final t in preview) _target(t),
      const SizedBox(height: SpacingTokens.md),
      FilledButton(
        onPressed: busy || !scopeChecked || selected.isEmpty ? null : _approve,
        child: const Text('保存核对的内容'),
      ),
      const SizedBox(height: SpacingTokens.sm),
      const Text('保存后，请试听实际示范。只有播放完整并确认读准的片段，才用于孩子的听音题。音色变化后需要重新确认。'),
      TextButton(
        onPressed: busy ? null : () => Navigator.pop(context),
        child: const Text('完成，返回本课'),
      ),
    ];
    return ParentAccessBoundary(child: frame('家长准备', rows));
  }

  Widget _target(RecognitionTarget t) {
    final c = _cue(t);
    final node =
        c == null ? t.node : pack!.nodes.firstWhere((n) => n.id == c.nodeId);
    final readyTarget = targets.firstWhere((r) => r.id == t.id);

    return Padding(
      padding: const EdgeInsets.only(bottom: SpacingTokens.md),
      child: ColoredCard(
        color: Theme.of(context).colorScheme.primary,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextbookCourseText(node: t.node),
            AppTile(
              iconColor: Theme.of(context).colorScheme.primary,
              subtitle: '',
              icon: Icons.menu_book_outlined,
              title: '对照生字原书',
              onTap:
                  t.node.sources.isEmpty || busy ? null : () => _source(t.node),
            ),
            AppTile(
              iconColor: Theme.of(context).colorScheme.primary,
              subtitle: '',
              icon: Icons.edit_outlined,
              title: '修改生字、拼音或来源',
              onTap: busy ? null : () => _edit(t.node),
            ),
            if (c == null)
              const Text('注音尚不能确定，请先修改并核对。')
            else ...[
              DropdownButtonFormField<String>(
                initialValue: c.key,
                isExpanded: true,
                decoration: const InputDecoration(labelText: '这次使用的示范'),
                items: [
                  for (final cue in t.cues)
                    DropdownMenuItem(
                      value: cue.key,
                      child: Text(
                        cue.text,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: busy
                    ? null
                    : (v) {
                        unawaited(stopAudio());
                        setState(() {
                          chosen[t.id] = v!;
                          playingKey = null;
                        });
                      },
              ),
              if (node is TextbookCourseParagraph && node.id != t.id) ...[
                TextbookCourseText(node: node),
                AppTile(
                  iconColor: Theme.of(context).colorScheme.primary,
                  subtitle: '',
                  icon: Icons.menu_book_outlined,
                  title: '对照示范原书',
                  onTap: busy ? null : () => _source(node),
                ),
                AppTile(
                  iconColor: Theme.of(context).colorScheme.primary,
                  subtitle: '',
                  icon: Icons.edit_outlined,
                  title: '修改示范和拼音',
                  onTap: busy ? null : () => _edit(node),
                ),
              ],
              Material(
                type: MaterialType.transparency,
                child: CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: selected.contains(t.id),
                  title: const Text('已核对这个字、拼音和选定示范'),
                  onChanged: busy
                      ? null
                      : (v) => setState(() {
                            if (v == true) {
                              selected.add(t.id);
                            } else {
                              selected.remove(t.id);
                            }
                          }),
                ),
              ),
              if (readyTarget.ready &&
                  readyTarget.cues.any((x) => x.key == c.key))
                _audioControls(readyTarget, c),
              if (readyTarget.ready &&
                  c.nodeId != t.id &&
                  readyTarget.cues.isNotEmpty) ...[
                const Text('再试听单字，用于在词句里找字。'),
                _audioControls(
                  readyTarget,
                  readyTarget.cues.firstWhere((x) => x.nodeId == t.id),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _audioControls(RecognitionTarget t, RecognitionCue c) {
    final approved = recognitionAudio(progress!, t, c) != null;
    final active = playingKey == c.key &&
        ['playing', 'preparing', 'buffering'].contains(audioStatus?.name);
    final paused = playingKey == c.key && audioStatus?.name == 'paused';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        OutlinedButton.icon(
          onPressed: busy
              ? null
              : () async {
                  if (playingKey != c.key) await stopAudio();
                  if (!current) return;
                  setState(() => playingKey = c.key);
                  playAudio(c.text);
                },
          icon: Icon(active ? Icons.pause : Icons.volume_up_outlined),
          label: Text(
            active
                ? '暂停'
                : paused
                    ? '继续播放'
                    : '试听示范：${c.text}',
          ),
        ),
        TextButton(
          onPressed:
              busy || !heard || heardText != c.text || playingKey != c.key
                  ? null
                  : () => _confirmAudio(t, c),
          child: Text(approved ? '已确认此片段读准' : '完整听过，确认读准'),
        ),
      ],
    );
  }
}
