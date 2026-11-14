import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:poemath/data/models/math_textbook_course.dart';

/// 中文使用正常段落换行，公式保留二维排版；长公式可横向查看。
class MathTextbookContent extends StatelessWidget {
  const MathTextbookContent({super.key, required this.spans});
  final List<MathTextbookSpan> spans;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final style = Theme.of(context).textTheme.bodyLarge!;
      return Text.rich(
        TextSpan(
          children: [
            for (final span in spans)
              if (span.text != null)
                TextSpan(text: span.text)
              else
                WidgetSpan(
                  alignment: PlaceholderAlignment.middle,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: constraints.maxWidth),
                    child: Semantics(
                      label: _expressionLabel(span.expression!),
                      child: ExcludeSemantics(
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Math.tex(
                            span.expression!.latex,
                            textStyle: style.copyWith(
                              fontSize: MediaQuery.textScalerOf(context)
                                  .scale(style.fontSize!),
                            ),
                            onErrorFallback: (_) => const Text('公式暂无法显示，请查看原书'),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
          ],
        ),
        style: style,
      );
    },
  );
}

String _expressionLabel(MathTextbookExpression expression) {
  if (expression is! MathTextbookVerticalAddition) return expression.readable;
  final carries = expression.carries.map(
    (carry) => '从右数第 ${carry.columnFromRight + 1} 列进位 ${carry.value}',
  );
  return ['加法竖式', expression.readable, ...carries].join('，');
}
