import 'package:flutter/material.dart';

/// Original Recall vector family. SVG masters are in assets/icons.
/// A separate Flora exploration was reviewed; these remain original vectors.
enum RecallGlyph {
  today,
  projects,
  sources,
  add,
  paste,
  mic,
  file,
  image,
  search,
  back,
  close,
  compare,
  edit,
  person,
  language,
  calendar,
  send,
  check,
  clock,
  history,
  offline,
  export,
  settings,
  arrowRight,
  quote,
}

class RecallIcon extends StatelessWidget {
  const RecallIcon(
    this.glyph, {
    super.key,
    this.size = 24,
    this.color,
    this.semanticLabel,
  });
  final RecallGlyph glyph;
  final double size;
  final Color? color;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final direction = Directionality.of(context);
    final shouldMirror =
        direction == TextDirection.rtl &&
        (glyph == RecallGlyph.back || glyph == RecallGlyph.arrowRight);
    final visual = CustomPaint(
      size: Size.square(size),
      painter: _RecallIconPainter(
        glyph,
        color ??
            IconTheme.of(context).color ??
            Theme.of(context).colorScheme.onSurface,
        shouldMirror,
      ),
    );
    return Semantics(
      label: semanticLabel,
      excludeSemantics: true,
      child: SizedBox.square(dimension: size, child: visual),
    );
  }
}

const _definitions = <RecallGlyph, List<String>>{
  RecallGlyph.today: [
    'M5 5H19V19H5Z',
    'M9 3V7M15 3V7M5 10H19',
    'M9 14L11 16L15 12',
  ],
  RecallGlyph.projects: [
    'M3.5 7.5V18C3.5 19 4.5 20 5.5 20H18.5C19.6 20 20.5 19.1 20.5 18V8.5H12L10 5H5.5C4.4 5 3.5 6 3.5 7.5Z',
    'M3.5 10H20.5',
  ],
  RecallGlyph.sources: [
    'M6 3.5H14.5L19 8V20.5H6Z',
    'M14 3.5V8.5H19',
    'M9 12H16M9 16H14',
  ],
  RecallGlyph.add: ['M12 4V20M4 12H20'],
  RecallGlyph.paste: ['M8 5H5V21H19V5H16', 'M9 3H15V7H9Z', 'M8 11H16M8 15H14'],
  RecallGlyph.mic: [
    'M9 5C9 1 15 1 15 5V11C15 15 9 15 9 11Z',
    'M5.5 10.5V11C5.5 19 18.5 19 18.5 11V10.5M12 17V21M8 21H16',
  ],
  RecallGlyph.file: ['M5 3H14L19 8V21H5Z', 'M14 3V8H19'],
  RecallGlyph.image: [
    'M4 4H20V20H4Z',
    'M4 16L9 11L14 16L17 13L20 16',
    'M15.5 7C13.5 7 13.5 10 15.5 10C17.5 10 17.5 7 15.5 7Z',
  ],
  RecallGlyph.search: [
    'M10.5 3.5C1.2 3.5 1.2 17.5 10.5 17.5C19.8 17.5 19.8 3.5 10.5 3.5Z',
    'M16 16L21 21',
  ],
  RecallGlyph.back: ['M14.5 5L7.5 12L14.5 19'],
  RecallGlyph.close: ['M5 5L19 19M19 5L5 19'],
  RecallGlyph.compare: [
    'M3.5 4H9V20H3.5ZM15 4H20.5V20H15Z',
    'M9 8H15M12 6L15 8L12 10M15 16H9M12 14L9 16L12 18',
  ],
  RecallGlyph.edit: [
    'M4 16L14.5 5.5L18.5 9.5L8 20H4Z',
    'M13 7L17 11M16 4L17.5 2.5L21.5 6.5L20 8',
  ],
  RecallGlyph.person: [
    'M12 3.5C6.7 3.5 6.7 11.5 12 11.5C17.3 11.5 17.3 3.5 12 3.5Z',
    'M4.5 21V18.5C4.5 12.5 19.5 12.5 19.5 18.5V21',
  ],
  RecallGlyph.language: [
    'M3 5H14M8.5 3V5M5 8C6 12 9 15 13 17M12 5C11.5 11 8 15 3 17',
    'M14 21L18 11L22 21M15.5 18H20.5',
  ],
  RecallGlyph.calendar: [
    'M4 5H20V21H4Z',
    'M8 3V7M16 3V7M4 10H20M8 14H10M14 14H16M8 17H10',
  ],
  RecallGlyph.send: ['M3 4L21 12L3 20L6 12Z', 'M6 12H21'],
  RecallGlyph.check: ['M4 12L9 17L20 6'],
  RecallGlyph.clock: [
    'M12 3C0 3 0 21 12 21C24 21 24 3 12 3Z',
    'M12 7V12L15.5 14',
  ],
  RecallGlyph.history: [
    'M3.5 10C5.2 1.2 19.5 1 21 10.5C22.5 20 8.5 25 4 17',
    'M3 4V10H9M12 7V12L16 14',
  ],
  RecallGlyph.offline: [
    'M3 3L21 21M4 9C8 5.5 16 5.5 20 9M7 12C10 9.5 14 9.5 17 12M10 15C11.2 14 12.8 14 14 15',
    'M12 19H12.01',
  ],
  RecallGlyph.export: ['M4 13V21H20V13', 'M12 16V3M7 8L12 3L17 8'],
  RecallGlyph.settings: [
    'M9.5 3H14.5L15 6L17.5 7.5L20 6L22 10L19.5 12L20 15L22 16L19.5 20L17 18.5L14.5 20L14 22H10L9.5 19L7 17.5L4.5 19L2 15L4.5 13V10L2 8.5L4.5 4.5L7 6L9.5 5Z',
    'M12 8C6.7 8 6.7 16 12 16C17.3 16 17.3 8 12 8Z',
  ],
  RecallGlyph.arrowRight: ['M4 12H20M13 5L20 12L13 19'],
  RecallGlyph.quote: [
    'M4 7H10V13H7C7 16 6 17 4 18M14 7H20V13H17C17 16 16 17 14 18',
  ],
};

// A deliberately restricted parser for the original masters: M/L/H/V/C/Q/Z.
// All commands are absolute; these are not arbitrary third-party SVG files.
Path _readPath(String data) {
  final tokens = RegExp(
    r'[MLHVCQZ]|-?\d*\.?\d+',
  ).allMatches(data).map((m) => m.group(0)!).toList();
  final path = Path();
  var i = 0;
  var x = 0.0;
  var y = 0.0;
  double number() => double.parse(tokens[i++]);
  while (i < tokens.length) {
    final command = tokens[i++];
    switch (command) {
      case 'M':
        x = number();
        y = number();
        path.moveTo(x, y);
      case 'L':
        x = number();
        y = number();
        path.lineTo(x, y);
      case 'H':
        x = number();
        path.lineTo(x, y);
      case 'V':
        y = number();
        path.lineTo(x, y);
      case 'C':
        final x1 = number();
        final y1 = number();
        final x2 = number();
        final y2 = number();
        x = number();
        y = number();
        path.cubicTo(x1, y1, x2, y2, x, y);
      case 'Q':
        final x1 = number();
        final y1 = number();
        x = number();
        y = number();
        path.quadraticBezierTo(x1, y1, x, y);
      case 'Z':
        path.close();
      default:
        throw FormatException('Unsupported Recall icon command: $command');
    }
  }
  return path;
}

final _cachedPaths = <RecallGlyph, List<Path>>{};

class _RecallIconPainter extends CustomPainter {
  const _RecallIconPainter(this.glyph, this.color, this.mirrored);
  final RecallGlyph glyph;
  final Color color;
  final bool mirrored;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 24, size.height / 24);
    if (mirrored) {
      canvas.translate(24, 0);
      canvas.scale(-1, 1);
    }
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.7
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final paths = _cachedPaths.putIfAbsent(
      glyph,
      () => _definitions[glyph]!.map(_readPath).toList(),
    );
    for (final path in paths) {
      canvas.drawPath(path, paint);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _RecallIconPainter oldDelegate) =>
      glyph != oldDelegate.glyph ||
      color != oldDelegate.color ||
      mirrored != oldDelegate.mirrored;
}
