/// 比较答案：写法统一 + 数值比较；表达式解析成多项式比较（见 expr.dart）。
/// 用来判断 Benny 输入的练习答案和重做原题的答案对不对。
library;

import 'expr.dart';

String _halfWidth(String s) => String.fromCharCodes(s.runes.map((c) {
      if (c >= 0xFF01 && c <= 0xFF5E) return c - 0xFEE0; // 全角字符
      if (c == 0x3000) return 0x20; // 全角空格
      return c;
    }));

String normAnswer(String? s) {
  if (s == null) return '';
  var t = _halfWidth(s).replaceAll(r'$', '');
  // \frac{1}{4} → 1/4；分子分母不是单个数时加括号：\frac{x+1}{2} → (x+1)/(2)
  String frac(String a, String b) => RegExp(r'^\d+(\.\d+)?$').hasMatch(a) && RegExp(r'^\d+(\.\d+)?$').hasMatch(b) ? '$a/$b' : '($a)/($b)';
  t = t.replaceAllMapped(RegExp(r'\\[dt]?frac\s*\{([^{}]*)\}\s*\{([^{}]*)\}'), (m) => frac(m[1]!.trim(), m[2]!.trim()));
  t = t.replaceAllMapped(RegExp(r'\\[dt]?frac(\d)(\d)'), (m) => '${m[1]}/${m[2]}'); // \frac14 这种简写
  t = t
      .replaceAll(RegExp(r'\\left|\\right'), '')
      .replaceAll(RegExp(r'\\cdot|\\times|×|·'), '*')
      .replaceAll(RegExp(r'\\div|÷'), '/')
      .replaceAll(RegExp('[−–—]'), '-')
      .replaceAll(RegExp(r'\\[,;: !]|~'), '')
      .replaceAll(RegExp(r'[{}]'), '')
      .replaceAll(RegExp(r'\s+'), '')
      .replaceAll(RegExp(r'[。，,；;]+$'), '');
  return t.toLowerCase();
}

/// 只认整数、小数、分数（可带括号和正负号），其他返回 null
double? answerToNumber(String s) {
  final t = normAnswer(s).replaceAll(RegExp(r'[()]'), '');
  final m = RegExp(r'^([+-]?\d*\.?\d+)(?:/([+-]?\d*\.?\d+))?$').firstMatch(t);
  if (m == null) return null;
  final n = double.parse(m[1]!);
  final d = m[2] == null ? 1.0 : double.parse(m[2]!);
  return d == 0 ? null : n / d;
}

String _stripVar(String s) => s.replaceFirst(RegExp(r'^[a-z]='), '');

bool _same(String a, String b, String type) {
  final x = normAnswer(a);
  final y = normAnswer(b);
  if (x.isEmpty || y.isEmpty) return false;
  if (type == '选择') {
    final lx = x.replaceAll(RegExp('[^a-d]'), '');
    final ly = y.replaceAll(RegExp('[^a-d]'), '');
    return lx.isNotEmpty && ly.isNotEmpty && lx[0] == ly[0];
  }
  if (x == y) return true;
  if (type == '表达式') {
    final px = parseExpr(x), py = parseExpr(y);
    if (px == null || py == null || !sameValue(px, py)) return false;
    // 参考答案是化简好的样子，学生的也要化简好（不能把原式抄一遍）
    return !isSimplified(py) || isSimplified(px);
  }
  final x2 = _stripVar(x);
  final y2 = _stripVar(y);
  if (x2 == y2) return true;
  final nx = answerToNumber(x2);
  final ny = answerToNumber(y2);
  return nx != null && ny != null && (nx - ny).abs() <= 1e-9 * (ny.abs() > 1 ? ny.abs() : 1);
}

bool checkAnswer(String? input, List<String> accepted, String type) =>
    input != null && accepted.any((a) => _same(input, a, type));
