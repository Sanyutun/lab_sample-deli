// ignore_for_file: use_build_context_synchronously

import 'package:flutter/material.dart';

import '../core/app_services.dart';
import '../data/models/models.dart';
import 'call_log_screen.dart';
import 'common.dart';

class DeliveryManManagementScreen extends StatefulWidget {
  const DeliveryManManagementScreen({super.key});

  @override
  State<DeliveryManManagementScreen> createState() =>
      _DeliveryManManagementScreenState();
}

class _DeliveryManManagementScreenState
    extends State<DeliveryManManagementScreen> {
  List<DeliveryMan> _men = [];
  Map<String, DeliveryManCall> _latestCalls = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final services = AppScope.of(context);
    final men = await services.deliveryMen.all();
    final latestCalls = await services.callLog.latestByMan();
    if (!mounted) return;
    setState(() {
      _men = men;
      _latestCalls = latestCalls;
      _loading = false;
    });
  }

  Future<void> _add() async {
    final result = await _editDialog();
    if (result == null) return;
    if (result.name.isEmpty) {
      showMessage(context, 'Name is required', error: true);
      return;
    }
    final services = AppScope.of(context);
    final created = await services.deliveryMen.create(
      name: result.name,
      phone: result.phone,
      active: result.active,
      requireQr: result.requireQr,
    );
    await services.audit.record(
      'DELIVERY_MAN_CREATED',
      refId: created.id,
      newValue: '${created.name} active=${created.active}',
    );
    _load();
  }

  Future<void> _edit(DeliveryMan man) async {
    final result = await _editDialog(
      name: man.name,
      phone: man.phone,
      active: man.active,
      requireQr: man.requireQr,
    );
    if (result == null) return;
    if (result.name.isEmpty) {
      showMessage(context, 'Name is required', error: true);
      return;
    }
    final services = AppScope.of(context);
    final updated = DeliveryMan(
      id: man.id,
      name: result.name,
      phone: result.phone,
      active: result.active,
      requireQr: result.requireQr,
      createdAt: man.createdAt,
    );
    await services.deliveryMen.update(updated);
    await services.audit.record(
      'DELIVERY_MAN_UPDATED',
      refId: man.id,
      oldValue: '${man.name} active=${man.active}',
      newValue: '${updated.name} active=${updated.active}',
    );
    _load();
  }

  Future<_ManForm?> _editDialog({
    String name = '',
    String phone = '',
    bool active = true,
    bool requireQr = false,
  }) async {
    final nameC = TextEditingController(text: name);
    final phoneC = TextEditingController(text: phone);
    var isActive = active;
    var needsQr = requireQr;
    final result = await showDialog<_ManForm>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text(name.isEmpty ? 'Add Delivery Man' : 'Edit Delivery Man'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameC,
                decoration: const InputDecoration(labelText: 'Name'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: phoneC,
                decoration: const InputDecoration(labelText: 'Phone'),
              ),
              const SizedBox(height: 8),
              CheckboxListTile(
                title: const Text('Active'),
                value: isActive,
                onChanged: (v) => setState(() => isActive = v ?? true),
              ),
              CheckboxListTile(
                title: const Text('Require QR scan'),
                subtitle: const Text(
                  'Must be picked by scanning; by hand needs an admin PIN',
                  style: TextStyle(fontSize: 12),
                ),
                value: needsQr,
                onChanged: (v) => setState(() => needsQr = v ?? false),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(
                ctx,
                _ManForm(
                  nameC.text.trim(),
                  phoneC.text.trim(),
                  isActive,
                  needsQr,
                ),
              ),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    return result;
  }

  /// Phone and id, plus the man's latest call to the lab when there was one.
  String _subtitle(DeliveryMan man) {
    final base = '${man.phone} · ${man.id}';
    final last = _latestCalls[man.id];
    if (last == null) return base;
    final state = last.answered ? 'answered' : 'missed';
    return '$base\nLast call ${fmtDate(last.receivedAt)} · $state';
  }

  @override
  Widget build(BuildContext context) {
    return PageScaffold(
      title: 'Delivery Man Management',
      floatingActionButton: FloatingActionButton(
        onPressed: _add,
        child: const Icon(Icons.add),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _men.isEmpty
          ? const EmptyState(message: 'No delivery men yet. Tap + to add.')
          : ListView.builder(
              itemCount: _men.length,
              itemBuilder: (ctx, i) {
                final man = _men[i];
                return ListTile(
                  leading: CircleAvatar(
                    child: Text(man.name.isEmpty ? '?' : man.name[0]),
                  ),
                  title: Text(man.name),
                  subtitle: Text(_subtitle(man)),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (man.requireQr)
                        const Icon(
                          Icons.qr_code_2,
                          size: 20,
                          color: Colors.teal,
                        ),
                      if (!man.active)
                        const Chip(
                          label: Text(
                            'INACTIVE',
                            style: TextStyle(fontSize: 11),
                          ),
                          backgroundColor: Colors.grey,
                        ),
                      IconButton(
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => CallLogScreen(
                              deliveryManId: man.id,
                            ),
                          ),
                        ),
                        icon: const Icon(Icons.call),
                        tooltip: 'Call history',
                      ),
                      IconButton(
                        onPressed: () => _edit(man),
                        icon: const Icon(Icons.edit),
                      ),
                    ],
                  ),
                  onTap: () => _edit(man),
                );
              },
            ),
    );
  }
}

class _ManForm {
  const _ManForm(this.name, this.phone, this.active, this.requireQr);
  final String name;
  final String phone;
  final bool active;
  final bool requireQr;
}
