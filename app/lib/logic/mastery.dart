// 知识点掌握状态规则：确定的规则，不交给 GPT（从原来的后端 mastery.ts 原样搬过来）。
//   薄弱：分析时需要学 / 判为"不会"，课后练习没过关，或者重做原题时用错了
//   学习中：练习过关
//   基本掌握：重做原题时用对了，或者分析时判为"会"（之前没有记录）
//   熟练：留给以后的间隔复习
// 数据都是能直接存成 JSON 的 Map。

typedef Json = Map<String, dynamic>;

Json _fresh(int at) => {
      'state': 'weak', 'firstAt': at, 'lastAt': at, 'wrongCount': 0,
      'lessonsPassed': 0, 'lessonsFailed': 0, 'practiceRight': 0, 'practiceTotal': 0, 'lastErrorType': null,
    };

int _int(Object? v) => (v as num?)?.toInt() ?? 0;

/// 把一个事件应用到知识点状态上（直接改 [states]）
void applyToKps(Json states, Json e) {
  final at = _int(e['at']);
  Json take(String id) => states[id] = {...(states[id] as Map?)?.cast<String, dynamic>() ?? _fresh(at)};

  switch (e['type']) {
    case 'problem.analyzed':
      final kps = [for (final k in e['knowledgePoints'] as List? ?? []) (k as Map).cast<String, dynamic>()];
      final weak = {for (final id in e['missingKps'] as List? ?? []) '$id', for (final k in kps) if (k['judgement'] == '不会') '${k['kpId']}'};
      for (final id in weak) {
        final s = take(id);
        s['state'] = 'weak';
        s['wrongCount'] = _int(s['wrongCount']) + 1;
        s['lastErrorType'] = (e['error'] as Map?)?['type'];
        s['lastAt'] = at;
      }
      for (final k in kps) {
        final id = '${k['kpId']}';
        if (k['judgement'] == '会' && !weak.contains(id) && states[id] == null) states[id] = {..._fresh(at), 'state': 'basic'};
      }
    case 'practice.graded':
      if (e['skipped'] == true) return;
      final s = take('${e['kpId']}');
      s['practiceTotal'] = _int(s['practiceTotal']) + 1;
      if (e['correct'] == true && e['revealed'] != true) s['practiceRight'] = _int(s['practiceRight']) + 1;
      s['lastAt'] = at;
    case 'lesson.finished':
      final s = take('${e['kpId']}');
      if (e['passed'] == true) {
        s['lessonsPassed'] = _int(s['lessonsPassed']) + 1;
        if (s['state'] == 'weak') s['state'] = 'learning';
      } else {
        s['lessonsFailed'] = _int(s['lessonsFailed']) + 1;
        s['state'] = 'weak';
      }
      s['lastAt'] = at;
    case 'redo.checked':
      for (final c in e['kpChecks'] as List? ?? []) {
        final check = (c as Map).cast<String, dynamic>();
        if (check['applied'] == '没用到') continue;
        final s = take('${check['kpId']}');
        if (check['applied'] == '用对了') {
          if (s['state'] == 'weak' || s['state'] == 'learning') s['state'] = 'basic';
        } else {
          s['state'] = 'weak';
          s['wrongCount'] = _int(s['wrongCount']) + 1;
        }
        s['lastAt'] = at;
      }
  }
}

/// 把事件应用到题目记录上（家长报表用）。返回新的记录；与题目无关的事件返回 null。
Json? applyToProblem(Json? p, Json e) {
  final at = _int(e['at']);
  switch (e['type']) {
    case 'problem.analyzed':
      return {
        'pid': e['pid'],
        'createdAt': p?['createdAt'] ?? at,
        'updatedAt': at,
        'source': e['source'],
        'status': e['status'],
        'problemText': e['problemText'] ?? '',
        'studentAnswer': e['studentAnswer'],
        'isCorrect': e['isCorrect'],
        'correctAnswer': e['correctAnswer'] ?? '',
        'error': e['error'] ?? {'step': null, 'type': '无错误', 'description': ''},
        'knowledgePoints': e['knowledgePoints'] ?? [],
        'missingKps': e['missingKps'] ?? [],
        'lessons': p?['lessons'] ?? <String, dynamic>{},
        'redo': p?['redo'],
      };
    case 'lesson.finished':
      if (p == null) return null;
      final lessons = {...(p['lessons'] as Map?)?.cast<String, dynamic>() ?? {}};
      final prev = (lessons['${e['kpId']}'] as Map?)?.cast<String, dynamic>();
      final round = _int(e['round']);
      lessons['${e['kpId']}'] = {
        'rounds': _int(prev?['rounds']) > round ? _int(prev?['rounds']) : round,
        'passed': e['passed'] == true, 'right': _int(e['right']), 'total': _int(e['total']),
      };
      return {...p, 'updatedAt': at, 'lessons': lessons};
    case 'redo.checked':
      if (p == null) return null;
      return {...p, 'updatedAt': at, 'redo': {'at': at, 'isCorrect': e['isCorrect'] == true, 'kpChecks': e['kpChecks'] ?? []}};
  }
  return null;
}

/// 事件对当天统计的增量
Map<String, int> dailyDelta(Json e) => switch (e['type']) {
      'problem.analyzed' => {'problems': 1, 'firstTryCorrect': e['isCorrect'] == true ? 1 : 0},
      'practice.graded' => e['skipped'] == true ? {} : {'practice': 1, 'practiceRight': e['correct'] == true && e['revealed'] != true ? 1 : 0},
      'lesson.finished' => {'lessons': 1, 'lessonsPassed': e['passed'] == true ? 1 : 0},
      'redo.checked' => {'redos': 1, 'redoCorrect': e['isCorrect'] == true ? 1 : 0},
      'treasure.found' => {'treasures': 1},
      'session.ended' => {'seconds': _int(e['seconds'])},
      _ => {},
    };

/// 本地日期（YYYY-MM-DD），每日统计按这台设备的时区分天
String dayOf(int at) {
  final d = DateTime.fromMillisecondsSinceEpoch(at);
  return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
