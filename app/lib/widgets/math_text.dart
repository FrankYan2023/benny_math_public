import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';

/// 显示夹着 $...$ 公式的文字：文字用像素字体，公式用 LaTeX 正常排版（公式不用像素字体，保证看得清）。
class MathText extends StatelessWidget {
  const MathText(this.text, {super.key, this.style, this.textAlign = TextAlign.start});

  final String text;
  final TextStyle? style;
  final TextAlign textAlign;

  static final _pattern = RegExp(r'\$\$([^$]+)\$\$|\$([^$]+)\$');

  @override
  Widget build(BuildContext context) {
    final base = style ?? DefaultTextStyle.of(context).style;
    final spans = <InlineSpan>[];
    var last = 0;
    for (final m in _pattern.allMatches(text)) {
      if (m.start > last) spans.add(TextSpan(text: text.substring(last, m.start)));
      final tex = m.group(1) ?? m.group(2)!;
      spans.add(WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: Math.tex(
          tex,
          mathStyle: m.group(1) != null ? MathStyle.display : MathStyle.text,
          textStyle: TextStyle(fontSize: (base.fontSize ?? 16) * 1.05, color: base.color),
          onErrorFallback: (_) => Text(tex, style: base),
        ),
      ));
      last = m.end;
    }
    if (last < text.length) spans.add(TextSpan(text: text.substring(last)));
    return Text.rich(TextSpan(style: base, children: spans), textAlign: textAlign);
  }
}
