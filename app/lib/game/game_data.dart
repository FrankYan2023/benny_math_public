import 'dart:convert';

import 'package:flutter/services.dart';

import '../i18n.dart';

/// 游戏设定（assets/game.json，由 shared/game.json 同步）：怪兽的形容词、宝藏的种类和材质、能力、等级称号
class GameData {
  GameData._(Map<String, dynamic> j)
      : species = (j['monster']['species'] as Map).cast<String, String>(),
        personalities = _list(j['monster']['personalities']),
        looks = _list(j['monster']['looks']),
        colors = _list(j['monster']['colors']),
        kinds = _list(j['treasure']['kinds']),
        materials = _list(j['treasure']['materials']),
        prefixes = _list(j['treasure']['prefixes']),
        drops = _list(j['treasure']['drops']),
        stats = [
          for (final s in j['stats'] as List)
            (
              id: '${s['id']}',
              name: '${s['name']}',
              desc: '${s['desc']}',
              nameEn: '${s['name_en']}',
              descEn: '${s['desc_en']}',
              nameEs: '${s['name_es']}',
              descEs: '${s['desc_es']}',
              nameHant: '${s['name_hant']}',
              descHant: '${s['desc_hant']}',
            ),
        ],
        rarities = [
          for (final r in j['rarities'] as List)
            (
              id: '${r['id']}',
              name: '${r['name']}',
              nameEn: '${r['name_en']}',
              nameEs: '${r['name_es']}',
              nameHant: '${r['name_hant']}',
              boost: r['boost'] as int,
              coins: ((r['coins'] as List)[0] as int, (r['coins'] as List)[1] as int),
            ),
        ],
        titles = _list(j['titles']),
        titlesEn = _list(j['titles_en']),
        titlesEs = _list(j['titles_es']),
        titlesHant = _list(j['titles_hant']),
        _en = (j['en'] as Map).cast<String, String>(),
        _es = (j['es'] as Map).cast<String, String>(),
        _esMaterial = (j['es_material'] as Map).cast<String, String>(),
        _esGender = (j['es_gender'] as Map).cast<String, String>(),
        _esFeminine = (j['es_feminine'] as Map).cast<String, String>(),
        _hant = (j['hant'] as Map).cast<String, String>();

  static List<String> _list(Object? v) => [for (final x in v as List) '$x'];

  final Map<String, String> species; // 错因 → 怪兽种类
  final List<String> personalities;
  final List<String> looks;
  final List<String> colors;
  final List<String> kinds;
  final List<String> materials;
  final List<String> prefixes;
  final List<String> drops;
  final List<
      ({String id, String name, String desc, String nameEn, String descEn, String nameEs, String descEs, String nameHant, String descHant})> stats;
  final List<({String id, String name, String nameEn, String nameEs, String nameHant, int boost, (int, int) coins})> rarities;
  final List<String> titles; // 简体中文（内部）
  final List<String> titlesEn;
  final List<String> titlesEs;
  final List<String> titlesHant;
  final Map<String, String> _en;
  final Map<String, String> _es;
  final Map<String, String> _esMaterial; // 材质和颜色同名时（青铜），材质的西班牙文
  final Map<String, String> _esGender; // 宝藏种类：m / f / mp / fp
  final Map<String, String> _esFeminine; // 宝藏前缀的阴性形式
  final Map<String, String> _hant;

  /// 一个游戏词（怪兽形容词、宝藏种类、材质…）按当前语言显示；词本身是简体中文的固定值
  String word(String zh) => switch (i18n.lang) { Lang.zh => _hant[zh] ?? zh, Lang.es => _es[zh] ?? _en[zh] ?? zh, Lang.en => _en[zh] ?? zh };

  /// 宝藏材质（西班牙文里材质写成 "de oro" 这样）
  String material(String zh) => i18n.es ? (_esMaterial[zh] ?? word(zh)) : word(zh);

  /// 西班牙文的宝藏前缀要跟种类的阴阳性、单复数一致
  String prefixFor(String prefix, String kind) {
    if (!i18n.es) return word(prefix);
    final g = _esGender[kind] ?? 'm';
    var w = g.startsWith('f') ? (_esFeminine[prefix] ?? word(prefix)) : word(prefix);
    if (g.endsWith('p') && !w.contains(' ')) {
      w = 'aeiouáéíóú'.contains(w[w.length - 1]) ? '${w}s' : (w.endsWith('z') ? '${w.substring(0, w.length - 1)}ces' : '${w}es');
    }
    return w;
  }

  String statName(String id) {
    final s = stats.where((s) => s.id == id).firstOrNull;
    return s == null ? id : tr(s.nameHant, s.nameEn, s.nameEs);
  }

  String statDesc(String id) {
    final s = stats.where((s) => s.id == id).firstOrNull;
    return s == null ? '' : tr(s.descHant, s.descEn, s.descEs);
  }

  String rarityName(String id) {
    final r = rarities.where((r) => r.id == id).firstOrNull;
    return r == null ? id : tr(r.nameHant, r.nameEn, r.nameEs);
  }

  List<String> get titleList => switch (i18n.lang) { Lang.zh => titlesHant, Lang.es => titlesEs, Lang.en => titlesEn };

  String? statId(String name) => stats.where((s) => s.name == name || s.id == name).firstOrNull?.id;

  static GameData? _cache;
  static GameData get instance => _cache ?? (throw StateError('GameData 还没加载'));

  static Future<GameData> load() async =>
      _cache ??= GameData._(jsonDecode(await rootBundle.loadString('assets/game.json')) as Map<String, dynamic>);

  /// 测试用：直接给 JSON
  static GameData fromJson(Map<String, dynamic> j) => _cache = GameData._(j);
}

/// 稳定的哈希（同一个字符串在哪台设备上算都一样），用来当随机种子
int stableHash(String s) {
  var h = 0x811c9dc5;
  for (final c in s.codeUnits) {
    h ^= c;
    h = (h * 0x01000193) & 0xffffffff;
  }
  return h;
}

/// 小小的伪随机数（种子一样，结果就一样）
class SeededRandom {
  SeededRandom(int seed) : _s = seed == 0 ? 0x9e3779b9 : seed & 0xffffffff;
  int _s;

  int next() {
    _s ^= (_s << 13) & 0xffffffff;
    _s ^= _s >> 17;
    _s ^= (_s << 5) & 0xffffffff;
    return _s & 0x7fffffff;
  }

  int below(int n) => n <= 0 ? 0 : next() % n;
  bool chance(double p) => next() / 0x7fffffff < p;
  T pick<T>(List<T> xs) => xs[below(xs.length)];
}
