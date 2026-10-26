import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import 'calls/incoming_calls.dart';
import 'core/app_services.dart';
import 'core/office_link.dart';
import 'data/models/models.dart';
import 'data/storage/http_storage.dart';
import 'data/storage/sqlite_storage.dart';
import 'print/app_window.dart';
import 'print/print_spool_watcher.dart';
import 'ui/dashboard_screen.dart';
import 'ui/login_screen.dart';
import 'ui/office_link_dialog.dart';
import 'ui/scan_flow.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // A client terminal must keep reading from the office server after a restart,
  // not silently fall back to its own empty database.
  final link = await OfficeLink.load();
  runApp(
    LabCommissionApp(
      link: link,
      loader: openServices,
      printWatcher: officeSpoolWatcher,
    ),
  );
}

/// Opens the app on this device's database, or on another office terminal's
/// database when a [link] has been configured.
Future<AppServices> openServices(OfficeLink? link) async {
  final remote = link != null && link.isConfigured;
  final storage = remote
      ? HttpStorage(baseUrl: link.url, key: link.key)
      : await SqliteStorage.open();
  return AppServices.bootstrap(
    storage,
    canHostServer: !remote,
    sessionScope: remote ? link.terminalId : '',
  );
}

class LabCommissionApp extends StatefulWidget {
  const LabCommissionApp({
    super.key,
    this.services,
    this.loader,
    this.link,
    this.printWatcher,
  });

  /// Pre-wired services. Tests use this; production passes [loader].
  final AppServices? services;

  /// Builds the services for a link on startup and after a link change.
  final Future<AppServices> Function(OfficeLink? link)? loader;

  /// Where the services came from. Null means "this device".
  final OfficeLink? link;

  /// Handed in by main() (the shared [officeSpoolWatcher]) and by tests (a
  /// fake); detection is off when null.
  final PrintSpoolWatcher? printWatcher;

  @override
  State<LabCommissionApp> createState() => _LabCommissionAppState();
}

class _LabCommissionAppState extends State<LabCommissionApp> {
  AppServices? _services;
  late OfficeLink _link;
  Object? _error;
  final _navigatorKey = GlobalKey<NavigatorState>();
  StreamSubscription<PrintedInvoice>? _printSubscription;
  StreamSubscription<Map<String, Object?>>? _callSubscription;

  /// Watching runs only when a watcher is handed in — main() passes the
  /// shared [officeSpoolWatcher], tests a fake. Widget tests without one must
  /// never watch, because polling the real spool folder does file I/O and
  /// leaves timers pending in the fake-async test zone.
  bool get _watchPrintsEnabled => widget.printWatcher != null;

  @override
  void initState() {
    super.initState();
    _services = widget.services;
    _link = widget.link ?? OfficeLink.local;
    if (_services == null) {
      _load(_link);
    } else {
      _watchPrints();
      _watchCalls();
    }
  }

  Future<void> _load(OfficeLink link) async {
    final loader = widget.loader;
    if (loader == null) return;
    _printSubscription?.cancel();
    setState(() {
      _error = null;
      _services = null;
      // Remember the address being tried, so a failed reconnect shows (and
      // pre-fills) the new server instead of the old one.
      _link = link;
    });
    try {
      final services = await loader(link.isConfigured ? link : null);
      if (!mounted) return;
      setState(() {
        _services = services;
      });
      _watchPrints();
      _watchCalls();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _services = null;
      });
    }
  }

  /// Opens the delivery flow for every printed receipt, wherever the user is
  /// in the app: the terminal is usually busy with something else when the
  /// receipt prints, so the window pops up and goes straight to the flow.
  void _watchPrints() {
    if (!Platform.isWindows || !_watchPrintsEnabled) return;
    final watcher = widget.printWatcher!;
    _printSubscription?.cancel();
    _printSubscription = watcher.invoices.listen((printed) {
      final services = _services;
      if (services == null) return;
      // Keep what the receipt printed even when nobody is logged in: the
      // board and history screens show it later by barcode.
      unawaited(
        services.printedReceipts
            .save(
              PrintedReceipt(
                barcode: printed.invoice,
                patient: printed.name ?? '',
                ageSex: printed.ageSex ?? '',
                refer: printed.refer ?? '',
                receiptDate: printed.date ?? '',
                totalAmount: printed.totalAmount ?? '',
                detectedAt: DateTime.now().millisecondsSinceEpoch,
              ),
            )
            .catchError((Object _) {}),
      );
      // Nothing to record against when logged out; the flow would fail at
      // the confirm step anyway.
      if (!services.auth.isLoggedIn) return;
      bringAppWindowToFront();
      _navigatorKey.currentState?.push(
        MaterialPageRoute(
          builder: (_) => SelectDeliveryManScreen(
            barcode: printed.invoice,
            receipt: printed,
          ),
        ),
      );
    });
    watcher.start();
  }

  /// On Android, logs every call that rings the lab from a registered delivery
  /// man's number. The permission dialog comes up once at start; refused, the
  /// events simply carry no number and nothing is recorded.
  void _watchCalls() {
    if (!Platform.isAndroid) return;
    unawaited(IncomingCalls.requestPermission());
    _callSubscription?.cancel();
    _callSubscription = IncomingCalls.events.listen(
      (event) {
        final services = _services;
        final number = event['number'] as String?;
        final at = event['at'] as int?;
        if (services == null || number == null || at == null) return;
        unawaited(
          services.callLog.recordIncoming(
            number: number,
            at: at,
            answered: event['answered'] == true,
          ),
        );
      },
      // A channel that never came up must not take the app down.
      onError: (Object _) {},
    );
  }

  @override
  void dispose() {
    _printSubscription?.cancel();
    _callSubscription?.cancel();
    super.dispose();
  }

  /// Remembers the new link and rebuilds the services against it.
  Future<void> _reconnect(OfficeLink link) async {
    if (link.isConfigured) {
      final saved = await OfficeLink.save(link);
      await _load(saved);
    } else {
      await OfficeLink.clear();
      await _load(OfficeLink.local);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return _ConnectionErrorApp(
        link: _link,
        error: _error!,
        onRetry: () => _load(_link),
        onReconnect: _reconnect,
      );
    }
    final services = _services;
    if (services == null) {
      return const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(body: Center(child: CircularProgressIndicator())),
      );
    }
    return AppScope(
      services: services,
      child: MaterialApp(
        title: 'TWOK Sample Deli - Office',
        navigatorKey: _navigatorKey,
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
          useMaterial3: true,
        ),
        // A remembered session (restored during bootstrap) lands on the
        // dashboard; otherwise ask for the PIN.
        home: services.auth.isLoggedIn
            ? DashboardScreen(
                userName: services.auth.currentUser!.name,
                isAdmin: services.auth.isAdmin,
              )
            : LoginScreen(link: _link, onReconnect: _reconnect),
      ),
    );
  }
}

/// Shown when the app cannot open its data — usually a wrong or unreachable
/// office server. Without this the app would die before drawing anything.
class _ConnectionErrorApp extends StatelessWidget {
  const _ConnectionErrorApp({
    required this.link,
    required this.error,
    required this.onRetry,
    required this.onReconnect,
  });

  final OfficeLink link;
  final Object error;
  final Future<void> Function() onRetry;
  final Future<void> Function(OfficeLink) onReconnect;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        useMaterial3: true,
      ),
      home: Builder(
        // The dialog needs a context below MaterialApp's Navigator; using the
        // builder's own context made "Server settings" do nothing on Android.
        builder: (context) => Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.cloud_off, size: 48, color: Colors.grey),
                  const SizedBox(height: 16),
                  Text(
                    'Cannot open the office data',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Text('$error', textAlign: TextAlign.center),
                  if (link.isConfigured)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        'Server: ${link.url}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  const SizedBox(height: 24),
                  Wrap(
                    spacing: 12,
                    children: [
                      FilledButton.icon(
                        onPressed: onRetry,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Retry'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () async {
                          final chosen = await showOfficeLinkDialog(
                            context,
                            link,
                          );
                          if (chosen != null) await onReconnect(chosen);
                        },
                        icon: const Icon(Icons.dns),
                        label: const Text('Server settings'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
