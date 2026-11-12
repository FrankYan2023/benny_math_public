"""像素画小工具：画布、基本图形、自动描边、写 PNG（只用标准库）。"""
import math
import struct
import zlib


def hexc(s):
    s = s.lstrip('#')
    return (int(s[0:2], 16), int(s[2:4], 16), int(s[4:6], 16), 255 if len(s) == 6 else int(s[6:8], 16))


class Canvas:
    def __init__(self, w, h):
        self.w, self.h = w, h
        self.px = [[None] * w for _ in range(h)]

    def get(self, x, y):
        return self.px[y][x] if 0 <= x < self.w and 0 <= y < self.h else None

    def set(self, x, y, c):
        x, y = int(x), int(y)
        if 0 <= x < self.w and 0 <= y < self.h:
            self.px[y][x] = c

    def rect(self, x, y, w, h, c):
        for yy in range(int(y), int(y + h)):
            for xx in range(int(x), int(x + w)):
                self.set(xx, yy, c)

    def ellipse(self, cx, cy, rx, ry, c, only=None):
        """实心椭圆（按像素中心判断）。only 给定时只覆盖这些颜色的像素。"""
        for y in range(int(cy - ry - 1), int(cy + ry + 2)):
            for x in range(int(cx - rx - 1), int(cx + rx + 2)):
                dx, dy = (x + 0.5 - cx) / rx, (y + 0.5 - cy) / ry
                if dx * dx + dy * dy <= 1.0 and (only is None or self.get(x, y) in only):
                    self.set(x, y, c)

    def line(self, x0, y0, x1, y1, c):
        x0, y0, x1, y1 = int(x0), int(y0), int(x1), int(y1)
        dx, dy = abs(x1 - x0), -abs(y1 - y0)
        sx, sy = (1 if x0 < x1 else -1), (1 if y0 < y1 else -1)
        err = dx + dy
        while True:
            self.set(x0, y0, c)
            if x0 == x1 and y0 == y1:
                break
            e2 = 2 * err
            if e2 >= dy:
                err += dy
                x0 += sx
            if e2 <= dx:
                err += dx
                y0 += sy

    def grid(self, x, y, rows, pal):
        """按字符画贴图：pal 把字符映射到颜色，'.' 和空格透明。"""
        for j, row in enumerate(rows):
            for i, ch in enumerate(row):
                if ch in '. ':
                    continue
                self.set(x + i, y + j, pal[ch])

    def outline(self, c, diagonal=False):
        """给所有不透明区域的外边描一圈"""
        add = []
        for y in range(self.h):
            for x in range(self.w):
                if self.px[y][x] is not None:
                    continue
                nb = [(1, 0), (-1, 0), (0, 1), (0, -1)]
                if diagonal:
                    nb += [(1, 1), (-1, -1), (1, -1), (-1, 1)]
                if any(self.get(x + dx, y + dy) not in (None, c) for dx, dy in nb):
                    add.append((x, y))
        for x, y in add:
            self.px[y][x] = c

    def replace_edge(self, target, new, side):
        """把 target 颜色区域靠某一边（'r' 右、'b' 下、'l' 左、't' 上）的那一层像素换成 new，做简单的明暗"""
        d = {'r': (1, 0), 'l': (-1, 0), 'b': (0, 1), 't': (0, -1)}[side]
        hits = []
        for y in range(self.h):
            for x in range(self.w):
                if self.px[y][x] == target and self.get(x + d[0], y + d[1]) != target:
                    hits.append((x, y))
        for x, y in hits:
            self.px[y][x] = new

    def blit(self, other, ox, oy):
        for y in range(other.h):
            for x in range(other.w):
                c = other.px[y][x]
                if c is not None:
                    self.set(ox + x, oy + y, c)

    def flipped(self):
        out = Canvas(self.w, self.h)
        for y in range(self.h):
            out.px[y] = list(reversed(self.px[y]))
        return out

    def copy(self):
        out = Canvas(self.w, self.h)
        out.px = [row[:] for row in self.px]
        return out

    def scaled(self, n):
        out = Canvas(self.w * n, self.h * n)
        for y in range(out.h):
            for x in range(out.w):
                out.px[y][x] = self.px[y // n][x // n]
        return out

    def save(self, path, scale=1, bg=None, alpha=True):
        """alpha=False 存成不带透明通道的 RGB（App Store 的图标不能有透明通道）"""
        c = self.scaled(scale) if scale > 1 else self
        raw = bytearray()
        for y in range(c.h):
            raw.append(0)
            for x in range(c.w):
                p = c.px[y][x]
                if p is None:
                    p = bg if bg is not None else (0, 0, 0, 0)
                raw.extend(p if alpha else p[:3])
        def chunk(tag, data):
            return struct.pack('>I', len(data)) + tag + data + struct.pack('>I', zlib.crc32(tag + data) & 0xffffffff)
        png = b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', c.w, c.h, 8, 6 if alpha else 2, 0, 0, 0))
        png += chunk(b'IDAT', zlib.compress(bytes(raw), 9)) + chunk(b'IEND', b'')
        with open(path, 'wb') as f:
            f.write(png)


def sheet(items, scale, cols, pad=2, bg='#c9d6df'):
    """把几张小图排成一张预览图"""
    cw = max(c.w for _, c in items) + pad * 2
    ch = max(c.h for _, c in items) + pad * 2
    rows = math.ceil(len(items) / cols)
    out = Canvas(cw * cols, ch * rows)
    out.rect(0, 0, out.w, out.h, hexc(bg))
    for i, (_, c) in enumerate(items):
        out.blit(c, (i % cols) * cw + pad, (i // cols) * ch + pad)
    return out.scaled(scale)
