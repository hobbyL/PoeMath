import 'package:poemath/data/models/poem.dart';

/// 只以内容中的册次字段确定教材归属，不用难度推测教材单元。
List<Poem> requiredTextbookPoems(
    Iterable<Poem> poems, int grade, String semester,) {
  return poems
      .where((poem) =>
          poem.grade == grade && poem.semester == semester && poem.isRequired,)
      .toList()
    ..sort(compareCurriculumPoems);
}

int compareCurriculumPoems(Poem a, Poem b) {
  final unitA = a.textbookUnit ?? '';
  final unitB = b.textbookUnit ?? '';
  final indexA = RegExp(r'课文(\d+)').firstMatch(unitA);
  final indexB = RegExp(r'课文(\d+)').firstMatch(unitB);
  if (indexA != null || indexB != null) {
    final order = (indexA == null ? 10000 : int.parse(indexA.group(1)!))
        .compareTo(indexB == null ? 10000 : int.parse(indexB.group(1)!));
    if (order != 0) return order;
  }
  final unitOrder = unitA.compareTo(unitB);
  return unitOrder != 0 ? unitOrder : a.id.compareTo(b.id);
}
