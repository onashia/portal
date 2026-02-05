import 'dart:developer' as developer;
import 'package:flutter/foundation.dart';

class AppLogger {
  static const _name = 'portal';

  static void log(
    String message, {
    String? subCategory,
    int level = 500,
    Object? error,
    StackTrace? stackTrace,
  }) {
    if (kDebugMode) {
      final name = subCategory != null ? '$_name.$subCategory' : _name;
      // Mirror logs to stdout so they appear in flutter run output.
      final details = <String>[
        if (error != null) 'error=$error',
        if (stackTrace != null) 'stack=$stackTrace',
      ].join(' ');
      debugPrint(
        '[$name] $message${details.isNotEmpty ? ' ($details)' : ''}',
      );
      developer.log(
        message,
        name: name,
        level: level,
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  static void info(String message, {String? subCategory}) {
    log(message, subCategory: subCategory, level: 500);
  }

  static void debug(String message, {String? subCategory}) {
    log(message, subCategory: subCategory, level: 700);
  }

  static void warning(String message, {String? subCategory}) {
    log(message, subCategory: subCategory, level: 900);
  }

  static void error(
    String message, {
    String? subCategory,
    Object? error,
    StackTrace? stackTrace,
  }) {
    log(
      message,
      subCategory: subCategory,
      level: 1000,
      error: error,
      stackTrace: stackTrace,
    );
  }
}
