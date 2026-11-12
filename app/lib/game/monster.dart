import '../i18n.dart';
import 'game_data.dart';

/// 一只错题怪兽：名字 = 性格 + 外形 + 颜色 + 种类（种类由错因决定），例如"调皮长角火红粗心鬼"。
/// 外形决定身上长什么，颜色决定配色，性格决定表情，seed 让同样的组合也长得有点不一样。
class MonsterTraits {
  const MonsterTraits({
    required this.species,
    required this.personality,
    required this.look,
    required this.color,
    required this.seed,
    this.intro = '',
  });

  final String species; // 粗心鬼 / 糊涂虫 / 迷路怪 / 马虎眼 / 地基鼠
  final String personality;
  final String look;
  final String color;
  final int seed;
  final String intro; // GPT 写的一句介绍

  /// 名字（中文，也是去重用的身份）
  String get name => '$personality$look$color$species';

  /// 按当前语言显示的名字："調皮長角火紅粗心鬼" / "Cheeky Horned Crimson Blunder Ghost" / "Duende Despistado travieso rojo fuego con cuernos"
  String get displayName {
    final g = GameData.instance;
    return switch (i18n.lang) {
      Lang.zh => [personality, look, color, species].map(g.word).join(),
      Lang.en => [personality, look, color, species].map(g.word).join(' '),
      Lang.es => [species, personality, color, look].map(g.word).join(' '),
    };
  }

  Map<String, dynamic> toJson() =>
      {'species': species, 'personality': personality, 'look': look, 'color': color, 'seed': seed, 'intro': intro, 'name': name};

  static MonsterTraits? fromJson(Object? j) {
    if (j is! Map) return null;
    final g = GameData.instance;
    final p = '${j['personality']}', l = '${j['look']}', c = '${j['color']}', s = '${j['species']}';
    if (!g.personalities.contains(p) || !g.looks.contains(l) || !g.colors.contains(c) || !g.species.values.contains(s)) return null;
    return MonsterTraits(species: s, personality: p, look: l, color: c, seed: (j['seed'] as num?)?.toInt() ?? stableHash('$p$l$c'), intro: '${j['intro'] ?? ''}');
  }

  /// 没有 GPT 挑的形容词时（旧的题、示例），按题目编号算出一只（同一道题每次都一样）
  static MonsterTraits fromSeed(String key, String errorType) {
    final g = GameData.instance;
    final r = SeededRandom(stableHash(key));
    return MonsterTraits(
      species: g.species[errorType] ?? '迷路怪',
      personality: r.pick(g.personalities),
      look: r.pick(g.looks),
      color: r.pick(g.colors),
      seed: stableHash(key),
    );
  }

  /// 用 GPT 挑的形容词起名；和 [taken] 里已有的名字重了，就换一个没用过的组合（先换性格，再换颜色、外形）
  static MonsterTraits unique({
    required String errorType,
    required String key,
    String? personality,
    String? look,
    String? color,
    String intro = '',
    Set<String> taken = const {},
  }) {
    final g = GameData.instance;
    final r = SeededRandom(stableHash(key));
    final species = g.species[errorType] ?? '迷路怪';
    final p0 = g.personalities.contains(personality) ? personality! : r.pick(g.personalities);
    final l0 = g.looks.contains(look) ? look! : r.pick(g.looks);
    final c0 = g.colors.contains(color) ? color! : r.pick(g.colors);
    List<String> from(List<String> all, String first) => [first, ...all.where((x) => x != first)];
    for (final l in from(g.looks, l0)) {
      for (final c in from(g.colors, c0)) {
        for (final p in from(g.personalities, p0)) {
          final m = MonsterTraits(species: species, personality: p, look: l, color: c, seed: stableHash(key), intro: intro);
          if (!taken.contains(m.name)) return m;
        }
      }
    }
    return MonsterTraits(species: species, personality: p0, look: l0, color: c0, seed: stableHash(key), intro: intro);
  }
}
