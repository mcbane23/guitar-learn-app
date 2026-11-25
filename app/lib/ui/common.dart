import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import 'themes.dart';

/// The OK button: the center of a TV remote's arrows, or Enter on a keyboard.
bool isOkKey(LogicalKeyboardKey key) =>
    key == LogicalKeyboardKey.select ||
    key == LogicalKeyboardKey.enter ||
    key == LogicalKeyboardKey.numpadEnter ||
    key == LogicalKeyboardKey.gameButtonA;

const _screen = MethodChannel('guitar_learn/screen');

/// Keeps the screen from turning off (or the TV screensaver from starting).
void keepScreenOn(bool on) {
  _screen.invokeMethod<void>('keepOn', {'on': on}).catchError((Object _) {
    // Not available here (e.g. widget tests); nothing to do.
  });
}

bool? _tv;

/// Whether the app runs on a TV (Android TV), where a remote is the only
/// way to control it. Decided once and cached; false where unknown.
Future<bool> isTelevision() async {
  if (_tv case final known?) return known;
  try {
    _tv = await _screen.invokeMethod<bool>('isTv') ?? false;
  } catch (_) {
    _tv = false;
  }
  return _tv!;
}

/// Keeps a screen in landscape and full screen while it is open
/// (the neck needs the whole width), and keeps the screen awake.
mixin LandscapeScreen<T extends StatefulWidget> on State<T> {
  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    keepScreenOn(true);
  }

  @override
  void dispose() {
    SystemChrome.setPreferredOrientations(const []);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    keepScreenOn(false);
    super.dispose();
  }
}

/// A big card that is easy to hit with a finger and shows a clear outline
/// when selected with a TV remote. It is a pane of "glass": a translucent
/// white over the glowing background, with a thin line around it.
class FocusCard extends StatefulWidget {
  const FocusCard({
    super.key,
    required this.child,
    required this.onTap,
    this.onLongPress,
    this.color,
    this.width,
    this.height,
    this.autofocus = false,
    this.radius = cardRadius,
  });

  final Widget child;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  /// The card's color; glass by default.
  final Color? color;
  final double? width;
  final double? height;
  final bool autofocus;
  final double radius;

  @override
  State<FocusCard> createState() => _FocusCardState();
}

class _FocusCardState extends State<FocusCard> {
  bool _focused = false;

  /// How far the card grows on each side when it is selected.
  static const _growth = 6.0;

  double _scale = 1;

  void _onFocusChange(bool focused) {
    if (focused) {
      // The card grows by a few pixels, not by a share of its width: a wide
      // card would otherwise grow past the edge of the screen.
      final width = context.size?.width ?? widget.width;
      _scale = width == null || width <= 0 ? 1.05 : (1 + 2 * _growth / width).clamp(1.0, 1.05);
      // Bring the ring and the glow into view too, not just the card.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _focused) revealFocused(context);
      });
    }
    setState(() => _focused = focused);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(widget.radius),
      side: _focused ? const BorderSide(color: focusRing, width: 3) : const BorderSide(color: glassBorder),
    );
    return AnimatedScale(
      scale: _focused ? _scale : 1,
      duration: const Duration(milliseconds: 120),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        width: widget.width,
        height: widget.height,
        decoration: ShapeDecoration(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(widget.radius)),
          // The selected card also lights up around the edge, so it is
          // found at a glance from the couch.
          shadows: _focused
              ? [BoxShadow(color: scheme.secondary.withValues(alpha: 0.45), blurRadius: 20, spreadRadius: 1)]
              : const [],
        ),
        child: Material(
          // The glow would show through a glass card, so the selected card
          // gets a solid fill in a hint of the glow's color instead.
          color: widget.color ??
              (_focused ? Color.alphaBlend(scheme.secondary.withValues(alpha: 0.16), scheme.surface) : glass),
          clipBehavior: Clip.antiAlias,
          shape: shape,
          child: InkWell(
            autofocus: widget.autofocus,
            onTap: widget.onTap,
            onLongPress: widget.onLongPress,
            onFocusChange: _onFocusChange,
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

/// Room to leave around a selected control when a list scrolls it into
/// view, so its ring and glow are not cut by the edge of the screen.
const focusMargin = 16.0;

/// Scrolls every list around [context] so that its widget is fully in
/// view with [margin] free on each side. Flutter's own scrolling on focus
/// stops as soon as the widget's box is in view, which leaves the ring
/// around it cut off at the edge.
///
/// Only once the remote (or a keyboard) is in use: a finger does not need
/// it, and the card that takes the focus when the home screen opens would
/// scroll the title off a phone.
void revealFocused(BuildContext context, {double margin = focusMargin}) {
  if (FocusManager.instance.highlightMode != FocusHighlightMode.traditional) return;
  final target = context.findRenderObject();
  if (target == null || !target.attached) return;
  var scrollable = Scrollable.maybeOf(context);
  var ctx = context;
  while (scrollable != null) {
    final object = ctx.findRenderObject();
    final viewport = object == null ? null : RenderAbstractViewport.maybeOf(object);
    if (object == null || viewport == null) return;
    final position = scrollable.position;
    final rect = MatrixUtils.transformRect(target.getTransformTo(object), target.paintBounds).inflate(margin);
    var to = position.pixels;
    final end = viewport.getOffsetToReveal(object, 1, rect: rect).offset;
    if (end > to) to = end;
    final start = viewport.getOffsetToReveal(object, 0, rect: rect).offset;
    if (start < to) to = start;
    to = to.clamp(position.minScrollExtent, position.maxScrollExtent);
    if ((to - position.pixels).abs() > 0.5) {
      position.animateTo(to, duration: const Duration(milliseconds: 120), curve: Curves.easeOut);
    }
    ctx = scrollable.context;
    scrollable = Scrollable.maybeOf(ctx);
  }
}

/// Draws the remote's white ring around a control that has no ring of its
/// own (a row in the settings), whenever the focus is on it or inside it.
class FocusHighlight extends StatefulWidget {
  const FocusHighlight({super.key, required this.child, this.radius = 16});

  final Widget child;
  final double radius;

  @override
  State<FocusHighlight> createState() => _FocusHighlightState();
}

class _FocusHighlightState extends State<FocusHighlight> {
  bool _focused = false;

  void _onFocusChange(bool focused) {
    if (focused) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _focused) revealFocused(context);
      });
    }
    setState(() => _focused = focused);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onFocusChange: _onFocusChange,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        decoration: BoxDecoration(
          color: _focused ? Color.alphaBlend(scheme.secondary.withValues(alpha: 0.16), scheme.surface) : Colors.transparent,
          borderRadius: BorderRadius.circular(widget.radius),
          border: Border.all(color: _focused ? focusRing : Colors.transparent, width: 3),
          boxShadow: _focused
              ? [BoxShadow(color: scheme.secondary.withValues(alpha: 0.35), blurRadius: 16)]
              : const [],
        ),
        child: widget.child,
      ),
    );
  }
}

/// How the remote's arrows move between controls: to the nearest control
/// in the same row (left, right) or the same column (up, down), measured
/// from the center of the selected one. Flutter's own rule has two habits
/// that confuse on a TV: with nothing to the right in the row it jumps to
/// the nearest control in any row, often a card half off the screen in
/// the row below; and once a list is scrolled it only looks at controls
/// placed directly in that list, so from the wide "Continue" card a press
/// down skips every row of song cards.
class TvFocusTraversalPolicy extends ReadingOrderTraversalPolicy {
  @override
  bool inDirection(FocusNode currentNode, TraversalDirection direction) {
    final scope = currentNode.nearestScope;
    final focused = scope?.focusedChild;
    if (scope == null || focused == null || focused.context == null) {
      return super.inDirection(currentNode, direction);
    }
    final from = focused.rect;
    final vertical = direction == TraversalDirection.up || direction == TraversalDirection.down;
    bool beyond(Rect r) => switch (direction) {
          TraversalDirection.up => r.center.dy <= from.top,
          TraversalDirection.down => r.center.dy >= from.bottom,
          TraversalDirection.left => r.center.dx <= from.left,
          TraversalDirection.right => r.center.dx >= from.right,
        };
    bool inLine(Rect r) =>
        vertical ? r.left < from.right && r.right > from.left : r.top < from.bottom && r.bottom > from.top;
    var candidates = [
      for (final node in scope.traversalDescendants)
        if (node != focused && node.context != null && node.rect != from && beyond(node.rect) && inLine(node.rect)) node,
    ];
    // Inside a list, the rest of the list comes first: a settings row goes
    // to the row above it, not to the Back button that floats over the
    // list, until the rows run out. A row of cards inside the list counts
    // as part of it.
    final list = Scrollable.maybeOf(focused.context!);
    if (list != null) {
      bool inside(FocusNode node) {
        for (var s = Scrollable.maybeOf(node.context!); s != null; s = Scrollable.maybeOf(s.context)) {
          if (s == list) return true;
        }
        return false;
      }

      final within = candidates.where(inside).toList();
      if (within.isNotEmpty) candidates = within;
    }
    if (candidates.isEmpty) {
      // Nothing above or below in this column: let Flutter look further
      // afield. Nothing further along the row: stay where we are.
      return vertical ? super.inDirection(currentNode, direction) : false;
    }
    double along(Rect r) => vertical ? (r.center.dy - from.center.dy).abs() : (r.center.dx - from.center.dx).abs();
    double across(Rect r) => vertical ? (r.center.dx - from.center.dx).abs() : (r.center.dy - from.center.dy).abs();
    candidates.sort((a, b) {
      final c = along(a.rect).compareTo(along(b.rect));
      return c != 0 ? c : across(a.rect).compareTo(across(b.rect));
    });
    final backward = direction == TraversalDirection.up || direction == TraversalDirection.left;
    requestFocusCallback(
      candidates.first,
      alignmentPolicy: backward ? ScrollPositionAlignmentPolicy.keepVisibleAtStart : ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
    );
    return true;
  }
}

/// A pane of glass that does nothing itself: a frame around content.
class GlassPanel extends StatelessWidget {
  const GlassPanel({
    super.key,
    required this.child,
    this.padding = EdgeInsets.zero,
    this.radius = cardRadius,
    this.color = glass,
    this.clip = false,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final Color color;

  /// Cut the content at the rounded corners (for a neck that fills the pane).
  final bool clip;

  @override
  Widget build(BuildContext context) {
    final box = Container(
      padding: padding,
      clipBehavior: clip ? Clip.antiAlias : Clip.none,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: glassBorder),
      ),
      child: child,
    );
    return box;
  }
}

/// The one big button on a screen (Play): a glowing pill in the accent
/// color, with the remote's white ring on top when it is selected.
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.onPressed,
    required this.icon,
    required this.label,
    this.autofocus = false,
    this.height = 60,
    this.iconSize = 32,
    this.fontSize = 20,
  });

  final VoidCallback? onPressed;
  final IconData icon;
  final String label;
  final bool autofocus;
  final double height;
  final double iconSize;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = scheme.primary;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(height),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color.lerp(accent, Colors.white, 0.18)!, accent, Color.lerp(accent, Colors.black, 0.12)!],
        ),
        boxShadow: [BoxShadow(color: accent.withValues(alpha: 0.35), blurRadius: 18, offset: const Offset(0, 6))],
      ),
      child: FilledButton.icon(
        autofocus: autofocus,
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: Colors.transparent,
          disabledBackgroundColor: Colors.transparent,
          foregroundColor: scheme.onPrimary,
          minimumSize: Size(64, height),
          shadowColor: Colors.transparent,
          textStyle: TextStyle(fontSize: fontSize, fontWeight: FontWeight.w800),
          padding: const EdgeInsets.symmetric(horizontal: 22),
        ),
        icon: Icon(icon, size: iconSize),
        label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
    );
  }
}

/// A small round badge with a finger number in that finger's color.
class FingerBadge extends StatelessWidget {
  const FingerBadge({super.key, required this.finger, required this.color, required this.textColor, this.size = 22});

  final int finger;
  final Color color;
  final Color textColor;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
        boxShadow: [BoxShadow(color: color.withValues(alpha: 0.5), blurRadius: 8)],
      ),
      child: Text('$finger', style: TextStyle(color: textColor, fontSize: size * 0.6, fontWeight: FontWeight.w900, height: 1)),
    );
  }
}

/// A round icon toggle with a label underneath, used in the player controls.
class LabeledToggle extends StatelessWidget {
  const LabeledToggle({
    super.key,
    required this.icon,
    required this.label,
    required this.selected,
    required this.onPressed,
    this.showLabel = true,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback? onPressed;

  /// Without the label the button is just the icon; the label stays as a tooltip.
  final bool showLabel;

  /// Width of the text under the icon (and so of the whole button).
  static const labelWidth = 76.0;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: label,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton.filledTonal(
            isSelected: selected,
            onPressed: onPressed,
            icon: Icon(icon),
            style: IconButton.styleFrom(
              backgroundColor: selected ? scheme.primary : glassHigh,
              foregroundColor: selected ? scheme.onPrimary : scheme.onSurface,
              disabledBackgroundColor: glassLow,
              disabledForegroundColor: Colors.white38,
            ),
          ),
          if (showLabel)
            // Every labeled button is the same width, so a long word shrinks
            // to fit instead of pushing the row off the screen.
            SizedBox(
              width: labelWidth,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: scheme.onSurfaceVariant), maxLines: 1),
              ),
            ),
        ],
      ),
    );
  }
}

/// A rounded strip behind a few related buttons, so they read as one group.
class ControlGroup extends StatelessWidget {
  const ControlGroup({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: glassLow,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: glassBorder),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Row(mainAxisSize: MainAxisSize.min, children: children),
      ),
    );
  }
}
