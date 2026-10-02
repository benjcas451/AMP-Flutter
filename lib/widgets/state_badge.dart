import 'package:flutter/material.dart';

import '../api/models.dart';

class StateBadge extends StatelessWidget {
  const StateBadge(AppState this.state, {super.key});

  /// The AMP instance process itself is not running.
  const StateBadge.offline({super.key}) : state = null;

  final AppState? state;

  @override
  Widget build(BuildContext context) {
    final color = state?.color ?? Colors.grey;
    final label = state?.label ?? 'Instanz aus';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.circle, size: 10, color: color),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(color: color, fontSize: 12)),
        ],
      ),
    );
  }
}
