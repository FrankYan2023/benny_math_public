import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:nes_ui/nes_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../ai/ai_service.dart' show maxPhotos;
import '../i18n.dart';
import '../logic/hunt_controller.dart';
import '../theme/pixel_theme.dart';
import 'math_text.dart';
import 'turtles.dart';
import 'pixel_box.dart';

export 'pixel_box.dart';

/// 像素风按钮：主要操作用 primary，次要用 normal
class PxButton extends StatelessWidget {
  const PxButton(this.text, {super.key, this.onPressed, this.type = NesButtonType.primary, this.icon, this.big = false});

  final String text;
  final VoidCallback? onPressed;
  final NesButtonType type;
  final NesIconData? icon;
  final bool big;

  @override
  Widget build(BuildContext context) {
    final light = type == NesButtonType.primary || type == NesButtonType.error;
    final pad = big ? 14.0 : 8.0;
    final iconSize = big ? 26.0 : 20.0;
    return LayoutBuilder(builder: (context, box) {
      // 文字太长（西班牙语、手机屏幕）时换行，不撑出可用的宽度；
      // 外面没限制宽度（比如放在 Row 里）时按屏幕宽度估
      final room = box.maxWidth.isFinite ? box.maxWidth : MediaQuery.sizeOf(context).width - 60;
      final textMax = (room - pad * 2 - 24 - (icon == null ? 0 : iconSize + 10)).clamp(60.0, double.infinity);
      return Opacity(
        opacity: onPressed == null ? 0.45 : 1,
        child: NesButton(
          type: type,
          onPressed: onPressed,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: pad, vertical: big ? 8 : 2),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (icon != null) ...[NesIcon(iconData: icon!, size: Size.square(iconSize)), const SizedBox(width: 10)],
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: textMax),
                child: Text(text, textAlign: TextAlign.center, style: pixelText(big ? 20 : 16, color: light ? Colors.white : Px.ink)),
              ),
            ]),
          ),
        ),
      );
    });
  }
}

/// 像素风的确认框：放生怪兽、卖宝藏这类做了就不能撤回的事先问一句。点了 [ok] 返回 true
Future<bool> confirmBox(BuildContext context, {required Widget leading, required String title, required String body, required String ok, required String cancel}) async =>
    await showDialog<bool>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: PixelBox(
            padding: const EdgeInsets.all(18),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                leading,
                const SizedBox(width: 16),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(title, style: pixelText(20, weight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    Text(body, style: pixelText(16, color: Px.shadow)),
                  ]),
                ),
              ]),
              const SizedBox(height: 18),
              Wrap(alignment: WrapAlignment.end, spacing: 12, runSpacing: 10, children: [
                PxButton(cancel, type: NesButtonType.normal, onPressed: () => Navigator.of(ctx).pop(false)),
                PxButton(ok, type: NesButtonType.warning, onPressed: () => Navigator.of(ctx).pop(true)),
              ]),
            ]),
          ),
        ),
      ),
    ) ??
    false;

/// 对错标记：用 nes_ui 的像素图标（像素字体里没有 ✓ ✕ 这类符号）
enum Mark { ok, bad, warn, none }

const markColors = {Mark.ok: Px.okText, Mark.bad: Px.brick, Mark.warn: Px.amber, Mark.none: Px.shadow};

class MarkIcon extends StatelessWidget {
  const MarkIcon(this.mark, {super.key, this.size = 22});
  final Mark mark;
  final double size;

  @override
  Widget build(BuildContext context) => NesIcon(
        iconData: switch (mark) { Mark.ok => NesIcons.check, Mark.bad => NesIcons.close, Mark.warn => NesIcons.exclamationMarkBlock, Mark.none => NesIcons.remove },
        size: Size.square(size),
        primaryColor: markColors[mark],
      );
}

/// 一行判定结果：图标 + 文字（文字里可以有公式）
class Verdict extends StatelessWidget {
  const Verdict(this.mark, this.text, {super.key, this.size = 18});
  final Mark mark;
  final String text;
  final double size;

  @override
  Widget build(BuildContext context) => Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        MarkIcon(mark, size: size + 4),
        const SizedBox(width: 10),
        Expanded(child: MathText(text, style: pixelText(size, color: markColors[mark]!, weight: FontWeight.w700))),
      ]);
}

/// 面板：带标题的像素框
class Panel extends StatelessWidget {
  const Panel({super.key, this.title, required this.child, this.color});
  final String? title;
  final Widget child;
  final Color? color;

  @override
  Widget build(BuildContext context) => PixelBox(
        color: color ?? Px.panel,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: title == null
            ? child
            : Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
                Text(title!, style: pixelText(15, color: Px.shadow, weight: FontWeight.w700)),
                const SizedBox(height: 4),
                const _DottedLine(),
                const SizedBox(height: 10),
                child,
              ]),
      );
}

/// 面板标题下面的一排像素点
class _DottedLine extends StatelessWidget {
  const _DottedLine();

  @override
  Widget build(BuildContext context) => SizedBox(height: 2, child: CustomPaint(painter: _DotsPainter()));
}

class _DotsPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = Px.stone;
    for (var x = 0.0; x < size.width; x += 6) {
      canvas.drawRect(Rect.fromLTWH(x, 0, 2, 2), p);
    }
  }

  @override
  bool shouldRepaint(_DotsPainter old) => false;
}

/// 小加和小减说话：头像 + 打字机效果的气泡
class TurtlesSay extends StatelessWidget {
  const TurtlesSay(this.text, {super.key, this.mood = TurtleMood.idle, this.size = 72});
  final String text;
  final TurtleMood mood;
  final double size;

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Turtles(size: size, mood: mood),
          const SizedBox(width: 16),
          Expanded(
            child: PixelBox(
              padding: const EdgeInsets.all(14),
              child: NesRunningText(key: ValueKey(text), text: text, textStyle: pixelText(17)),
            ),
          ),
        ],
      );
}

/// 按顺序拍的几张照片：题目和解答写在同一张纸上，一张写不下就接着拍。
/// 照片只放在内存里，在 iPad 上压缩到 1600 像素以内再用。
class PhotoPages extends StatelessWidget {
  const PhotoPages({super.key, required this.photos, required this.title, required this.hint});

  final PhotoSet photos;
  final String title;
  final String hint;

  static const _size = (w: 150.0, h: 200.0);

  Future<List<Uint8List>> _pick(BuildContext context, {required bool camera, int limit = 1}) async {
    final picker = ImagePicker();
    try {
      final List<XFile> files;
      if (camera) {
        final f = await picker.pickImage(source: ImageSource.camera, maxWidth: 1600, maxHeight: 1600, imageQuality: 85);
        files = [?f];
      } else if (limit > 1) {
        files = await picker.pickMultiImage(maxWidth: 1600, maxHeight: 1600, imageQuality: 85, limit: limit);
      } else {
        final f = await picker.pickImage(source: ImageSource.gallery, maxWidth: 1600, maxHeight: 1600, imageQuality: 85);
        files = [?f];
      }
      return [for (final f in files) await f.readAsBytes()];
    } catch (e) {
      if (context.mounted) NesSnackbar.show(context, text: tr('打不開相機或相簿：$e', "Couldn't open the camera or photos: $e", 'No se pudo abrir la cámara ni las fotos: $e'), type: NesSnackbarType.error);
      return [];
    }
  }

  Future<void> _add(BuildContext context, {required bool camera}) async {
    final left = maxPhotos - photos.items.length;
    if (left <= 0) return;
    final list = await _pick(context, camera: camera, limit: left);
    if (list.isNotEmpty) photos.add(list);
  }

  Future<void> _retake(BuildContext context, int i) async {
    final list = await _pick(context, camera: true);
    if (list.isNotEmpty) photos.replace(i, list.first);
  }

  void _preview(BuildContext context, int i, Uint8List b) => showDialog<void>(
        context: context,
        builder: (ctx) => Dialog(
          backgroundColor: Px.paper,
          insetPadding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
              child: Row(children: [
                Expanded(child: Text(tr('第 ${i + 1} 張（兩指可以放大，看看字清不清楚）', 'Photo ${i + 1} (pinch to zoom and check it is clear)', 'Foto ${i + 1} (pellizca para ampliar y comprobar que se ve bien)'), style: pixelText(16))),
                PxButton(tr('關閉', 'Close', 'Cerrar'), type: NesButtonType.normal, onPressed: () => Navigator.of(ctx).pop()),
              ]),
            ),
            Flexible(child: InteractiveViewer(maxScale: 5, child: Image.memory(b, fit: BoxFit.contain))),
          ]),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final list = photos.items;
    final full = list.length >= maxPhotos;
    return Panel(
      title: title,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(hint, style: pixelText(14, color: Px.shadow)),
          const SizedBox(height: 12),
          Wrap(spacing: 14, runSpacing: 14, children: [
            for (final (i, b) in list.indexed)
              _PhotoPage(
                index: i,
                bytes: b,
                size: _size,
                onOpen: () => _preview(context, i, b),
                onRetake: () => _retake(context, i),
                onRemove: () => photos.remove(i),
                onMoveUp: i > 0 ? () => photos.moveUp(i) : null,
              ),
            if (!full)
              GestureDetector(
                onTap: () => _add(context, camera: true),
                child: PixelBox(
                  width: _size.w,
                  height: _size.h,
                  color: Px.paperDim,
                  dashed: true,
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    NesIcon(iconData: NesIcons.camera, size: const Size.square(36)),
                    const SizedBox(height: 10),
                    Text(list.isEmpty ? tr('點這裡拍照', 'Tap to snap', 'Toca para hacer la foto') : tr('接著拍\n第 ${list.length + 1} 張', 'Snap\nphoto ${list.length + 1}', 'Hacer\nfoto ${list.length + 1}'), textAlign: TextAlign.center, style: pixelText(15, color: Px.sky)),
                  ]),
                ),
              ),
          ]),
          const SizedBox(height: 12),
          Wrap(spacing: 10, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
            PxButton(list.isEmpty ? tr('拍照', 'Camera', 'Cámara') : tr('接著拍', 'Snap more', 'Más fotos'), type: NesButtonType.normal, icon: NesIcons.camera, onPressed: full ? null : () => _add(context, camera: true)),
            PxButton(tr('從相簿選', 'From photos', 'De la galería'), type: NesButtonType.normal, icon: NesIcons.gallery, onPressed: full ? null : () => _add(context, camera: false)),
            if (list.isNotEmpty) Text(tr('已拍 ${list.length} 張${full ? '，最多 $maxPhotos 張' : ''}', '${list.length} photo${list.length == 1 ? '' : 's'}${full ? ' (max $maxPhotos)' : ''}', '${list.length} foto${list.length == 1 ? '' : 's'}${full ? ' (máx. $maxPhotos)' : ''}'), style: pixelText(14, color: Px.shadow)),
          ]),
        ],
      ),
    );
  }
}

class _PhotoPage extends StatelessWidget {
  const _PhotoPage({
    required this.index,
    required this.bytes,
    required this.size,
    required this.onOpen,
    required this.onRetake,
    required this.onRemove,
    required this.onMoveUp,
  });

  final int index;
  final Uint8List bytes;
  final ({double w, double h}) size;
  final VoidCallback onOpen;
  final VoidCallback onRetake;
  final VoidCallback onRemove;
  final VoidCallback? onMoveUp;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: size.w,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          GestureDetector(
            onTap: onOpen,
            child: PixelBox(
              width: size.w,
              height: size.h,
              color: Colors.white,
              child: Stack(fit: StackFit.expand, children: [
                Image.memory(bytes, fit: BoxFit.cover),
                Positioned(
                  left: 0,
                  top: 0,
                  child: Container(
                    color: Px.ink,
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    child: Text('${index + 1}', style: pixelText(14, color: Colors.white)),
                  ),
                ),
              ]),
            ),
          ),
          const SizedBox(height: 6),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            _TinyButton(tr('前移', 'Up', 'Subir'), onMoveUp),
            _TinyButton(tr('重拍', 'Retake', 'Repetir'), onRetake),
            _TinyButton(tr('刪掉', 'Delete', 'Borrar'), onRemove, color: Px.brick),
          ]),
        ]),
      );
}

class _TinyButton extends StatelessWidget {
  const _TinyButton(this.text, this.onTap, {this.color = Px.sky});
  final String text;
  final VoidCallback? onTap;
  final Color color;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          child: Text(text, style: pixelText(14, color: onTap == null ? Px.stone : color)),
        ),
      );
}

/// 等 AI 的时候：小加和小减思考 + 已等秒数 + 取消
class BusyOverlay extends StatefulWidget {
  const BusyOverlay({super.key, required this.busy, required this.onCancel, required this.demo});
  final BusyState busy;
  final VoidCallback onCancel;
  final bool demo;

  @override
  State<BusyOverlay> createState() => _BusyOverlayState();
}

class _BusyOverlayState extends State<BusyOverlay> {
  Timer? _timer;
  static List<String> get _tips => [
        tr('小知識：減去一個數，等於加上它的相反數。', 'Tip: subtracting a number is the same as adding its opposite.', 'Truco: restar un número es lo mismo que sumar su opuesto.'),
        tr('小知識：數軸上，越往右的數越大。', 'Tip: on the number line, numbers get bigger to the right.', 'Truco: en la recta numérica, los números son mayores cuanto más a la derecha.'),
        tr('小知識：絕對值就是到原點的距離，所以不會是負數。', "Tip: absolute value is the distance from zero, so it's never negative.", 'Truco: el valor absoluto es la distancia al cero, así que nunca es negativo.'),
        tr('小加悄悄說：錯題是最好的老師。', 'Plus whispers: mistakes are the best teachers.', 'Más susurra: los errores son los mejores maestros.'),
      ];

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sec = DateTime.now().difference(widget.busy.startedAt).inSeconds;
    return ColoredBox(
      color: Px.ink.withValues(alpha: 0.55),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: PixelBox(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Turtles(size: 96, mood: TurtleMood.thinking),
              const SizedBox(height: 16),
              Text(widget.busy.label, textAlign: TextAlign.center, style: pixelText(20, weight: FontWeight.w700)),
              const SizedBox(height: 8),
              Text(tr('已等 $sec 秒${widget.demo ? '' : '，一般要 20 到 60 秒'}', 'Waited ${sec}s${widget.demo ? '' : ' — usually 20 to 60 seconds'}', 'Esperando $sec s${widget.demo ? '' : ' (suele tardar de 20 a 60 segundos)'}'), style: pixelText(15, color: Px.shadow)),
              const SizedBox(height: 12),
              Text(_tips[(sec ~/ 8) % _tips.length], textAlign: TextAlign.center, style: pixelText(14, color: Px.shadow)),
              const SizedBox(height: 16),
              PxButton(tr('取消', 'Cancel', 'Cancelar'), type: NesButtonType.normal, onPressed: widget.onCancel),
            ]),
          ),
        ),
      ),
    );
  }
}

/// 出错提示条
class ErrorBanner extends StatelessWidget {
  const ErrorBanner({super.key, required this.error, required this.onRetry, required this.onClose});
  final HuntError error;
  final VoidCallback? onRetry;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => Panel(
        color: Px.brickLight,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            const Turtles(size: 56, mood: TurtleMood.oops),
            const SizedBox(width: 12),
            Expanded(child: Text(error.message, style: pixelText(16))),
          ]),
          const SizedBox(height: 10),
          Wrap(alignment: WrapAlignment.end, spacing: 8, runSpacing: 8, children: [
            // 额度用完：OpenAI 要求把"管理用量"当成主要的按钮
            if (error.code == 'quota') const ManageUsageButton(primary: true),
            if (onRetry != null && error.code != 'quota') PxButton(tr('重試', 'Retry', 'Reintentar'), onPressed: onRetry),
            PxButton(tr('關閉', 'Close', 'Cerrar'), type: NesButtonType.normal, onPressed: onClose),
          ]),
        ]),
      );
}

/// ChatGPT 的用量设置页（OpenAI 的界面规范：用量相关的地方都要能点到这里）
const manageUsageUrl = 'https://chatgpt.com/settings/usage';

Future<void> openManageUsage() => launchUrl(Uri.parse(manageUsageUrl), mode: LaunchMode.externalApplication);

class ManageUsageButton extends StatelessWidget {
  const ManageUsageButton({super.key, this.primary = false});
  final bool primary;

  @override
  Widget build(BuildContext context) =>
      PxButton(tr('管理用量', 'Manage usage', 'Gestionar uso'), type: primary ? NesButtonType.primary : NesButtonType.normal, onPressed: openManageUsage);
}

/// "正在用你的 ChatGPT 方案"的小标记，旁边是"管理用量"链接（OpenAI 的界面规范）
class ChatGptPlanTag extends StatelessWidget {
  const ChatGptPlanTag({super.key});

  @override
  Widget build(BuildContext context) => Wrap(spacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
        Text(tr('正在使用 ChatGPT 方案', 'Using ChatGPT plan', 'Usando el plan de ChatGPT'), style: pixelText(13, color: Px.shadow)),
        GestureDetector(
          onTap: openManageUsage,
          child: Text(tr('管理用量', 'Manage usage', 'Gestionar uso'), style: pixelText(13, color: Px.sky).copyWith(decoration: TextDecoration.underline)),
        ),
      ]);
}

/// 左边是图（怪兽、乌龟、监狱…），右边是文字；手机上改成图在上、文字在下
class LeadRow extends StatelessWidget {
  const LeadRow({super.key, required this.lead, required this.child, this.gap = 16});
  final List<Widget> lead;
  final Widget child;
  final double gap;

  @override
  Widget build(BuildContext context) => isNarrow(context)
      ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: lead),
          const SizedBox(height: 10),
          child,
        ])
      : Row(children: [...lead, SizedBox(width: gap), Expanded(child: child)]);
}
