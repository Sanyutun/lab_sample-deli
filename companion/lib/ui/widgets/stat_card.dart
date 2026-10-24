import 'package:flutter/material.dart';

import '../../core/formatters.dart';

/// One dashboard figure. Monetary values always render as MMK.
class StatCard extends StatelessWidget {
  const StatCard({
    super.key,
    required this.label,
    this.value,
    this.amount,
    this.color,
    this.icon,
  });

  final String label;
  final String? value;

  /// When set, shown as MMK in the given colour.
  final int? amount;
  final Color? color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final text = amount != null ? fmtMMK(amount!) : (value ?? '—');
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 16, color: color ?? Colors.teal),
                  const SizedBox(width: 6),
                ],
                Expanded(
                  child: Text(
                    label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                text,
                style: Theme.of(context).textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold, color: color),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
