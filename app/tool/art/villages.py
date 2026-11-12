"""地图上的村庄（每个知识点一个），按掌握状态画成不同的样子。16×16。"""
from pixel import Canvas, hexc

K = hexc('#2a1f2d')


def _house(roof, roof_dark, wall=hexc('#f4ead2'), wall_dark=hexc('#d6c7a4'), chimney=True):
    c = Canvas(16, 16)
    c.rect(3, 9, 10, 5, wall)
    c.rect(3, 13, 10, 1, wall_dark)
    if chimney:
        c.rect(11, 2, 2, 4, hexc('#9a6b4e'))
    for i in range(7):   # 尖屋顶
        c.rect(1 + i, 8 - i, 14 - 2 * i, 1, roof)
    c.replace_edge(roof, roof_dark, 'r')
    c.rect(1, 8, 14, 1, roof_dark)
    c.rect(7, 10, 2, 4, hexc('#7a4a32'))   # 门
    c.rect(4, 10, 2, 2, hexc('#9fd3ff')); c.rect(10, 10, 2, 2, hexc('#9fd3ff'))   # 窗
    return c


def untested():
    """没去过：灰色小屋，屋顶上一个问号"""
    c = _house(hexc('#a8adb8'), hexc('#868b98'), hexc('#d9d9dd'), hexc('#b9bac2'), chimney=False)
    q = hexc('#ffffff')
    for x, y in [(7, 3), (8, 2), (9, 2), (10, 3), (9, 4), (8, 5), (8, 7)]:
        c.set(x, y, q)
    c.outline(K)
    return c


def weak():
    """薄弱：被怪兽占领的营地——红帐篷、骷髅旗"""
    c = Canvas(16, 16)
    r, rd = hexc('#e0464f'), hexc('#a82c36')
    for i in range(7):
        c.rect(7 - i, 7 + i, 2 + 2 * i, 1, r)
    c.replace_edge(r, rd, 'r')
    c.rect(7, 10, 2, 4, hexc('#3a1f2a'))   # 帐篷门
    c.rect(8, 1, 1, 7, hexc('#5a3a2a'))     # 旗杆
    c.rect(9, 1, 5, 4, hexc('#2a1f2d'))
    c.set(11, 2, hexc('#ffffff')); c.set(10, 2, hexc('#ffffff')); c.set(12, 2, hexc('#ffffff')); c.set(11, 3, hexc('#ffffff'))
    c.set(2, 14, hexc('#9a7be0')); c.set(3, 14, hexc('#9a7be0')); c.set(2, 13, hexc('#9a7be0')); c.set(3, 13, hexc('#9a7be0'))   # 小怪兽
    c.set(2, 13, hexc('#ffffff'))
    c.outline(K)
    return c


def learning():
    """学习中：正在盖的房子，黄色屋顶、脚手架"""
    c = _house(hexc('#f2c14e'), hexc('#c9971f'), chimney=False)
    sc = hexc('#9a6b3e')
    for y in range(6, 15):
        c.set(14, y, sc)
    c.rect(12, 9, 3, 1, sc); c.rect(12, 12, 3, 1, sc)
    c.set(1, 14, hexc('#d9654a')); c.set(2, 14, hexc('#d9654a')); c.set(1, 13, hexc('#d9654a'))   # 砖
    c.outline(K)
    return c


def basic():
    """基本掌握：蓝屋顶小房子，有烟囱"""
    c = _house(hexc('#3b7dd8'), hexc('#28589e'))
    c.set(12, 0, hexc('#e6eef7')); c.set(13, 0, hexc('#e6eef7'))
    c.outline(K)
    return c


def solid():
    """熟练：小城堡，金色旗子"""
    c = Canvas(16, 16)
    s, sd, sl = hexc('#c9ced8'), hexc('#9aa1b0'), hexc('#e7eaf0')
    c.rect(3, 6, 10, 8, s)
    for x in (3, 6, 9, 12):   # 城垛
        c.rect(x, 4, 2 if x < 12 else 1, 2, s)
    c.rect(3, 13, 10, 1, sd)
    c.rect(3, 6, 1, 7, sl)
    c.rect(7, 9, 2, 5, hexc('#5a3a2a'))
    c.rect(5, 7, 1, 2, hexc('#2a1f2d')); c.rect(10, 7, 1, 2, hexc('#2a1f2d'))
    c.rect(8, 0, 1, 4, hexc('#5a3a2a'))
    c.rect(9, 0, 4, 3, hexc('#ffd84a')); c.set(12, 2, None)
    c.outline(K)
    return c


VILLAGES = {'untested': untested, 'weak': weak, 'learning': learning, 'basic': basic, 'solid': solid}
