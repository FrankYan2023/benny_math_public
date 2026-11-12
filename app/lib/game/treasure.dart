import '../i18n.dart';
import '../models/hunt.dart';
import 'game_data.dart';

/// 一件宝藏。每只怪兽、每个村庄只有一件，只能拿一次（第一次把修炼都打完时得到；
/// 不用修炼的题在第一次打赢 Boss 时得到）。能力加几点、值多少金币由稀有度决定。
/// 宝藏可以卖掉换金币：卖掉的从宝藏箱里拿走，加过的能力保留。
class Treasure {
  const Treasure({
    required this.id,
    required this.name,
    required this.kind,
    required this.material,
    required this.rarity,
    required this.stats,
    required this.value,
    required this.story,
    required this.source,
    this.at = 0,
    this.soldAt,
  });

  final String id; // 去重用：题目编号/treasure（旧版本还有 题目编号/知识点/r1 这类）
  final String name;
  final String kind; // 剑、盾、宝石…
  final String material; // 黄金、水晶…
  final String rarity; // common / rare / epic / legend
  final Map<String, int> stats; // 能力 id → 加几点
  final int value; // 金币
  final String story;
  final String source; // lesson / boss / village（旧版本还有 retry）
  final int at;
  final int? soldAt; // 卖掉的时间；没卖为空

  bool get sold => soldAt != null;

  Treasure soldOn(int at) => Treasure(
        id: id, name: name, kind: kind, material: material, rarity: rarity, stats: stats, value: value, story: story, source: source,
        at: this.at, soldAt: at,
      );

  Map<String, dynamic> toJson() => {
        'id': id, 'name': name, 'kind': kind, 'material': material, 'rarity': rarity, 'stats': stats,
        'value': value, 'story': story, 'source': source, 'at': at, 'soldAt': ?soldAt,
      };

  factory Treasure.fromJson(Map<String, dynamic> j) => Treasure(
        id: '${j['id']}',
        name: '${j['name']}',
        kind: '${j['kind']}',
        material: '${j['material']}',
        rarity: '${j['rarity']}',
        stats: {for (final e in (j['stats'] as Map? ?? {}).entries) '${e.key}': (e.value as num).toInt()},
        value: (j['value'] as num?)?.toInt() ?? 0,
        story: '${j['story'] ?? ''}',
        source: '${j['source'] ?? 'lesson'}',
        at: (j['at'] as num?)?.toInt() ?? 0,
        soldAt: (j['soldAt'] as num?)?.toInt(),
      );

  /// 上报后端用（不带 at，时间在事件上）
  Map<String, dynamic> toEvent() => {
        'id': id, 'name': name, 'kind': kind, 'material': material, 'rarity': rarity, 'stats': stats,
        'value': value, 'story': story, 'source': source,
      };
}

const rarityOrder = ['common', 'rare', 'epic', 'legend'];

/// 修炼的稀有度（规则写在这里，不交给 GPT）：
///   传说：4 只小怪都一次答对，没看提示、没看解答
///   史诗：全部答对
///   稀有：过关
///   普通：打完了就有
/// 再打一遍的（题目已经见过）最高只到稀有。
String lessonRarity(LessonState l) {
  final idx = [for (var i = 0; i < l.practice.length; i++) if (!(l.results[i]?.skipped ?? false)) i];
  final rs = [for (final i in idx) l.results[i]];
  final allRight = rs.isNotEmpty && rs.every((r) => r != null && r.counted);
  final perfect = allRight && rs.every((r) => r!.tries == 1 && r.hints == 0 && !r.revealed && !r.override);
  final r = perfect
      ? 'legend'
      : allRight
          ? 'epic'
          : l.score().passed
              ? 'rare'
              : 'common';
  return l.round > 1 && rarityOrder.indexOf(r) > 1 ? 'rare' : r;
}

/// 一只怪兽（一个村庄）的宝藏稀有度：看它所有知识点的修炼，按最差的那个算
String huntRarity(Iterable<LessonState> ls) =>
    ls.map(lessonRarity).reduce((a, b) => rarityOrder.indexOf(a) <= rarityOrder.indexOf(b) ? a : b);

/// App 组合的宝藏的来历（按种类）
const kindStory = {
  '剑': '揮一揮，難題就裂開一條縫。',
  '盾': '擋得住粗心鬼的偷襲。',
  '宝石': '對著光看，能看見藏起來的條件。',
  '药水': '喝一口，腦子清清爽爽。',
  '卷轴': '上面寫著一條古老的運算法則。',
  '戒指': '戴上它，手寫的每一步都很穩。',
  '王冠': '只有打敗過怪獸的人才戴得上。',
  '护身符': '遇到難題時，它會悄悄發熱提醒你。',
  '靴子': '走在數軸上又快又準。',
  '魔法书': '翻開就能想起學過的方法。',
  '钥匙': '能打開一道鎖著的難題。',
  '法杖': '一揮就把式子變得整整齊齊。',
};

const kindStoryEn = {
  '剑': 'One swing and a hard problem cracks open.',
  '盾': 'Blocks sneak attacks from the Blunder Ghost.',
  '宝石': 'Hold it to the light to spot hidden conditions.',
  '药水': 'One sip and your head feels clear.',
  '卷轴': 'An ancient rule of arithmetic is written on it.',
  '戒指': 'Wear it and every written step stays steady.',
  '王冠': 'Only those who have beaten a monster can wear it.',
  '护身符': 'It warms up quietly when a tricky problem appears.',
  '靴子': 'Fast and sure-footed on the number line.',
  '魔法书': 'Open it to remember the methods you learned.',
  '钥匙': 'Unlocks a problem that seemed locked tight.',
  '法杖': 'One wave and the expression lines up neatly.',
};

const kindStoryEs = {
  '剑': 'Un tajo y el problema difícil se abre en dos.',
  '盾': 'Para los ataques por sorpresa del Duende Despistado.',
  '宝石': 'Mírala a contraluz y verás las condiciones escondidas.',
  '药水': 'Un sorbo y tu cabeza queda despejada.',
  '卷轴': 'Lleva escrita una antigua regla de la aritmética.',
  '戒指': 'Póntelo y cada paso que escribas será firme.',
  '王冠': 'Solo quien ha vencido a un monstruo puede llevarla.',
  '护身符': 'Se calienta en silencio cuando aparece un problema difícil.',
  '靴子': 'Rápidas y seguras sobre la recta numérica.',
  '魔法书': 'Ábrelo y recordarás los métodos que aprendiste.',
  '钥匙': 'Abre un problema que parecía cerrado a cal y canto.',
  '法杖': 'Un movimiento y la expresión queda bien ordenada.',
};

/// 每章最能锻炼的能力（GPT 没给宝藏时用）
const moduleStat = {
  'X': 'calc', '7A-1': 'space', '7A-2': 'calc', '7A-3': 'logic', '7A-4': 'calc', '7A-5': 'logic', '7A-6': 'space',
  '7B-7': 'space', '7B-8': 'calc', '7B-9': 'space', '7B-10': 'logic', '7B-11': 'logic', '7B-12': 'eye',
};

/// 错因 → Boss 掉落的宝藏加什么能力（另外总会加勇气）
const errorStat = {'计算失误': 'focus', '概念不清': 'logic', '审题错误': 'eye', '方法不会': 'logic', '未作答': 'brave', '前置缺失': 'calc', '无错误': 'focus'};

(int, Map<String, int>) _value(String id, String rarity, List<String> statIds) {
  final g = GameData.instance;
  final r = g.rarities.firstWhere((x) => x.id == rarity, orElse: () => g.rarities.first);
  final (lo, hi) = r.coins;
  return (lo + SeededRandom(stableHash(id)).below(hi - lo + 1), {for (final s in statIds.toSet().take(3)) s: r.boost});
}

/// 用 GPT 起的名字和来历（训练任务里每个知识点都起了一件，用第一件能用的）
Treasure? fromGpt({required String id, required Map<String, dynamic>? spec, required String rarity, required String source}) {
  if (spec == null) return null;
  final g = GameData.instance;
  final ids = [for (final s in spec['stats'] as List? ?? []) ?g.statId('$s')];
  final name = '${spec['name'] ?? ''}'.trim();
  if (name.isEmpty || ids.isEmpty || !g.kinds.contains(spec['kind']) || !g.materials.contains(spec['material'])) return null;
  final (value, stats) = _value(id, rarity, ids);
  return Treasure(
    id: id, name: name.length > 20 ? name.substring(0, 20) : name, kind: '${spec['kind']}', material: '${spec['material']}',
    rarity: rarity, stats: stats, value: value, story: '${spec['story'] ?? ''}', source: source,
  );
}

/// App 自己组合一件宝藏：前缀 + 材质 + 种类（和 [owned] 里的名字不重复）
Treasure procedural({
  required String id,
  required String rarity,
  required List<String> statIds,
  required String source,
  Set<String> owned = const {},
  String? name,
  String? story,
}) {
  final g = GameData.instance;
  final r = SeededRandom(stableHash(id));
  var kind = r.pick(g.kinds), material = r.pick(g.materials), prefix = r.pick(g.prefixes);
  String compose() => switch (i18n.lang) {
        Lang.zh => '${g.word(prefix)}${g.word(material)}${g.word(kind)}',
        Lang.en => '${g.word(prefix)} ${g.word(material)} ${g.word(kind)}',
        Lang.es => '${g.word(kind)} ${g.prefixFor(prefix, kind)} ${g.material(material)}',
      };
  var n = name ?? compose();
  for (var k = 0; name == null && owned.contains(n) && k < 400; k++) {
    kind = r.pick(g.kinds);
    material = r.pick(g.materials);
    prefix = r.pick(g.prefixes);
    n = compose();
  }
  if (owned.contains(n)) n = '$n·${owned.length + 1}';
  final (value, stats) = _value(id, rarity, statIds);
  return Treasure(
    id: id, name: n, kind: kind, material: material, rarity: rarity, stats: stats, value: value, source: source,
    story: story ?? (switch (i18n.lang) { Lang.zh => kindStory[kind], Lang.en => kindStoryEn[kind], Lang.es => kindStoryEs[kind] }) ?? tr('裡面藏著神秘的力量。', 'A mysterious power hides inside.', 'Dentro se esconde un poder misterioso.'),
  );
}
