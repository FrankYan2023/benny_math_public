"""错题怪兽（按错因）和练习小怪（按难度），32×32。"""
from pixel import Canvas, hexc

K = hexc('#22182a')
W = hexc('#ffffff')
E = hexc('#22182a')
PINK = hexc('#ff8fa3')
RED = hexc('#e0464f')


def shade(c, base, dark, light=None):
    c.replace_edge(base, dark, 'b')
    c.replace_edge(base, dark, 'r')
    if light:
        c.replace_edge(base, light, 't')


def eye(c, x, y, size=2, shine=True, color=E):
    c.rect(x, y, size, size + 1, color)
    if shine:
        c.set(x, y, W)


def ghost():
    """粗心鬼（计算失误）：吐舌头、一只眼眨着的小幽灵，手里转着铅笔"""
    b, d, l = hexc('#f1eefe'), hexc('#c5bde8'), hexc('#ffffff')
    c = Canvas(32, 32)
    c.ellipse(16, 13, 10, 10, b)
    c.rect(6, 13, 20, 12, b)
    for i, x in enumerate(range(6, 26, 4)):   # 波浪下摆
        c.ellipse(x + 2, 25, 2.2, 2.2 if i % 2 else 3, b)
    c.ellipse(4.5, 18, 2.2, 1.6, b); c.ellipse(27.5, 16, 2.2, 1.6, b)   # 小手
    shade(c, b, d, l)
    eye(c, 11, 11, 2)
    c.rect(19, 12, 3, 1, E)   # 眨眼
    c.rect(13, 17, 6, 2, E)
    c.rect(15, 19, 3, 2, PINK)   # 舌头
    c.set(9, 15, PINK); c.set(22, 15, PINK)
    # 铅笔
    for i in range(6):
        c.set(26 + i // 2, 9 + i, hexc('#f2c14e'))
        c.set(27 + i // 2, 9 + i, hexc('#e0a020'))
    c.set(29, 15, hexc('#f6d7b0')); c.set(29, 16, E)
    c.set(26, 8, PINK); c.set(27, 8, PINK)
    c.outline(K)
    return c


def bug():
    """糊涂虫（概念不清）：绿色毛毛虫，转圈圈的眼睛，触角打结"""
    g, d, l = hexc('#7ccf5a'), hexc('#4f9a3a'), hexc('#a8e58a')
    y_, yd = hexc('#f2c14e'), hexc('#d9a12a')
    c = Canvas(32, 32)
    for x, y, r in [(6, 23, 4), (11, 22, 4.5), (16.5, 21, 5)]:
        c.ellipse(x, y, r, r, g)
    for x, y in [(6, 23), (11, 22), (16.5, 21)]:
        c.set(int(x), y - 1, y_); c.set(int(x) + 1, y - 1, y_)
    c.ellipse(22, 14, 7.5, 7, g)   # 头
    shade(c, g, d, l)
    for x, y in [(5, 27), (9, 27), (13, 27), (17, 26)]:   # 小脚
        c.rect(x, y, 2, 2, d)
    # 触角
    for x, y in [(19, 7), (18, 6), (18, 5), (19, 4), (20, 5), (25, 7), (26, 6), (27, 5), (27, 4), (26, 4)]:
        c.set(x, y, d)
    c.ellipse(20.5, 4.5, 1.2, 1.2, y_); c.ellipse(26, 3.5, 1.2, 1.2, y_)
    # 转圈的眼睛
    for ex in (19, 25):
        c.ellipse(ex, 13, 2.6, 2.6, W)
        c.set(ex - 1, 12, E); c.set(ex, 12, E); c.set(ex, 13, E); c.set(ex - 1, 14, E); c.set(ex + 1, 14, E); c.set(ex + 1, 12, E)
    c.rect(20, 18, 4, 1, E); c.set(19, 17, E); c.set(24, 19, E)   # 歪嘴
    c.set(17, 16, hexc('#ff9f9f')); c.set(27, 16, hexc('#ff9f9f'))
    c.outline(K)
    return c


def lost():
    """迷路怪（方法不会）：紫色软团子，拿着倒过来的地图，头上冒问号"""
    v, d, l = hexc('#9a7be0'), hexc('#6c50b8'), hexc('#c2aef5')
    c = Canvas(32, 32)
    c.ellipse(16, 20, 11, 9, v)
    c.ellipse(16, 15, 8, 8, v)
    shade(c, v, d, l)
    eye(c, 11, 14, 3); eye(c, 19, 14, 3)
    c.rect(14, 21, 4, 1, E); c.set(13, 22, E); c.set(18, 22, E)
    # 地图
    m, md = hexc('#f6ecd2'), hexc('#d8c69c')
    c.rect(4, 22, 10, 7, m); c.rect(4, 28, 10, 1, md)
    for x, y in [(6, 24), (7, 25), (9, 24), (10, 26), (12, 25)]:
        c.set(x, y, RED if x == 12 else hexc('#7a8a9a'))
    # 问号
    q = hexc('#f2c14e')
    for x, y in [(23, 2), (24, 1), (25, 1), (26, 2), (26, 3), (25, 4), (24, 5), (24, 6), (24, 8)]:
        c.set(x, y, q)
    c.outline(K)
    return c


def cyclops():
    """马虎眼（审题错误）：独眼怪，眼皮耷拉着只看一半"""
    o, d, l = hexc('#f5a64a'), hexc('#d27a26'), hexc('#ffc983')
    c = Canvas(32, 32)
    c.ellipse(16, 17, 11, 11, o)
    for x0 in (8, 22):   # 角
        c.rect(x0, 4, 2, 3, hexc('#f6ecd2')); c.set(x0 + (0 if x0 < 16 else 1), 3, hexc('#f6ecd2'))
    shade(c, o, d, l)
    c.ellipse(16, 15, 6, 5.5, W)
    c.rect(10, 10, 13, 5, o)   # 耷拉的眼皮盖住上半
    c.rect(10, 14, 13, 1, d)
    c.rect(15, 15, 3, 3, E); c.set(15, 15, W)
    c.rect(12, 23, 8, 1, E); c.set(11, 22, E); c.set(20, 22, E)
    c.set(13, 24, W); c.set(18, 24, W)   # 小牙
    c.rect(9, 27, 3, 2, d); c.rect(20, 27, 3, 2, d)   # 脚
    c.outline(K)
    return c


def mouse():
    """地基鼠（前置缺失）：戴安全帽的鼹鼠，抱着一块被挖走的砖"""
    g, d, l = hexc('#9a8a9e'), hexc('#6f6075'), hexc('#bdb0c0')
    c = Canvas(32, 32)
    c.ellipse(16, 20, 10, 9, g)
    c.ellipse(16, 13, 8, 7, g)
    c.ellipse(8, 9, 3, 3, g); c.ellipse(24, 9, 3, 3, g)   # 耳朵
    c.ellipse(8, 9, 1.5, 1.5, PINK); c.ellipse(24, 9, 1.5, 1.5, PINK)
    shade(c, g, d, l)
    # 安全帽
    y_, yd = hexc('#f2c14e'), hexc('#c9971f')
    c.ellipse(16, 8.5, 7.5, 4, y_)
    c.rect(8, 8, 16, 2, y_); c.rect(7, 10, 18, 1, yd)
    c.rect(15, 5, 2, 4, yd)
    eye(c, 12, 13, 2); eye(c, 19, 13, 2)
    c.ellipse(16, 17, 2.5, 1.6, PINK); c.set(16, 17, E)
    c.set(15, 19, W); c.set(17, 19, W)   # 大门牙
    # 砖
    br, brd = hexc('#d9654a'), hexc('#a8452f')
    c.rect(10, 22, 12, 6, br)
    c.rect(10, 24, 12, 1, brd); c.rect(15, 22, 1, 2, brd); c.rect(12, 25, 1, 3, brd); c.rect(18, 25, 1, 3, brd)
    c.ellipse(9, 24, 2, 1.8, l); c.ellipse(23, 24, 2, 1.8, l)   # 爪子
    c.outline(K)
    return c


def slime():
    """史莱姆（基础）"""
    g, d, l = hexc('#6fd38a'), hexc('#3fa65e'), hexc('#b5f2c4')
    c = Canvas(32, 32)
    c.ellipse(16, 22, 12, 8, g)
    c.ellipse(16, 17, 8, 8, g)
    c.rect(4, 22, 24, 7, g)
    shade(c, g, d)
    c.ellipse(11, 13, 2, 3, l)   # 高光
    c.set(10, 12, W)
    eye(c, 12, 18, 2); eye(c, 19, 18, 2)
    c.rect(15, 23, 3, 1, E); c.set(14, 22, E); c.set(18, 22, E)
    c.set(10, 22, hexc('#ff9f9f')); c.set(22, 22, hexc('#ff9f9f'))
    c.outline(K)
    return c


def skeleton():
    """骷髅兵（变式）"""
    b, d = hexc('#f4efe2'), hexc('#c8c0ad')
    c = Canvas(32, 32)
    c.ellipse(16, 10, 8, 7.5, b)
    c.rect(11, 15, 10, 3, b)
    shade(c, b, d)
    c.ellipse(12.5, 10, 2.2, 2.5, E); c.ellipse(19.5, 10, 2.2, 2.5, E)
    c.set(12, 9, RED); c.set(19, 9, RED)
    c.rect(15, 13, 2, 1, E)
    for x in (12, 14, 16, 18):
        c.set(x, 16, E)
    # 身体骨头
    c.rect(15, 19, 2, 8, b)
    for y in (20, 22, 24):
        c.rect(12, y, 8, 1, b)
    c.rect(9, 19, 2, 6, b); c.rect(21, 19, 2, 6, b)
    c.rect(12, 27, 2, 4, b); c.rect(18, 27, 2, 4, b)
    # 剑
    s, sd = hexc('#cfd8e3'), hexc('#8d99a8')
    for i in range(10):
        c.set(24 + i // 3, 21 - i, s); c.set(25 + i // 3, 21 - i, sd)
    c.rect(22, 22, 5, 1, hexc('#9a6b3e'))
    c.outline(K)
    return c


def knight():
    """骑士（提高）"""
    a, d, l = hexc('#aeb9c8'), hexc('#7a879a'), hexc('#dce3ec')
    c = Canvas(32, 32)
    c.ellipse(15, 11, 8, 8, a)
    c.rect(7, 11, 16, 8, a)
    c.rect(9, 19, 13, 9, a)
    c.rect(10, 28, 4, 3, d); c.rect(17, 28, 4, 3, d)
    shade(c, a, d, l)
    c.rect(9, 12, 13, 2, E)   # 面罩缝
    c.set(12, 12, hexc('#ffd84a')); c.set(18, 12, hexc('#ffd84a'))
    for y in range(15, 18):
        c.set(15, y, d)
    # 羽毛
    r = hexc('#e0464f')
    for x, y in [(15, 2), (16, 1), (17, 1), (18, 2), (19, 2), (20, 3), (21, 4)]:
        c.rect(x, y, 1, 2, r)
    # 盾
    s, sd = hexc('#3b7dd8'), hexc('#28589e')
    c.rect(20, 17, 9, 10, s)
    c.rect(21, 27, 7, 1, s); c.rect(22, 28, 5, 1, s); c.rect(23, 29, 3, 1, s)
    c.replace_edge(s, sd, 'r')
    c.rect(24, 19, 1, 8, hexc('#f2c14e')); c.rect(21, 22, 7, 1, hexc('#f2c14e'))
    c.outline(K)
    return c


def boss():
    """小 Boss（挑战）：戴王冠的小紫龙"""
    v, d, l = hexc('#a35bd6'), hexc('#7337a3'), hexc('#c993ee')
    c = Canvas(32, 32)
    # 翅膀
    wing = hexc('#5b2f86')
    for i in range(7):
        c.rect(2 + i, 10 + i, 6 - i // 2, 1, wing)
        c.rect(24 - i // 2 + i, 10 + i, 6 - i // 2, 1, wing)
    c.ellipse(16, 22, 9, 8, v)
    c.ellipse(16, 13, 8.5, 7, v)
    shade(c, v, d, l)
    c.ellipse(16, 24, 5, 5, hexc('#f2d27a'))   # 肚子
    # 王冠
    g, gd = hexc('#ffd84a'), hexc('#d9a520')
    c.rect(10, 4, 12, 3, g)
    for x in (10, 14, 17, 21):
        c.rect(x, 2, 1 if x in (10, 21) else 2, 2, g)
    c.rect(10, 6, 12, 1, gd)
    c.set(15, 5, RED); c.set(16, 5, RED)
    # 眼睛（凶凶的）
    c.rect(11, 11, 3, 3, W); c.rect(18, 11, 3, 3, W)
    c.rect(12, 12, 2, 2, E); c.rect(18, 12, 2, 2, E)
    c.rect(10, 10, 4, 1, E); c.rect(18, 10, 4, 1, E)
    c.rect(13, 16, 6, 1, E)
    c.set(13, 17, W); c.set(18, 17, W)   # 小尖牙
    c.rect(9, 29, 4, 2, d); c.rect(19, 29, 4, 2, d)
    c.outline(K)
    return c


def house():
    """怪兽屋：以前抓到的错题怪兽都住在这里。紫屋顶、石头墙，窗户里亮着怪兽的眼睛"""
    c = Canvas(32, 32)
    wall, wall_d, wall_l = hexc('#c9b8a6'), hexc('#9c8a78'), hexc('#e3d6c6')
    roof, roof_d = hexc('#7b4fc4'), hexc('#5a3596')
    c.rect(5, 14, 22, 16, wall)
    for y in (17, 21, 25):   # 石头缝
        c.rect(5, y, 22, 1, wall_d)
    for x, y in [(9, 14), (17, 14), (13, 18), (22, 18), (9, 22), (19, 22), (13, 26), (23, 26)]:
        c.rect(x, y, 1, 3, wall_d)
    c.rect(5, 14, 1, 16, wall_l)
    for i in range(10):   # 尖屋顶
        c.rect(3 + i, 13 - i, 26 - 2 * i, 1, roof)
    c.replace_edge(roof, roof_d, 'r')
    c.rect(2, 13, 28, 1, roof_d)
    c.rect(22, 2, 3, 6, hexc('#8a8a96'))   # 烟囱
    for x, y in [(23, 0), (25, 1), (22, 1)]:
        c.set(x, y, hexc('#b5e86a'))   # 冒绿烟
    # 圆窗户，里面一双发亮的眼睛
    for cx in (10, 22):
        c.ellipse(cx, 19, 3, 3, hexc('#2a1f3a'))
        c.set(cx - 1, 19, hexc('#ffe45a')); c.set(cx + 1, 19, hexc('#ffe45a'))
    # 门
    door = hexc('#6a3e26')
    c.rect(13, 22, 6, 8, door)
    c.rect(14, 21, 4, 1, door)
    c.set(17, 26, hexc('#ffd84a'))
    # 门口的小牌子
    c.rect(12, 9, 8, 3, hexc('#f6ecd2'))
    for x in (13, 15, 17):
        c.set(x, 10, hexc('#5a3596'))
    c.outline(K)
    return c


def jail():
    """怪兽监狱：放弃过的题关在这里。灰石头碉堡，铁栏杆窗户里关着一只怪兽，门上挂着大锁"""
    c = Canvas(32, 32)
    stone, stone_d, stone_l = hexc('#9aa3ad'), hexc('#6c7480'), hexc('#c4cbd3')
    c.rect(3, 9, 26, 21, stone)
    for x in (3, 9, 15, 21, 27):   # 城垛
        c.rect(x, 6, 4, 3, stone)
    for y in (13, 17, 21, 25):   # 石头缝
        c.rect(3, y, 26, 1, stone_d)
    for i, y in enumerate((9, 13, 17, 21, 25)):
        for x in range(6 + 4 * (i % 2), 28, 8):
            c.rect(x, y + 1, 1, 3, stone_d)
    c.rect(3, 6, 1, 24, stone_l)
    # 铁栏杆窗户，里面一只紫怪兽和它的眼睛
    c.rect(7, 11, 18, 9, hexc('#2a1f3a'))
    c.ellipse(16, 18, 6, 5, hexc('#8a5cd6'), only={hexc('#2a1f3a')})
    for x in (13, 18):
        c.rect(x, 14, 2, 2, W); c.set(x + 1, 15, E)
    c.rect(14, 18, 4, 1, E)
    bar = hexc('#4a4f5a')
    for x in (8, 11, 14, 17, 20, 23):
        c.rect(x, 11, 1, 9, bar)
    c.rect(7, 11, 18, 1, bar); c.rect(7, 19, 18, 1, bar)
    # 铁门和大锁
    door = hexc('#5a5f6a')
    c.rect(12, 22, 8, 8, door)
    for x in (14, 17):
        c.rect(x, 22, 1, 8, bar)
    c.rect(14, 24, 4, 4, hexc('#ffd84a'))
    c.set(15, 26, hexc('#3a2010')); c.set(16, 26, hexc('#3a2010'))
    c.rect(14, 24, 4, 1, hexc('#c9971f'))
    c.outline(K)
    return c


def chest(open_=False):
    """宝箱：修炼完、打赢 Boss 时打开"""
    c = Canvas(32, 32)
    wood, wood_d, wood_l = hexc('#a8693a'), hexc('#6e4020'), hexc('#d08f58')
    gold, gold_d = hexc('#ffd84a'), hexc('#c9971f')
    # 箱身
    c.rect(4, 16, 24, 12, wood)
    for y in (19, 23):
        c.rect(4, y, 24, 1, wood_d)
    c.rect(4, 16, 24, 1, wood_l)
    c.rect(4, 16, 2, 12, gold); c.rect(26, 16, 2, 12, gold)
    c.rect(4, 27, 24, 1, gold_d)
    if open_:
        # 打开的盖子（往后翻）和冒出来的光
        c.rect(5, 7, 22, 7, wood)
        c.rect(5, 7, 22, 1, wood_l)
        c.rect(5, 13, 22, 1, wood_d)
        c.rect(5, 7, 2, 7, gold); c.rect(25, 7, 2, 7, gold)
        c.rect(6, 14, 20, 2, hexc('#3a2010'))
        glow = hexc('#fff3a8')
        for x, y in [(10, 4), (16, 2), (22, 4), (13, 5), (19, 5), (16, 5), (8, 2), (24, 2)]:
            c.set(x, y, glow)
        for x in range(8, 25, 2):
            c.set(x, 15, gold)
    else:
        c.rect(4, 9, 24, 7, wood)
        c.rect(4, 9, 24, 1, wood_l)
        c.rect(4, 15, 24, 1, wood_d)
        c.rect(4, 9, 2, 7, gold); c.rect(26, 9, 2, 7, gold)
        c.ellipse(16, 9.5, 12, 3, wood, only=None)
        c.rect(14, 13, 4, 5, gold)   # 锁
        c.set(15, 15, hexc('#3a2010')); c.set(16, 15, hexc('#3a2010'))
        c.rect(14, 13, 4, 1, gold_d)
    c.outline(K)
    return c


def coin():
    """金币 16×16"""
    c = Canvas(16, 16)
    c.ellipse(8, 8, 6.5, 6.5, hexc('#f2c14e'))
    c.ellipse(8, 8, 4.5, 4.5, hexc('#ffd84a'))
    c.replace_edge(hexc('#f2c14e'), hexc('#c9971f'), 'b')
    c.replace_edge(hexc('#f2c14e'), hexc('#c9971f'), 'r')
    c.rect(7, 5, 2, 6, hexc('#c9971f'))
    c.set(5, 4, hexc('#fff3a8')); c.set(4, 5, hexc('#fff3a8'))
    c.outline(K)
    return c


MONSTERS = {
    'ghost': ghost, 'bug': bug, 'lost': lost, 'cyclops': cyclops, 'mouse': mouse,
    'slime': slime, 'skeleton': skeleton, 'knight': knight, 'boss': boss,
    'house': house,
    'jail': jail,
    'chest': chest,
    'chest_open': lambda: chest(True),
    'coin': coin,
}
