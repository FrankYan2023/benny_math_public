import 'dart:convert';

import 'package:flutter/services.dart';

import '../i18n.dart';

/// 七年级知识点清单（assets/knowledge.json，由 tool/sync_knowledge.sh 从 shared/ 同步）
class KnowledgePoint {
  const KnowledgePoint({
    required this.id,
    required this.name,
    required this.tier,
    required this.module,
    required this.pre,
    this.nameEn = '',
    this.nameEs = '',
    this.nameHant = '',
  });

  final String id;
  final String name; // 简体中文名（发给 GPT 用，不直接显示）
  final String nameEn;
  final String nameEs;
  final String nameHant;

  /// 按界面语言显示的名字
  String get label => _pick(name, nameHant, nameEn, nameEs);

  /// 层级名字：小学衔接 / 初一必备 / 拓展
  String get tierLabel => switch (tier) { 'b' => tr('小學銜接', 'Primary Review', 'Repaso de Primaria'), 'e' => tr('拓展', 'Extension', 'Ampliación'), _ => tr('初一必備', 'Grade 7 Core', 'Básico de 1.º ESO') };
  final String tier; // b 小学衔接 / c 初一必备 / e 拓展
  final String module;
  final List<String> pre;

  bool get isExtension => tier == 'e';
}

class KnowledgeModule {
  const KnowledgeModule({
    required this.id,
    required this.name,
    required this.term,
    this.nameEn = '',
    this.shortEn = '',
    this.nameEs = '',
    this.shortEs = '',
    this.nameHant = '',
  });

  final String id;
  final String name; // 简体中文名
  final String nameEn;
  final String shortEn; // 短名（地图上的木牌）
  final String nameEs;
  final String shortEs;
  final String nameHant;
  final String term; // 前置基础 / 七年级上 / 七年级下（内部值）

  String get shortLabel => _pick(name, nameHant, shortEn, shortEs);
  String get label => _pick(name, nameHant, nameEn, nameEs);
  String get termLabel => switch (term) {
        '前置基础' => tr('前置基礎', 'Foundations', 'Fundamentos'),
        '七年级上' => tr('七年級上', 'Grade 7 · Term 1', '1.º ESO · 1.ª parte'),
        '七年级下' => tr('七年級下', 'Grade 7 · Term 2', '1.º ESO · 2.ª parte'),
        _ => term,
      };
}

class Knowledge {
  Knowledge._(this.version, this.modules, this.kps) : byId = {for (final k in kps) k.id: k};

  final String version;
  final List<KnowledgeModule> modules;
  final List<KnowledgePoint> kps;
  final Map<String, KnowledgePoint> byId;

  List<KnowledgePoint> inModule(String moduleId) => kps.where((k) => k.module == moduleId).toList();

  static Future<Knowledge> load() async {
    final raw = jsonDecode(await rootBundle.loadString('assets/knowledge.json')) as Map<String, dynamic>;
    return Knowledge._(
      raw['version'] as String,
      [
        for (final m in raw['modules'] as List)
          KnowledgeModule(
            id: m['id'] as String,
            name: m['name'] as String,
            term: m['term'] as String,
            nameEn: m['name_en'] as String? ?? '',
            shortEn: m['short_en'] as String? ?? '',
            nameEs: m['name_es'] as String? ?? '',
            shortEs: m['short_es'] as String? ?? '',
            nameHant: m['name_hant'] as String? ?? '',
          ),
      ],
      [
        for (final k in raw['kps'] as List)
          KnowledgePoint(
            id: k['id'] as String,
            name: k['name'] as String,
            tier: k['tier'] as String,
            module: k['module'] as String,
            pre: [for (final p in k['pre'] as List) p as String],
            nameEn: k['name_en'] as String? ?? '',
            nameEs: k['name_es'] as String? ?? '',
            nameHant: k['name_hant'] as String? ?? '',
          ),
      ],
    );
  }
}

/// 按界面语言挑名字；缺了就退回英文，再退回简体中文
String _pick(String zhHans, String zhHant, String en, String es) => switch (i18n.lang) {
      Lang.zh => zhHant.isNotEmpty ? zhHant : zhHans,
      Lang.es => es.isNotEmpty ? es : (en.isNotEmpty ? en : zhHans),
      Lang.en => en.isNotEmpty ? en : zhHans,
    };
