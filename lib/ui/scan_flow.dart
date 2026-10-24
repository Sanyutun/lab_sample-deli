import 'dart:io';

import 'package:flutter/material.dart';
import 'package:lab_commission_contract/lab_commission_contract.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../core/app_services.dart';
import '../data/models/models.dart';
import '../domain/delivery_board.dart';
import '../domain/exceptions.dart';
import '../print/print_spool_watcher.dart';
import 'common.dart';
import 'delivery_card.dart';
import 'print_monitor_screen.dart';
import 'trip_history_screen.dart';

/// Step 1 — fast barcode capture. No OCR, no receipt amount entry.
class ScanReceiptScreen extends StatefulWidget {
  const ScanReceiptScreen({super.key});

  @override
  State<ScanReceiptScreen> createState() => _ScanReceiptScreenState();
}

class _ScanReceiptScreenState extends State<ScanReceiptScreen> {
  bool _handled = false;

  void _onDetect(String code) {
    if (_handled) return;
    _handled = true;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => SelectDeliveryManScreen(barcode: code)),
    );
  }

  Future<void> _manualEntry() async {
    final controller = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Enter receipt barcode'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textInputAction: TextInputAction.done,
          decoration: const InputDecoration(
            hintText: 'e.g. 100125',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('OK'),
          ),
        ],
      ),
    );
    if (code != null && code.isNotEmpty && mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => SelectDeliveryManScreen(barcode: code),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scan Receipt')),
      body: Column(
        children: [
          Expanded(
            child: MobileScanner(
              onDetect: (capture) {
                final code = capture.barcodes.isNotEmpty
                    ? capture.barcodes.first.rawValue
                    : null;
                if (code != null && code.isNotEmpty) _onDetect(code);
              },
            ),
          ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            color: Colors.black87,
            child: SafeArea(
              top: false,
              child: Column(
                children: [
                  const Text(
                    'Point the camera at the receipt barcode',
                    style: TextStyle(color: Colors.white70),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      FilledButton.icon(
                        onPressed: _manualEntry,
                        icon: const Icon(Icons.keyboard),
                        label: const Text('Enter barcode manually'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Step 1b — scan the delivery man's personal QR from their companion app.
/// The code carries only an opaque token, verified against the shared backend
/// before it can be used on a receipt.
class ScanDeliveryManQrScreen extends StatefulWidget {
  const ScanDeliveryManQrScreen({super.key});

  @override
  State<ScanDeliveryManQrScreen> createState() =>
      _ScanDeliveryManQrScreenState();
}

class _ScanDeliveryManQrScreenState extends State<ScanDeliveryManQrScreen> {
  bool _handled = false;

  Future<void> _handle(String payload) async {
    if (_handled) return;
    _handled = true;
    final services = AppScope.of(context);
    final token = tokenFromQrPayload(payload);
    if (token == null) {
      _fail('That QR is not a delivery-man code.');
      return;
    }
    final profile = await services.companion.verifyQr(token);
    if (profile == null) {
      _fail('QR code is unknown or has been revoked.');
      return;
    }
    final man = await services.deliveryMen.findById(profile.id);
    if (man == null || !man.active) {
      _fail('This delivery man is no longer active.');
      return;
    }
    if (!mounted) return;
    Navigator.pop(context, man);
  }

  void _fail(String message) {
    if (!mounted) return;
    showMessage(context, message, error: true);
    setState(() => _handled = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scan Delivery Man QR')),
      body: Column(
        children: [
          Expanded(
            child: MobileScanner(
              onDetect: (capture) {
                final code = capture.barcodes.isNotEmpty
                    ? capture.barcodes.first.rawValue
                    : null;
                if (code != null && code.isNotEmpty) _handle(code);
              },
            ),
          ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            color: Colors.black87,
            child: const SafeArea(
              top: false,
              child: Text(
                'Point the camera at the QR code shown in the '
                'delivery man\'s companion app.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Step 2 — searchable delivery-man picker (active only for staff).
class SelectDeliveryManScreen extends StatefulWidget {
  const SelectDeliveryManScreen({
    super.key,
    required this.barcode,
    this.receipt,
  });

  final String barcode;

  /// The printed receipt's fields (name, refer, …) when the flow started from
  /// a print job; null on the phone's scan path.
  final PrintedInvoice? receipt;

  @override
  State<SelectDeliveryManScreen> createState() =>
      _SelectDeliveryManScreenState();
}

class _SelectDeliveryManScreenState extends State<SelectDeliveryManScreen> {
  List<DeliveryMan> _men = [];
  Map<String, DeliveryManCall> _lastCalls = {};
  String _query = '';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final services = AppScope.of(context);
    final men = await services.deliveryMen.search(
      _query,
      includeInactive: services.auth.isAdmin,
    );
    final lastCalls = await services.callLog.latestByMan();
    if (!mounted) return;
    setState(() {
      _men = men;
      _lastCalls = lastCalls;
      _loading = false;
    });
  }

  Future<void> _scanQr() async {
    final man = await Navigator.push<DeliveryMan>(
      context,
      MaterialPageRoute(builder: (_) => const ScanDeliveryManQrScreen()),
    );
    if (man == null || !mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SelectCommissionScreen(
          barcode: widget.barcode,
          deliveryMan: man,
          receipt: widget.receipt,
        ),
      ),
    );
  }

  /// Picks [man] for this receipt. A "require QR" man cannot be chosen by hand;
  /// an admin PIN unlocks the manual path.
  Future<void> _pick(DeliveryMan man) async {
    if (man.requireQr && !await _askAdminPin(man)) return;
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SelectCommissionScreen(
          barcode: widget.barcode,
          deliveryMan: man,
          receipt: widget.receipt,
        ),
      ),
    );
  }

  Future<bool> _askAdminPin(DeliveryMan man) => askAdminPin(
    context,
    title: '${man.name} must be scanned',
    reason:
        'This delivery man is only picked by scanning their QR code. '
        'To choose without scanning, enter an admin PIN.',
  );

  @override
  Widget build(BuildContext context) {
    final activeMen = _men.where((m) => m.active).toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Select Delivery Man'),
        actions: [
          IconButton(
            icon: const Icon(Icons.qr_code_scanner),
            tooltip: 'Scan delivery-man QR',
            onPressed: _scanQr,
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            color: Colors.teal.shade50,
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.qr_code),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Receipt: ${widget.barcode}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
                if (widget.receipt != null)
                  ...receiptFieldLines(widget.receipt!),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Search name or phone',
                border: OutlineInputBorder(),
              ),
              onChanged: (v) {
                _query = v;
                _load();
              },
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : activeMen.isEmpty
                ? const EmptyState(
                    message: 'No active delivery men found.\nAsk admin to register one.',
                  )
                : ListView.builder(
                    itemCount: activeMen.length,
                    itemBuilder: (ctx, i) {
                      final man = activeMen[i];
                      return ListTile(
                        leading: CircleAvatar(
                          child: Text(man.name.isEmpty ? '?' : man.name[0]),
                        ),
                        title: Text(man.name),
                        subtitle: Text(_subtitle(man)),
                        trailing: Icon(
                          man.requireQr ? Icons.qr_code_2 : Icons.chevron_right,
                        ),
                        onTap: () => _pick(man),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  /// What the staff member sees while choosing: the man's phone (and QR
  /// rule), plus his latest call to the lab — the sign that he rang to say he
  /// sent a patient in.
  String _subtitle(DeliveryMan man) {
    final base = man.requireQr ? '${man.phone} · QR scan required' : man.phone;
    final last = _lastCalls[man.id];
    if (last == null) return base;
    return '$base · last call ${fmtDate(last.receivedAt)}';
  }
}

/// Step 3 — direct commission selection: 1,000 / 2,000 / 3,000 (configurable).
class SelectCommissionScreen extends StatefulWidget {
  const SelectCommissionScreen({
    super.key,
    required this.barcode,
    required this.deliveryMan,
    this.receipt,
  });

  final String barcode;
  final DeliveryMan deliveryMan;

  /// The printed receipt's fields when the flow started from a print job.
  final PrintedInvoice? receipt;

  @override
  State<SelectCommissionScreen> createState() => _SelectCommissionScreenState();
}

class _SelectCommissionScreenState extends State<SelectCommissionScreen> {
  List<int> _amounts = [];
  int? _selected;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final commissions = AppScope.of(context).commissions;
    final amounts = await commissions.selectableAmounts();
    // A printed receipt carries its total, and the rule set in admin settings
    // already decides what that total earns: pre-select that amount so the
    // staff member only confirms it — or taps another when they know better.
    var selected = _selected;
    final total = _totalAmount(widget.receipt?.totalAmount);
    if (total != null) {
      final expected = await commissions.expectedCommission(total);
      if (expected != null && amounts.contains(expected)) selected = expected;
    }
    if (!mounted) return;
    setState(() {
      _amounts = amounts;
      _selected = selected;
    });
  }

  /// Receipt totals print as `75,000 MMK` or `104000`; the digits are the
  /// amount. Null when the job carried no total — then nothing is guessed.
  static int? _totalAmount(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    return int.tryParse(raw.replaceAll(RegExp('[^0-9]'), ''));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Select Commission')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              child: ListTile(
                title: Text(
                  widget.deliveryMan.name,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Text('Receipt ${widget.barcode}'),
                leading: const Icon(Icons.person),
              ),
            ),
            if (widget.receipt != null)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: receiptFieldLines(widget.receipt!),
                  ),
                ),
              ),
            const SizedBox(height: 24),
            Text(
              'Commission amount',
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final amount in _amounts)
                  SizedBox(
                    width: 150,
                    height: 72,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: _selected == amount
                            ? Colors.teal
                            : Colors.teal.shade100,
                        foregroundColor: _selected == amount
                            ? Colors.white
                            : Colors.teal.shade900,
                        textStyle: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      onPressed: () => setState(() => _selected = amount),
                      child: Text(NumberFormatAmount.format(amount)),
                    ),
                  ),
              ],
            ),
            const Spacer(),
            FilledButton(
              style: FilledButton.styleFrom(padding: const EdgeInsets.all(16)),
              onPressed: _selected == null
                  ? null
                  : () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ConfirmDeliveryScreen(
                          barcode: widget.barcode,
                          deliveryMan: widget.deliveryMan,
                          commission: _selected!,
                          receipt: widget.receipt,
                        ),
                      ),
                    ),
              child: const Text('CONTINUE', style: TextStyle(fontSize: 18)),
            ),
          ],
        ),
      ),
    );
  }
}

class NumberFormatAmount {
  static String format(int amount) {
    final s = amount.toString();
    final b = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
      b.write(s[i]);
    }
    return b.toString();
  }
}

/// Step 4 — confirm and save the transaction.
class ConfirmDeliveryScreen extends StatefulWidget {
  const ConfirmDeliveryScreen({
    super.key,
    required this.barcode,
    required this.deliveryMan,
    required this.commission,
    this.receipt,
  });

  final String barcode;
  final DeliveryMan deliveryMan;
  final int commission;

  /// The printed receipt's fields when the flow started from a print job.
  final PrintedInvoice? receipt;

  @override
  State<ConfirmDeliveryScreen> createState() => _ConfirmDeliveryScreenState();
}

class _ConfirmDeliveryScreenState extends State<ConfirmDeliveryScreen> {
  bool _saving = false;

  Future<void> _confirm() async {
    setState(() => _saving = true);
    final services = AppScope.of(context);
    try {
      final result = await services.delivery.recordCommission(
        barcode: widget.barcode,
        deliveryManId: widget.deliveryMan.id,
        commission: widget.commission,
        staffUserId: services.auth.requireUser().id,
      );
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => DeliverySuccessScreen(
            record: result.record,
            rewards: result.rewards,
            deliveryManName: widget.deliveryMan.name,
          ),
        ),
      );
    } on DuplicateBarcodeException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Receipt already recorded'),
          content: Text(e.message),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    } on AppException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      showMessage(context, e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Confirm Delivery')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.qr_code),
                    title: const Text('Receipt barcode'),
                    trailing: Text(
                      widget.barcode,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  ListTile(
                    leading: const Icon(Icons.person),
                    title: const Text('Delivery man'),
                    trailing: Text(
                      widget.deliveryMan.name,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  ListTile(
                    leading: const Icon(Icons.payments),
                    title: const Text('Commission'),
                    trailing: Text(
                      fmtMMK(widget.commission),
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                        color: Colors.teal,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (widget.receipt != null) ...[
              const SizedBox(height: 8),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: receiptFieldLines(widget.receipt!),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 8),
            Text(
              'No receipt amount required — verified later by official export.',
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
            const Spacer(),
            FilledButton.icon(
              style: FilledButton.styleFrom(padding: const EdgeInsets.all(16)),
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check_circle),
              label: Text(
                _saving ? 'Saving…' : 'CONFIRM SUCCESSFUL DELIVERY',
                style: const TextStyle(fontSize: 16),
              ),
              onPressed: _saving ? null : _confirm,
            ),
          ],
        ),
      ),
    );
  }
}

class DeliverySuccessScreen extends StatefulWidget {
  const DeliverySuccessScreen({
    super.key,
    required this.record,
    required this.rewards,
    required this.deliveryManName,
  });

  final CommissionRecord record;
  final List<MilestoneReward> rewards;
  final String deliveryManName;

  @override
  State<DeliverySuccessScreen> createState() => _DeliverySuccessScreenState();
}

class _DeliverySuccessScreenState extends State<DeliverySuccessScreen> {
  DeliverySlot? _slot;
  DeliveryGroup? _group;

  /// The milestone rewards this delivery earned, kept live so paying or
  /// un-paying one here shows its new status immediately.
  late List<MilestoneReward> _rewards;

  @override
  void initState() {
    super.initState();
    _rewards = widget.rewards;
    _resolveSlot();
  }

  /// Finds the board position and its group for the just-recorded delivery so
  /// the whole group of 10 cards can be shown here, matching the board.
  Future<void> _resolveSlot() async {
    final services = AppScope.of(context);
    final records = await services.commissions.all(
      deliveryManId: widget.record.deliveryManId,
    );
    final board = DeliveryBoard.from(records: records, rewards: const []);
    DeliverySlot? foundSlot;
    DeliveryGroup? foundGroup;
    for (final group in board.groups) {
      for (final slot in group.slots) {
        if (slot.record?.id == widget.record.id) {
          foundSlot = slot;
          foundGroup = group;
          break;
        }
      }
      if (foundSlot != null) break;
    }
    if (!mounted) return;
    setState(() {
      _slot = foundSlot;
      _group = foundGroup;
    });
  }

  /// Tapping this delivery's card toggles its payment status (paid <-> unpaid).
  /// Un-paying needs today's PIN: it puts money back into the cash box.
  Future<void> _togglePayment(DeliverySlot slot) async {
    final record = slot.record;
    if (record == null || !record.isActive) return;
    final name = widget.deliveryManName;
    if (!record.isPaid) {
      if (!await confirmMarkPaid(
        context,
        label: '$name · commission',
        amount: record.commission,
      )) {
        return;
      }
    } else if (!await askDailyPin(
      context,
      reason:
          'Take back the ${fmtMMK(record.commission)} commission '
          'paid to $name?',
    )) {
      return;
    }
    if (!mounted) return;
    final services = AppScope.of(context);
    final user = services.auth.currentUser;
    if (user == null) return;
    try {
      await services.delivery.togglePaymentStatus(
        recordId: record.id,
        staffUserId: user.id,
      );
      if (!mounted) return;
      await _resolveSlot();
    } on Exception catch (e) {
      if (!mounted) return;
      showMessage(context, e.toString(), error: true);
    }
  }

  /// Pays or un-pays a milestone reward earned by this delivery, right here
  /// on the "delivery recorded" screen; the cash ledger follows either way.
  Future<void> _toggleReward(MilestoneReward reward) async {
    final paying = !reward.isPaid;
    final name = widget.deliveryManName;
    if (paying) {
      if (!await confirmMarkPaid(
        context,
        label: '$name · milestone reward',
        amount: reward.rewardAmount,
      )) {
        return;
      }
    } else if (!await askDailyPin(
      context,
      reason:
          'Take back the ${fmtMMK(reward.rewardAmount)} milestone '
          'reward paid to $name?',
    )) {
      return;
    }
    if (!mounted) return;
    final services = AppScope.of(context);
    final user = services.auth.currentUser;
    if (user == null) return;
    try {
      if (paying) {
        await services.cashService.payMilestoneReward(
          rewardId: reward.id,
          staffUserId: user.id,
        );
      } else {
        await services.cashService.unpayMilestoneReward(
          rewardId: reward.id,
          byUserId: user.id,
        );
      }
      final fresh = await services.milestones.findReward(reward.id);
      if (!mounted) return;
      if (fresh != null) {
        setState(() {
          _rewards = [for (final r in _rewards) r.id == fresh.id ? fresh : r];
        });
      }
      showMessage(
        context,
        paying
            ? 'Reward paid (-${fmtMMK(reward.rewardAmount)})'
            : 'Reward un-paid (+${fmtMMK(reward.rewardAmount)})',
      );
    } on AppException catch (e) {
      if (!mounted) return;
      showMessage(context, e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final record = widget.record;
    final group = _group;
    final slot = _slot;
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 8),
              const Icon(Icons.check_circle, color: Colors.green, size: 72),
              const SizedBox(height: 12),
              Text(
                'Delivery Recorded',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 20),
              if (group != null && slot != null)
                _GroupPreview(
                  group: group,
                  highlightNumber: slot.number,
                  onCardTap: _togglePayment,
                )
              else
                const SizedBox(
                  height: 120,
                  child: Center(child: CircularProgressIndicator()),
                ),
              const SizedBox(height: 16),
              _CommissionCard(record: record),
              const SizedBox(height: 12),
              Card(
                child: Column(
                  children: [
                    ListTile(
                      title: const Text('Receipt'),
                      trailing: Text(
                        record.barcode,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    ListTile(
                      title: const Text('Delivery man'),
                      trailing: Text(
                        widget.deliveryManName,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    ListTile(
                      title: const Text('Time'),
                      trailing: Text(
                        record.dateTimeLocal,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ),
              if (_rewards.isNotEmpty) ...[
                const SizedBox(height: 12),
                for (final r in _rewards)
                  Card(
                    color: Colors.amber.shade100,
                    child: ListTile(
                      leading: const Icon(Icons.emoji_events),
                      title: Text('Milestone reached: ${r.everyN} deliveries!'),
                      subtitle: Text(
                        'Reward ${fmtMMK(r.rewardAmount)} earned'
                        '${r.isPaid ? ' · paid' : ' · unpaid'}',
                      ),
                      trailing: TextButton(
                        onPressed: () => _toggleReward(r),
                        child: Text(r.isPaid ? 'UNPAY' : 'PAY'),
                      ),
                    ),
                  ),
              ],
              const SizedBox(height: 20),
              OutlinedButton.icon(
                icon: const Icon(Icons.route),
                label: const Text('VIEW TRIP (LAST 20 MIN)'),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => TripHistoryScreen(
                      barcode: record.barcode,
                      deliveryManName: widget.deliveryManName,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.all(16),
                ),
                icon: Icon(
                  Platform.isWindows ? Icons.print : Icons.qr_code_scanner,
                ),
                label: Text(
                  Platform.isWindows
                      ? 'BACK TO PRINT MONITOR'
                      : 'SCAN NEXT RECEIPT',
                  style: const TextStyle(fontSize: 16),
                ),
                onPressed: () => Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(
                    builder: (_) => Platform.isWindows
                        ? const PrintMonitorScreen()
                        : const ScanReceiptScreen(),
                  ),
                  (route) => route.isFirst,
                ),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: () => Navigator.popUntil(context, (r) => r.isFirst),
                child: const Text('Back to dashboard'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Prominent green commission card shown right after a delivery is recorded.
class _CommissionCard extends StatelessWidget {
  const _CommissionCard({required this.record});

  final CommissionRecord record;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      color: Colors.green.shade50,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.green.shade400, width: 2),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: const [
                Icon(Icons.check_circle, color: Colors.green, size: 20),
                SizedBox(width: 8),
                Text(
                  'SUCCESSFUL DELIVERY',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.green,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Commission earned',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                fmtMMK(record.commission),
                style: TextStyle(
                  fontSize: 34,
                  fontWeight: FontWeight.bold,
                  color: Colors.green.shade800,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Receipt ${record.barcode}',
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: Colors.black54),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shows all 10 cards of the group the just-recorded delivery landed in,
/// laid out 5-per-row like the board, with the new delivery highlighted.
class _GroupPreview extends StatelessWidget {
  const _GroupPreview({
    required this.group,
    required this.highlightNumber,
    required this.onCardTap,
  });

  final DeliveryGroup group;
  final int highlightNumber;
  final void Function(DeliverySlot slot) onCardTap;

  @override
  Widget build(BuildContext context) {
    final slots = group.slots;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Group ${group.groupNumber}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                Text(
                  '${slots.first.number} – ${slots.last.number}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'This delivery is card $highlightNumber · tap this card to toggle paid / unpaid',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 10),
            LayoutBuilder(
              builder: (context, constraints) {
                const gap = 6.0;
                final cardWidth = (constraints.maxWidth - gap * 4) / 5;
                final cardHeight = cardWidth * 1.12;
                final rows = <Widget>[];
                for (var start = 0; start < slots.length; start += 5) {
                  final end = (start + 5).clamp(0, slots.length);
                  if (rows.isNotEmpty) rows.add(const SizedBox(height: 6));
                  rows.add(
                    _buildRow(
                      slots.sublist(start, end),
                      cardWidth,
                      cardHeight,
                      gap,
                    ),
                  );
                }
                return Column(children: rows);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRow(
    List<DeliverySlot> slots,
    double width,
    double height,
    double gap,
  ) {
    final children = <Widget>[];
    for (var i = 0; i < slots.length; i++) {
      if (i > 0) children.add(SizedBox(width: gap));
      children.add(
        SizedBox(width: width, height: height, child: _card(slots[i])),
      );
    }
    return Row(children: children);
  }

  Widget _card(DeliverySlot slot) {
    final isTarget = slot.number == highlightNumber;
    final card = DeliverySlotCard(
      slot: slot,
      onTap: isTarget ? () => onCardTap(slot) : null,
    );
    if (!isTarget) return card;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.teal, width: 2.5),
      ),
      child: card,
    );
  }
}
