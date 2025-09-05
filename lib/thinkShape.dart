import 'package:flutter/material.dart';
import 'dart:math';

// 定義形狀的列舉
enum ShapeType {
  circleGrid,
  rectangle,
  star,
  flower, // 新增花朵形狀
}

// 定義動畫狀態的列舉
enum AnimationState {
  continuousRotation, // 不停旋轉
  rotate45andPause, // 轉45度 0.6秒 停0.4秒
}

// This component encapsulates the rotating CustomPaint.
class AnimatedShapeWidget extends StatefulWidget {
  final ShapeType shapeType; // Property to select the shape
  final AnimationState animationState; // New property to select animation state
  final double scale; // 新增的參數：控制縮放比例

  const AnimatedShapeWidget({
    super.key,
    required this.shapeType,
    required this.animationState,
    this.scale = 1.0, // 預設縮放值為 1.0
  });

  @override
  State<AnimatedShapeWidget> createState() => _AnimatedShapeWidgetState();
}

class _AnimatedShapeWidgetState extends State<AnimatedShapeWidget> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _currentRotationAnimation;
  double _currentAngle = 0; // 新增：追蹤當前旋轉角度

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this);
    _setupAnimation();
  }

  // Helper method to set up the animation based on the selected state
  void _setupAnimation() {
    _controller.stop();
    _controller.reset();

    switch (widget.animationState) {
      case AnimationState.continuousRotation:
        _currentAngle = 0; // 重置角度
        _controller.duration = const Duration(seconds: 5);
        _currentRotationAnimation = Tween<double>(begin: 0, end: 2 * pi).animate(_controller);
        _controller.repeat();
        break;
      case AnimationState.rotate45andPause:
        _controller.duration = const Duration(milliseconds: 3000); // 0.6秒旋轉
        // 每次都建立新的 Tween 和 CurvedAnimation，確保 begin 值是當前的 _currentAngle
        _currentRotationAnimation = Tween<double>(
          begin: _currentAngle,
          end: _currentAngle + pi /2,
        ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));

        _controller.forward().whenComplete(() {
          if (!mounted) return;
          // 動畫完成後，更新角度並延遲後再次啟動
          _currentAngle = _currentRotationAnimation.value;
          Future.delayed(const Duration(milliseconds: 500), () {
            if (mounted) {
              _setupAnimation(); // 再次啟動下一個動畫
            }
          });
        });
        break;
    }
  }

  // Handle shape type or animation state changes from the parent widget
  @override
  void didUpdateWidget(covariant AnimatedShapeWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.shapeType != oldWidget.shapeType || widget.animationState != oldWidget.animationState) {
      // 在切換動畫模式時，重置角度
      _currentAngle = 0;
      _setupAnimation();
    }
  }

  @override
  void dispose() {
    _controller.dispose(); // Dispose the controller
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 200,
      height: 200,
      child: AnimatedBuilder(
        animation: _currentRotationAnimation, // 監聽動畫本身
        builder: (context, child) {
          return Transform.rotate(
            angle: _currentRotationAnimation.value,
            child: child,
          );
        },
        child: CustomPaint(
          // 將 scale 參數傳入 ShapePainter
          painter: ShapePainter(shapeType: widget.shapeType, scale: widget.scale),
        ),
      ),
    );
  }
}

// The ShapePainter draws based on the shapeType
// 這個類別現在是獨立於 _AnimatedShapeWidgetState 的頂層類別
class ShapePainter extends CustomPainter {
  final ShapeType shapeType;
  final double scale; // 新增的參數：用於縮放

  ShapePainter({required this.shapeType, this.scale = 1.0});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    final paint2 = Paint()
      ..color = Colors.yellow
      ..style = PaintingStyle.fill;

    // 使用 canvas.scale() 來對整個畫布進行等比縮放
    canvas.save();
    canvas.scale(scale);

    // 縮放後，中心點也需要對應調整
    final center = Offset(size.width / 2 / scale, size.height / 2 / scale);

    switch (shapeType) {
      case ShapeType.star:
        int circleCount = 8;
        double circleDistance = 20;
        double smallCircleRadius = 25;

        canvas.drawCircle(center, 30, paint);

        for (int i = 0; i < circleCount; i++) {
          double angle = (2 * pi / circleCount) * i;
          double x = center.dx + circleDistance * cos(angle);
          double y = center.dy + circleDistance * sin(angle);

          double ovalWidth = smallCircleRadius * 2;
          double ovalHeight = smallCircleRadius * 1.2;

          canvas.save();
          canvas.translate(x, y);
          canvas.rotate(angle + pi); // Rotate each oval to face outwards

          Rect ovalRect = Rect.fromCenter(center: Offset.zero, width: ovalWidth, height: ovalHeight);
          canvas.drawOval(ovalRect, paint);
          canvas.restore();
        }

        circleCount = 5;
        circleDistance = 10;
        smallCircleRadius = 15;

        for (int i = 0; i < circleCount; i++) {
          double angle = (2 * pi / circleCount) * i;
          double x = center.dx + circleDistance * cos(angle);
          double y = center.dy + circleDistance * sin(angle);

          double ovalWidth = smallCircleRadius * 2;
          double ovalHeight = smallCircleRadius * 1.2;

          canvas.save();
          canvas.translate(x, y);
          canvas.rotate(angle + pi); // Rotate each oval to face outwards

          Rect ovalRect = Rect.fromCenter(center: Offset.zero, width: ovalWidth, height: ovalHeight);
          canvas.drawOval(ovalRect, paint2);
          canvas.restore();
        }
        break;

      case ShapeType.rectangle:
        int circleCount = 4;
        double circleDistance = 20;
        double smallCircleRadius = 20;

        canvas.drawCircle(center, 30, paint); // 繪製中間的大圓，半徑 60

        // 開始繪製外圍的圓形
        for (int i = 0; i < circleCount; i++) {
          double angle = (2 * pi / circleCount) * i;
          double x = center.dx + circleDistance * cos(angle);
          double y = center.dx + circleDistance * sin(angle);

          // 直接繪製圓形，不再進行橢圓的變換
          canvas.drawCircle(Offset(x, y), smallCircleRadius, paint);
        }
        break;

      case ShapeType.circleGrid:
        int circleCount = 8;
        double circleDistance = 27;
        double smallCircleRadius = 18;

        canvas.drawCircle(center, 30, paint); // 繪製中間的大圓，半徑 60

        // 開始繪製外圍的圓形
        for (int i = 0; i < circleCount; i++) {
          double angle = (2 * pi / circleCount) * i;
          double x = center.dx + circleDistance * cos(angle);
          double y = center.dy + circleDistance * sin(angle);

          // 直接繪製圓形，不再進行橢圓的變換
          canvas.drawCircle(Offset(x, y), smallCircleRadius, paint);
        }
        circleCount = 5;
        circleDistance = 10;
        smallCircleRadius = 15;

        for (int i = 0; i < circleCount; i++) {
          double angle = (2 * pi / circleCount) * i;
          double x = center.dx + circleDistance * cos(angle);
          double y = center.dy + circleDistance * sin(angle);

          double ovalWidth = smallCircleRadius * 2;
          double ovalHeight = smallCircleRadius * 1.2;

          canvas.save();
          canvas.translate(x, y);
          canvas.rotate(angle + pi); // Rotate each oval to face outwards

          Rect ovalRect = Rect.fromCenter(center: Offset.zero, width: ovalWidth, height: ovalHeight);
          canvas.drawOval(ovalRect, paint2);
          canvas.restore();
        }

        break;

      case ShapeType.flower:
        int circleCount = 5;
        double circleDistance = 20;
        double smallCircleRadius = 35;

        canvas.drawCircle(center, 30, paint);

        for (int i = 0; i < circleCount; i++) {
          double angle = (2 * pi / circleCount) * i;
          double x = center.dx + circleDistance * cos(angle);
          double y = center.dy + circleDistance * sin(angle);

          double ovalWidth = smallCircleRadius * 2;
          double ovalHeight = smallCircleRadius * 1.2;

          canvas.save();
          canvas.translate(x, y);
          canvas.rotate(angle + pi); // Rotate each oval to face outwards

          Rect ovalRect = Rect.fromCenter(center: Offset.zero, width: ovalWidth, height: ovalHeight);
          canvas.drawOval(ovalRect, paint);
          canvas.restore();
        }

        circleCount = 8;
        circleDistance = 10;
        smallCircleRadius = 10;

        for (int i = 0; i < circleCount; i++) {
          double angle = (2 * pi / circleCount) * i;
          double x = center.dx + circleDistance * cos(angle);
          double y = center.dy + circleDistance * sin(angle);

          double ovalWidth = smallCircleRadius * 2;
          double ovalHeight = smallCircleRadius * 1.2;

          canvas.save();
          canvas.translate(x, y);
          canvas.rotate(angle + pi); // Rotate each oval to face outwards

          Rect ovalRect = Rect.fromCenter(center: Offset.zero, width: ovalWidth, height: ovalHeight);
          canvas.drawOval(ovalRect, paint2);
          canvas.restore();
        }
        break;
    }

    canvas.restore(); // 恢復畫布狀態
  }

  @override
  bool shouldRepaint(covariant ShapePainter oldDelegate) {
    // 只要形狀或縮放值有變化，就重新繪製
    return oldDelegate.shapeType != shapeType || oldDelegate.scale != scale;
  }
}