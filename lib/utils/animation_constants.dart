import 'package:flutter/material.dart';
import 'package:motor/motor.dart';

class AnimationConstants {
  // Border radius (unchanged - not animation related)
  static const double borderRadiusSm = 8.0;
  static const double borderRadiusMd = 12.0;
  static const double borderRadiusLg = 16.0;
  static const double borderRadiusXl = 24.0;
  static const double borderRadiusFull = 9999.0;

  // MD3 Spring Motion Tokens
  // Spatial Motion (for position, size, layout changes)
  static final Motion standardSpatialFast =
      MaterialSpringMotion.standardSpatialFast();
  static final Motion standardSpatialDefault =
      MaterialSpringMotion.standardSpatialDefault();
  static final Motion standardSpatialSlow =
      MaterialSpringMotion.standardSpatialSlow();
  static final Motion expressiveSpatialFast =
      MaterialSpringMotion.expressiveSpatialFast();
  static final Motion expressiveSpatialDefault =
      MaterialSpringMotion.expressiveSpatialDefault();
  static final Motion expressiveSpatialSlow =
      MaterialSpringMotion.expressiveSpatialSlow();

  // Effects Motion (for opacity, color, and other visual properties)
  static final Motion standardEffectsFast =
      MaterialSpringMotion.standardEffectsFast();
  static final Motion standardEffectsDefault =
      MaterialSpringMotion.standardEffectsDefault();
  static final Motion standardEffectsSlow =
      MaterialSpringMotion.standardEffectsSlow();
  static final Motion expressiveEffectsFast =
      MaterialSpringMotion.expressiveEffectsFast();
  static final Motion expressiveEffectsDefault =
      MaterialSpringMotion.expressiveEffectsDefault();
  static final Motion expressiveEffectsSlow =
      MaterialSpringMotion.expressiveEffectsSlow();

  // Backward compatibility curves (for components that need curves)
  static const Curve defaultEnter = Curves.easeOutCubic;
  static const Curve defaultExit = Curves.easeInCubic;
  static const Curve standardCurve = Curves.easeInOut;

  // Slide distances (unchanged)
  static const double defaultSlideDistance = 16.0;
  static const double enterSlideDistance = 24.0;
}
