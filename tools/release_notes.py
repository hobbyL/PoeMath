#!/usr/bin/env python3
"""从 git 历史生成面向用户的中文 release notes。

用法：
    python3 tools/release_notes.py [TAG]

TAG 缺省读环境变量 GITHUB_REF_NAME，再缺省回落 'HEAD'。
stdout 只输出 notes 文本（无可展示变更时为空串），诊断信息走 stderr。
notes 为空也以 0 退出；仅 tag 不存在 / git 不可用等硬错误非 0。

设计契约见 .trellis/tasks/10-10-update-dialog-notes-fix/design.md §2.1 / §3.1。
"""

import os
import re
import subprocess
import sys

# conventional commit type → 面向用户的中文小节（顺序即输出顺序）。
GROUPS = [
    ('新增功能', {'feat'}),
    ('问题修复', {'fix'}),
    ('优化改进', {'refactor', 'perf'}),
]
OTHERS_TITLE = '其他更新'

# 对用户无意义的类型，直接丢弃。
DROP = {'chore', 'docs', 'test', 'ci', 'style', 'build', 'revert'}

PATTERN = re.compile(
    r'^(?P<type>[a-z]+)(?:\((?P<scope>[^)]*)\))?(?P<bang>!)?:\s*(?P<desc>.+)$',
)

# 描述尾部的内部任务引用标记（如 "(AC4)" / "（#12）"），对用户无意义。
TASK_REF = re.compile(r'\s*[（(](?:AC\d+|#\d+)[）)]\s*$')

# 条目总数硬上限，防止一次发版上百 commit 把 latest.json 撑大。
MAX_ITEMS = 30
TRUNCATED_HINT = '还有更多细节改进，详见发布页面。'


def _clean_desc(desc):
    """剥离描述尾部的任务引用标记并去空白。"""
    text = desc.strip()
    while True:
        stripped = TASK_REF.sub('', text).strip()
        if stripped == text:
            return text
        text = stripped


def build_notes(subjects):
    """commit subject 列表 → 分组 notes 文本（纯函数，无 git 依赖）。"""
    buckets = {title: [] for title, _ in GROUPS}
    buckets[OTHERS_TITLE] = []

    for subject in subjects:
        raw = (subject or '').strip()
        if not raw:
            continue
        match = PATTERN.match(raw)
        if not match:
            # 非规范 commit（如 "Initial commit"）兜底归入「其他更新」。
            desc = _clean_desc(raw)
            if desc and desc not in buckets[OTHERS_TITLE]:
                buckets[OTHERS_TITLE].append(desc)
            continue

        ctype = match.group('type')
        if ctype in DROP:
            continue
        desc = _clean_desc(match.group('desc'))
        if not desc:
            continue

        title = OTHERS_TITLE
        for group_title, types in GROUPS:
            if ctype in types:
                title = group_title
                break
        if desc not in buckets[title]:
            buckets[title].append(desc)

    total = 0
    truncated = False
    blocks = []
    for title in [t for t, _ in GROUPS] + [OTHERS_TITLE]:
        items = buckets.get(title) or []
        kept = []
        for item in items:
            if total >= MAX_ITEMS:
                truncated = True
                break
            kept.append('• {}'.format(item))
            total += 1
        if kept:
            blocks.append(title + '\n' + '\n'.join(kept))

    notes = '\n\n'.join(blocks)
    if truncated:
        notes = notes + '\n\n' + TRUNCATED_HINT if notes else TRUNCATED_HINT
    return notes


def _git(args):
    """执行 git 命令，返回 (returncode, stdout)。git 不可用时硬失败。"""
    try:
        done = subprocess.run(
            ['git'] + args,
            capture_output=True,
            text=True,
            check=False,
        )
    except OSError as error:  # git 不在 PATH 等硬错误
        print('git 执行失败：{}'.format(error), file=sys.stderr)
        raise SystemExit(1)
    return done.returncode, done.stdout.strip()


def _rev_exists(rev):
    code, _ = _git(['rev-parse', '--verify', '--quiet', '{}^{{commit}}'.format(rev)])
    return code == 0


def previous_tag(tag):
    """上一个 tag；首个 tag 或浅克隆时返回 None。"""
    code, out = _git(['describe', '--tags', '--abbrev=0', '{}^'.format(tag)])
    if code != 0 or not out:
        print(
            '未能定位上一个 tag（首个版本或浅克隆），退化为全量 commit。',
            file=sys.stderr,
        )
        return None
    return out


def collect_subjects(tag):
    """返回 (subjects, prev_tag)；tag 不存在时硬失败。"""
    if not _rev_exists(tag):
        print('tag/revision 不存在：{}'.format(tag), file=sys.stderr)
        raise SystemExit(1)

    prev = previous_tag(tag)
    rev = '{}..{}'.format(prev, tag) if prev else tag
    code, out = _git(['log', '--no-merges', '--pretty=format:%s', rev])
    if code != 0:
        print('git log 失败：{}'.format(rev), file=sys.stderr)
        raise SystemExit(1)
    subjects = [line.strip() for line in out.split('\n') if line.strip()]
    return subjects, prev


def main(argv):
    tag = argv[1] if len(argv) > 1 else os.environ.get('GITHUB_REF_NAME') or 'HEAD'
    subjects, prev = collect_subjects(tag)
    notes = build_notes(subjects)
    adopted = sum(1 for line in notes.split('\n') if line.startswith('• '))
    print(
        'tag={} prev={} commits={} items={} chars={}'.format(
            tag,
            prev or '(none)',
            len(subjects),
            adopted,
            len(notes),
        ),
        file=sys.stderr,
    )
    # notes 为空也正常退出：workflow 据此写入空 notes，不回落版本号占位。
    sys.stdout.write(notes)
    if notes:
        sys.stdout.write('\n')
    return 0


if __name__ == '__main__':
    raise SystemExit(main(sys.argv))
