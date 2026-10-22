import 'models/math_problem.dart';
import 'models/word_problem_plan.dart';
import 'word_problem_catalog.dart';
import 'word_problem_plan_rules.dart';

typedef RenderedWordProblem = ({String text, String explanation});

class WordProblemRenderer {
  const WordProblemRenderer._();

  static RenderedWordProblem render(WordProblemPlan plan) {
    final result = WordProblemPlanRules.validate(plan);
    if (!result.canSave) throw ArgumentError(result.issues.first.message);
    final scene = WordProblemCatalog.find(plan.sceneId)!;
    final values = plan.skeleton.operands;
    final a = values[0], b = values[1];
    final object = scene.object, unit = scene.unit, group = scene.group;
    final prefix = plan.variantId == 'alternate' ? '活动准备时，' : '';
    final text = switch (plan.relation) {
      WordProblemRelation.merge =>
        '$prefix${scene.place}里有$a$unit$object，又运来$b$unit$object，合起来有多少$unit$object？',
      WordProblemRelation.increase =>
        '$prefix${scene.place}原有$a$unit$object，又添了$b$unit$object，现在有多少$unit$object？',
      WordProblemRelation.decrease =>
        '$prefix${scene.place}原有$a$unit$object，用去$b$unit$object，还剩多少$unit$object？',
      WordProblemRelation.more =>
        '$prefix小明有$a$unit$object，小红比小明多$b$unit，小红有多少$unit$object？',
      WordProblemRelation.less =>
        '$prefix小明有$a$unit$object，小红比小明少$b$unit，小红有多少$unit$object？',
      WordProblemRelation.difference =>
        '$prefix甲组有$a$unit$object，乙组有$b$unit$object，甲组比乙组多多少$unit$object？',
      WordProblemRelation.restoreInitial =>
        '$prefix${scene.place}用去$b$unit$object后，还剩$a$unit$object，原来有多少$unit$object？',
      WordProblemRelation.findAdded =>
        '$prefix${scene.place}原有$b$unit$object，又添了一些后有$a$unit$object，添了多少$unit$object？',
      WordProblemRelation.inverseMore =>
        '$prefix小红有$a$unit$object，比小明多$b$unit，小明有多少$unit$object？',
      WordProblemRelation.inverseLess =>
        '$prefix小红有$a$unit$object，比小明少$b$unit，小明有多少$unit$object？',
      WordProblemRelation.equalGroups => scene.purchase
          ? '$prefix每$group${scene.object}$a元，买$b$group${scene.object}，一共花了多少元？'
          : scene.id == 'petals'
              ? '$prefix每朵纸花有$a片花瓣，$b朵这样的纸花共有多少片花瓣？'
              : '$prefix每$group有$a$unit$object，$b$group共有多少$unit$object？',
      WordProblemRelation.equalShare =>
        '$prefix一共有$a$unit$object，平均分给$b个小组，每组分到多少$unit$object？',
      WordProblemRelation.groupCount => scene.id == 'money'
          ? '$prefix一共有$a元活动经费，每份分配$b元，可以分成多少份？'
          : '$prefix一共有$a$unit$object，每$group装$b$unit，能装多少$group？',
      WordProblemRelation.sequential => _sequential(plan, scene, prefix),
      WordProblemRelation.groupedChange => '$prefix${scene.place}原有$a$unit$object，'
          '${plan.skeleton.operators.first == Operator.add ? '又运来' : '取出'}${values[2]}$group，'
          '每$group有$b$unit$object，${plan.skeleton.operators.first == Operator.add ? '现在有' : '还剩'}多少$unit$object？',
      WordProblemRelation.sharedChange =>
        plan.skeleton.operators.first == Operator.add
            ? '$prefix甲组原有$a$unit$object。乙组把$b$unit$object平均分成${values[2]}份，'
                '送给甲组其中一份。甲组现在有多少$unit$object？'
            : '$prefix甲组原有$a$unit$object。乙组把$b$unit$object平均分成${values[2]}份。'
                '甲组送出与乙组一份同样多的$object，甲组还剩多少$unit$object？',
    };
    final quantities = {
      for (final q in WordProblemPlanRules.quantities(plan)) q.id: q,
    };
    final reasons = _reasons(plan);
    final lines = <String>[];
    final steps = WordProblemPlanRules.steps(plan);
    for (var i = 0; i < steps.length; i++) {
      final step = steps[i];
      lines.add(
          '${reasons[i]}${quantities[step.inputs[0]]!.value} ${step.operator.symbol} '
          '${quantities[step.inputs[1]]!.value} = ${step.value}。');
    }
    lines.add('答：${plan.skeleton.answer}${plan.skeleton.unitHint}。');
    final explanation = lines.join('\n');
    if (text.length > 120 || explanation.length > 300) {
      throw StateError('本地模板超过长度限制');
    }
    return (text: text, explanation: explanation);
  }

  static String _sequential(
    WordProblemPlan plan,
    WordProblemScene scene,
    String prefix,
  ) {
    final values = plan.skeleton.operands;
    final phrases = <String>[];
    for (var i = 0; i < plan.skeleton.operators.length; i++) {
      final verb = plan.skeleton.operators[i] == Operator.add ? '添了' : '用去';
      phrases.add('$verb${values[i + 1]}${scene.unit}${scene.object}');
    }
    return '$prefix${scene.place}原有${values[0]}${scene.unit}${scene.object}，'
        '${phrases.join('，又')}，最后有多少${scene.unit}${scene.object}？';
  }

  static List<String> _reasons(WordProblemPlan plan) => switch (plan.relation) {
        WordProblemRelation.merge => ['求合起来的数量，用加法。'],
        WordProblemRelation.increase => ['求增加后的数量，用加法。'],
        WordProblemRelation.decrease => ['求剩下的数量，用减法。'],
        WordProblemRelation.more => ['小红比小明多，把原有数量加上多出的数量。'],
        WordProblemRelation.less => ['小红比小明少，从原有数量减去少的数量。'],
        WordProblemRelation.difference => ['求相差的数量，用较大的数量减去较小的数量。'],
        WordProblemRelation.restoreInitial => ['求原来的数量，把剩下的数量加上用去的数量。'],
        WordProblemRelation.findAdded => ['求添了多少，从现在的数量减去原有的数量。'],
        WordProblemRelation.inverseMore => ['小红比小明多，求小明的数量要从小红的数量减去多出的数量。'],
        WordProblemRelation.inverseLess => ['小红比小明少，求小明的数量要在小红的数量上加上少的数量。'],
        WordProblemRelation.equalGroups => ['求总量，用每份数量乘份数。'],
        WordProblemRelation.equalShare => ['求每组数量，用总量除以组数。'],
        WordProblemRelation.groupCount => ['求份数，用总量除以每份数量。'],
        WordProblemRelation.sequential => ['先计算第一次变化后的数量。', '再计算第二次变化后的数量。'],
        WordProblemRelation.groupedChange => [
            '先用每份数量乘份数，求变化的总量。',
            plan.skeleton.operators.first == Operator.add
                ? '再加上原有数量。'
                : '再从原有数量减去取出的总量。',
          ],
        WordProblemRelation.sharedChange => [
            '先用分配总量除以份数，求一份的数量。',
            plan.skeleton.operators.first == Operator.add
                ? '再加上原有数量。'
                : '再从原有数量减去取走的数量。',
          ],
      };
}
