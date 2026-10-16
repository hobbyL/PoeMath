/// 每天首次生成后固定的学习清单；状态只向完成推进，不补发替代任务。
enum TodayTaskKind {
  review('复习'),
  mistake('错题回练'),
  newPoem('新学');

  const TodayTaskKind(this.label);
  final String label;
}

class TodayPlanConfig {
  const TodayPlanConfig({
    this.reviewCount = 2,
    this.mistakeCount = 3,
    this.newPoemCount = 1,
    this.order = const [
      TodayTaskKind.review,
      TodayTaskKind.mistake,
      TodayTaskKind.newPoem,
    ],
  });

  final int reviewCount;
  final int mistakeCount;
  final int newPoemCount;
  final List<TodayTaskKind> order;

  int countFor(TodayTaskKind kind) => switch (kind) {
        TodayTaskKind.review => reviewCount,
        TodayTaskKind.mistake => mistakeCount,
        TodayTaskKind.newPoem => newPoemCount,
      };

  Map<String, dynamic> toJson() => {
        'review': reviewCount,
        'mistake': mistakeCount,
        'newPoem': newPoemCount,
        'order': order.map((kind) => kind.name).toList(),
      };

  factory TodayPlanConfig.fromJson(Map<String, dynamic> json) {
    final counts = [
      json['review'] as int,
      json['mistake'] as int,
      json['newPoem'] as int,
    ];
    final order = (json['order'] as List<dynamic>)
        .map((value) => TodayTaskKind.values.byName(value as String))
        .toList();
    if (counts.any((count) => count < 0 || count > 5) ||
        order.length != TodayTaskKind.values.length ||
        order.toSet().length != order.length) {
      throw const FormatException('今日计划配置无效');
    }
    return TodayPlanConfig(
      reviewCount: counts[0],
      mistakeCount: counts[1],
      newPoemCount: counts[2],
      order: order,
    );
  }
}

class TodayTaskCandidate {
  const TodayTaskCandidate(
      {required this.id, required this.title, required this.baseline,});
  final String id;
  final String title;
  final int baseline;
}

class TodayPlanTask {
  const TodayPlanTask({
    required this.kind,
    required this.targetId,
    required this.title,
    required this.baseline,
    this.completed = false,
  });
  final TodayTaskKind kind;
  final String targetId;
  final String title;
  final int baseline;
  final bool completed;
  String get id => '${kind.name}:$targetId';

  TodayPlanTask complete() => TodayPlanTask(
        kind: kind,
        targetId: targetId,
        title: title,
        baseline: baseline,
        completed: true,
      );

  Map<String, dynamic> toJson() => {
        'kind': kind.name,
        'targetId': targetId,
        'title': title,
        'baseline': baseline,
        'completed': completed,
      };

  factory TodayPlanTask.fromJson(Map<String, dynamic> json) => TodayPlanTask(
        kind: TodayTaskKind.values.byName(json['kind'] as String),
        targetId: json['targetId'] as String,
        title: json['title'] as String,
        baseline: json['baseline'] as int,
        completed: json['completed'] as bool,
      );
}

class TodayPlan {
  const TodayPlan({
    required this.dateKey,
    required this.profileId,
    required this.grade,
    required this.semester,
    required this.tasks,
    this.epoch = 0,
  });
  final String dateKey;
  final String profileId;
  final int grade;
  final String semester;
  final List<TodayPlanTask> tasks;
  final int epoch;
  int get completedCount => tasks.where((task) => task.completed).length;

  Map<String, dynamic> toJson() => {
        'version': 1,
        'date': dateKey,
        'epoch': epoch,
        'profileId': profileId,
        'grade': grade,
        'semester': semester,
        'tasks': tasks.map((task) => task.toJson()).toList(),
      };

  factory TodayPlan.fromJson(Map<String, dynamic> json) {
    final tasks = (json['tasks'] as List<dynamic>)
        .map((value) => TodayPlanTask.fromJson(value as Map<String, dynamic>))
        .toList();
    final grade = json['grade'] as int;
    final semester = json['semester'] as String;
    final epoch = json['epoch'] as int? ?? 0;
    if (json['version'] != 1 ||
        tasks.length > 15 ||
        grade < 1 ||
        grade > 6 ||
        epoch < 0 ||
        !const ['上', '下'].contains(semester) ||
        tasks.map((t) => t.id).toSet().length != tasks.length) {
      throw const FormatException('今日计划无效');
    }
    return TodayPlan(
      dateKey: json['date'] as String,
      profileId: json['profileId'] as String,
      grade: grade,
      semester: semester,
      tasks: tasks,
      epoch: epoch,
    );
  }
}

String planDateKey(DateTime date) =>
    '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
