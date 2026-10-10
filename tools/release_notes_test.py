#!/usr/bin/env python3
"""tools/release_notes.py 自测（零依赖纯 assert）。

用法：
    python3 tools/release_notes_test.py

断言全部落在纯函数 build_notes 上，不依赖本仓 git 历史，CI 可重复。
失败以非 0 退出（AssertionError 冒泡）。
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from release_notes import MAX_ITEMS, TRUNCATED_HINT, build_notes  # noqa: E402


def test_groups_and_filtering():
    """v0.0.7 风格输入 → 三小节齐、条目以 '• ' 起、chore/docs 类被丢弃。"""
    notes = build_notes([
        'fix(llm): 配置链路审查修复——弹层死锁/编辑竞态/防御与语义补齐',
        'feat(llm-settings): AI 讲解提示词内置到设置——可见可编辑与重置恢复默认',
        'refactor(math-engine): 错因中文标签收敛为单一映射表',
        'feat(llm): 诗词与口算 AI 讲解——场景级厂商选择与单轮讲解链路',
        'perf(poem): 列表滚动性能优化',
        'chore: bump deps',
        'docs: README 同步 AI 能力',
        'ci: 修复发布流水线',
        'test(math): 补充生成器用例',
    ])

    assert '新增功能' in notes, notes
    assert '问题修复' in notes, notes
    assert '优化改进' in notes, notes
    assert '其他更新' not in notes, notes

    items = [line for line in notes.split('\n') if line.startswith('• ')]
    assert len(items) == 5, items
    for line in notes.split('\n'):
        if line and line not in ('新增功能', '问题修复', '优化改进'):
            assert line.startswith('• '), line

    # 丢弃类 commit 文案不得泄漏到 notes。
    for dropped in ('bump deps', 'README 同步 AI 能力', '修复发布流水线', '补充生成器用例'):
        assert dropped not in notes, notes

    # scope 是内部模块名，不进 notes。
    assert 'llm-settings' not in notes, notes

    # 小节顺序固定：新增功能 → 问题修复 → 优化改进。
    assert notes.index('新增功能') < notes.index('问题修复') < notes.index('优化改进'), notes


def test_all_dropped_yields_empty():
    """全为 chore/docs/test/ci 类 → 空串（workflow 据此写入空 notes）。"""
    notes = build_notes([
        'chore: bump deps',
        'docs: 更新 README',
        'test: 补充用例',
        'ci: 调整流水线',
        'style: 格式化',
        'build: 升级 gradle',
        'revert: 回滚上一次改动',
    ])

    assert notes == '', repr(notes)
    assert build_notes([]) == ''
    assert build_notes(['', '   ']) == ''


def test_task_reference_marker_stripped():
    """描述尾部的内部任务引用标记（(AC4) / （#12））被剥离。"""
    notes = build_notes([
        'feat(poem): TTS 朗读 + 拼音显隐切换 (AC4)',
        'fix(math): 错题重练入口修复（#12）',
        'Initial commit',
    ])

    assert '(AC4)' not in notes, notes
    assert '#12' not in notes, notes
    assert '• TTS 朗读 + 拼音显隐切换' in notes, notes
    assert '• 错题重练入口修复' in notes, notes
    # 非规范 commit 兜底归入「其他更新」。
    assert '其他更新' in notes, notes
    assert '• Initial commit' in notes, notes


def test_dedup_and_truncation():
    """同文案去重；条目超 MAX_ITEMS 时截断并追加提示。"""
    deduped = build_notes([
        'feat(a): 同一件事',
        'feat(b): 同一件事',
    ])
    assert deduped.count('• 同一件事') == 1, deduped

    many = build_notes(
        ['feat(x): 功能 {}'.format(i) for i in range(MAX_ITEMS + 5)],
    )
    items = [line for line in many.split('\n') if line.startswith('• ')]
    assert len(items) == MAX_ITEMS, len(items)
    assert many.endswith(TRUNCATED_HINT), many[-40:]


def main():
    tests = [
        test_groups_and_filtering,
        test_all_dropped_yields_empty,
        test_task_reference_marker_stripped,
        test_dedup_and_truncation,
    ]
    for test in tests:
        test()
        print('PASS {}'.format(test.__name__))
    print('{} tests passed'.format(len(tests)))
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
