import 'package:motor/motor.dart';

class AnimationConstants {
  // MD3 Spring Motion Tokens
  // Spatial Motion (for position, size, layout changes)
  static final Motion expressiveSpatialDefault =
      MaterialSpringMotion.expressiveSpatialDefault();

  // Effects Motion (for opacity, color, and other visual properties)
  static final Motion standardEffectsFast =
      MaterialSpringMotion.standardEffectsFast();
  static final Motion expressiveEffectsDefault =
      MaterialSpringMotion.expressiveEffectsDefault();

  // Slide distances
  static const double defaultSlideDistance = 16.0;
}
