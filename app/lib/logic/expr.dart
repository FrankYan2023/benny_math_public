/// 表达式比对（初一的整式）：把答案解析成多项式，比较是否相等。
/// 例如 4x^4-1/4、4x⁴-0.25、-1/4+4x^4 都算同一个答案。
/// 还要求学生写的是化简好的样子：参考答案没有括号时，学生的答案也不能有括号，同类项要合并（不能把原式抄一遍）。
library;

import 'dart:math' as math;

sealed class _E {}

class _Num extends _E {
  _Num(this.v);
  final double v;
}

class _Var extends _E {
  _Var(this.name);
  final String name;
}

class _Bin extends _E {
  _Bin(this.op, this.a, this.b);
  final String op; // + - * / ^
  final _E a, b;
}

class _Neg extends _E {
  _Neg(this.a);
  final _E a;
}

/// 解析出来的表达式，外加"顶层有几项、有没有括号"（用来判断有没有化简）
class Parsed {
  Parsed._(this._e, this.topTerms, this.hasParens);
  final _E _e;
  final int topTerms;
  final bool hasParens;
}

const _sup = {'²': '^2', '³': '^3', '⁴': '^4', '⁵': '^5', '¹': '^1', '⁰': '^0'};

/// 输入应该已经过 normAnswer（去掉 $、\frac 换成除法、全角转半角、小写、去空格）
Parsed? parseExpr(String s) {
  var t = s;
  _sup.forEach((k, v) => t = t.replaceAll(k, v));
  t = t.replaceAll('**', '^');
  final tokens = <String>[];
  for (var i = 0; i < t.length;) {
    final c = t[i];
    if (RegExp(r'[0-9.]').hasMatch(c)) {
      var j = i;
      while (j < t.length && RegExp(r'[0-9.]').hasMatch(t[j])) {
        j++;
      }
      tokens.add(t.substring(i, j));
      i = j;
    } else if (RegExp(r'[a-z+\-*/^()]').hasMatch(c)) {
      tokens.add(c);
      i++;
    } else {
      return null; // 不认识的符号
    }
  }
  if (tokens.isEmpty) return null;
  // 省略的乘号：2x、x(…)、(…)(…)、2(…)、xy
  bool endsOperand(String k) => k == ')' || RegExp(r'^[0-9.a-z]').hasMatch(k);
  bool startsOperand(String k) => k == '(' || RegExp(r'^[0-9.a-z]').hasMatch(k);
  final full = <String>[];
  for (final k in tokens) {
    if (full.isNotEmpty && endsOperand(full.last) && startsOperand(k) && !(RegExp(r'^[0-9.]').hasMatch(full.last) && RegExp(r'^[0-9.]').hasMatch(k))) {
      full.add('*');
    }
    full.add(k);
  }
  final p = _Parser(full);
  try {
    final e = p.expr();
    if (p.i != full.length) return null;
    return Parsed._(e, p.topTerms, tokens.contains('('));
  } catch (_) {
    return null;
  }
}

class _Parser {
  _Parser(this.t);
  final List<String> t;
  int i = 0;
  int depth = 0;
  int topTerms = 0;

  String? get _peek => i < t.length ? t[i] : null;

  _E expr() {
    final top = depth == 0;
    var e = term();
    if (top) topTerms = 1;
    while (_peek == '+' || _peek == '-') {
      final op = t[i++];
      e = _Bin(op, e, term());
      if (top) topTerms++;
    }
    return e;
  }

  _E term() {
    var e = unary();
    while (_peek == '*' || _peek == '/') {
      final op = t[i++];
      e = _Bin(op, e, unary());
    }
    return e;
  }

  _E unary() {
    if (_peek == '-') {
      i++;
      return _Neg(unary());
    }
    if (_peek == '+') {
      i++;
      return unary();
    }
    return power();
  }

  _E power() {
    final base = atom();
    if (_peek == '^') {
      i++;
      return _Bin('^', base, unary());
    }
    return base;
  }

  _E atom() {
    final k = _peek;
    if (k == null) throw const FormatException('缺东西');
    i++;
    if (k == '(') {
      depth++;
      final e = expr();
      depth--;
      if (_peek != ')') throw const FormatException('括号不配对');
      i++;
      return e;
    }
    if (RegExp(r'^[0-9.]+$').hasMatch(k)) {
      final v = double.tryParse(k);
      if (v == null) throw const FormatException('数字不对');
      return _Num(v);
    }
    if (RegExp(r'^[a-z]$').hasMatch(k)) return _Var(k);
    throw FormatException('多余的符号 $k');
  }
}

// ---------- 多项式：单项式（字母和次数）→ 系数 ----------
typedef _Poly = Map<String, double>;

String _key(Map<String, int> m) => (m.keys.toList()..sort()).map((k) => '$k${m[k]}').join();
Map<String, int> _unkey(String k) => {for (final m in RegExp(r'([a-z])(\d+)').allMatches(k)) m[1]!: int.parse(m[2]!)};

_Poly _clean(_Poly p) => {for (final e in p.entries) if (e.value.abs() > 1e-12) e.key: e.value};

_Poly? _poly(_E e) {
  switch (e) {
    case _Num(:final v):
      return {'': v};
    case _Var(:final name):
      return {'${name}1': 1};
    case _Neg(:final a):
      final p = _poly(a);
      return p == null ? null : {for (final x in p.entries) x.key: -x.value};
    case _Bin(:final op, :final a, :final b):
      final pa = _poly(a), pb = _poly(b);
      if (pa == null || pb == null) return null;
      switch (op) {
        case '+':
        case '-':
          final out = Map<String, double>.of(pa);
          pb.forEach((k, v) => out[k] = (out[k] ?? 0) + (op == '+' ? v : -v));
          return _clean(out);
        case '*':
          return _mul(pa, pb);
        case '/':
          final c = _constant(pb);
          if (c == null || c == 0) return null; // 分母里有字母，不当多项式处理
          return {for (final x in pa.entries) x.key: x.value / c};
        case '^':
          final n = _constant(pb);
          if (n == null || n < 0 || n > 12 || n != n.roundToDouble()) return null;
          var out = <String, double>{'': 1};
          for (var k = 0; k < n; k++) {
            out = _mul(out, pa);
          }
          return out;
      }
  }
  return null;
}

double? _constant(_Poly p) {
  final c = _clean(p);
  if (c.isEmpty) return 0;
  return c.length == 1 && c.containsKey('') ? c[''] : null;
}

_Poly _mul(_Poly a, _Poly b) {
  final out = <String, double>{};
  for (final x in a.entries) {
    for (final y in b.entries) {
      final m = _unkey(x.key);
      _unkey(y.key).forEach((k, v) => m[k] = (m[k] ?? 0) + v);
      final k = _key(m);
      out[k] = (out[k] ?? 0) + x.value * y.value;
    }
  }
  return _clean(out);
}

double _eval(_E e, Map<String, double> env) => switch (e) {
      _Num(:final v) => v,
      _Var(:final name) => env[name] ?? double.nan,
      _Neg(:final a) => -_eval(a, env),
      _Bin(:final op, :final a, :final b) => switch (op) {
          '+' => _eval(a, env) + _eval(b, env),
          '-' => _eval(a, env) - _eval(b, env),
          '*' => _eval(a, env) * _eval(b, env),
          '/' => _eval(a, env) / _eval(b, env),
          _ => math.pow(_eval(a, env), _eval(b, env)).toDouble(),
        },
    };

Set<String> _vars(_E e) => switch (e) {
      _Num() => {},
      _Var(:final name) => {name},
      _Neg(:final a) => _vars(a),
      _Bin(:final a, :final b) => {..._vars(a), ..._vars(b)},
    };

bool _close(double a, double b) => (a - b).abs() <= 1e-9 * math.max(1, b.abs());

/// 两个表达式是不是相等（都已经 normAnswer）
bool sameValue(Parsed x, Parsed y) {
  final px = _poly(x._e), py = _poly(y._e);
  if (px != null && py != null) {
    final keys = {...px.keys, ...py.keys};
    return keys.every((k) => _close(px[k] ?? 0, py[k] ?? 0));
  }
  // 不是多项式（比如分母里有字母）：代几组数算一算
  final vars = {..._vars(x._e), ..._vars(y._e)};
  const samples = [1.37, -0.83, 2.11, 0.59, -1.73, 3.07];
  for (var k = 0; k < 3; k++) {
    final env = {for (final (i, v) in vars.indexed) v: samples[(i + k * 2) % samples.length] + k * 0.31};
    final a = _eval(x._e, env), b = _eval(y._e, env);
    if (a.isNaN || b.isNaN || a.isInfinite || b.isInfinite || !_close(a, b)) return false;
  }
  return true;
}

/// 是不是化简好的整式：没有括号，顶层的项数和合并后的单项式个数一样（同类项都合并了）
bool isSimplified(Parsed p) {
  if (p.hasParens) return false;
  final poly = _poly(p._e);
  if (poly == null) return false;
  return p.topTerms == math.max(1, poly.length);
}
