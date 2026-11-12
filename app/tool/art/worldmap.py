"""冒险世界地图：每个年级一块陆地，每个知识点一个村庄，沿着一条路按顺序排开。
输出：地图底图（不含村庄，村庄由 App 按掌握状态画上去）和布局（每个知识点的坐标、区域和模块牌子的位置）。"""
import json
import math
import random

from pixel import Canvas, hexc

W, H = 640, 400
STEP = 17.5   # 村庄间距（地图像素）

C = {k: hexc(v) for k, v in {
    'sea': '#3f8fd6', 'sea2': '#3683cb', 'wave': '#7dbdf0', 'shallow': '#62acea', 'foam': '#cfe9fb',
    'sand': '#f2dc9b', 'sand2': '#e0c27a',
    'meadow': '#a5dc6e', 'meadow2': '#8fcc5c', 'flower1': '#ffffff', 'flower2': '#ffd84a', 'flower3': '#ff9fb0',
    'grass': '#6dbf4b', 'grass2': '#5aa83c', 'grass3': '#80cc5c',
    'desert': '#ecc97a', 'desert2': '#d9b05c', 'desert3': '#f6dc9c',
    'fog': '#b7bccb', 'fog2': '#a3a9ba', 'cloud': '#f4f6fb', 'cloud2': '#dde2ee',
    'road': '#f0dcae', 'road2': '#c9a46a',
    'tree': '#3f9a4a', 'tree2': '#2e7a3a', 'tree3': '#5cb85c', 'trunk': '#7a4a32',
    'pine': '#2f7d55', 'pine2': '#235f41',
    'rock': '#a39a90', 'rock2': '#7d746b', 'snow': '#ffffff',
    'cactus': '#4fa84a', 'cactus2': '#3a8a3a',
    'outline': '#2a3a4a', 'bridge': '#b07a4a', 'bridge2': '#7a4a32',
}.items()}


def serpentine(spans, rows):
    """蛇形路线：spans[i] = (起点 x, 终点 x)，rows[i] = 这一行的 y；行与行之间在外侧用半圆拐弯"""
    pts = []
    for i, ((a, b), y) in enumerate(zip(spans, rows)):
        n = max(2, int(abs(b - a) / 4))
        pts += [(a + (b - a) * k / n, y) for k in range(n + 1)]
        if i + 1 < len(rows):
            ny = rows[i + 1]
            r = abs(ny - y) / 2
            d = 1 if b > a else -1
            for k in range(1, 12):
                t = math.pi * k / 12
                pts.append((b + d * r * math.sin(t), y + (ny - y) * (1 - math.cos(t)) / 2))
    return pts


def resample(pts, n, margin=0.5):
    """沿折线等距取 n 个点"""
    seg = [math.dist(pts[i], pts[i + 1]) for i in range(len(pts) - 1)]
    total = sum(seg)
    out = []
    for k in range(n):
        target = total * (k + margin) / n
        acc = 0
        for i, s in enumerate(seg):
            if acc + s >= target:
                t = (target - acc) / s if s else 0
                out.append((pts[i][0] + (pts[i + 1][0] - pts[i][0]) * t, pts[i][1] + (pts[i + 1][1] - pts[i][1]) * t))
                break
            acc += s
    return out, total


def build(kb):
    rnd = random.Random(7)
    modules = kb['modules']
    by_module = {}
    for k in kb['kps']:
        by_module.setdefault(k['module'], []).append(k['id'])

    # ---------- 路线 ----------
    # 小学衔接：左下角的出发草原，弯弯的一小段
    road_a = [(30, 372), (50, 362), (72, 368), (96, 358), (118, 364), (140, 352), (158, 336), (168, 316), (172, 296)]
    # 七年级上：中间偏左的大陆，从出发草原上来，5 行蛇形，自下而上，最后到右上角的桥
    rows_b = [272, 222, 172, 122, 72]
    road_b = [(172, 290)] + serpentine([(172, 318), (318, 52), (52, 318), (318, 52), (52, 318)], rows_b)
    # 七年级下：右边的沙漠，4 行蛇形，自上而下
    road_c = serpentine([(414, 590), (590, 414), (414, 590), (590, 414)], [66, 118, 170, 222])

    def place(road, mods, gap_after_module=0.0):
        ids = [i for m in mods for i in by_module[m]]
        pts, total = resample(road, len(ids))
        return dict(zip(ids, pts)), total

    pos = {}
    for road, mods in [(road_a, ['X']), (road_b, [m['id'] for m in modules if m['term'] == '七年级上']),
                       (road_c, [m['id'] for m in modules if m['term'] == '七年级下'])]:
        p, total = place(road, mods)
        pos.update(p)
    order = [k['id'] for k in kb['kps']]

    # ---------- 陆地形状 ----------
    land = [[None] * W for _ in range(H)]

    def blob(cx, cy, rx, ry, kind):
        for y in range(max(0, int(cy - ry - 2)), min(H, int(cy + ry + 3))):
            for x in range(max(0, int(cx - rx - 2)), min(W, int(cx + rx + 3))):
                if ((x - cx) / rx) ** 2 + ((y - cy) / ry) ** 2 <= 1:
                    land[y][x] = kind

    def around(points, kind, pad, jitter):
        for (x, y) in points[::2]:
            r = pad + rnd.uniform(-jitter, jitter)
            blob(x, y, r * 1.15, r, kind)

    def densify(road):
        out = []
        for i in range(len(road) - 1):
            a, b = road[i], road[i + 1]
            n = max(1, int(math.dist(a, b) / 3))
            out += [(a[0] + (b[0] - a[0]) * t / n, a[1] + (b[1] - a[1]) * t / n) for t in range(n)]
        return out + [road[-1]]

    dense_a, dense_b, dense_c = densify(road_a), densify(road_b), densify(road_c)
    around(dense_b, 'B', 26, 4)
    blob(190, 160, 160, 120, 'B')
    around(dense_c, 'C', 25, 4)
    blob(508, 150, 105, 102, 'C')
    around(dense_a, 'A', 22, 3)
    blob(95, 352, 80, 34, 'A')
    # 八年级、九年级：右下角雾里的两座岛
    blob(462, 336, 44, 30, 'D'); blob(470, 320, 30, 26, 'D')
    blob(570, 340, 48, 34, 'E'); blob(585, 322, 30, 24, 'E')
    # 区域之间留一条窄海峡（七上和七下之间、七下和雾岛之间）
    for y in range(H):
        for x in range(W):
            if land[y][x] == 'B' and x > 356 + 6 * math.sin(y / 23):
                land[y][x] = None
            if land[y][x] == 'C' and x < 380 + 6 * math.sin(y / 19):
                land[y][x] = None
            if land[y][x] == 'C' and y > 270:
                land[y][x] = None
            if land[y][x] == 'B' and y > 300 and x < 190:
                land[y][x] = 'A'
    # 海岸线加一点起伏
    for _ in range(2):
        nxt = [row[:] for row in land]
        for y in range(1, H - 1):
            for x in range(1, W - 1):
                nb = [land[y + dy][x + dx] for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))]
                if land[y][x] is None and sum(n is not None for n in nb) >= 3:
                    nxt[y][x] = next(n for n in nb if n)
                elif land[y][x] is not None and sum(n is None for n in nb) >= 3:
                    nxt[y][x] = None
        land = nxt

    def dist_to_sea(x, y, limit=4):
        for r in range(1, limit + 1):
            for dx in range(-r, r + 1):
                for dy in (-r, r):
                    xx, yy = x + dx, y + dy
                    if 0 <= xx < W and 0 <= yy < H and land[yy][xx] is None:
                        return r
                    xx, yy = x + dy, y + dx
                    if 0 <= xx < W and 0 <= yy < H and land[yy][xx] is None:
                        return r
        return limit + 1

    def dist_to_land(x, y, limit=4):
        for r in range(1, limit + 1):
            for dx in range(-r, r + 1):
                for dy in (-r, r):
                    for xx, yy in ((x + dx, y + dy), (x + dy, y + dx)):
                        if 0 <= xx < W and 0 <= yy < H and land[yy][xx] is not None:
                            return r
        return limit + 1

    # ---------- 上色 ----------
    c = Canvas(W, H)
    fills = {'A': ('meadow', 'meadow2'), 'B': ('grass', 'grass2'), 'C': ('desert', 'desert2'), 'D': ('fog', 'fog2'), 'E': ('fog', 'fog2')}
    for y in range(H):
        for x in range(W):
            k = land[y][x]
            if k is None:
                d = dist_to_land(x, y, 3)
                col = C['shallow'] if d <= 2 else C['sea']
                if d == 1:
                    col = C['foam'] if (x + y) % 5 == 0 else C['shallow']
                elif d > 3 and (x * 7 + y * 13) % 97 == 0:
                    col = C['sea2']
                c.set(x, y, col)
            else:
                base, alt = fills[k]
                s = dist_to_sea(x, y, 3)
                if s == 1:
                    c.set(x, y, C['outline'] if k not in 'DE' else C['fog2'])
                elif s <= 3 and k in 'ABC':
                    c.set(x, y, C['sand'] if s == 2 else (C['sand2'] if k != 'C' else C['desert2']))
                else:
                    c.set(x, y, C[alt] if rnd.random() < 0.08 else C[base])
    # 海浪
    for _ in range(140):
        x, y = rnd.randrange(4, W - 8), rnd.randrange(4, H - 4)
        if all(land[y][xx] is None for xx in range(x - 3, x + 7)) and dist_to_land(x, y, 5) > 4:
            for dx, dy in ((0, 1), (1, 0), (2, 0), (3, 1), (4, 1), (5, 0)):
                c.set(x + dx, y + dy, C['wave'])

    # ---------- 路 ----------
    road_mask = set()

    def draw_road(dense):
        for (x, y) in dense:
            for dx in range(-2, 3):
                for dy in range(-2, 3):
                    road_mask.add((int(x + dx), int(y + dy)))
        for (x, y) in dense:
            for dx in range(-2, 2):
                for dy in range(-2, 2):
                    xx, yy = int(x + dx), int(y + dy)
                    if land[yy][xx] is not None:
                        c.set(xx, yy, C['road2'])
        for (x, y) in dense:
            for dx in range(-1, 1):
                for dy in range(-1, 1):
                    xx, yy = int(x + dx), int(y + dy)
                    if land[yy][xx] is not None:
                        c.set(xx, yy, C['road'])

    link_ab = densify([(172, 296), (172, 290)])
    link_bc = densify([road_b[-1], (334, 64), (360, 52), (392, 54), road_c[0]])
    link_cd = densify([road_c[-1], (412, 252), (430, 288), (446, 306)])
    for d in (dense_a, link_ab, dense_b, link_bc, dense_c):
        draw_road(d)
    # 去雾岛的路：虚线，表示还没开放
    for i, (x, y) in enumerate(link_cd):
        if i % 4 < 2:
            c.rect(int(x) - 1, int(y) - 1, 2, 2, C['road2'])
    # 桥：路经过海面的地方
    for d in (link_bc,):
        for (x, y) in d:
            if land[int(y)][int(x)] is None:
                c.rect(int(x) - 3, int(y) - 2, 6, 4, C['bridge'])
                c.set(int(x) - 3, int(y) - 2, C['bridge2']); c.set(int(x) + 2, int(y) - 2, C['bridge2'])
                c.set(int(x) - 3, int(y) + 1, C['bridge2']); c.set(int(x) + 2, int(y) + 1, C['bridge2'])

    # ---------- 装饰：树、松树、仙人掌、石头、花、山 ----------
    occupied = set(road_mask)
    for (x, y) in pos.values():
        for dx in range(-10, 11):
            for dy in range(-12, 9):
                occupied.add((int(x + dx), int(y + dy)))

    def free(x, y, w, h, kind):
        for yy in range(y - 1, y + h + 1):
            for xx in range(x - 1, x + w + 1):
                if not (0 <= xx < W and 0 <= yy < H) or (xx, yy) in occupied or land[yy][xx] != kind or dist_to_sea(xx, yy, 3) <= 3:
                    return False
        return True

    def stamp(x, y, rows, pal):
        for j, row in enumerate(rows):
            for i, ch in enumerate(row):
                if ch != '.':
                    c.set(x + i, y + j, pal[ch])
        for yy in range(y - 1, y + len(rows) + 1):
            for xx in range(x - 1, x + len(rows[0]) + 1):
                occupied.add((xx, yy))

    tree = ['..ggg..', '.gGggg.', 'gGgggdg', 'gggggdg', '.gdgdd.', '..ddd..', '...t...', '...t...']
    pine = ['...p...', '..ppp..', '..pPp..', '.ppppp.', '.pPppP.', 'ppppppp', '...t...']
    cactus = ['..c..', '.cc.c', 'c.c.c', 'c.ccc', 'ccc..', '..c..', '..c..']
    rock = ['.rrr.', 'rRrrr', 'rrrRr', '.rRR.']
    mountain = ['.......s.......', '......sss......', '.....sssrr.....', '....rrrrrrr....', '...rrrRrrrRr...',
                '..rrrRrrrrrRr..', '.rrRrrrrRrrrRr.', 'rrrrrRrrrrrrRrr']
    pal = {'g': C['tree'], 'G': C['tree3'], 'd': C['tree2'], 't': C['trunk'], 'p': C['pine'], 'P': C['pine2'],
           'c': C['cactus'], 'r': C['rock'], 'R': C['rock2'], 's': C['snow']}
    plans = [('B', mountain, 4), ('C', mountain, 5), ('B', tree, 260), ('B', pine, 70), ('A', tree, 25),
             ('C', cactus, 70), ('C', rock, 40), ('B', rock, 25), ('A', rock, 8)]
    for kind, rows, n in plans:
        tries = 0
        placed = 0
        while placed < n and tries < n * 60:
            tries += 1
            x, y = rnd.randrange(0, W - len(rows[0])), rnd.randrange(0, H - len(rows))
            if free(x, y, len(rows[0]), len(rows), kind):
                stamp(x, y, rows, pal)
                placed += 1
    # 小花
    for _ in range(500):
        x, y = rnd.randrange(W), rnd.randrange(H)
        if land[y][x] in ('A', 'B') and (x, y) not in occupied and dist_to_sea(x, y, 3) > 3:
            c.set(x, y, C[rnd.choice(['flower1', 'flower2', 'flower3'])] if land[y][x] == 'A' or rnd.random() < 0.3 else C['grass3'])

    # ---------- 雾岛：云 ----------
    for cx, cy in [(450, 318), (478, 344), (440, 350), (560, 322), (590, 350), (600, 316), (548, 356)]:
        for k in range(5):
            r = rnd.uniform(7, 12)
            ox, oy = cx + rnd.uniform(-10, 10), cy + rnd.uniform(-6, 6)
            for y in range(int(oy - r), int(oy + r) + 1):
                for x in range(int(ox - r * 1.4), int(ox + r * 1.4) + 1):
                    if 0 <= x < W and 0 <= y < H and ((x - ox) / (r * 1.4)) ** 2 + ((y - oy) / r) ** 2 <= 1:
                        c.set(x, y, C['cloud2'] if ((x - ox) / (r * 1.4)) ** 2 + ((y - oy) / r) ** 2 > 0.72 and y > oy else C['cloud'])

    # 雾岛上的锁
    lock = ['..kkkkk..', '.k.....k.', '.k.....k.', 'kkkkkkkkk', 'kyyyyyyyk', 'kyyykyyyk', 'kyyykyyyk', 'kyyyyyyyk', 'kkkkkkkkk']
    for cx, cy in [(462, 330), (574, 334)]:
        stamp(cx - 4, cy - 4, lock, {'k': C['outline'], 'y': hexc('#ffd84a')})

    # ---------- 布局 ----------
    regions = [
        {'id': 'X', 'name': '小学衔接 · 出发草原', 'name_en': 'Primary Review · Starting Meadow', 'name_es': 'Repaso de Primaria · Pradera de salida', 'name_hant': '小學銜接 · 出發草原', 'x': 92, 'y': 392, 'locked': False},
        {'id': '7A', 'name': '七年级上 · 森林大陆', 'name_en': 'Grade 7 Term 1 · Forest Land', 'name_es': '1.º ESO, 1.ª parte · Tierra del Bosque', 'name_hant': '七年級上 · 森林大陸', 'x': 196, 'y': 22, 'locked': False},
        {'id': '7B', 'name': '七年级下 · 黄金沙漠', 'name_en': 'Grade 7 Term 2 · Golden Desert', 'name_es': '1.º ESO, 2.ª parte · Desierto Dorado', 'name_hant': '七年級下 · 黃金沙漠', 'x': 508, 'y': 26, 'locked': False},
        {'id': '8', 'name': '八年级 · 迷雾岛', 'name_en': 'Grade 8 · Misty Isle', 'name_es': '2.º ESO · Isla de la Niebla', 'name_hant': '八年級 · 迷霧島', 'x': 462, 'y': 378, 'locked': True},
        {'id': '9', 'name': '九年级 · 云端岛', 'name_en': 'Grade 9 · Cloud Isle', 'name_es': '3.º ESO · Isla de las Nubes', 'name_hant': '九年級 · 雲端島', 'x': 572, 'y': 386, 'locked': True},
    ]
    signs = []
    for m in modules:
        first = by_module[m['id']][0]
        x, y = pos[first]
        signs.append({'module': m['id'], 'name': m['name'], 'x': round(x, 1), 'y': round(y, 1)})
    layout = {
        'size': [W, H],
        'villages': {k: [round(pos[k][0], 1), round(pos[k][1], 1)] for k in order},
        'regions': regions,
        'signs': signs,
    }
    return c, layout


if __name__ == '__main__':
    import sys
    kb = json.load(open(sys.argv[1]))
    canvas, layout = build(kb)
    print(len(layout['villages']), 'villages')
