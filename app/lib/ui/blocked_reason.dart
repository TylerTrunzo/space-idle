import 'package:material_ui/material_ui.dart';
import 'package:space_idle/theme.dart';

/// Why an action cannot happen now, such as "needs 5K credits (you have
/// 250)": a lock icon and the reason in amber, so the state is never
/// told by colour alone.
class BlockedReason extends StatelessWidget {
  /// Creates the line for [reason].
  const BlockedReason(this.reason, {super.key});

  /// The reason, as the view model gives it.
  final String reason;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.lock_outline, size: 16, color: Palette.amber),
        const SizedBox(width: 6),
        Expanded(
          child: Text(reason, style: const TextStyle(color: Palette.amber)),
        ),
      ],
    ),
  );
}
