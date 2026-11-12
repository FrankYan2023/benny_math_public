import 'package:benny_math/logic/answer_check.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // 数值、方程的解、选择、表达式
  final cases = <(String, List<String>, String, bool)>[
    ('-1/2', ['-0.5'], '数值', true),
    (r'\frac{1}{2}', ['0.5'], '数值', true),
    ('x=3', ['3'], '方程的解', true),
    ('3', ['x=3'], '方程的解', true),
    ('b', ['B'], '选择', true),
    ('2.5', ['5/2'], '数值', true),
    ('−10', ['-10'], '数值', true),
    ('3a+2b', ['3a+2b'], '表达式', true),
    ('-6', ['4'], '数值', false),
    ('', ['4'], '数值', false),
    ('C', ['B'], '选择', false),
    (r'$-\dfrac{3}{4}$', ['-3/4'], '数值', true),
    ('(-3)/(4)', ['-0.75'], '数值', true),
    ('10', ['-10'], '数值', false),
    ('５', ['5'], '数值', true), // 全角数字
    // 表达式：解析成多项式比较（Benny 2026-10-05 的真题，参考答案是 GPT 写的 LaTeX）
    ('4x^4-1/4', [r'$4x^4-\frac{1}{4}$'], '表达式', true),
    ('4x^4-0.25', [r'$4x^4-\frac{1}{4}$'], '表达式', true),
    ('-1/4+4x^4', [r'$4x^4-\frac{1}{4}$'], '表达式', true),
    ('4x⁴-1/4', [r'4x^4-\frac14'], '表达式', true),
    ('4x^4+1/4', [r'$4x^4-\frac{1}{4}$'], '表达式', false),
    ('3x^3+x^2-3/4x+1/8', [r'$4x^4-\frac{1}{4}$'], '表达式', false),
    (r'[(x-1/2)^2+(x+1/2)^2](2x^2-1/2)', [r'$4x^4-\frac{1}{4}$'], '表达式', false), // 把原式抄一遍不算
    ('(2x^2+1/2)(2x^2-1/2)', ['4x^4-1/4'], '表达式', false), // 没化简完
    ('x+x+1', ['2x+1'], '表达式', false), // 同类项没合并
    ('2x+1', ['2x+1'], '表达式', true),
    ('1+2x', ['2x+1'], '表达式', true),
    ('-2a+3b', ['3b-2a'], '表达式', true),
    ('2ab-a^2', ['-a^2+2ab'], '表达式', true),
    ('6x-2', ['2(3x-1)'], '表达式', true), // 参考答案带括号时不要求同样的样子
    ('x/2+1', [r'\frac{1}{2}x+1'], '表达式', true),
    ('3x·2y', ['6xy'], '表达式', true),
    ('2x+', ['2x+1'], '表达式', false), // 写了一半
  ];
  for (final (input, accepted, type, want) in cases) {
    test('"$input" vs $accepted（$type）→ $want', () {
      expect(checkAnswer(input, accepted, type), want);
    });
  }
}
