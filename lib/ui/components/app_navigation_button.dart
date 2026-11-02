// Adapted from google_nav_bar 5.0.7. The original pill animation is retained;
// the label reveal is clipped so it cannot paint across the icon.
// MIT License
//
// Copyright (c) 2019 Soo Xiao Tong
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

import 'dart:math' show pow;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:google_nav_bar/google_nav_bar.dart' show GnavStyle;

class AppNavigationButton extends StatefulWidget {
  final bool? active;
  final bool? debug;
  final bool? haptic;
  final double? gap;
  final Color? iconColor;
  final Color? rippleColor;
  final Color? hoverColor;
  final Color? iconActiveColor;
  final Color? textColor;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final TextStyle? textStyle;
  final double? iconSize;
  final Function? onPressed;
  final String text;
  final IconData icon;
  final Color? backgroundColor;
  final Duration? duration;
  final Curve? curve;
  final Gradient? backgroundGradient;
  final Widget? leading;
  final BorderRadius? borderRadius;
  final Border? border;
  final Border? activeBorder;
  final List<BoxShadow>? shadow;
  final String? semanticLabel;
  final GnavStyle? style;
  final double? textSize;

  const AppNavigationButton({
    super.key,
    this.active,
    this.haptic,
    this.backgroundColor,
    required this.icon,
    this.iconColor,
    this.rippleColor,
    this.hoverColor,
    this.iconActiveColor,
    this.text = '',
    this.textColor,
    this.padding,
    this.margin,
    this.duration,
    this.debug,
    this.gap,
    this.curve,
    this.textStyle,
    this.iconSize,
    this.leading,
    this.onPressed,
    this.backgroundGradient,
    this.borderRadius,
    this.border,
    this.activeBorder,
    this.shadow,
    this.semanticLabel,
    this.style = GnavStyle.google,
    this.textSize,
  });

  @override
  State<AppNavigationButton> createState() => _AppNavigationButtonState();
}

class _AppNavigationButtonState extends State<AppNavigationButton> {
  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: widget.semanticLabel ?? widget.text,
      child: _ClippedButton(
        textSize: widget.textSize,
        style: widget.style,
        borderRadius: widget.borderRadius,
        border: widget.border,
        activeBorder: widget.activeBorder,
        shadow: widget.shadow,
        debug: widget.debug,
        duration: widget.duration,
        iconSize: widget.iconSize,
        active: widget.active,
        onPressed: () {
          if (widget.haptic!) HapticFeedback.selectionClick();
          widget.onPressed?.call();
        },
        padding: widget.padding,
        margin: widget.margin,
        gap: widget.gap,
        color: widget.backgroundColor,
        rippleColor: widget.rippleColor,
        hoverColor: widget.hoverColor,
        gradient: widget.backgroundGradient,
        curve: widget.curve,
        leading: widget.leading,
        iconActiveColor: widget.iconActiveColor,
        iconColor: widget.iconColor,
        icon: widget.icon,
        text: Text(
          widget.text,
          style: widget.textStyle ??
              TextStyle(
                fontWeight: FontWeight.w600,
                color: widget.textColor,
              ),
        ),
      ),
    );
  }
}

class _ClippedButton extends StatefulWidget {
  const _ClippedButton({
    this.icon,
    this.iconSize,
    this.leading,
    this.iconActiveColor,
    this.iconColor,
    this.text,
    this.gap,
    this.color,
    this.rippleColor,
    this.hoverColor,
    required this.onPressed,
    this.duration,
    this.curve,
    this.padding,
    this.margin,
    required this.active,
    this.debug,
    this.gradient,
    this.borderRadius,
    this.border,
    this.activeBorder,
    this.shadow,
    this.style = GnavStyle.google,
    this.textSize,
  });

  final IconData? icon;
  final double? iconSize;
  final Text? text;
  final Widget? leading;
  final Color? iconActiveColor;
  final Color? iconColor;
  final Color? color;
  final Color? rippleColor;
  final Color? hoverColor;
  final double? gap;
  final bool? active;
  final bool? debug;
  final VoidCallback onPressed;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final Duration? duration;
  final Curve? curve;
  final Gradient? gradient;
  final BorderRadius? borderRadius;
  final Border? border;
  final Border? activeBorder;
  final List<BoxShadow>? shadow;
  final GnavStyle? style;
  final double? textSize;

  @override
  _ClippedButtonState createState() => _ClippedButtonState();
}

class _ClippedButtonState extends State<_ClippedButton>
    with TickerProviderStateMixin {
  late bool _expanded;
  late final AnimationController expandController;

  @override
  void initState() {
    super.initState();
    _expanded = widget.active!;

    expandController =
        AnimationController(vsync: this, duration: widget.duration)
          ..addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    expandController.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    var curveValue = expandController
        .drive(CurveTween(
            curve: _expanded ? widget.curve! : widget.curve!.flipped))
        .value;
    var colorTween =
        ColorTween(begin: widget.iconColor, end: widget.iconActiveColor);
    var colorTweenAnimation = colorTween.animate(CurvedAnimation(
        parent: expandController,
        curve: _expanded ? Curves.easeInExpo : Curves.easeOutCirc));

    _expanded = !widget.active!;
    if (_expanded) {
      expandController.reverse();
    } else {
      expandController.forward();
    }

    Widget icon = widget.leading ??
        Icon(widget.icon,
            color: colorTweenAnimation.value, size: widget.iconSize);

    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        highlightColor: widget.hoverColor,
        splashColor: widget.rippleColor,
        borderRadius: widget.borderRadius,
        onTap: widget.onPressed,
        child: Container(
          padding: widget.margin,
          child: AnimatedContainer(
            curve: Curves.easeOut,
            padding: widget.padding,
            duration: widget.duration!,
            decoration: BoxDecoration(
              boxShadow: widget.shadow,
              border: widget.active!
                  ? (widget.activeBorder ?? widget.border)
                  : widget.border,
              gradient: widget.gradient,
              color: _expanded
                  ? widget.color!.withValues(alpha: 0)
                  : widget.debug!
                      ? Colors.red
                      : widget.gradient != null
                          ? Colors.white
                          : widget.color,
              borderRadius: widget.borderRadius,
            ),
            child: FittedBox(
              fit: BoxFit.fitHeight,
              child: Builder(
                builder: (_) {
                  if (widget.style == GnavStyle.google) {
                    return Stack(
                      children: [
                        if (widget.text!.data != '')
                          Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                Opacity(
                                  opacity: 0,
                                  child: icon,
                                ),
                                ClipRect(
                                  child: Align(
                                    alignment: Alignment.centerRight,
                                    widthFactor: curveValue,
                                    child: Opacity(
                                        opacity: _expanded
                                            ? pow(expandController.value, 13)
                                                as double
                                            : expandController
                                                .drive(CurveTween(
                                                    curve: Curves.easeIn))
                                                .value,
                                        child: Padding(
                                          padding: EdgeInsets.only(
                                              left: widget.gap! +
                                                  8 -
                                                  (8 *
                                                      expandController
                                                          .drive(CurveTween(
                                                              curve: Curves
                                                                  .easeOutSine))
                                                          .value),
                                              right: 8 *
                                                  expandController
                                                      .drive(CurveTween(
                                                          curve: Curves
                                                              .easeOutSine))
                                                      .value),
                                          child: widget.text,
                                        )),
                                  ),
                                ),
                              ]),
                        Align(alignment: Alignment.centerLeft, child: icon),
                      ],
                    );
                  } else if (widget.style == GnavStyle.oldSchool) {
                    return Column(
                      children: [
                        icon,
                        Container(
                          padding: EdgeInsets.only(top: widget.gap!),
                          child: Text(
                            widget.text!.data!,
                            style: TextStyle(
                              color: colorTweenAnimation.value,
                              fontSize: widget.textSize ?? 16,
                            ),
                          ),
                        ),
                      ],
                    );
                  } else {
                    return Container();
                  }
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}
