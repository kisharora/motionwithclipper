import 'dart:math';

import 'package:flutter/widgets.dart' hide Shadow;

import 'package:motion_platform_interface/motion_platform_interface.dart';

import 'model/configurations.dart';
import 'model/controller.dart';
import 'motion.dart';
import 'motion_provider.dart';

class MotionStreamBuilder extends StatefulWidget {
  /// The controller that holds the widget's motion data.
  final MotionController? controller;

  /// The target widget.
  final Widget child;

  /// Whether to apply a dynamic glare effect to the widget.
  final GlareConfiguration? glare;

  /// Whether to apply a dynamic shadow to the widget.
  final ShadowConfiguration? shadow;

  /// Whether to apply a dynamic translation effect on the widget's X and Y positions.
  final TranslationConfiguration? translation;

  /// An optional border radius to apply to the widget.
  final BorderRadius? borderRadius;

  /// The filter quality with which to apply the transform as a bitmap operation.
  ///
  /// Defaults to [defaultFilterQuality] when omitted in the constructor.
  final FilterQuality? filterQuality;
  final CustomClipper<Path>? clipper;

  /// Creates a [Motion] widget with the given [child] and [controller], applying all of the effects.
  const MotionStreamBuilder({
    Key? key,
    this.controller,
    required this.child,
    required this.glare,
    required this.shadow,
    required this.translation,
    this.borderRadius,
    this.filterQuality = defaultFilterQuality,
    this.clipper,
  }) : super(key: key);

  @override
  State<MotionStreamBuilder> createState() => _MotionStreamBuilderState();
}

class _MotionStreamBuilderState extends State<MotionStreamBuilder> {
  /// The controller to use.
  MotionController get controller =>
      widget.controller ?? MotionController.defaultController;

  /// The intensity of the glare effect. Used as the gradient's opacity.
  double get glareOpacity => max(
      0,
      min(
        widget.glare?.minOpacity ?? minGlareOpacity,
        (widget.glare?.minOpacity ?? minGlareOpacity) +
            (controller.x / controller.maxAngle) *
                ((widget.glare?.maxOpacity ?? maxGlareOpacity) -
                    (widget.glare?.minOpacity ?? minGlareOpacity)),
      ));

  /// The rotation of the glare effect's gradient.
  double get glareRotation =>
      pi / 2 + (controller.y / (controller.maxAngle * 2) * (2 * pi));

  /// The shadow's offset on the horizontal axis.
  double get horizontalShadowOffset =>
      (controller.y / controller.maxAngle) * (widget.shadow?.maxOffset.dy ?? 0);

  /// The shadow's offset on the vertical axis.
  double get verticalShadowOffset =>
      (controller.x / controller.maxAngle) * (widget.shadow?.maxOffset.dx ?? 0);

  /// The device's orientation.
  Orientation? orientation;

  /// The effective filter quality. It ensures that the platform is not Safari Mobile, whose implementation
  /// of Transform.filterQuality renders artifacts.
  FilterQuality? get filterQuality =>
      Motion.instance.isSafariMobile ? null : widget.filterQuality;

  /// Computes the new rotation for each axis from the given [event], and updates the controller's value.
  Matrix4 computeTransformForEvent(MotionEvent? event) {
    final matrix = Matrix4.identity()..setEntry(3, 2, 0.0015);

    if (event != null) {
      // In case of relative rotation events...
      if (event.type == MotionType.gyroscope) {
        // Apply the event's rotation based on the device orientation.
        controller.x +=
            (orientation == Orientation.landscape ? -event.y : event.x) * 0.01;
        controller.y -=
            (orientation == Orientation.landscape ? event.x : event.y) * 0.01;

        // Normalize the values.
        controller.normalize();

        // Apply the damping factor — which may equal 1 and have no effect, if damping is null.
        controller.x *= controller.dampingFactor;
        controller.y *= controller.dampingFactor;
      } else {
        // In case of absolute rotation events...
        controller.x = event.x * (controller.maxAngle / 2);
        controller.y = event.y * (controller.maxAngle / 2);
      }

      // Rotate the matrix by the resulting x and y values.
      matrix.rotateX(controller.x);
      matrix.rotateY(controller.y);

      matrix.translate(
        controller.y * -((widget.translation?.maxOffset.dy ?? 0) * 2.0),
        controller.x * (widget.translation?.maxOffset.dx ?? 0),
      );
    }

    return matrix;
  }

  @override
  void didChangeDependencies() {
    orientation = MediaQuery.of(context).orientation;
    super.didChangeDependencies();
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<MotionEvent>(
      stream: MotionProvider.of(context)?.stream ??
          const Stream<MotionEvent>.empty(),
      initialData: MotionEvent.zero(
          type: Motion.instance.isGyroscopeAvailable
              ? MotionType.gyroscope
              : MotionType.pointer),
      builder: (ctx, snapshot) => Stack(clipBehavior: Clip.none, children: [
            // The widget's drop shadow
            if (widget.shadow != null && widget.shadow!.isVisible)
              Positioned(
                  left: horizontalShadowOffset,
                  right: -horizontalShadowOffset,
                  top: -verticalShadowOffset + widget.shadow!.topOffset,
                  bottom: verticalShadowOffset - widget.shadow!.topOffset,
                  child: IgnorePointer(
                      child: ClipRRect(
                    borderRadius: BorderRadius.circular(25),
                    child: ClipPath(
                      clipper: widget.clipper,
                      child: Container(
                          clipBehavior: Clip.hardEdge,
                          decoration: BoxDecoration(
                              borderRadius: widget.borderRadius,
                              boxShadow: [
                                BoxShadow(
                                    blurRadius: widget.shadow!.blurRadius,
                                    color: widget.shadow!.color
                                        .withOpacity(widget.shadow!.opacity))
                              ])),
                    ),
                  ))),

            // The transformation widgets
            Transform(
                transform: computeTransformForEvent(snapshot.data),
                alignment: FractionalOffset.center,
                filterQuality: filterQuality,
                child: widget.glare != null &&
                        Motion.instance.isGradientOverlayAvailable
                    ? Stack(clipBehavior: Clip.none, children: [
                        widget.child,
                        Positioned.fill(
                            child: ClipPath(
                          clipper: widget.clipper,
                          child: IgnorePointer(
                              child: Container(
                                  clipBehavior: Clip.hardEdge,
                                  decoration: BoxDecoration(
                                    borderRadius: widget.borderRadius,
                                    gradient: LinearGradient(
                                        colors: [
                                          (widget.glare?.color ??
                                                  defaultGlareColor)
                                              .withOpacity(
                                                  widget.glare?.minOpacity ??
                                                      minGlareOpacity),
                                          (widget.glare?.color ??
                                                  defaultGlareColor)
                                              .withOpacity(
                                                  widget.glare?.maxOpacity ??
                                                      maxGlareOpacity)
                                        ],
                                        transform:
                                            GradientRotation(glareRotation)),
                                  ))),
                        ))
                      ])
                    : widget.child),
          ]));
}
