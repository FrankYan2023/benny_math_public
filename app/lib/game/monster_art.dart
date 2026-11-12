import 'package:flutter/material.dart';

import '../widgets/sprite.dart' show greyscale;
import 'game_data.dart';
import 'monster.dart';

/// 像素格子：32×32，每格一个颜色（null 是透明）
class PixelGrid {
  PixelGrid(this.w, this.h) : px = List<Color?>.filled(w * h, null);
  final int w, h;
  final List<Color?> px;

  Color? get(int x, int y) => x < 0 || y < 0 || x >= w || y >= h ? null : px[y * w + x];
  void set(int x, int y, Color? c) {
    if (x >= 0 && y >= 0 && x < w && y < h) px[y * w + x] = c;
  }

  void rect(int x, int y, int rw, int rh, Color c) {
    for (var j = y; j < y + rh; j++) {
      for (var i = x; i < x + rw; i++) {
        set(i, j, c);
      }
    }
  }

  void ellipse(double cx, double cy, double rx, double ry, Color c, {bool Function(Color?)? only}) {
    for (var y = (cy - ry - 1).floor(); y <= (cy + ry + 1).ceil(); y++) {
      for (var x = (cx - rx - 1).floor(); x <= (cx + rx + 1).ceil(); x++) {
        final dx = (x + 0.5 - cx) / rx, dy = (y + 0.5 - cy) / ry;
        if (dx * dx + dy * dy <= 1 && (only == null || only(get(x, y)))) set(x, y, c);
      }
    }
  }

  /// 把 target 颜色区域靠 (dx, dy) 那一边的一层换成 to（做明暗）
  void shadeEdge(Color target, Color to, int dx, int dy) {
    final hits = <int>[];
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        if (get(x, y) == target && get(x + dx, y + dy) != target) hits.add(y * w + x);
      }
    }
    for (final i in hits) {
      px[i] = to;
    }
  }

  /// 不透明区域外面描一圈
  void outline(Color c) {
    final hits = <int>[];
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        if (get(x, y) != null) continue;
        if ([get(x + 1, y), get(x - 1, y), get(x, y + 1), get(x, y - 1)].any((p) => p != null && p != c)) hits.add(y * w + x);
      }
    }
    for (final i in hits) {
      px[i] = c;
    }
  }

  /// 某一列最上面一个不透明格子的 y
  int top(int x) {
    for (var y = 0; y < h; y++) {
      if (get(x, y) != null) return y;
    }
    return h;
  }
}

typedef _Pal = ({Color base, Color dark, Color light});

const _palettes = <String, _Pal>{
  '火红': (base: Color(0xffe5533d), dark: Color(0xffa8352a), light: Color(0xffff8a73)),
  '冰蓝': (base: Color(0xff6ec6f0), dark: Color(0xff3a8fc0), light: Color(0xffc4ecff)),
  '金黄': (base: Color(0xfff2c14e), dark: Color(0xffc4901c), light: Color(0xffffe39a)),
  '翠绿': (base: Color(0xff5cc35a), dark: Color(0xff358a3a), light: Color(0xffa6ec90)),
  '葡紫': (base: Color(0xff9a6be0), dark: Color(0xff6a42b0), light: Color(0xffc8aaf6)),
  '粉红': (base: Color(0xffff9fc0), dark: Color(0xffd96a95), light: Color(0xffffd3e4)),
  '墨黑': (base: Color(0xff4a4a5e), dark: Color(0xff2a2a36), light: Color(0xff70708a)),
  '雪白': (base: Color(0xffeef0f6), dark: Color(0xffb8bed0), light: Color(0xffffffff)),
  '橘橙': (base: Color(0xfff5913a), dark: Color(0xffc0661a), light: Color(0xffffc285)),
  '青铜': (base: Color(0xffb08850), dark: Color(0xff7a5a30), light: Color(0xffdcb880)),
  '彩虹': (base: Color(0xffff8080), dark: Color(0xffa04a6a), light: Color(0xfffff0a0)),
  '透明': (base: Color(0xb0d8e6f5), dark: Color(0xc08aa8c8), light: Color(0xc0ffffff)),
};
const _rainbow = [Color(0xffe5533d), Color(0xfff5913a), Color(0xfff2c14e), Color(0xff5cc35a), Color(0xff4a90e0), Color(0xff9a6be0)];

const _ink = Color(0xff22182a);
const _white = Color(0xffffffff);
const _pink = Color(0xffff8fa3);
const _blue = Color(0xff5cc8ff);
const _mouthIn = Color(0xff7a2e35);
const _bone = Color(0xfff6ecd2);
const _boneDark = Color(0xffc9b48a);
const _gold = Color(0xffffd84a);
const _goldDark = Color(0xffc9971f);

/// 性格 → (眼睛, 嘴, 额外的小东西)
const _faces = <String, (String, String, String)>{
  '调皮': ('round', 'tongue', ''),
  '慌张': ('wide', 'open', 'sweat'),
  '瞌睡': ('closed', 'small', 'zz'),
  '暴躁': ('angry', 'teeth', ''),
  '嘻哈': ('happy', 'grin', ''),
  '糊涂': ('spiral', 'flat', ''),
  '傲慢': ('half', 'smirk', ''),
  '害羞': ('happy', 'small', 'blush'),
  '贪吃': ('round', 'drool', ''),
  '爱哭': ('teary', 'frown', ''),
  '鬼祟': ('side', 'smirk', ''),
  '冒失': ('wide', 'open', ''),
  '懒散': ('half', 'flat', ''),
  '神气': ('star', 'grin', ''),
  '话痨': ('round', 'big', ''),
  '倔强': ('angry', 'frown', ''),
};

final _cache = <String, PixelGrid>{};

/// 按特征画一只怪兽（同样的特征和 seed 画出来一模一样）
PixelGrid drawMonster(MonsterTraits t) => _cache.putIfAbsent('${t.name}/${t.seed}', () => _draw(t));

PixelGrid _draw(MonsterTraits t) {
  final r = SeededRandom(t.seed);
  final pal = _palettes[t.color] ?? _palettes['翠绿']!;
  final g = PixelGrid(32, 32);
  final look = t.look;
  var wide = (r.below(3) - 1) * 0.5;
  var tall = 0.0;
  if (look == '圆滚') wide += 2;
  if (look == '细长') {
    wide -= 2;
    tall += 2;
  }

  // ---------- 身体后面的东西：翅膀、尾巴 ----------
  if (look == '飞翼') {
    for (var i = 0; i < 8; i++) {
      final len = 7 - i ~/ 2;
      g.rect(1 + i ~/ 3, 8 + i, len, 1, pal.dark);
      g.rect(31 - i ~/ 3 - len, 8 + i, len, 1, pal.dark);
    }
  }
  if (look == '长尾') {
    final pts = [(25, 26), (27, 25), (28, 23), (29, 21), (29, 19), (28, 17)];
    for (final (x, y) in pts) {
      g.rect(x, y, 2, 2, pal.base);
    }
    g.set(28, 16, pal.dark);
    g.set(27, 15, pal.dark);
  }

  // ---------- 身体：按种类 ----------
  late double fx, fy, fw;
  var single = false; // 独眼
  switch (t.species) {
    case '粗心鬼':
      g.ellipse(16, 13 - tall / 2, 9.5 + wide, 9 + tall, pal.base);
      g.rect((6 - wide).round(), 13, (20 + wide * 2).round(), 11, pal.base);
      for (var x = 7; x <= 25; x += 4) {
        g.ellipse(x + 0.5, 24.5, 2.3, 2.3, pal.base);
      }
      g.ellipse(4.5 - wide, 18, 2.2, 1.6, pal.base);
      g.ellipse(27.5 + wide, 17, 2.2, 1.6, pal.base);
      fx = 16;
      fy = 12;
      fw = 4;
    case '糊涂虫':
      for (final (x, y, rad) in [(7.0, 24.0, 4.2), (12.0, 23.0, 4.6), (17.5, 22.0, 5.0)]) {
        g.ellipse(x, y, rad + wide / 3, rad, pal.base);
      }
      g.ellipse(22, 14 - tall / 2, 7.5 + wide / 2, 7 + tall / 2, pal.base);
      for (final x in [5, 10, 15, 19]) {
        g.rect(x, 27, 2, 2, pal.dark);
      }
      fx = 22;
      fy = 13;
      fw = 3;
    case '马虎眼':
      g.ellipse(16, 17, 11 + wide, 11 + tall / 2, pal.base);
      g.rect(9, 27, 3, 2, pal.dark);
      g.rect(20, 27, 3, 2, pal.dark);
      fx = 16;
      fy = 15;
      fw = 0;
      single = true;
    case '地基鼠':
      g.ellipse(16, 21, 10 + wide, 9, pal.base);
      g.ellipse(16, 13 - tall / 2, 8 + wide / 2, 7 + tall / 2, pal.base);
      g.ellipse(8, 8, 3, 3, pal.base);
      g.ellipse(24, 8, 3, 3, pal.base);
      g.ellipse(8, 8, 1.5, 1.5, _pink);
      g.ellipse(24, 8, 1.5, 1.5, _pink);
      fx = 16;
      fy = 12;
      fw = 3.5;
    default: // 迷路怪
      g.ellipse(16, 20, 11 + wide, 9, pal.base);
      g.ellipse(16, 14 - tall, 8 + wide / 2, 8 + tall, pal.base);
      fx = 16;
      fy = 14 - tall;
      fw = 4;
  }

  // ---------- 花纹 ----------
  bool isBody(Color? c) => c == pal.base;
  if (t.color == '彩虹') {
    for (var y = 0; y < 32; y++) {
      for (var x = 0; x < 32; x++) {
        if (isBody(g.get(x, y))) g.set(x, y, _rainbow[(y ~/ 3) % _rainbow.length]);
      }
    }
  } else {
    if (look == '条纹') {
      for (var y = 0; y < 32; y++) {
        for (var x = 0; x < 32; x++) {
          if (y % 4 == 2 && isBody(g.get(x, y)) && (y > fy + 5 || (x - fx).abs() > fw + 3)) g.set(x, y, pal.dark);
        }
      }
    }
    if (look == '斑点') {
      for (var k = 0; k < 7; k++) {
        final x = 4 + r.below(24), y = 6 + r.below(22);
        if ((x - fx).abs() < fw + 3 && (y - fy).abs() < 5) continue;
        if (isBody(g.get(x, y)) && isBody(g.get(x + 1, y + 1))) g.rect(x, y, 2, 2, pal.light);
      }
    }
    g.shadeEdge(pal.base, pal.dark, 0, 1);
    g.shadeEdge(pal.base, pal.dark, 1, 0);
    for (final (dx, dy) in [(-5, -6), (-4, -7), (-6, -5)]) {
      final x = (fx + dx).round(), y = (fy + dy).round();
      if (isBody(g.get(x, y))) g.set(x, y, pal.light);
    }
  }

  // ---------- 头上和身上的东西 ----------
  final cx = fx.round();
  if (look == '长角') {
    for (final side in [-1, 1]) {
      final x = (fx + side * (fw + 2)).round();
      final y = g.top(x);
      for (var k = 0; k < 4; k++) {
        g.rect(x - (k < 2 ? 1 : 0) + (side > 0 && k >= 2 ? 1 : 0), y - 1 - k, k < 2 ? 2 : 1, 1, k == 0 ? _boneDark : _bone);
      }
    }
  }
  if (look == '带刺') {
    for (var x = 4; x < 29; x += 3) {
      final y = g.top(x);
      if (y >= 31) continue;
      g.set(x, y - 1, pal.dark);
      g.set(x, y - 2, pal.dark);
      g.set(x + 1, y - 1, pal.dark);
    }
  }
  if (look == '戴冠') {
    final y = g.top(cx) - 1;
    g.rect(cx - 4, y - 2, 9, 3, _gold);
    g.rect(cx - 4, y, 9, 1, _goldDark);
    for (final dx in [-4, 0, 4]) {
      g.set(cx + dx, y - 3, _gold);
    }
    g.set(cx, y - 1, const Color(0xffe0464f));
  }
  if (look == '触角') {
    for (final side in [-1, 1]) {
      final x0 = (fx + side * 2).round();
      final y0 = g.top(x0);
      for (var k = 1; k <= 4; k++) {
        g.set(x0 + side * (k ~/ 2), y0 - k, pal.dark);
      }
      g.rect(x0 + side * 2 - (side < 0 ? 1 : 0), y0 - 6, 2, 2, pal.light);
    }
  }
  if (look == '短腿') {
    var bottom = 0;
    for (var y = 31; y >= 0; y--) {
      if (g.get(cx, y) != null) {
        bottom = y;
        break;
      }
    }
    for (final dx in [-6, -2, 2, 6]) {
      g.rect(cx + dx - 1, bottom, 2, 3, pal.dark);
    }
  }
  if (look == '毛绒') {
    final add = <(int, int)>[];
    for (var y = 0; y < 32; y++) {
      for (var x = 0; x < 32; x++) {
        if (g.get(x, y) != null) continue;
        final n = [g.get(x + 1, y), g.get(x - 1, y), g.get(x, y + 1), g.get(x, y - 1)].where((c) => c != null).length;
        if (n > 0 && r.chance(0.45)) add.add((x, y));
      }
    }
    for (final (x, y) in add) {
      g.set(x, y, t.color == '彩虹' ? _rainbow[(y ~/ 3) % _rainbow.length] : pal.base);
    }
  }

  // ---------- 脸 ----------
  final face = _faces[t.personality] ?? ('round', 'grin', '');
  final ey = fy.round();
  if (single) {
    // 独眼：大眼白，性格决定眼皮和瞳孔
    g.ellipse(fx, fy, 5, 4.5, _white);
    final (eye, _, _) = face;
    if (eye == 'closed' || eye == 'happy') {
      g.rect(cx - 3, ey, 7, 1, _ink);
    } else {
      final px = eye == 'side' ? cx + 2 : cx;
      g.rect(px - 1, ey - 1, 3, 3, _ink);
      g.set(px - 1, ey - 1, _white);
      if (eye == 'half' || eye == 'angry') g.rect(cx - 4, ey - 4, 9, 2, t.color == '彩虹' ? _rainbow[0] : pal.dark);
    }
  } else {
    final eyes = [(cx - fw.round(), ey), (cx + fw.round() - 1, ey)];
    if (look == '三眼') eyes.add((cx, ey - 4));
    for (final (x, y) in eyes) {
      _eye(g, face.$1, x, y);
    }
  }
  final my = single ? ey + 7 : ey + 4;
  _mouth(g, look == '大嘴' && face.$2 != 'teeth' ? 'big' : face.$2, cx, my);
  if (look == '独牙') {
    g.set(cx + 2, my + (look == '大嘴' ? 3 : 1), _white);
    g.set(cx + 2, my + (look == '大嘴' ? 4 : 2), _white);
  }
  switch (face.$3) {
    case 'sweat':
      g.rect(cx + fw.round() + 4, ey - 5, 2, 3, _blue);
      g.set(cx + fw.round() + 5, ey - 6, _blue);
    case 'zz':
      for (final (x, y) in [(26, 3), (27, 3), (28, 3), (27, 4), (26, 5), (27, 5), (28, 5)]) {
        g.set(x, y, _white);
      }
    case 'blush':
      g.set(cx - fw.round() - 2, ey + 2, _pink);
      g.set(cx + fw.round() + 1, ey + 2, _pink);
  }

  g.outline(_ink);
  if (look == '发光') {
    final glow = Color.from(alpha: 0.55, red: pal.light.r, green: pal.light.g, blue: pal.light.b);
    final hits = <(int, int)>[];
    for (var y = 0; y < 32; y++) {
      for (var x = 0; x < 32; x++) {
        if (g.get(x, y) == null && [g.get(x + 1, y), g.get(x - 1, y), g.get(x, y + 1), g.get(x, y - 1)].contains(_ink)) hits.add((x, y));
      }
    }
    for (final (x, y) in hits) {
      g.set(x, y, glow);
    }
  }
  return g;
}

void _eye(PixelGrid g, String style, int x, int y) {
  switch (style) {
    case 'happy':
      g.set(x - 1, y + 1, _ink);
      g.set(x, y, _ink);
      g.set(x + 1, y, _ink);
      g.set(x + 2, y + 1, _ink);
    case 'closed':
      g.rect(x - 1, y + 1, 4, 1, _ink);
    case 'spiral':
      g.rect(x - 1, y - 1, 3, 3, _white);
      for (final (dx, dy) in [(-1, -1), (0, -1), (1, -1), (1, 0), (1, 1), (0, 1), (0, 0)]) {
        g.set(x + dx, y + dy, _ink);
      }
    case 'half':
      g.rect(x, y + 1, 2, 2, _ink);
      g.rect(x - 1, y, 4, 1, _ink);
    case 'side':
      g.rect(x - 1, y - 1, 3, 3, _white);
      g.rect(x + 1, y, 1, 2, _ink);
    case 'wide':
      g.rect(x - 1, y - 1, 3, 3, _white);
      g.set(x, y, _ink);
    case 'star':
      for (final (dx, dy) in [(0, -1), (-1, 0), (0, 0), (1, 0), (0, 1)]) {
        g.set(x + dx, y + dy, _gold);
      }
    case 'angry':
      g.rect(x, y, 2, 2, _ink);
      g.set(x, y, _white);
      g.set(x - 1, y - 2, _ink);
      g.set(x, y - 2, _ink);
      g.set(x + 1, y - 1, _ink);
    case 'teary':
      g.rect(x, y - 1, 2, 3, _ink);
      g.set(x, y - 1, _white);
      g.set(x, y + 2, _blue);
      g.set(x, y + 3, _blue);
    default: // round
      g.rect(x, y - 1, 2, 3, _ink);
      g.set(x, y - 1, _white);
  }
}

void _mouth(PixelGrid g, String style, int mx, int my) {
  switch (style) {
    case 'grin':
      g.set(mx - 2, my, _ink);
      g.set(mx + 2, my, _ink);
      g.rect(mx - 1, my + 1, 3, 1, _ink);
    case 'tongue':
      g.set(mx - 2, my, _ink);
      g.set(mx + 2, my, _ink);
      g.rect(mx - 1, my + 1, 3, 1, _ink);
      g.rect(mx, my + 2, 2, 1, _pink);
    case 'open':
      g.rect(mx - 1, my, 3, 2, _mouthIn);
    case 'flat':
      g.rect(mx - 1, my, 3, 1, _ink);
    case 'teeth':
      g.rect(mx - 2, my, 5, 2, _mouthIn);
      g.set(mx - 2, my, _white);
      g.set(mx, my, _white);
      g.set(mx + 2, my, _white);
    case 'smirk':
      g.rect(mx - 1, my + 1, 3, 1, _ink);
      g.set(mx + 2, my, _ink);
    case 'small':
      g.set(mx, my, _ink);
    case 'drool':
      g.rect(mx - 1, my, 3, 2, _mouthIn);
      g.set(mx + 1, my + 2, _blue);
      g.set(mx + 1, my + 3, _blue);
    case 'big':
      g.rect(mx - 2, my, 5, 3, _mouthIn);
      g.rect(mx - 2, my, 5, 1, _white);
      g.set(mx, my + 2, _pink);
    case 'frown':
      g.rect(mx - 1, my, 3, 1, _ink);
      g.set(mx - 2, my + 1, _ink);
      g.set(mx + 2, my + 1, _ink);
  }
}

/// 画格子
class PixelGridPainter extends CustomPainter {
  PixelGridPainter(this.grid);
  final PixelGrid grid;

  @override
  void paint(Canvas canvas, Size size) {
    final cw = size.width / grid.w, ch = size.height / grid.h;
    final paint = Paint()..isAntiAlias = false;
    for (var y = 0; y < grid.h; y++) {
      for (var x = 0; x < grid.w; x++) {
        final c = grid.px[y * grid.w + x];
        if (c == null) continue;
        paint.color = c;
        canvas.drawRect(Rect.fromLTWH(x * cw, y * ch, cw + 0.5, ch + 0.5), paint);
      }
    }
  }

  @override
  bool shouldRepaint(PixelGridPainter old) => old.grid != grid;
}

/// 一只错题怪兽；defeated 时变灰、倒下
class MonsterAvatar extends StatelessWidget {
  const MonsterAvatar(this.traits, {super.key, this.size = 96, this.defeated = false});
  final MonsterTraits traits;
  final double size;
  final bool defeated;

  @override
  Widget build(BuildContext context) {
    final art = RepaintBoundary(child: SizedBox.square(dimension: size, child: CustomPaint(painter: PixelGridPainter(drawMonster(traits)))));
    return Semantics(
      label: traits.name,
      image: true,
      child: AnimatedRotation(
        turns: defeated ? 0.25 : 0,
        duration: const Duration(milliseconds: 400),
        child: defeated ? ColorFiltered(colorFilter: greyscale, child: art) : art,
      ),
    );
  }
}
