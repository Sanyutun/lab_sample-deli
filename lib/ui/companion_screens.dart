import 'package:flutter/material.dart';
import 'package:lab_commission_contract/lab_commission_contract.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../companion/companion_api_server.dart';
import '../core/app_services.dart';
import '../data/models/models.dart';
import '../domain/exceptions.dart';
import 'common.dart';

/// Admin: register and control companion-app accounts for delivery men, and
/// revoke/rotate their QR identities.
class CompanionAccountsScreen extends StatefulWidget {
  const CompanionAccountsScreen({super.key});

  @override
  State<CompanionAccountsScreen> createState() =>
      _CompanionAccountsScreenState();
}

class _CompanionAccountsScreenState extends State<CompanionAccountsScreen> {
  List<DeliveryMan> _men = [];
  Map<String, DeliveryManAccount> _byMan = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final services = AppScope.of(context);
    final men = await services.deliveryMen.all();
    final accounts = await services.companion.allAccounts();
    if (!mounted) return;
    setState(() {
      _men = men;
      _byMan = {for (final a in accounts) a.deliveryManId: a};
      _loading = false;
    });
  }

  Future<void> _register(DeliveryMan man) async {
    final loginC = TextEditingController(text: man.id);
    final pinC = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Companion account · ${man.name}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: loginC,
              decoration: const InputDecoration(labelText: 'Login ID'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: pinC,
              obscureText: true,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'PIN (min 4 digits)',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Create'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await AppScope.of(context).companion.registerAccount(
        deliveryManId: man.id,
        loginId: loginC.text,
        pin: pinC.text,
      );
      if (!mounted) return;
      showMessage(context, 'Companion account created for ${man.name}');
      await _load();
    } on AppException catch (e) {
      if (mounted) showMessage(context, e.message, error: true);
    }
  }

  Future<void> _manage(DeliveryMan man, DeliveryManAccount account) async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(man.name),
              subtitle: Text('Login: ${account.loginId}'),
            ),
            SwitchListTile(
              title: const Text('Account active'),
              value: account.active,
              onChanged: (v) async {
                Navigator.pop(ctx);
                await AppScope.of(context).companion.setActive(account.id, v);
                if (mounted) await _load();
              },
            ),
            ListTile(
              leading: const Icon(Icons.password),
              title: const Text('Reset PIN'),
              onTap: () async {
                Navigator.pop(ctx);
                await _resetPin(account);
              },
            ),
            ListTile(
              leading: const Icon(Icons.qr_code_2),
              title: const Text('Revoke QR code'),
              subtitle: const Text(
                'The current code stops working immediately',
              ),
              onTap: () async {
                Navigator.pop(ctx);
                await AppScope.of(context).companion.revokeQr(account.id);
                if (mounted) {
                  showMessage(context, 'QR code revoked');
                  await _load();
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _resetPin(DeliveryManAccount account) async {
    final pinC = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reset PIN'),
        content: TextField(
          controller: pinC,
          obscureText: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'New PIN'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Reset'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await AppScope.of(context).companion.resetPin(account.id, pinC.text);
      if (mounted) {
        showMessage(context, 'PIN reset. The delivery man must sign in again.');
        await _load();
      }
    } on AppException catch (e) {
      if (mounted) showMessage(context, e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PageScaffold(
      title: 'Companion Accounts',
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _men.isEmpty
          ? const EmptyState(
              message:
                  'No delivery men yet.\nAdd one under Delivery Men first.',
            )
          : ListView.builder(
              itemCount: _men.length,
              itemBuilder: (ctx, i) {
                final man = _men[i];
                final account = _byMan[man.id];
                return ListTile(
                  leading: CircleAvatar(
                    child: Text(man.name.isEmpty ? '?' : man.name[0]),
                  ),
                  title: Text(man.name),
                  subtitle: Text(
                    account == null
                        ? 'No companion account'
                        : 'Login: ${account.loginId}'
                              '${account.active ? '' : ' · DEACTIVATED'}',
                  ),
                  trailing: Icon(
                    account == null ? Icons.add_circle_outline : Icons.tune,
                    color: account == null ? Colors.teal : Colors.grey,
                  ),
                  onTap: () =>
                      account == null ? _register(man) : _manage(man, account),
                );
              },
            ),
    );
  }
}

/// Admin: run the LAN server companion apps connect to.
class CompanionServerScreen extends StatefulWidget {
  const CompanionServerScreen({super.key});

  @override
  State<CompanionServerScreen> createState() => _CompanionServerScreenState();
}

class _CompanionServerScreenState extends State<CompanionServerScreen> {
  List<String> _addresses = [];
  String? _error;
  String? _officeKey;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    // The server may already be running (left on earlier, or auto-started at
    // launch), so show its address straight away.
    _refreshAddresses();
    _loadOfficeKey();
  }

  Future<void> _loadOfficeKey() async {
    final services = AppScope.of(context);
    if (!services.canHostServer) return;
    final key = await services.storeGateway.officeKey;
    if (!mounted) return;
    setState(() => _officeKey = key);
  }

  Future<void> _regenerateOfficeKey() async {
    final services = AppScope.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New link key?'),
        content: const Text(
          'Every office terminal connected with the old key will stop working '
          'until you enter the new key there.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Create new key'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final key = await services.storeGateway.regenerateOfficeKey();
    if (!mounted) return;
    setState(() => _officeKey = key);
  }

  Future<void> _refreshAddresses() async {
    if (!AppScope.of(context).companionServerRunning) return;
    final ips = await localServerAddresses();
    if (!mounted) return;
    setState(() => _addresses = ips);
  }

  Future<void> _toggle() async {
    setState(() => _busy = true);
    final services = AppScope.of(context);
    final enable = !services.companionServerRunning;
    try {
      await services.setCompanionServerEnabled(enable);
      if (!mounted) return;
      setState(() {
        _error = null;
        if (!enable) _addresses = [];
      });
      if (enable) await _refreshAddresses();
    } on Exception catch (e) {
      if (mounted) setState(() => _error = 'Could not start: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    final running = services.companionServerRunning;
    final port = services.companionServerPort;
    return PageScaffold(
      title: 'Companion Sync Server',
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (!services.canHostServer)
            const Card(
              color: Color(0xFFE0F2F1),
              child: Padding(
                padding: EdgeInsets.all(12),
                child: Text(
                  'This terminal is a client of another office server. It reads '
                  'and writes that server\'s data; the server itself is run on '
                  'the host terminal. Change this in the login screen under '
                  '"Server".',
                ),
              ),
            )
          else ...[
            Card(
              child: SwitchListTile(
                title: const Text('Server running'),
                subtitle: Text(
                  running
                      ? 'Companion apps can connect on this network. '
                            'Stays on until you switch it off.'
                      : 'Off — no companion app can reach the office data',
                ),
                value: running,
                onChanged: _busy ? null : (_) => _toggle(),
              ),
            ),
            if (running) ...[
              const SectionTitle('Connect from the companion app'),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Port: $port'),
                      const SizedBox(height: 4),
                      const Text(
                        'If the other device cannot connect, allow this app '
                        'through the computer firewall and keep both devices on '
                        'the same Wi-Fi.',
                        style: TextStyle(fontSize: 12),
                      ),
                      const SizedBox(height: 8),
                      if (_addresses.isEmpty)
                        const Text(
                          'No Wi-Fi address found. Connect this device to the '
                          'office Wi-Fi/VPN, then toggle the server again.',
                        )
                      else
                        for (final ip in _addresses) ...[
                          SelectableText(
                            'http://$ip:$port',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontFamily: 'monospace',
                            ),
                          ),
                          const SizedBox(height: 8),
                          Center(
                            child: QrImageView(
                              data: 'http://$ip:$port',
                              version: QrVersions.auto,
                              size: 180,
                              backgroundColor: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Delivery man: open the companion app, tap the '
                            'server address and choose "Scan QR".',
                            style: TextStyle(fontSize: 12),
                          ),
                          const SizedBox(height: 16),
                        ],
                    ],
                  ),
                ),
              ),
            ],
            const SectionTitle('Connect another office terminal'),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'On the other office terminal: login screen → "Server" → '
                      'enter the address above and this key.',
                    ),
                    const SizedBox(height: 12),
                    SelectableText(
                      _officeKey ?? '—',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontFamily: 'monospace',
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Whoever has this key can read and change the office '
                      'data. Treat it like a password and keep it off the '
                      'public network.',
                      style: TextStyle(fontSize: 12),
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: _busy ? null : _regenerateOfficeKey,
                        icon: const Icon(Icons.refresh, size: 18),
                        label: const Text('New key'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          if (_error != null)
            Card(
              color: Colors.red.shade50,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(_error!),
              ),
            ),
          const SectionTitle('GPS tracking policy'),
          const _GpsPolicySection(),
          const SectionTitle('How it stays safe'),
          const Card(
            child: Padding(
              padding: EdgeInsets.all(12),
              child: Text(
                '• Delivery men sign in with their own ID and PIN.\n'
                '• Each request is authorised here; a delivery man only ever '
                'sees their own deliveries, commission and rewards.\n'
                '• The companion app cannot change commissions, payments or '
                'rewards — there is no such endpoint.\n'
                '• QR codes are opaque and can be revoked from Companion '
                'Accounts.',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Admin: the office-wide GPS policy every companion phone follows. Phones pick
/// the saved values up the next time they sign in.
class _GpsPolicySection extends StatefulWidget {
  const _GpsPolicySection();

  @override
  State<_GpsPolicySection> createState() => _GpsPolicySectionState();
}

class _GpsPolicySectionState extends State<_GpsPolicySection> {
  int? _interval;
  int? _retention;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final policy = await AppScope.of(context).companion.gpsPolicy();
    if (!mounted) return;
    setState(() {
      _interval = policy.intervalMinutes;
      _retention = policy.retentionMinutes;
      _loading = false;
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await AppScope.of(context).companion.saveGpsPolicy(
        GpsPolicyDto(
          intervalMinutes: _interval!,
          retentionMinutes: _retention!,
        ),
      );
      if (mounted) showMessage(context, 'GPS policy saved');
    } on AppException catch (e) {
      if (mounted) showMessage(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const SizedBox.shrink();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Applies to every companion phone the next time the delivery man '
              'signs in. It does not change the office window used for a '
              'delivery route.',
              style: TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              initialValue: _interval,
              decoration: const InputDecoration(
                labelText: 'Capture a fix every',
              ),
              items: [
                for (final m in GpsPolicyDto.intervalOptions)
                  DropdownMenuItem(value: m, child: Text(_minutes(m))),
              ],
              onChanged: (v) => setState(() => _interval = v),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              initialValue: _retention,
              decoration: const InputDecoration(
                labelText: 'Keep sent fixes on the phone for',
              ),
              items: [
                for (final m in GpsPolicyDto.retentionOptions)
                  DropdownMenuItem(value: m, child: Text(_minutes(m))),
              ],
              onChanged: (v) => setState(() => _retention = v),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: const Text('SAVE GPS POLICY'),
            ),
          ],
        ),
      ),
    );
  }

  static String _minutes(int m) {
    if (m >= 1440 && m % 1440 == 0) return '${m ~/ 1440} days';
    return m == 1 ? '1 minute' : '$m minutes';
  }
}
