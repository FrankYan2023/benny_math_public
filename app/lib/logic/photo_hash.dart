import 'dart:typed_data';
import 'dart:ui' as ui;

/// 照片指纹：256 位的差值哈希（dHash）。
/// 同一张照片（比如从相册再选一次）指纹完全一样；同一页纸换个时间再拍，只要角度和取景差不多，指纹也很接近。
/// 用来认出"这道题以前拍过"，直接打开以前的分析，不再调用 GPT。
Future<String?> photoHash(Uint8List bytes) async {
  try {
    // 先缩到 68×64，再按 4×4 的格子求平均，得到 17×16 的灰度图（比直接缩到 17×16 更稳）
    const w = 17, h = 16, k = 4;
    final codec = await ui.instantiateImageCodec(bytes, targetWidth: w * k, targetHeight: h * k);
    final frame = await codec.getNextFrame();
    final data = await frame.image.toByteData(format: ui.ImageByteFormat.rawRgba);
    frame.image.dispose();
    codec.dispose();
    if (data == null) return null;
    final gray = List<double>.filled(w * h, 0);
    for (var y = 0; y < h * k; y++) {
      for (var x = 0; x < w * k; x++) {
        final i = (y * w * k + x) * 4;
        gray[(y ~/ k) * w + x ~/ k] += data.getUint8(i) * 0.299 + data.getUint8(i + 1) * 0.587 + data.getUint8(i + 2) * 0.114;
      }
    }
    final out = StringBuffer();
    for (var y = 0; y < h; y++) {
      var nibble = 0;
      for (var x = 0; x < w - 1; x++) {
        nibble = (nibble << 1) | (gray[y * w + x] > gray[y * w + x + 1] ? 1 : 0);
        if (x % 4 == 3) {
          out.write(nibble.toRadixString(16));
          nibble = 0;
        }
      }
    }
    return out.toString();
  } catch (_) {
    return null;
  }
}

/// 两个指纹有多少位不一样（0 = 一模一样）
int hashDistance(String a, String b) {
  if (a.length != b.length) return 1 << 20;
  var d = 0;
  for (var i = 0; i < a.length; i++) {
    var x = int.parse(a[i], radix: 16) ^ int.parse(b[i], radix: 16);
    while (x > 0) {
      d += x & 1;
      x >>= 1;
    }
  }
  return d;
}

/// 两组照片是不是同一道题：任意一对照片的指纹差不超过 12%（256 位里 30 位以内）
bool samePhotos(List<String> a, List<String> b) =>
    a.any((x) => b.any((y) => hashDistance(x, y) <= 30));
