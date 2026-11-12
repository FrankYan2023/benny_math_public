"""Benny：胖胖的中国男孩，板刷头（深棕色短发），黑色方框眼镜，黑色连帽衫带青色亮边，笑眯眯。"""
from pixel import Canvas, hexc

P = {k: hexc(v) for k, v in {
    'K': '#1b1626',  # 描边
    'H': '#1c1410', 'h': '#2e2119', 'j': '#4b3628',  # 头发：深、中、高光（深棕，接近黑）
    'S': '#f6c7a0', 's': '#e2a079', 'L': '#ffe1c7', 'b': '#f28b7d',  # 皮肤、阴影、高光、腮红
    'G': '#101016', 'W': '#e6f2ff', 'w': '#ffffff', 'E': '#2a2236',  # 眼镜框、镜片、反光、眼睛
    'M': '#7a2e35', 'T': '#ffffff',  # 嘴、牙
    'D': '#191a22', 'd': '#2b2d3b', 'f': '#3f4357',  # 连帽衫：暗、中、亮
    'C': '#3fe6f5', 'c': '#1ba5c2',  # 青色亮边
    'P': '#3a4a70', 'p': '#28324d',  # 裤子
    'O': '#f4f4f6', 'o': '#b6bacb',  # 鞋
}.items()}


def big(mood='happy', blink=False):
    """大图 32×36：首页、胜利页"""
    c = Canvas(32, 36)
    # 身体（先画，头会盖住上面一部分）
    c.ellipse(16, 27.5, 9.5, 5.5, P['d'])
    c.rect(8, 23, 16, 6, P['d'])
    c.rect(5, 23, 4, 6, P['d'])     # 左臂
    c.rect(23, 23, 4, 6, P['d'])    # 右臂
    c.ellipse(6.5, 29.5, 2, 1.8, P['S'])   # 手
    c.ellipse(25.5, 29.5, 2, 1.8, P['S'])
    c.rect(10, 31, 5, 2, P['P'])    # 腿
    c.rect(17, 31, 5, 2, P['P'])
    c.rect(9, 33, 6, 2, P['O'])     # 鞋
    c.rect(17, 33, 6, 2, P['O'])
    # 连帽衫细节：帽子边沿的青色亮边（从肩膀绕到下巴下面）、拉链、抽绳、口袋
    for x, y in [(8, 23), (9, 23), (10, 23), (11, 24), (12, 24), (21, 23), (22, 23), (23, 23), (20, 24), (19, 24)]:
        c.set(x, y, P['C'])
    for y in range(24, 31):
        c.set(16, y, P['c'])
    c.set(16, 24, P['C'])
    c.rect(13, 25, 1, 2, P['C']); c.rect(19, 25, 1, 2, P['C'])
    c.set(13, 27, P['O']); c.set(19, 27, P['O'])   # 抽绳的头
    c.rect(11, 28, 11, 2, P['D'])
    for x in (11, 12, 13, 14, 18, 19, 20, 21):
        c.set(x, 28, P['c'])
    c.replace_edge(P['d'], P['f'], 'l')
    c.replace_edge(P['d'], P['D'], 'r')
    c.replace_edge(P['P'], P['p'], 'r')
    c.replace_edge(P['O'], P['o'], 'b')

    # 头：圆脸 + 鼓鼓的腮帮子
    c.ellipse(16, 13, 10.6, 9.2, P['S'])
    c.ellipse(16, 15.8, 11.2, 6.4, P['S'])
    c.ellipse(4.8, 14.5, 1.6, 2.2, P['S'])   # 耳朵
    c.ellipse(27.2, 14.5, 1.6, 2.2, P['S'])
    c.set(5, 14, P['s']); c.set(27, 14, P['s'])
    # 板刷头：平顶、短短的刺
    for y in range(2, 12):
        for x in range(4, 29):
            if c.get(x, y) != P['S'] and not (y >= 3 and 6 <= x <= 25):
                continue
            # 发际线：前面的刘海略微往左斜，两边鬓角往下
            if x <= 6 or x >= 25:
                limit = 11
            elif x <= 13:
                limit = 7
            elif x <= 19:
                limit = 6
            else:
                limit = 6
            if y <= limit:
                c.set(x, y, P['h'])
    # 平顶上的刺：最上面一排隔一个点一根
    for x in range(7, 25):
        c.set(x, 2, P['h'] if x % 2 == 0 else None)
        c.set(x, 3, P['h'])
    c.set(6, 3, P['h']); c.set(25, 3, P['h'])
    for x in range(5, 27):
        if c.get(x, 4) is None:
            c.set(x, 4, P['h'])
    # 头发明暗
    for x in range(9, 15):
        c.set(x, 4, P['j'])
    for x in range(8, 12):
        c.set(x, 5, P['j'])
    for x in (8, 10, 12, 14, 16, 18, 20, 22):
        c.set(x, 3, P['j'] if x < 15 else P['h'])
    for y in range(5, 12):
        for x in range(4, 29):
            if c.get(x, y) == P['h'] and (c.get(x, y + 1) == P['S']):
                c.set(x, y, P['H'])   # 发际线那一层深一点
    # 刘海的几缕
    c.set(10, 8, P['h']); c.set(11, 8, P['H']); c.set(16, 7, P['H']); c.set(22, 7, P['H'])

    # 脸的明暗：右下阴影、左上高光
    c.replace_edge(P['S'], P['s'], 'r')
    c.replace_edge(P['S'], P['s'], 'b')
    for x, y in [(8, 10), (9, 10), (7, 11)]:
        if c.get(x, y) == P['S']:
            c.set(x, y, P['L'])

    # 眼镜：两个黑色方框 + 鼻梁
    for (x0, x1) in [(7, 14), (18, 25)]:
        for x in range(x0, x1 + 1):
            c.set(x, 10, P['G']); c.set(x, 15, P['G'])
        for y in range(10, 16):
            c.set(x0, y, P['G']); c.set(x1, y, P['G'])
        c.rect(x0 + 1, 11, x1 - x0 - 1, 4, P['W'])
        c.set(x0 + 1, 11, P['w']); c.set(x0 + 2, 11, P['w']); c.set(x0 + 1, 12, P['w'])
    c.rect(15, 11, 3, 1, P['G'])
    c.set(6, 11, P['G']); c.set(26, 11, P['G'])   # 镜腿
    # 眼睛：笑眯眯的弯眼（^ ^），眨眼时一条线
    for ex in (10, 21):
        if blink or mood == 'happy':
            c.set(ex - 1, 13, P['E']); c.set(ex, 12, P['E']); c.set(ex + 1, 12, P['E']); c.set(ex + 2, 13, P['E'])
        else:
            c.rect(ex, 12, 2, 2, P['E']); c.set(ex, 12, P['w'])
    # 腮红、鼻子、嘴（咧嘴笑）
    for x in (7, 8, 23, 24):
        c.set(x, 17, P['b'])
    c.set(16, 16, P['s'])
    c.set(13, 18, P['M']); c.set(19, 18, P['M'])
    c.rect(14, 18, 5, 1, P['T'])
    c.rect(14, 19, 5, 1, P['M'])
    c.set(15, 20, P['M']); c.set(16, 20, P['M']); c.set(17, 20, P['M'])
    c.outline(P['K'])
    return c


def small(frame=0):
    """地图上的小 Benny 16×20，两帧走路"""
    rows = [
        '...K.K.K.K.K....',
        '..KhKhKhKhKhK...',
        '.KhjjjhhhhhhhK..',
        'KHhjhhhhhhhhhHK.',
        'KHHHHHHHHHHHHHK.',
        'KSGGGGSSSGGGGSK.',
        'KGWWWGGGGGWWWGK.',
        'KSGWEGSSSGWEGSK.',
        'KSGGGGSsSGGGGSK.',
        'KbSSSSSSSSSSSbK.',
        '.KsSSSMTTMSSsK..',
        '..KssSSMMSSsK...',
        '.KdCCdddddCCdK..',
        'KfdddCdcdCdddDK.',
        'KSfddddcdddDdSK.',
        '.KfddcccccdDDK..',
        '..KPPPKKKPPPK...',
        '..KPPpK.KPPpK...',
        '.KOOOoK.KOOOoK..',
        '..KKKK...KKKK...',
    ]
    pal = dict(P)
    c = Canvas(16, 20)
    c.grid(0, 0, rows, pal)
    if frame == 1:   # 第二帧：身子往下一点，腿换步
        moved = Canvas(16, 20)
        for y in range(15, -1, -1):
            for x in range(16):
                moved.set(x, y + 1, c.get(x, y))
        legs = [
            '..KPPPKKKPPPK...',
            '..KPPpKKPPpK....',
            '.KOOOoKKOOOoK...',
            '..KKKK..KKKK....',
        ]
        for j in range(4):
            for x in range(16):
                moved.set(x, 16 + j, None)
        moved.grid(0, 16, legs, pal)
        c = moved
    return c
