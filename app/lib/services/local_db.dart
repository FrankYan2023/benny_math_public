import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../i18n.dart';
import '../logic/mastery.dart';
import '../models/hunt.dart';
import '../models/jail.dart';
import '../theme/pixel_theme.dart';

class LocalDbException implements Exception {
  LocalDbException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// 一个知识点的掌握状态
class KpInfo {
  const KpInfo(this.status, this.lastAt);
  final KpStatus status;
  final int lastAt; // 最近一次学习的时间（毫秒）
}

/// 一个村庄的修炼情况（地图上显示）
class VillageInfo {
  VillageInfo.fromJson(Map<String, dynamic> j)
      : finished = j['finished'] as bool? ?? false,
        defeated = (j['defeated'] as num?)?.toInt() ?? 0,
        total = (j['total'] as num?)?.toInt() ?? 0;

  final bool finished;
  final int defeated;
  final int total;
}

/// 打怪存档列表里的一项
class HuntSummary {
  HuntSummary.fromJson(Map<String, dynamic> j)
      : pid = j['pid'] as String,
        createdAt = (j['createdAt'] as num).toInt(),
        updatedAt = (j['updatedAt'] as num).toInt(),
        problemText = j['problemText'] as String? ?? '',
        stage = j['stage'] as String? ?? 'analysis',
        kpIds = [for (final k in j['kpIds'] as List? ?? []) '$k'],
        errorType = j['errorType'] as String? ?? '',
        photoHashes = [for (final h in j['photoHashes'] as List? ?? []) '$h'],
        monster = (j['monster'] as Map?)?.cast<String, dynamic>(),
        done = j['done'] as bool? ?? false;

  final String pid;
  final int createdAt;
  final int updatedAt;
  final String problemText;
  final String stage;
  final List<String> kpIds;
  final String errorType;
  final List<String> photoHashes;
  final Map<String, dynamic>? monster; // 这只错题怪兽（MonsterTraits 的 JSON）
  final bool done;
}

/// 本机数据库：全部学习记录只存在这台设备上（应用支持目录下的 data/），不上传到任何服务器。
/// 每份存档一个 JSON 文件；列表用的摘要另存一份索引，打开怪兽屋不用读全部存档。
///   hunts/<题目编号>.json、hunts.json（索引）     打怪存档：分析结果、修炼内容、进度
///   villages/<知识点>.json、villages.json（索引）  村庄修炼存档
///   jail/<编号>.json                              怪兽监狱
///   kp.json、problems.json、daily.json            知识点状态、题目记录、每日统计（家长报表用）
///   events.jsonl                                  全部学习事件（以后改规则可以重算）
class LocalDb {
  LocalDb(this.dir);

  final Directory dir;

  static LocalDb? _instance;
  static LocalDb get instance => _instance ?? (throw StateError('LocalDb 还没打开，先调用 LocalDb.open()'));

  /// App 启动时打开
  static Future<LocalDb> open() async => _instance ??= LocalDb(Directory('${(await getApplicationSupportDirectory()).path}/data'));

  /// 测试用：换一个目录
  static LocalDb useDirectory(Directory d) => _instance = LocalDb(d);

  // ---------- 文件 ----------
  static String safe(String id) => id.replaceAll(RegExp(r'[^A-Za-z0-9_.~-]'), '_');
  File _file(String rel) => File('${dir.path}/$rel');

  Future<Map<String, dynamic>?> _readJson(String rel) async {
    final f = _file(rel);
    if (!await f.exists()) return null;
    try {
      return (jsonDecode(await f.readAsString()) as Map).cast<String, dynamic>();
    } catch (_) {
      return null; // 文件坏了当作没有
    }
  }

  // 同一个文件的写入排队进行；先写临时文件再改名，写到一半断电也不会坏
  final _queues = <String, Future<void>>{};
  Future<void> _queue(String rel, Future<void> Function(File f) op) {
    final next = (_queues[rel] ?? Future<void>.value()).then((_) => op(_file(rel)));
    _queues[rel] = next.catchError((_) {});
    return next;
  }

  Future<void> _writeJson(String rel, Object value) => _queue(rel, (f) async {
        await f.parent.create(recursive: true);
        final tmp = File('${f.path}.tmp');
        await tmp.writeAsString(jsonEncode(value), flush: true);
        await tmp.rename(f.path);
      });

  Future<void> _delete(String rel) => _queue(rel, (f) async {
        if (await f.exists()) await f.delete();
      });

  // 常用的几个表放在内存里，改完整份写回
  final _tables = <String, Map<String, dynamic>>{};
  Future<Map<String, dynamic>> _table(String rel) async => _tables[rel] ??= await _readJson(rel) ?? {};
  Future<void> _saveTable(String rel) => _writeJson(rel, _tables[rel] ?? {});

  int get _now => DateTime.now().millisecondsSinceEpoch;

  // ---------- 学习事件 ----------
  /// 记一个学习事件：更新知识点状态、题目记录、每日统计
  Future<void> record(String type, Map<String, dynamic> payload) => apply({'type': type, 'at': _now, ...payload});

  Future<void> apply(Map<String, dynamic> e) async {
    final kp = await _table('kp.json');
    final problems = await _table('problems.json');
    final daily = await _table('daily.json');
    applyToKps(kp, e);
    final pid = e['pid'];
    if (pid is String) {
      final next = applyToProblem((problems[pid] as Map?)?.cast<String, dynamic>(), e);
      if (next != null) problems[pid] = next;
    }
    final day = dayOf((e['at'] as num).toInt());
    final d = (daily[day] as Map?)?.cast<String, dynamic>() ?? {};
    dailyDelta(e).forEach((k, v) => d[k] = ((d[k] as num?)?.toInt() ?? 0) + v);
    daily[day] = d;
    await Future.wait([
      _saveTable('kp.json'),
      _saveTable('problems.json'),
      _saveTable('daily.json'),
      _queue('events.jsonl', (f) async {
        await f.parent.create(recursive: true);
        await f.writeAsString('${jsonEncode(e)}\n', mode: FileMode.append, flush: true);
      }),
    ]);
  }

  /// 家庭版时期没传上后端的学习事件（存在本机的 pendingEvents 队列里）：按时间顺序记进本机数据库，然后删掉队列。
  /// 宝藏的拿到、卖掉当时就已经记在本机（PlayerStore），这里只算每日统计。返回收进来的条数。
  Future<int> ingestLegacyQueue() async {
    final p = await SharedPreferences.getInstance();
    final queue = p.getStringList('pendingEvents');
    if (queue == null) return 0;
    final events = <Map<String, dynamic>>[];
    for (final s in queue) {
      try {
        final e = (jsonDecode(s) as Map).cast<String, dynamic>();
        if (e['type'] is String && e['at'] is num) events.add(e);
      } catch (_) {}
    }
    events.sort((a, b) => (a['at'] as num).compareTo(b['at'] as num));
    for (final e in events) {
      await apply(e);
    }
    await p.remove('pendingEvents');
    return events.length;
  }

  /// 每个知识点的掌握状态和最近一次学习的时间；没有记录的知识点不在返回里（视为未检测）
  Future<Map<String, KpInfo>> kpStates() async {
    final kp = await _table('kp.json');
    return {
      for (final e in kp.entries)
        e.key: KpInfo(KpStatus.parse((e.value as Map)['state'] as String?), ((e.value as Map)['lastAt'] as num?)?.toInt() ?? 0),
    };
  }

  /// 原始的知识点状态、题目记录、每日统计（家长报表用）
  Future<Map<String, dynamic>> rawKpStates() => _table('kp.json');
  Future<Map<String, dynamic>> problems() => _table('problems.json');
  Future<Map<String, dynamic>> daily() => _table('daily.json');

  // ---------- 打怪存档 ----------
  /// 打怪存档：分析结果和全部修炼内容只让 GPT 生成一次，存在这里，之后打开直接读
  Future<void> saveHunt(HuntSession s) async {
    if (s.demo) return;
    final index = await _table('hunts.json');
    final now = _now;
    final createdAt = ((index[s.pid] as Map?)?['createdAt'] as num?)?.toInt() ?? s.createdAt;
    index[s.pid] = {...s.summary(), 'pid': s.pid, 'createdAt': createdAt, 'updatedAt': now};
    await Future.wait([
      _writeJson('hunts/${safe(s.pid)}.json', {'pid': s.pid, 'createdAt': createdAt, 'updatedAt': now, 'session': s.toJson()}),
      _saveTable('hunts.json'),
    ]);
  }

  /// 存档列表（摘要，最近更新的在前）
  Future<List<HuntSummary>> listHunts({int limit = 50}) async {
    final index = await _table('hunts.json');
    final list = [for (final v in index.values) HuntSummary.fromJson((v as Map).cast<String, dynamic>())]
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return list.take(limit).toList();
  }

  Future<HuntSession> getHunt(String pid) async {
    final doc = await _readJson('hunts/${safe(pid)}.json');
    if (doc == null) throw LocalDbException(tr('找不到這道題的存檔。', "Can't find this problem's save.", 'No se encuentra la partida guardada de este problema.'));
    return HuntSession.fromJson((doc['session'] as Map).cast<String, dynamic>());
  }

  /// 放生一只怪兽：删掉这道题的存档和题目记录（宝藏、知识点状态、学习事件不删）
  Future<void> deleteHunt(String pid) async {
    final index = await _table('hunts.json');
    final problems = await _table('problems.json');
    index.remove(pid);
    problems.remove(pid);
    await Future.wait([_delete('hunts/${safe(pid)}.json'), _saveTable('hunts.json'), _saveTable('problems.json')]);
  }

  // ---------- 村庄修炼 ----------
  /// 村庄修炼存档：冒险地图上每个知识点的修炼内容只让 GPT 生成一次，存在这里
  Future<void> saveVillage(HuntSession s) async {
    if (s.demo || s.village == null) return;
    final index = await _table('villages.json');
    final now = _now;
    final createdAt = ((index[s.village] as Map?)?['createdAt'] as num?)?.toInt() ?? now;
    index[s.village!] = {...s.villageSummary(), 'createdAt': createdAt, 'updatedAt': now};
    await Future.wait([
      _writeJson('villages/${safe(s.village!)}.json', {'kpId': s.village, 'createdAt': createdAt, 'updatedAt': now, 'session': s.toJson()}),
      _saveTable('villages.json'),
    ]);
  }

  /// 读村庄修炼存档；还没有就返回 null
  Future<HuntSession?> getVillage(String kpId) async {
    final doc = await _readJson('villages/${safe(kpId)}.json');
    return doc == null ? null : HuntSession.fromJson((doc['session'] as Map).cast<String, dynamic>());
  }

  Future<Map<String, VillageInfo>> listVillages() async {
    final index = await _table('villages.json');
    return {for (final e in index.entries) e.key: VillageInfo.fromJson((e.value as Map).cast<String, dynamic>())};
  }

  // ---------- 怪兽监狱 ----------
  Future<void> saveJail(JailCase c) async {
    final rel = 'jail/${safe(c.id)}.json';
    final prev = await _readJson(rel);
    final now = _now;
    await _writeJson(rel, {'id': c.id, 'createdAt': prev?['createdAt'] ?? now, 'updatedAt': now, 'summary': c.summary(), 'case': c.toJson()});
  }

  Future<List<JailCase>> listJail() async => [for (final d in await _jailDocs()) JailCase.fromJson((d['case'] as Map).cast<String, dynamic>())];

  /// 监狱里每道题的摘要（家长报表用）
  Future<List<Map<String, dynamic>>> jailSummaries() async => [for (final d in await _jailDocs()) (d['summary'] as Map).cast<String, dynamic>()];

  Future<List<Map<String, dynamic>>> _jailDocs() async {
    final d = Directory('${dir.path}/jail');
    if (!await d.exists()) return [];
    final out = <Map<String, dynamic>>[];
    await for (final f in d.list()) {
      if (f is! File || !f.path.endsWith('.json')) continue;
      try {
        out.add((jsonDecode(await f.readAsString()) as Map).cast<String, dynamic>());
      } catch (_) {}
    }
    return out;
  }

  /// 读监狱里的一道题；没有就返回 null
  Future<JailCase?> getJail(String id) async {
    final doc = await _readJson('jail/${safe(id)}.json');
    return doc == null ? null : JailCase.fromJson((doc['case'] as Map).cast<String, dynamic>());
  }

  // ---------- 备份和恢复 ----------
  /// 一起备份的本机设置：宝藏、孩子的名字、没打完的题（不含 ChatGPT 登录信息）
  static const backupPrefs = ['player.treasures.v1', 'studentName', 'hunt.v2'];
  static const _backupFormat = 1;

  /// 导出全部数据（一个 JSON，换设备、手机和 iPad 之间搬数据用）
  Future<Map<String, dynamic>> exportAll() async {
    await Future.wait(_queues.values); // 等正在写的写完
    final files = <String, Object>{};
    if (await dir.exists()) {
      await for (final f in dir.list(recursive: true)) {
        if (f is! File || f.path.endsWith('.tmp')) continue;
        final rel = f.path.substring(dir.path.length + 1).replaceAll(r'\\', '/');
        final text = await f.readAsString();
        files[rel] = rel.endsWith('.jsonl') ? text : jsonDecode(text) as Object;
      }
    }
    final p = await SharedPreferences.getInstance();
    return {
      'app': 'benny-math',
      'format': _backupFormat,
      'exportedAt': _now,
      'files': files,
      'prefs': {for (final k in backupPrefs) if (p.getString(k) != null) k: p.getString(k)},
    };
  }

  /// 从备份恢复：这台设备上原来的学习记录全部换成备份里的
  Future<void> importAll(Map<String, dynamic> backup) async {
    final files = backup['files'];
    if (backup['app'] != 'benny-math' || backup['format'] != _backupFormat || files is! Map) {
      throw LocalDbException(tr('這不是 Benny Math 的備份檔案。', "This isn't a Benny Math backup file.", 'Esto no es una copia de seguridad de Benny Math.'));
    }
    final ok = RegExp(r'^[A-Za-z0-9_.~-]+(/[A-Za-z0-9_.~-]+)?$');
    for (final rel in files.keys) {
      if (!ok.hasMatch('$rel') || '$rel'.contains('..')) throw LocalDbException(tr('備份檔案壞了。', 'The backup file is damaged.', 'El archivo de copia está dañado.'));
    }
    await Future.wait(_queues.values);
    _queues.clear();
    _tables.clear();
    if (await dir.exists()) await dir.delete(recursive: true);
    for (final e in files.entries) {
      final f = _file('${e.key}');
      await f.parent.create(recursive: true);
      await f.writeAsString(e.value is String ? e.value as String : jsonEncode(e.value), flush: true);
    }
    final p = await SharedPreferences.getInstance();
    final prefs = (backup['prefs'] as Map?) ?? {};
    for (final k in backupPrefs) {
      final v = prefs[k];
      v is String ? await p.setString(k, v) : await p.remove(k);
    }
  }
}
