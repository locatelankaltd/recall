import 'package:flutter/material.dart';
import 'recall_theme.dart';

/// Original folded-page mark, matching assets/brand/recall-mark.svg.
/// Interim original artwork; a separate Flora exploration was reviewed.
class RecallBrand extends StatelessWidget {
  const RecallBrand({super.key, this.size = 40, this.showWordmark = true});
  final double size;
  final bool showWordmark;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Recall',
    image: true,
    excludeSemantics: true,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox.square(
          dimension: size,
          child: const CustomPaint(painter: RecallMarkPainter()),
        ),
        if (showWordmark) ...[
          SizedBox(width: size * .24),
          Text(
            'Recall',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontSize: size * .7,
              letterSpacing: -size * .025,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ],
    ),
  );
}

class RecallMarkPainter extends CustomPainter {
  const RecallMarkPainter({this.background = true});
  final bool background;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 24, size.height / 24);
    if (background) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(0, 0, 24, 24),
          const Radius.circular(6),
        ),
        Paint()..color = RecallColors.petrol,
      );
    }
    final page = Path()
      ..moveTo(7, 20)
      ..lineTo(7, 7.5)
      ..quadraticBezierTo(7, 4, 10.5, 4)
      ..lineTo(14, 4)
      ..lineTo(18, 8)
      ..lineTo(18, 12)
      ..lineTo(14, 12)
      ..lineTo(14, 10)
      ..quadraticBezierTo(14, 9, 13, 9)
      ..lineTo(11, 9)
      ..lineTo(11, 20)
      ..close();
    // The open shoulder turns the folded page into a lowercase-r silhouette.
    canvas.drawPath(page, Paint()..color = RecallColors.paper);
    final fold = Path()
      ..moveTo(14, 4)
      ..lineTo(14, 8)
      ..lineTo(18, 8)
      ..close();
    canvas.drawPath(fold, Paint()..color = const Color(0xFFF1A88E));
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant RecallMarkPainter oldDelegate) =>
      background != oldDelegate.background;
}
