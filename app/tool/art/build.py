"""生成 App 用到的全部像素画：python3 tool/art/build.py（在 app/ 目录下运行）。
只用 Python 标准库。输出：
  assets/art/*.png         人物（Benny、两只小乌龟）、怪兽、村庄、地图底图（原始像素尺寸，App 里用 FilterQuality.none 放大）
  assets/art/worldmap.json 地图布局：每个知识点村庄的坐标、区域名和模块牌子的位置
  ios/.../AppIcon.appiconset/*.png  App 图标
"""
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
APP = os.path.abspath(os.path.join(HERE, '..', '..'))

from benny import big, small  # noqa: E402
from icon import downscale, icon  # noqa: E402
from monsters import MONSTERS  # noqa: E402
from turtles import MOODS, turtles  # noqa: E402
from villages import VILLAGES  # noqa: E402
from worldmap import build as build_map  # noqa: E402


def main():
    out = os.path.join(APP, 'assets', 'art')
    os.makedirs(out, exist_ok=True)
    big(mood='idle').save(f'{out}/benny_idle.png')
    big(mood='happy').save(f'{out}/benny_happy.png')
    big(mood='idle', blink=True).save(f'{out}/benny_blink.png')
    for f in (0, 1):
        small(f).save(f'{out}/benny_walk_{f}.png')
    for m in MOODS:
        turtles(m).save(f'{out}/pet_{m}.png')
    turtles('idle', blink=True).save(f'{out}/pet_blink.png')
    for name, fn in MONSTERS.items():
        fn().save(f'{out}/monster_{name}.png')
    for name, fn in VILLAGES.items():
        fn().save(f'{out}/village_{name}.png')

    kb = json.load(open(os.path.join(APP, '..', 'shared', 'knowledge.json')))
    canvas, layout = build_map(kb)
    canvas.save(f'{out}/worldmap.png')
    with open(f'{out}/worldmap.json', 'w') as fp:
        json.dump(layout, fp, ensure_ascii=False, separators=(',', ':'))

    # 图标：iOS 图标不能有透明
    big_icon = icon()   # 1024×1024，其他尺寸按面积平均缩出来
    appicon = os.path.join(APP, 'ios', 'Runner', 'Assets.xcassets', 'AppIcon.appiconset')
    contents = json.load(open(os.path.join(appicon, 'Contents.json')))
    done = {}
    for img in contents['images']:
        px = round(float(img['size'].split('x')[0]) * int(img['scale'][0]))
        name = img['filename']
        if name in done:
            continue
        (big_icon if big_icon.w == px else downscale(big_icon, px)).save(os.path.join(appicon, name), alpha=False)
        done[name] = px
    print(f'已生成：{len(os.listdir(out))} 个素材，{len(done)} 个 iOS 图标，地图 {len(layout["villages"])} 个村庄')


if __name__ == '__main__':
    main()
