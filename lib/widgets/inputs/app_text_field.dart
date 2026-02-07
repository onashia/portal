import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class AppTextField extends StatelessWidget {
  final TextEditingController? controller;
  final FocusNode? focusNode;
  final InputDecoration? decoration;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final List<TextInputFormatter>? inputFormatters;
  final bool obscureText;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final bool enabled;

  const AppTextField({
    super.key,
    this.controller,
    this.focusNode,
    this.decoration,
    this.keyboardType,
    this.textInputAction,
    this.inputFormatters,
    this.obscureText = false,
    this.onChanged,
    this.onSubmitted,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final inputBorder = Theme.of(context).inputDecorationTheme.border;
    final borderRadius = inputBorder is OutlineInputBorder
        ? inputBorder.borderRadius
        : BorderRadius.zero;
    final enabledBorder = OutlineInputBorder(
      borderRadius: borderRadius,
      borderSide: BorderSide(color: scheme.surfaceContainerHighest, width: 1),
    );
    final focusedBorder = OutlineInputBorder(
      borderRadius: borderRadius,
      borderSide: BorderSide(color: scheme.primary, width: 2),
    );
    final errorBorder = OutlineInputBorder(
      borderRadius: borderRadius,
      borderSide: BorderSide(color: scheme.error, width: 2),
    );
    final effectiveDecoration = (decoration ?? const InputDecoration())
        .copyWith(
          filled: true,
          fillColor: scheme.surfaceContainerLow,
          enabledBorder: enabledBorder,
          focusedBorder: focusedBorder,
          errorBorder: errorBorder,
          focusedErrorBorder: errorBorder,
        );

    return TextField(
      controller: controller,
      focusNode: focusNode,
      decoration: effectiveDecoration,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      inputFormatters: inputFormatters,
      obscureText: obscureText,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      enabled: enabled,
    );
  }
}

class AppTextFormField extends StatelessWidget {
  final TextEditingController? controller;
  final FocusNode? focusNode;
  final InputDecoration? decoration;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final List<TextInputFormatter>? inputFormatters;
  final bool obscureText;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onFieldSubmitted;
  final FormFieldValidator<String>? validator;
  final bool enabled;

  const AppTextFormField({
    super.key,
    this.controller,
    this.focusNode,
    this.decoration,
    this.keyboardType,
    this.textInputAction,
    this.inputFormatters,
    this.obscureText = false,
    this.onChanged,
    this.onFieldSubmitted,
    this.validator,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final inputBorder = Theme.of(context).inputDecorationTheme.border;
    final borderRadius = inputBorder is OutlineInputBorder
        ? inputBorder.borderRadius
        : BorderRadius.zero;
    final enabledBorder = OutlineInputBorder(
      borderRadius: borderRadius,
      borderSide: BorderSide(color: scheme.surfaceContainerHighest, width: 1),
    );
    final focusedBorder = OutlineInputBorder(
      borderRadius: borderRadius,
      borderSide: BorderSide(color: scheme.primary, width: 2),
    );
    final errorBorder = OutlineInputBorder(
      borderRadius: borderRadius,
      borderSide: BorderSide(color: scheme.error, width: 2),
    );
    final effectiveDecoration = (decoration ?? const InputDecoration())
        .copyWith(
          filled: true,
          fillColor: scheme.surfaceContainerLow,
          enabledBorder: enabledBorder,
          focusedBorder: focusedBorder,
          errorBorder: errorBorder,
          focusedErrorBorder: errorBorder,
        );

    return TextFormField(
      controller: controller,
      focusNode: focusNode,
      decoration: effectiveDecoration,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      inputFormatters: inputFormatters,
      obscureText: obscureText,
      onChanged: onChanged,
      onFieldSubmitted: onFieldSubmitted,
      validator: validator,
      enabled: enabled,
    );
  }
}
