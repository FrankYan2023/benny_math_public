"""小加和小减：Benny 的两只小乌龟——小加（大的，绿壳）和小减（小的，红壳），一起当向导。44×32，表情：idle（还有眨眼帧）、happy、oops、thinking。"""
from pixel import Canvas, hexc

K = hexc('#1f2a1f')
E = hexc('#1f1a2a')
W = hexc('#ffffff')
BLUSH = hexc('#ff9f9f')
MOUTH = hexc('#7a2e35')
SWEAT = hexc('#5cc8ff')

SKIN = (hexc('#9fdc7c'), hexc('#74b85a'), hexc('#c8f0a8'))   # 皮肤：主、暗、亮
SHELLS = {
    'green': (hexc('#3f9a54'), hexc('#2c7240'), hexc('#7cc96a'), hexc('#f0dc8a')),   # 壳：主、暗、花纹、壳边
    'red': (hexc('#d9473f'), hexc('#a32f2b'), hexc('#f27a62'), hexc('#f3dfa0')),
}


def turtle(c, cx, top, size, shell, mood, blink):
    """坐着、脸朝前的小乌龟。cx = 中心 x，top = 头顶 y，size = 头的半径"""
    s, sd, sp, rim = SHELLS[shell]
    skin, skin_d, skin_l = SKIN
    hr = size
    hy = top + hr
    # 壳在头后面，露出两边和下面
    shx, shy = cx, hy + hr * 1.25
    srx, sry = hr * 1.75, hr * 1.1
    c.ellipse(shx, shy, srx, sry, s)
    # 壳上的六边形花纹
    for dx, dy in [(-0.95, -0.15), (0.95, -0.15), (-0.5, 0.45), (0.5, 0.45), (0, -0.55)]:
        c.ellipse(shx + dx * srx * 0.62, shy + dy * sry * 0.8, srx * 0.18, sry * 0.2, sp)
    c.replace_edge(s, sd, 'b')
    c.replace_edge(s, sd, 'r')
    # 壳边（肚皮那一圈）
    for x in range(int(shx - srx) + 1, int(shx + srx)):
        y = int(shy + sry * 0.55)
        if c.get(x, y) in (s, sd, sp):
            c.set(x, y, rim)
    # 脚
    for fx in (-0.8, 0.8):
        c.ellipse(shx + fx * srx * 0.75, shy + sry * 0.85, hr * 0.42 + 1, hr * 0.32 + 1, K)
        c.ellipse(shx + fx * srx * 0.75, shy + sry * 0.85, hr * 0.42, hr * 0.32, skin)
    # 头
    c.ellipse(cx, hy, hr + 1, hr * 0.92 + 1, K)   # 头和壳之间描一圈，分得开
    c.ellipse(cx, hy, hr, hr * 0.92, skin)
    c.replace_edge(skin, skin_d, 'b')
    c.replace_edge(skin, skin_d, 'r')
    for dx, dy in [(-0.5, -0.65), (-0.35, -0.75), (-0.65, -0.45)]:
        x, y = int(cx + dx * hr), int(hy + dy * hr)
        if c.get(x, y) == skin:
            c.set(x, y, skin_l)
    # 眼睛
    ey = int(hy - hr * 0.1)
    big = hr >= 6
    for ex in (int(cx - hr * 0.45), int(cx + hr * 0.45) - (1 if big else 0)):
        if blink:
            c.rect(ex - 1, ey + 1, 3 if big else 2, 1, E)
        elif mood == 'happy':
            c.set(ex - 1, ey + 1, E); c.set(ex, ey, E); c.set(ex + 1, ey, E)
            if big:
                c.set(ex + 2, ey + 1, E)
        elif mood == 'oops':
            c.set(ex - 1, ey - 1, E); c.set(ex, ey, E); c.set(ex + 1, ey + 1, E)
            c.set(ex + 1, ey - 1, E); c.set(ex - 1, ey + 1, E)
        else:
            w = 2 if big else 1
            c.rect(ex, ey - 1, w, 3 if big else 2, E)
            look = 1 if mood == 'thinking' else 0
            c.set(ex + (w - 1 if look else 0), ey - 1, W)
    # 腮红和嘴
    my = int(hy + hr * 0.45)
    if mood != 'oops':
        c.set(int(cx - hr * 0.75), my - 1, BLUSH); c.set(int(cx + hr * 0.75), my - 1, BLUSH)
    if mood == 'happy':
        c.rect(int(cx) - 1, my, 3 if big else 2, 2 if big else 1, MOUTH)
    elif mood == 'oops':
        c.rect(int(cx) - (1 if big else 0), my, 2, 2 if big else 1, MOUTH)
    elif mood == 'thinking':
        c.rect(int(cx), my, 2, 1, E)
    else:
        c.set(int(cx) - 1, my, E); c.set(int(cx), my + 1, E); c.set(int(cx) + 1, my, E)
        if big:
            c.set(int(cx) + 2, my + 1, E); c.set(int(cx) + 3, my, E)


def turtles(mood='idle', blink=False):
    c = Canvas(44, 32)
    # 小减（小的，红壳）在后面右边，小加（大的，绿壳）在前面左边
    turtle(c, 33, 9, 5, 'red', mood, blink)
    turtle(c, 15, 3, 7, 'green', mood, blink)
    if mood == 'oops':
        c.rect(25, 3, 2, 3, SWEAT); c.set(26, 2, SWEAT); c.set(25, 3, W)
    if mood == 'thinking':
        q = hexc('#f2c14e')
        for x, y in [(40, 1), (41, 0), (42, 0), (43, 1), (43, 2), (42, 3), (41, 4), (41, 6)]:
            c.set(x, y, q)
    c.outline(K)
    return c


MOODS = ['idle', 'happy', 'oops', 'thinking']
