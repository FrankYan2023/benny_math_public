"""App 图标（1024×1024）：和 Benny Wallet 同一个风格——桃色背景上立体的、亮黄色的塑料小玩具，
不画脸，主题是数学。三个方案（DEFAULT 选用哪个）：
  blocks  四块胖乎乎的黄色积木：+ − × ÷（现在用的）
  ops     一枚黄色的圆币，上面是黑亮的 + − × ÷
  plus    一个胖乎乎的黄色大加号，中间一个像素风的 ÷
不是像素画：先算出每个点的高度，再按光照算明暗和高光，只用标准库。
小尺寸由 downscale 面积平均缩出来。"""
import math

from pixel import Canvas, hexc

N = 1024
DEFAULT = 'blocks'


def _hex(s):
    c = hexc(s)
    return (float(c[0]), float(c[1]), float(c[2]))


def _clamp(v, lo=0.0, hi=1.0):
    return lo if v < lo else hi if v > hi else v


def _smooth(a, b, x):
    """x 从 a 到 b 时，结果从 0 平滑到 1（a 可以大于 b）"""
    t = (x - a) / (b - a)
    t = 0.0 if t < 0.0 else 1.0 if t > 1.0 else t
    return t * t * (3.0 - 2.0 * t)


def _mix(a, b, t):
    return (a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t)


def _norm(x, y, z):
    k = 1.0 / math.sqrt(x * x + y * y + z * z)
    return (x * k, y * k, z * k)


def _ramp(stops, s):
    """按受光多少取颜色：stops 是 (受光, 颜色)，从暗到亮"""
    if s <= stops[0][0]:
        return stops[0][1]
    for i in range(1, len(stops)):
        if s <= stops[i][0]:
            a, b = stops[i - 1], stops[i]
            t = (s - a[0]) / (b[0] - a[0])
            return (a[1][0] + (b[1][0] - a[1][0]) * t, a[1][1] + (b[1][1] - a[1][1]) * t, a[1][2] + (b[1][2] - a[1][2]) * t)
    return stops[-1][1]


YELLOW = [(-0.35, _hex('#c2600c')), (0.05, _hex('#e27f16')), (0.38, _hex('#f5a023')), (0.58, _hex('#ffbd2e')),
          (0.72, _hex('#ffca3e')), (0.88, _hex('#ffdc6a')), (1.0, _hex('#ffeb9e'))]
LIGHT = _norm(-0.50, -0.66, 0.60)                      # 主光：左上方
HALF = _norm(LIGHT[0], LIGHT[1], LIGHT[2] + 1.0)       # 高光方向
BOUNCE = _norm(0.55, 0.62, 0.35)                       # 右下方反上来的暖光


def _seg_dist(x, y, a, b):
    vx, vy = b[0] - a[0], b[1] - a[1]
    t = ((x - a[0]) * vx + (y - a[1]) * vy) / (vx * vx + vy * vy)
    t = 0.0 if t < 0.0 else 1.0 if t > 1.0 else t
    return math.hypot(x - a[0] - vx * t, y - a[1] - vy * t)


def _rbox(px, py, hx, hy, r):
    qx, qy = abs(px) - (hx - r), abs(py) - (hy - r)
    return math.hypot(qx if qx > 0 else 0.0, qy if qy > 0 else 0.0) + min(max(qx, qy), 0.0) - r


def _plus(px, py, a, b, r, k):
    """加号：长 a、粗 b（都是一半）、外角的圆 r、里角的圆 k"""
    d1, d2 = _rbox(px, py, a, b, r), _rbox(px, py, b, a, r)
    h = k - abs(d1 - d2)
    return min(d1, d2) - (h * h * 0.25 / k if h > 0 else 0.0)


_S = math.sqrt(0.5)


def _shapes(variant, cx, cy):
    """黄色身体的距离函数（里面为负）、外框、圆边的半径、边框宽、凹槽深、影子（往下多少、散多宽）"""
    if variant == 'ops':
        r = 334.0
        return (lambda x, y: math.hypot(x - cx, y - cy) - r), (cx - r, cy - r, cx + r, cy + r), 52.0, 52.0, 9.0, (50.0, 84.0)
    if variant == 'plus':
        a = 330.0
        return (lambda x, y: _plus(x - cx, y - cy, a, 176.0, 84.0, 76.0)), (cx - a, cy - a, cx + a, cy + a), 58.0, 46.0, 7.0, (50.0, 84.0)
    o, a, b, r, k = 170.0, 134.0, 50.0, 49.0, 30.0   # blocks：四块积木

    def f(x, y):
        px, py = x - cx, y - cy
        qx, qy = px + o, py - o
        dx, dy = px - o, py - o
        return min(_plus(px + o, py + o, a, b, r, k), _rbox(px - o, py + o, a, b, r),
                   _plus((qx + qy) * _S, (qy - qx) * _S, a, b, r, k),
                   _rbox(dx, dy, a, b - 4, r - 4), math.hypot(dx, abs(dy) - 94.0) - 40.0)
    e = o + a + 12
    return f, (cx - e, cy - e, cx + e, cy + e), 40.0, None, 0.0, (26.0, 34.0)


def _strokes(cx, cy):
    """ops 方案里黑亮的 + − × ÷：一组线段和圆点"""
    o, a, d = 112.0, 64.0, 46.0
    segs, dots = [], []
    x, y = cx - o, cy - o
    segs += [((x - a, y), (x + a, y)), ((x, y - a), (x, y + a))]
    x, y = cx + o, cy - o
    segs += [((x - a, y), (x + a, y))]
    x, y = cx - o, cy + o
    segs += [((x - d, y - d), (x + d, y + d)), ((x - d, y + d), (x + d, y - d))]
    x, y = cx + o, cy + o
    segs += [((x - a, y), (x + a, y))]
    dots += [(x, y - 48.0), (x, y + 48.0)]
    return segs, dots


def render(variant=DEFAULT):
    n = N
    cx, cy = 512.0, 524.0
    R, G, B = [0.0] * (n * n), [0.0] * (n * n), [0.0] * (n * n)

    # ---------- 背景：桃色，上亮下暗一点 ----------
    top, bot = _hex('#fbdfc5'), _hex('#f3c5a0')
    for y in range(n):
        c = _mix(top, bot, y / (n - 1))
        R[y * n:(y + 1) * n] = [c[0]] * n
        G[y * n:(y + 1) * n] = [c[1]] * n
        B[y * n:(y + 1) * n] = [c[2]] * n

    lx, ly, lz = LIGHT
    hx_, hy_, hz_ = HALF
    b2x, b2y, b2z = BOUNCE
    warm = _hex('#ff9a2e')

    def tint(q, col, a):
        R[q] += (col[0] - R[q]) * a
        G[q] += (col[1] - G[q]) * a
        B[q] += (col[2] - B[q]) * a

    def darken(q, a):
        """暖色的阴影：红色留得多，蓝色去得多"""
        R[q] *= 1.0 - a * 0.50
        G[q] *= 1.0 - a * 0.68
        B[q] *= 1.0 - a * 0.82

    def yellow(nx, ny, nz, px, py):
        s = nx * lx + ny * ly + nz * lz - 0.10 * ((px - cx) * 0.45 + (py - cy) * 0.9) / 330.0
        c = _ramp(YELLOW, s)
        bn = nx * b2x + ny * b2y + nz * b2z
        if bn > 0 and s < 0.5:      # 背光的一面带一点暖色的反光，不会发灰
            c = _mix(c, warm, bn * (0.5 - s) * 0.55)
        hh = nx * hx_ + ny * hy_ + nz * hz_
        if hh > 0:
            spec = (hh ** 46) * 0.60 + (hh ** 9) * 0.10
            c = (c[0] + (255 - c[0]) * spec, c[1] + (255 - c[1]) * spec, c[2] + (255 - c[2]) * spec)
        return c

    ink, rimc = (26.0, 21.0, 21.0), _hex('#7a675c')

    def black(nx, ny, nz, px, py):
        s = nx * lx + ny * ly + nz * lz
        k = 0.62 + 0.55 * (s if s > 0 else 0.0)
        c = _mix((ink[0] * k, ink[1] * k, ink[2] * k), rimc, (1.0 - nz) ** 2 * 0.22)
        hh = nx * hx_ + ny * hy_ + nz * hz_
        if hh > 0:
            c = _mix(c, (255.0, 255.0, 255.0), (hh ** 34) * 0.80 + (hh ** 8) * 0.06)
        return c

    def relief(sdf, box, rf, shade, rim=None, gd=0.0, gw=20.0):
        """一块立体的东西：边是半径 rf 的圆角，（可选）离边 rim 处有一圈深 gd 的凹槽。按高度算法线再上色。
        返回"这个点在不在它里面"的函数。"""
        m = 3
        bx0, by0 = int(box[0]) - m, int(box[1]) - m
        bw, bh = int(box[2]) - int(box[0]) + 2 * m + 1, int(box[3]) - int(box[1]) + 2 * m + 1
        D, H = [9e9] * (bw * bh), [0.0] * (bw * bh)
        for j in range(bh):
            py, o = by0 + j + 0.5, j * bw
            for i in range(bw):
                d = sdf(bx0 + i + 0.5, py)
                D[o + i] = d
                if d < 0.0:
                    t = -d
                    h = math.sqrt(rf * rf - (rf - t) * (rf - t)) if t < rf else rf
                    if rim is not None and t > rim:
                        u = (t - rim) / gw
                        u = 1.0 if u > 1.0 else u
                        h -= gd * u * u * (3.0 - 2.0 * u)
                    H[o + i] = h
        for j in range(1, bh - 1):
            y = by0 + j
            if not 0 <= y < n:
                continue
            for i in range(1, bw - 1):
                k = j * bw + i
                d = D[k]
                x = bx0 + i
                if d >= 0.5 or not 0 <= x < n:
                    continue
                gx, gy = (H[k + 1] - H[k - 1]) * 0.5, (H[k + bw] - H[k - bw]) * 0.5
                inv = 1.0 / math.sqrt(gx * gx + gy * gy + 1.0)
                cov = 0.5 - d
                tint(y * n + x, shade(-gx * inv, -gy * inv, inv, x + 0.5, y + 0.5), 1.0 if cov > 1.0 else cov)

        def inside(px, py):
            i, j = int(px) - bx0, int(py) - by0
            return 0 <= i < bw and 0 <= j < bh and D[j * bw + i] < 0.0
        return inside

    body, box, rf, rim, gd, (sdy, spread) = _shapes(variant, cx, cy)
    x0, y0, x1, y1 = (int(v) for v in box)

    # ---------- 落在地上的影子 ----------
    sh = _hex('#cf8d64')
    for y in range(max(0, y0 - 20), min(n, y1 + int(sdy + spread) + 16)):
        py, row = y + 0.5 - sdy, y * n
        for x in range(max(0, x0 - 110), min(n, x1 + 110)):
            d = body(x + 0.5 - 4.0, py)
            if d < spread:
                tint(row + x, sh, 0.50 * _smooth(spread, -spread * 0.83, d))

    # ---------- 黄色的身体 ----------
    inside = relief(body, box, rf, yellow, rim, gd)

    if variant == 'ops':
        # ---------- 黑亮的 + − × ÷：先在币面上落影子，再画圆管 ----------
        segs, dots = _strokes(cx, cy)
        tr, dr = 19.0, 25.0

        def stroke(x, y):
            d = 9e9
            for a, b in segs:       # 交叉的地方圆滑地并在一起，不留折痕
                e = _seg_dist(x, y, a, b)
                h = 16.0 - abs(d - e)
                d = min(d, e) - (h * h / 64.0 if h > 0 else 0.0)
            d -= tr
            for dx, dy in dots:
                e = math.hypot(x - dx, y - dy) - dr
                if e < d:
                    d = e
            return d
        sb = (cx - 200, cy - 200, cx + 200, cy + 200)
        for y in range(int(sb[1]), int(sb[3]) + 30):
            for x in range(int(sb[0]), int(sb[2]) + 20):
                sd = stroke(x + 0.5 - 7.0, y + 0.5 - 15.0)
                if sd < 18.0 and inside(x, y):
                    darken(y * n + x, 0.38 * _smooth(18.0, -5.0, sd))
        relief(stroke, sb, tr, black)

    if variant == 'plus':
        # ---------- 中间一个像素风的 ÷ ----------
        mark = ['..#..', '.....', '#####', '.....', '..#..']
        cell, brown = 26.0, _hex('#7a3d0c')
        for gy in range(5):
            for gx in range(5):
                if mark[gy][gx] != '#':
                    continue
                ox, oy = int(cx + (gx - 2.5) * cell), int(cy + (gy - 2.5) * cell)
                for y in range(oy, oy + int(cell)):
                    for x in range(ox, ox + int(cell)):
                        tint(y * n + x, brown, 0.86)

    out = Canvas(n, n)
    for y in range(n):
        row, o = out.px[y], y * n
        for x in range(n):
            row[x] = (int(_clamp(R[o + x], 0, 255) + 0.5), int(_clamp(G[o + x], 0, 255) + 0.5), int(_clamp(B[o + x], 0, 255) + 0.5), 255)
    return out


def icon():
    return render(DEFAULT)


def downscale(src, size):
    """面积平均缩小（小尺寸图标不会糊成锯齿）"""
    out = Canvas(size, size)
    n = src.w
    f = n / size
    for y in range(size):
        y0, y1 = y * f, (y + 1) * f
        for x in range(size):
            x0, x1 = x * f, (x + 1) * f
            acc = [0.0, 0.0, 0.0]
            area = 0.0
            for sy in range(int(y0), min(n, int(y1 + 0.9999))):
                wy = min(y1, sy + 1) - max(y0, sy)
                for sx in range(int(x0), min(n, int(x1 + 0.9999))):
                    wx = min(x1, sx + 1) - max(x0, sx)
                    p = src.px[sy][sx]
                    w = wx * wy
                    for k in range(3):
                        acc[k] += p[k] * w
                    area += w
            out.px[y][x] = (round(acc[0] / area), round(acc[1] / area), round(acc[2] / area), 255)
    return out


if __name__ == '__main__':
    import sys
    render(sys.argv[2] if len(sys.argv) > 2 else DEFAULT).save(sys.argv[1] if len(sys.argv) > 1 else 'icon_preview.png', alpha=False)
