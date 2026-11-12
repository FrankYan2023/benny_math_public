import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'game_data.dart';
import 'treasure.dart';

/// Benny 的冒险者卡片（规则写在这里，不交给 GPT）：
///   能力 = 拿到过的全部宝藏加的点数之和（卖掉宝藏不扣能力）
///   金币 = 卖宝藏换来的
///   等级按能力总和算：升到第 L 级需要能力总和 ≥ 5 × L × (L − 1)：2 级 10、3 级 30、4 级 60、5 级 100、6 级 150…
class Player {
  Player(this.treasures);

  final List<Treasure> treasures; // 拿到过的全部宝藏（包括卖掉的），旧的在前

  /// 还在宝藏箱里的（没卖掉的）
  List<Treasure> get owned => [for (final t in treasures) if (!t.sold) t];
  List<Treasure> get soldList => [for (final t in treasures) if (t.sold) t];

  Map<String, int> get stats {
    final out = {for (final s in GameData.instance.stats) s.id: 0};
    for (final t in treasures) {
      t.stats.forEach((k, v) => out[k] = (out[k] ?? 0) + v);
    }
    return out;
  }

  int get power => stats.values.fold(0, (a, b) => a + b);
  int get coins => soldList.fold(0, (a, t) => a + t.value);

  /// 这只怪兽（这个村庄）的宝藏拿过没有：宝藏编号以题目编号开头，卖掉的也算
  bool tookFrom(String pid) => treasures.any((t) => t.id.startsWith('$pid/'));

  static int need(int level) => 5 * level * (level - 1);
  static int levelOf(int power) {
    var l = 1;
    while (power >= need(l + 1)) {
      l++;
    }
    return l;
  }

  int get level => levelOf(power);

  String get title {
    final titles = GameData.instance.titleList;
    return level <= titles.length ? titles[level - 1] : '${titles.last} ★${level - titles.length}';
  }

  /// 这一级的进度（0–1）
  double get progress {
    final lo = need(level), hi = need(level + 1);
    return ((power - lo) / (hi - lo)).clamp(0, 1).toDouble();
  }

  Set<String> get names => {for (final t in treasures) t.name};
}

/// 宝藏在本机也存一份（拿到就能马上显示），联网后和后端的合并（按宝藏编号去重）
abstract final class PlayerStore {
  static const _key = 'player.treasures.v1';

  static Future<Player> load() async {
    final p = await SharedPreferences.getInstance();
    try {
      final list = jsonDecode(p.getString(_key) ?? '[]') as List;
      return Player([for (final t in list) Treasure.fromJson((t as Map).cast<String, dynamic>())]);
    } catch (_) {
      return Player([]);
    }
  }

  static Future<void> _save(List<Treasure> list) async =>
      (await SharedPreferences.getInstance()).setString(_key, jsonEncode([for (final t in list) t.toJson()]));

  /// 拿到一件宝藏；返回 (之前, 之后)，用来判断有没有升级
  static Future<(Player, Player)> add(Treasure t) async {
    final before = await load();
    if (before.treasures.any((x) => x.id == t.id)) return (before, before);
    final after = Player([...before.treasures, t]);
    await _save(after.treasures);
    return (before, after);
  }

  /// 卖掉一件宝藏；返回卖掉的那件（没有这件、或者已经卖掉了返回空）
  static Future<Treasure?> sell(String id, {DateTime? now}) async {
    final list = [...(await load()).treasures];
    final i = list.indexWhere((t) => t.id == id && !t.sold);
    if (i < 0) return null;
    list[i] = list[i].soldOn((now ?? DateTime.now()).millisecondsSinceEpoch);
    await _save(list);
    return list[i];
  }

  /// 合并后端的宝藏（换了设备、重装 App 时找回来）；哪边记着卖掉了就算卖掉了
  static Future<Player> merge(List<Treasure> remote) async {
    final local = await load();
    final remoteById = {for (final t in remote) t.id: t};
    final byId = {
      for (final t in remote) t.id: t,
      for (final t in local.treasures) t.id: !t.sold && remoteById[t.id]?.soldAt != null ? t.soldOn(remoteById[t.id]!.soldAt!) : t,
    };
    final list = byId.values.toList()..sort((a, b) => a.at.compareTo(b.at));
    await _save(list);
    return Player(list);
  }
}
