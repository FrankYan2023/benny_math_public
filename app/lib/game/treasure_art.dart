import 'package:flutter/material.dart';

import '../theme/pixel_theme.dart';
import '../widgets/pixel_box.dart';
import 'game_data.dart';
import 'monster_art.dart';
import 'treasure.dart';

/// 宝藏图标：16×16，按种类画形状，按材质上色；m 主色、d 暗、l 亮、h 木柄、p 纸、g 宝石点缀、b 玻璃
const _shapes = <String, List<String>>{
  '剑': [
    '.............ll.',
    '............lml.',
    '...........lmd..',
    '..........lmd...',
    '.........lmd....',
    '........lmd.....',
    '.......lmd......',
    '...gg.lmd.......',
    '...ggdmd........',
    '....gdd.........',
    '...hhgg.........',
    '..hh..gg........',
    '.hh.............',
    'gh..............',
    '................',
    '................',
  ],
  '盾': [
    '................',
    '..dddddddddddd..',
    '..dllmmmmmmmmd..',
    '..dlmmmmggmmmd..',
    '..dlmmmmggmmmd..',
    '..dmmggggggmmd..',
    '..dmmggggggmmd..',
    '..dmmmmmggmmmd..',
    '..dmmmmmggmmmd..',
    '...dmmmmggmmd...',
    '...dmmmmmmmmd...',
    '....dmmmmmmd....',
    '.....dmmmmd.....',
    '......dmmd......',
    '.......dd.......',
    '................',
  ],
  '宝石': [
    '................',
    '................',
    '................',
    '....dddddddd....',
    '...dlllmmmmmd...',
    '..dlllmmmmmmmd..',
    '.dddddddddddddd.',
    '..dmmmmmmmmmmd..',
    '...dmmmmmmmmd...',
    '....dmmmmmmd....',
    '.....dmmmmd.....',
    '......dmmd......',
    '.......dd.......',
    '................',
    '................',
    '................',
  ],
  '药水': [
    '................',
    '......hhhh......',
    '......hhhh......',
    '.......bb.......',
    '.......bb.......',
    '......bbbb......',
    '.....bbbbbb.....',
    '....bbllbbbb....',
    '...bblmmmmmmb...',
    '...bmmmmmmmmb...',
    '...bmmmmmmmdb...',
    '...bmmmmmmmdb...',
    '....bmmmmmdb....',
    '.....bbbbbb.....',
    '................',
    '................',
  ],
  '卷轴': [
    '................',
    '..hhhhhhhhhhhh..',
    '..hppppppppppd..',
    '...pppppppppp...',
    '...pddddddddp...',
    '...pppppppppp...',
    '...pdddddddpp...',
    '...pppppppppp...',
    '...pddddddp.p...',
    '...pppppppppp...',
    '...pppmmmmppp...',
    '...pppmggmppp...',
    '..hppppppppppd..',
    '..hhhhhhhhhhhh..',
    '................',
    '................',
  ],
  '戒指': [
    '................',
    '................',
    '.......gg.......',
    '......gllg......',
    '......gggg......',
    '.....mmmmmm.....',
    '....ml....dm....',
    '...ml......dm...',
    '...m........m...',
    '...m........m...',
    '...md......dm...',
    '....md....dm....',
    '.....mmmmmm.....',
    '................',
    '................',
    '................',
  ],
  '王冠': [
    '................',
    '................',
    '................',
    '..m....m....m...',
    '..mm..mgm..mm...',
    '..mlm.mmm.mlm...',
    '..mlmmmmmmmlm...',
    '..mmmmmmmmmmm...',
    '..mmgmmgmmgmm...',
    '..mmmmmmmmmmm...',
    '..ddddddddddd...',
    '................',
    '................',
    '................',
    '................',
    '................',
  ],
  '护身符': [
    '................',
    '....d......d....',
    '.....d....d.....',
    '......d..d......',
    '.......dd.......',
    '......mmmm......',
    '.....mlllmm.....',
    '....mlmggmmm....',
    '....mlgggmmm....',
    '....mmmggmmd....',
    '.....mmmmmd.....',
    '......mmdd......',
    '.......dd.......',
    '................',
    '................',
    '................',
  ],
  '靴子': [
    '................',
    '................',
    '.....mmmmm......',
    '.....mlmmm......',
    '.....mlmmm......',
    '.....mmmmm......',
    '.....mggmm......',
    '.....mmmmm......',
    '.....mmmmmmm....',
    '.....mmmmmmmmm..',
    '....mmmmmmmmmmm.',
    '....ddddddddddd.',
    '................',
    '................',
    '................',
    '................',
  ],
  '魔法书': [
    '................',
    '................',
    '...mmmmmmmmmm...',
    '...mlmmmmmmmmp..',
    '...mlmmmggmmmp..',
    '...mlmmggggmmp..',
    '...mlmmmggmmmp..',
    '...mlmmmmmmmmp..',
    '...mlmmmmmmmmp..',
    '...mlmmmmmmmmp..',
    '...mlmmmmmmmmp..',
    '...ddddddddddp..',
    '....pppppppppp..',
    '................',
    '................',
    '................',
  ],
  '钥匙': [
    '................',
    '................',
    '....mmmm........',
    '...mlllmm.......',
    '...ml..dm.......',
    '...ml..dm.......',
    '...mmmmmm.......',
    '.....mm.........',
    '.....mm.........',
    '.....mmmm.......',
    '.....mm.........',
    '.....mmmm.......',
    '.....mm.........',
    '................',
    '................',
    '................',
  ],
  '法杖': [
    '................',
    '..........mmm...',
    '.........mllmm..',
    '.........mlmmm..',
    '..........mmd...',
    '.........hh.....',
    '........hh......',
    '.......hh.......',
    '......hh........',
    '.....hh.........',
    '....hh..........',
    '...hh...........',
    '..hh............',
    '................',
    '................',
    '................',
  ],
};

typedef _Mat = ({Color m, Color d, Color l, Color g});
const _materials = <String, _Mat>{
  '黄金': (m: Color(0xfff2c14e), d: Color(0xffb9851a), l: Color(0xfffff0a6), g: Color(0xffe0405a)),
  '白银': (m: Color(0xffd0d6e0), d: Color(0xff8e97a8), l: Color(0xffffffff), g: Color(0xff4a7de0)),
  '青铜': (m: Color(0xffc08a4a), d: Color(0xff7d5426), l: Color(0xffe8b67a), g: Color(0xff4fc38a)),
  '水晶': (m: Color(0xffa8e6ff), d: Color(0xff5aa8d6), l: Color(0xffecfbff), g: Color(0xffff8fc0)),
  '翡翠': (m: Color(0xff4fc38a), d: Color(0xff2a8a5a), l: Color(0xffa6f0c8), g: Color(0xfff2c14e)),
  '红宝石': (m: Color(0xffe0405a), d: Color(0xff9a2236), l: Color(0xffff8a9e), g: Color(0xfff2c14e)),
  '蓝宝石': (m: Color(0xff4a7de0), d: Color(0xff2a4a9e), l: Color(0xff9ec0ff), g: Color(0xfff2c14e)),
  '黑曜石': (m: Color(0xff4a4060), d: Color(0xff2a2238), l: Color(0xff7a6e96), g: Color(0xff9a6be0)),
};
const _wood = Color(0xff8a5a36);
const _paper = Color(0xfff6ecd2);
const _glass = Color(0xffd8f0ff);
const _ink = Color(0xff22182a);

/// 稀有度的颜色和名字
const rarityColors = {'common': Color(0xff8e97a8), 'rare': Color(0xff3b7dd8), 'epic': Color(0xff9a4fd8), 'legend': Color(0xfff08a1a)};
String rarityName(String id) => GameData.instance.rarityName(id);

final _cache = <String, PixelGrid>{};

PixelGrid drawTreasure(String kind, String material) => _cache.putIfAbsent('$kind/$material', () {
      final rows = _shapes[kind] ?? _shapes['宝石']!;
      final mat = _materials[material] ?? _materials['黄金']!;
      final g = PixelGrid(16, 16);
      for (var y = 0; y < 16; y++) {
        for (var x = 0; x < 16; x++) {
          final c = switch (rows[y][x]) {
            'm' => mat.m,
            'd' => mat.d,
            'l' => mat.l,
            'g' => mat.g,
            'h' => _wood,
            'p' => _paper,
            'b' => _glass,
            _ => null,
          };
          if (c != null) g.set(x, y, c);
        }
      }
      g.outline(_ink);
      return g;
    });

/// 宝藏图标，外面一圈稀有度颜色的框；传说的会闪光
class TreasureIcon extends StatelessWidget {
  const TreasureIcon(this.t, {super.key, this.size = 64});
  final Treasure t;
  final double size;

  @override
  Widget build(BuildContext context) => PixelBox(
        width: size,
        height: size,
        color: Color.alphaBlend(rarityColors[t.rarity]!.withValues(alpha: 0.18), Px.panel),
        border: rarityColors[t.rarity]!,
        shadow: false,
        padding: EdgeInsets.all(size * 0.08),
        child: CustomPaint(painter: PixelGridPainter(drawTreasure(t.kind, t.material))),
      );
}
