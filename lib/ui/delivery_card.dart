import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../data/models/models.dart';
import '../domain/delivery_board.dart';

/// The card used across the delivery board to represent a single slot.
///
/// For an earned delivery the card shows whether the commission is already
/// PAID or still UNPAID; empty positions stay blank. Shared by the delivery
/// board grid and the delivery success screen so both show the exact same card.
class DeliverySlotCard extends StatelessWidget {
  const DeliverySlotCard({super.key, required this.slot, this.onTap});

  final DeliverySlot slot;
  final VoidCallback? onTap;

  bool get _isPaid => slot.record?.paymentStatus == PaymentStatus.paid;

  @override
  Widget build(BuildContext context) {
    final (bg, border, fg) = _style();
    final borderColor = slot.milestoneAmount != null
        ? Colors.amber.shade700
        : border;
    final borderWidth = slot.milestoneAmount != null ? 2.0 : 1.0;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Ink(
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: borderColor, width: borderWidth),
          ),
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 3),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Flexible(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          slot.number.toString().padLeft(2, '0'),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: fg,
                          ),
                        ),
                      ),
                    ),
                    Flexible(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: _statusBadge(fg),
                      ),
                    ),
                    Flexible(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          _amountLabel(),
                          maxLines: 1,
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w600,
                            color: fg,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (slot.milestoneAmount != null)
                Positioned(
                  bottom: 1,
                  right: 1,
                  child: Icon(
                    Icons.emoji_events,
                    size: 12,
                    color: Colors.amber.shade700,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// Paid shows a check mark, earned-but-unpaid an hourglass, empty nothing.
  /// A reversed slot keeps its previous (paid/unpaid) icon.
  Widget _statusBadge(Color fg) {
    if (slot.state == DeliverySlotState.empty) {
      return const SizedBox.shrink();
    }
    final icon = _isPaid ? Icons.check_circle : Icons.hourglass_bottom;
    final label = slot.state == DeliverySlotState.reversed
        ? 'REV'
        : (_isPaid ? 'PAID' : 'UNPAID');
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: fg),
        const SizedBox(width: 2),
        Text(
          label,
          maxLines: 1,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.3,
            color: fg,
          ),
        ),
      ],
    );
  }

  String _amountLabel() {
    switch (slot.state) {
      case DeliverySlotState.empty:
      case DeliverySlotState.reversed:
        return '';
      case DeliverySlotState.pending:
      case DeliverySlotState.successful:
        return NumberFormat('#,###').format(slot.commission);
    }
  }

  (Color bg, Color border, Color fg) _style() {
    if (slot.state == DeliverySlotState.empty) {
      return (Colors.grey.shade100, Colors.grey.shade300, Colors.grey.shade500);
    }
    if (slot.state == DeliverySlotState.reversed) {
      return (Colors.red.shade50, Colors.red.shade200, Colors.red.shade400);
    }
    if (_isPaid) {
      return (
        Colors.green.shade50,
        Colors.green.shade400,
        Colors.green.shade800,
      );
    }
    return (Colors.amber.shade50, Colors.amber.shade600, Colors.amber.shade900);
  }
}
