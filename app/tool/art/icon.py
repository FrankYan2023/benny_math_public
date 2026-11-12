"""App 图标（1024×1024）：和 Benny Wallet 同一个风格——桃色背景上一个立体的、亮黄色的 Benny：
戴着大圆眼镜、吐着舌头笑。两个方案（DEFAULT 选用哪个）：
  coin  和钱包一样的圆脸，两个镜片里是像素风的 + 和 ÷（现在用的）
  plus  身体是一个胖乎乎的加号
不是像素画：先算出每个点的高度，再按光照算明暗和高光（像一个塑料小玩具），只用标准库。
小尺寸由 downscale 面积平均缩出来。"""
import math

from pixel import Canvas, hexc

N = 1024
DEFAULT = 'coin'

# 每个方案的尺寸：身体、眼镜、嘴
SPEC = {
    'plus': dict(cy=528, fillet=58, rim=46, groove=7, eye_dy=-36, eye_dx=120, lens=98, tube=13.0,
                 mouth_dy=106, mouth_w=98, mouth_h=80, arm=352, tongue=(8, 70, 42, 50), blush=(206, 78)),
    'coin': dict(cy=528, fillet=52, rim=52, groove=9, eye_dy=-72, eye_dx=132, lens=104, tube=13.5,
                 mouth_dy=96, mouth_w=122, mouth_h=96, arm=358, tongue=(12, 88, 52, 60), blush=(196, 62)),
}


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
PINK = [(-0.3, _hex('#c2405a')), (0.25, _hex('#e3667a')), (0.6, _hex('#fb8b97')), (0.85, _hex('#ffaab2')), (1.0, _hex('#ffd0d4'))]
LIGHT = _norm(-0.50, -0.66, 0.60)                      # 主光：左上方
HALF = _norm(LIGHT[0], LIGHT[1], LIGHT[2] + 1.0)       # 高光方向
BOUNCE = _norm(0.55, 0.62, 0.35)                       # 右下方反上来的暖光


def _body(variant, cx, cy):
    """身体的距离函数（里面为负）和外框"""
    if variant == 'coin':
        r = 334.0
        return (lambda x, y: math.hypot(x - cx, y - cy) - r), (cx - r, cy - r, cx + r, cy + r)
    a, b, r, k = 330.0, 176.0, 84.0, 76.0   # 加号：长、粗、外角的圆、里角的圆

    def rbox(px, py, hx, hy):
        qx, qy = abs(px) - (hx - r), abs(py) - (hy - r)
        return math.hypot(qx if qx > 0 else 0.0, qy if qy > 0 else 0.0) + min(max(qx, qy), 0.0) - r

    def f(x, y):
        px, py = x - cx, y - cy
        d1, d2 = rbox(px, py, a, b), rbox(px, py, b, a)
        h = k - abs(d1 - d2)
        return min(d1, d2) - (h * h * 0.25 / k if h > 0 else 0.0)
    return f, (cx - a, cy - a, cx + a, cy + a)


def _bezier(p0, p1, p2, steps=10):
    return [((1 - t) ** 2 * p0[0] + 2 * (1 - t) * t * p1[0] + t * t * p2[0], (1 - t) ** 2 * p0[1] + 2 * (1 - t) * t * p1[1] + t * t * p2[1])
            for t in (i / steps for i in range(steps + 1))]


def _seg_dist(x, y, a, b):
    vx, vy = b[0] - a[0], b[1] - a[1]
    t = ((x - a[0]) * vx + (y - a[1]) * vy) / (vx * vx + vy * vy)
    t = 0.0 if t < 0.0 else 1.0 if t > 1.0 else t
    return math.hypot(x - a[0] - vx * t, y - a[1] - vy * t)


def render(variant=DEFAULT):
    n = N
    sp = SPEC[variant]
    cx, cy = 512.0, float(sp['cy'])
    R, G, B = [0.0] * (n * n), [0.0] * (n * n), [0.0] * (n * n)

    # ---------- 背景：桃色，上亮下暗一点 ----------
    top, bot = _hex('#fbdfc5'), _hex('#f3c5a0')
    for y in range(n):
        c = _mix(top, bot, y / (n - 1))
        R[y * n:(y + 1) * n] = [c[0]] * n
        G[y * n:(y + 1) * n] = [c[1]] * n
        B[y * n:(y + 1) * n] = [c[2]] * n

    body, box = _body(variant, cx, cy)
    x0, y0, x1, y1 = (int(v) for v in box)

    # ---------- 身体落在地上的影子 ----------
    sh = _hex('#cf8d64')
    for y in range(max(0, y0 - 20), min(n, y1 + 150)):
        py, row = y + 0.5 - 50.0, y * n
        for x in range(max(0, x0 - 110), min(n, x1 + 110)):
            d = body(x + 0.5 - 4.0, py)
            if d >= 84.0:
                continue
            a = 0.50 * _smooth(84.0, -70.0, d)
            i = row + x
            R[i] += (sh[0] - R[i]) * a
            G[i] += (sh[1] - G[i]) * a
            B[i] += (sh[2] - B[i]) * a

    # ---------- 身体：先算每个点的高度（圆润的边、一圈浅浅的凹槽），再按光照上色 ----------
    m = 3
    bx0, by0 = x0 - m, y0 - m
    bw, bh = x1 - x0 + 2 * m + 1, y1 - y0 + 2 * m + 1
    D, H = [9e9] * (bw * bh), [0.0] * (bw * bh)
    rf, rim, gd, gw = float(sp['fillet']), float(sp['rim']), float(sp['groove']), 20.0
    for j in range(bh):
        py, o = by0 + j + 0.5, j * bw
        for i in range(bw):
            d = body(bx0 + i + 0.5, py)
            D[o + i] = d
            if d < 0.0:
                t = -d
                h = math.sqrt(rf * rf - (rf - t) * (rf - t)) if t < rf else rf
                if t > rim:
                    u = (t - rim) / gw
                    u = 1.0 if u > 1.0 else u
                    h -= gd * u * u * (3.0 - 2.0 * u)
                H[o + i] = h

    def inside(px, py):
        i, j = int(px) - bx0, int(py) - by0
        return 0 <= i < bw and 0 <= j < bh and D[j * bw + i] < 0.0

    lx, ly, lz = LIGHT
    hx_, hy_, hz_ = HALF
    b2x, b2y, b2z = BOUNCE
    warm = _hex('#ff9a2e')
    for j in range(1, bh - 1):
        y = by0 + j
        if not 0 <= y < n:
            continue
        py = y + 0.5
        for i in range(1, bw - 1):
            k = j * bw + i
            d = D[k]
            if d >= 0.5:
                continue
            x = bx0 + i
            if not 0 <= x < n:
                continue
            px = x + 0.5
            gx, gy = (H[k + 1] - H[k - 1]) * 0.5, (H[k + bw] - H[k - bw]) * 0.5
            inv = 1.0 / math.sqrt(gx * gx + gy * gy + 1.0)
            nx, ny, nz = -gx * inv, -gy * inv, inv
            s = nx * lx + ny * ly + nz * lz - 0.10 * ((px - cx) * 0.45 + (py - cy) * 0.9) / 330.0
            c = _ramp(YELLOW, s)
            bn = nx * b2x + ny * b2y + nz * b2z
            if bn > 0 and s < 0.5:      # 背光的一面带一点暖色的反光，不会发灰
                c = _mix(c, warm, bn * (0.5 - s) * 0.55)
            hh = nx * hx_ + ny * hy_ + nz * hz_
            if hh > 0:
                spec = (hh ** 46) * 0.60 + (hh ** 9) * 0.10
                c = (c[0] + (255 - c[0]) * spec, c[1] + (255 - c[1]) * spec, c[2] + (255 - c[2]) * spec)
            cov = 0.5 - d
            cov = 1.0 if cov > 1.0 else cov
            q = y * n + x
            R[q] += (c[0] - R[q]) * cov
            G[q] += (c[1] - G[q]) * cov
            B[q] += (c[2] - B[q]) * cov

    def tint(q, col, a):
        R[q] += (col[0] - R[q]) * a
        G[q] += (col[1] - G[q]) * a
        B[q] += (col[2] - B[q]) * a

    def darken(q, a):
        """暖色的阴影：红色留得多，蓝色去得多"""
        R[q] *= 1.0 - a * 0.50
        G[q] *= 1.0 - a * 0.68
        B[q] *= 1.0 - a * 0.82

    # ---------- 脸蛋上的红晕 ----------
    bdx, bdy = sp['blush']
    blush = _hex('#ff6a4e')
    for bxc in (cx - bdx, cx + bdx):
        byc = cy + bdy
        for y in range(int(byc - 70), int(byc + 70)):
            for x in range(int(bxc - 100), int(bxc + 100)):
                e = math.hypot((x + 0.5 - bxc) / 62.0, (y + 0.5 - byc) / 36.0)
                if e < 1.6 and inside(x, y):
                    tint(y * n + x, blush, 0.40 * _smooth(1.6, 0.2, e))

    # ---------- 嘴：张开笑，舌头吐出来 ----------
    mcx, mcy = cx, cy + sp['mouth_dy']
    mw, mh = float(sp['mouth_w']), float(sp['mouth_h'])
    curve = 0.26 / mw      # 嘴的上沿两头往上翘

    def mouth(x, y):
        e = (math.hypot((x - mcx) / mw, (y - mcy) / mh) - 1.0) * min(mw, mh)
        return max(e, (mcy + 4.0 - curve * (x - mcx) ** 2) - y)
    tdx, tdy, ta, tb = sp['tongue']
    tcx, tcy = mcx + tdx, mcy + tdy

    def tongue(x, y):
        e = (math.hypot((x - tcx) / ta, (y - tcy) / tb) - 1.0) * min(ta, tb)
        return max(e, (mcy + mh * 0.30) - y)
    dark, red = _hex('#5e0d12'), _hex('#b3272e')
    for y in range(int(mcy - mh * 0.5), int(tcy + tb + 26)):
        py = y + 0.5
        for x in range(int(mcx - mw - 16), int(mcx + mw + 16)):
            px = x + 0.5
            q = y * n + x
            dm = mouth(px, py)
            dt = tongue(px, py)
            if dm >= 0.5 and inside(px, py):
                # 嘴边一圈、舌头下面的阴影
                if dm < 12.0:
                    darken(q, 0.20 * _smooth(12.0, 0.0, dm))
                ds = tongue(px - 5.0, py - 12.0)
                if 0 < dt and ds < 14.0:
                    darken(q, 0.34 * _smooth(14.0, -6.0, ds))
            if dm < 0.5:
                c = _mix(dark, red, _clamp((py - (mcy - 8.0)) / (mh * 0.95)))
                c = _mix(dark, c, 0.55 + 0.45 * _smooth(0.0, 22.0, -dm))   # 嘴唇的影子落在嘴里
                tint(q, c, min(1.0, 0.5 - dm))
            if dt < 0.5:
                u, v = (px - tcx) / ta, (py - tcy) / tb
                z = math.sqrt(max(0.0, 1.0 - u * u - v * v))
                nx, ny, nz = _norm(u * 0.9, v * 0.9, z + 0.35)
                s = nx * lx + ny * ly + nz * lz
                c = _ramp(PINK, s)
                groove = abs(px - tcx) / 3.2
                if groove < 1.0 and -0.2 < v < 0.55:
                    c = _mix(c, _hex('#c9485c'), 0.55 * (1.0 - groove) * _smooth(-0.2, 0.0, v) * _smooth(0.55, 0.3, v))
                hh = nx * hx_ + ny * hy_ + nz * hz_
                if hh > 0:
                    c = _mix(c, (255.0, 255.0, 255.0), (hh ** 30) * 0.75)
                tint(q, c, min(1.0, 0.5 - dt))

    # ---------- 眼镜 ----------
    ey, edx, rl, rt = cy + sp['eye_dy'], float(sp['eye_dx']), float(sp['lens']), float(sp['tube'])
    eyes = [(cx - edx, ey), (cx + edx, ey)]
    arm_end = float(sp['arm'])
    bridge = _bezier((eyes[0][0] + rl - 3, ey - 10), (cx, ey - 30), (eyes[1][0] - rl + 3, ey - 10))
    arms = [[(cx + sgn * (edx + rl - 3), ey - 12), (cx + sgn * arm_end, ey - 4), (cx + sgn * (arm_end + 7), ey + 12), (cx + sgn * (arm_end + 3), ey + 40)]
            for sgn in (-1, 1)]
    rt_thin = rt * 0.82

    def frame(x, y):
        """到最近一段镜框中心线的距离，和这一段的粗细（半径）"""
        best, rad = abs(math.hypot(x - eyes[0][0], y - ey) - rl), rt
        d2 = abs(math.hypot(x - eyes[1][0], y - ey) - rl)
        if d2 < best:
            best = d2
        if abs(x - cx) < edx - rl + 24:
            for i in range(len(bridge) - 1):
                dd = _seg_dist(x, y, bridge[i], bridge[i + 1])
                if dd - rt_thin < best - rad:
                    best, rad = dd, rt_thin
        if abs(x - cx) > edx + rl - 30:
            for pts in arms:
                for i in range(len(pts) - 1):
                    dd = _seg_dist(x, y, pts[i], pts[i + 1])
                    if dd - rt_thin < best - rad:
                        best, rad = dd, rt_thin
        return best, rad

    gx0, gx1 = int(cx - arm_end - 30), int(cx + arm_end + 30)
    gy0, gy1 = int(ey - rl - rt - 6), int(ey + rl + rt + 30)

    # 镜框落在脸上的影子
    for y in range(gy0, gy1 + 24):
        py = y + 0.5
        for x in range(gx0, gx1):
            px = x + 0.5
            if not inside(px, py):
                continue
            dc, rad = frame(px - 6.0, py - 13.0)
            sd = dc - rad
            if sd < 16.0:
                darken(y * n + x, 0.30 * _smooth(16.0, -4.0, sd))

    # 镜片：一点点亮、（coin 方案）像素风的 + 和 ÷、弯弯的反光
    ri = rl - rt + 1.0
    glass = _hex('#fff4c8')
    marks = None
    if variant == 'coin':
        marks = [['..#..', '..#..', '#####', '..#..', '..#..'], ['..#..', '.....', '#####', '.....', '..#..']]
    brown = _hex('#7a3d0c')
    for e, (ex, _) in enumerate(eyes):
        for y in range(int(ey - ri - 1), int(ey + ri + 2)):
            py = y + 0.5
            for x in range(int(ex - ri - 1), int(ex + ri + 2)):
                px = x + 0.5
                dist = math.hypot(px - ex, py - ey)
                if dist >= ri + 0.5:
                    continue
                q = y * n + x
                cov = min(1.0, ri + 0.5 - dist)
                tint(q, glass, 0.16 * cov)
                if marks:
                    cell = 17.0
                    gx, gy = (px - (ex - 2.5 * cell + 3.0)) / cell, (py - (ey - 2.5 * cell + 6.0)) / cell
                    if 0 <= gx < 5 and 0 <= gy < 5 and marks[e][int(gy)][int(gx)] == '#':
                        tint(q, brown, 0.88)
                # 左上角一道弯弯的反光，右下角一道小的
                a1 = _clamp(0.5 - (dist - (ri - 13.0)) / 7.0) * _clamp(0.5 + (math.hypot(px - ex - 30.0, py - ey - 34.0) - (ri - 4.0)) / 9.0)
                a1 *= _smooth(0.30, 0.62, (-(px - ex) * 0.72 - (py - ey) * 0.69) / ri)
                a2 = _clamp(0.5 - (dist - (ri - 15.0)) / 6.0) * _clamp(0.5 + (math.hypot(px - ex + 20.0, py - ey + 22.0) - (ri - 8.0)) / 7.0)
                a2 *= _smooth(0.55, 0.80, ((px - ex) * 0.72 + (py - ey) * 0.69) / ri)
                a = a1 * 0.72 + a2 * 0.40
                if a > 0.003:
                    tint(q, (255.0, 255.0, 255.0), a * cov)

    # 镜框：黑亮的圆管，左上有高光
    ink, rimc = (26.0, 21.0, 21.0), _hex('#7a675c')
    for y in range(gy0, gy1 + 20):
        py = y + 0.5
        for x in range(max(0, gx0), min(n, gx1)):
            px = x + 0.5
            dc, rad = frame(px, py)
            sd = dc - rad
            if sd >= 0.5:
                continue
            ddx = (frame(px + 0.7, py)[0] - frame(px - 0.7, py)[0]) / 1.4
            ddy = (frame(px, py + 0.7)[0] - frame(px, py - 0.7)[0]) / 1.4
            t = dc / rad
            t = 1.0 if t > 1.0 else t
            g = math.hypot(ddx, ddy)
            joint = g < 0.8 or g > 1.2      # 两段镜框接在一起的地方方向算不准，不加高光
            if g > 1.0:
                ddx, ddy = ddx / g, ddy / g
            nx, ny, nz = ddx * t, ddy * t, math.sqrt(max(0.0, 1.0 - t * t))
            s = nx * lx + ny * ly + nz * lz
            k = 0.62 + 0.55 * (s if s > 0 else 0.0)
            c = (ink[0] * k, ink[1] * k, ink[2] * k)
            c = _mix(c, rimc, (1.0 - nz) ** 2 * 0.22)
            hh = nx * hx_ + ny * hy_ + nz * hz_
            if hh > 0 and not joint:
                c = _mix(c, (255.0, 255.0, 255.0), (hh ** 34) * 0.80)
            tint(y * n + x, c, min(1.0, 0.5 - sd))

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
