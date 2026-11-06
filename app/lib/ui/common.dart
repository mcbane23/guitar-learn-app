import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
/// when selected with a TV remote.
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
  });

  final Widget child;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final Color? color;
  final double? width;
  final double? height;
  final bool autofocus;

  @override
  State<FocusCard> createState() => _FocusCardState();
}

class _FocusCardState extends State<FocusCard> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AnimatedScale(
      scale: _focused ? 1.06 : 1,
      duration: const Duration(milliseconds: 120),
      child: SizedBox(
        width: widget.width,
        height: widget.height,
        child: Material(
          color: widget.color ?? scheme.surfaceContainerHigh,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: BorderSide(color: _focused ? Colors.white : Colors.transparent, width: 3),
          ),
          child: InkWell(
            autofocus: widget.autofocus,
            onTap: widget.onTap,
            onLongPress: widget.onLongPress,
            onFocusChange: (f) => setState(() => _focused = f),
            child: widget.child,
          ),
        ),
      ),
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
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback? onPressed;

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
              backgroundColor: selected ? scheme.primary : null,
              foregroundColor: selected ? scheme.onPrimary : null,
            ),
          ),
          Text(label, style: const TextStyle(fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }
}
