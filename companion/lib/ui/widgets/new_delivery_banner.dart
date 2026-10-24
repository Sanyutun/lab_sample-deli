import 'package:flutter/material.dart';

import '../../core/strings.dart';
import '../../data/services/delivery_watch.dart';

/// Announces deliveries the office has just recorded, with the amount, the time
/// and whether it is paid.
///
/// Shown inside the app because this phone has no push channel: it appears when
/// a refresh finds something new, which is the honest limit of what a read-only
/// app can do.
class NewDeliveryBanner extends StatelessWidget {
  const NewDeliveryBanner({
    super.key,
    required this.deliveries,
    required this.onViewBoard,
    required this.onDismiss,
  });

  final List<NewDelivery> deliveries;
  final VoidCallback onViewBoard;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    if (deliveries.isEmpty) return const SizedBox.shrink();
    final one = deliveries.length == 1;
    final first = deliveries.first;
    final paid = deliveries.every((d) => d.paid);
    final color = paid ? Colors.green.shade700 : Colors.orange.shade800;

    return Material(
      color: paid ? Colors.green.shade50 : Colors.orange.shade50,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              paid ? Icons.check_circle : Icons.notifications_active,
              color: color,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    one
                        ? S.newDeliveryTitle
                        : S.newDeliveriesTitle(deliveries.length),
                    style: TextStyle(fontWeight: FontWeight.bold, color: color),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    // One delivery is spelled out in full; several are summed,
                    // because a single line per delivery would flood the app.
                    one
                        ? S.newDeliveryBody(
                            first.amountLabel,
                            first.whenLabel,
                            first.statusLabel,
                          )
                        : S.newDeliveryBody(
                            _totalAmount(),
                            S.newDeliveriesTitle(deliveries.length),
                            paid ? S.badgePaid : S.badgeUnpaid,
                          ),
                    style: const TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ),
            TextButton(onPressed: onViewBoard, child: const Text(S.viewBoard)),
            IconButton(
              tooltip: S.dismiss,
              icon: const Icon(Icons.close, size: 18),
              onPressed: onDismiss,
            ),
          ],
        ),
      ),
    );
  }

  String _totalAmount() {
    final total = deliveries.fold<int>(0, (sum, d) => sum + d.commission);
    return NewDelivery(
      number: 0,
      commission: total,
      recordedAt: null,
      paid: false,
    ).amountLabel;
  }
}
