import 'package:flutter/material.dart';
import 'package:motor/motor.dart';

import '../utils/animation_constants.dart';

/// Applies a fade-in and downward-to-upward slide animation to its child using
/// Motor spring physics.
///
/// The [motion] parameter (and [slideDistance]) control the spatial translation
/// spring only. The opacity fade is always driven by
/// [AnimationConstants.expressiveEffectsDefault] and is not externally
/// configurable.
class AnimatedFadeSlide extends StatelessWidget {
  final Motion? motion;
  final double slideDistance;
  final double value;
  final double from;
  final Widget child;

  const AnimatedFadeSlide({
    super.key,
    this.motion,
    this.slideDistance = AnimationConstants.defaultSlideDistance,
    this.value = 1.0,
    this.from = 0.0,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return SingleMotionBuilder(
      motion: motion ?? AnimationConstants.expressiveSpatialDefault,
      value: value,
      from: from,
      builder: (context, spatialV, spatialChild) {
        return Transform.translate(
          offset: Offset(0, slideDistance * (1 - spatialV)),
          child: SingleMotionBuilder(
            motion: AnimationConstants.expressiveEffectsDefault,
            value: value,
            from: from,
            builder: (context, effectsV, innerChild) {
              return Opacity(
                opacity: effectsV.clamp(0.0, 1.0),
                child: innerChild,
              );
            },
            child: spatialChild,
          ),
        );
      },
      child: child,
    );
  }
}
