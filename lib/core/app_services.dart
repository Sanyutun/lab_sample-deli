import 'package:flutter/widgets.dart';

import '../companion/companion_api_server.dart';
import '../companion/store_gateway.dart';
import '../data/repositories/audit_repository.dart';
import '../data/repositories/cash_repository.dart';
import '../data/repositories/call_log_repository.dart';
import '../data/repositories/commission_repository.dart';
import '../data/repositories/companion_account_repository.dart';
import '../data/repositories/daily_pin_repository.dart';
import '../data/repositories/delivery_man_repository.dart';
import '../data/repositories/location_repository.dart';
import '../data/repositories/milestone_repository.dart';
import '../data/repositories/printed_receipt_repository.dart';
import '../data/repositories/receipt_repository.dart';
import '../data/repositories/settings_repository.dart';
import '../data/repositories/trip_repository.dart';
import '../data/repositories/user_repository.dart';
import '../data/storage/app_storage.dart';
import '../domain/exceptions.dart';
import '../domain/services/audit_service.dart';
import '../domain/services/auth_service.dart';
import '../domain/services/call_log_service.dart';
import '../domain/services/cash_service.dart';
import '../domain/services/companion_service.dart';
import '../domain/services/daily_pin_service.dart';
import '../domain/services/delivery_service.dart';
import '../domain/services/finance_service.dart';
import '../domain/services/google_sheets_service.dart';
import '../domain/services/reconciliation_service.dart';
import '../domain/services/trip_service.dart';

/// Composition root: repositories + services for the whole app.
class AppServices {
  AppServices._({
    required this.storage,
    required this.users,
    required this.deliveryMen,
    required this.commissions,
    required this.dailyPins,
    required this.milestones,
    required this.cash,
    required this.receipts,
    required this.printedReceipts,
    required this.auditRepo,
    required this.callLogRepo,
    required this.settings,
    required this.companionAccounts,
    required this.locations,
    required this.tripsRepo,
    required this.auth,
    required this.audit,
    required this.delivery,
    required this.cashService,
    required this.finance,
    required this.reconciliation,
    required this.sheets,
    required this.companion,
    required this.trips,
    required this.callLog,
    required this.companionServer,
    required this.storeGateway,
    required this.canHostServer,
  });

  final AppStorage storage;
  final UserRepository users;
  final DeliveryManRepository deliveryMen;
  final CommissionRepository commissions;
  final DailyPinService dailyPins;
  final MilestoneRepository milestones;
  final CashRepository cash;
  final ReceiptRepository receipts;
  final PrintedReceiptRepository printedReceipts;
  final AuditRepository auditRepo;
  final SettingsRepository settings;
  final CompanionAccountRepository companionAccounts;
  final LocationRepository locations;
  final TripRepository tripsRepo;
  final CallLogRepository callLogRepo;

  final AuthService auth;
  final AuditService audit;
  final DeliveryService delivery;
  final CashService cashService;
  final FinanceService finance;
  final ReconciliationService reconciliation;
  final GoogleSheetsService sheets;
  final CompanionService companion;
  final TripService trips;

  /// Incoming calls from delivery men, matched against their phone numbers.
  final CallLogService callLog;

  /// The LAN server companion apps connect to. Owned here, not by a screen, so
  /// it keeps running while the app is open once it has been started.
  final CompanionApiServer companionServer;

  /// Office-to-office data gateway used by the companion server.
  final StoreGateway storeGateway;

  /// False when this terminal is a *client* of another office terminal, so it
  /// must not run its own server — the host does that.
  final bool canHostServer;

  /// Setting that remembers whether the server was left running, so it starts
  /// again on the next launch.
  static const String _companionServerKey = 'companion.serverEnabled';

  bool get companionServerRunning => companionServer.isRunning;
  int? get companionServerPort => companionServer.boundPort;

  /// Starts or stops the LAN server and remembers the choice. A failed start
  /// (e.g. the port is in use) throws before anything is saved.
  Future<void> setCompanionServerEnabled(bool enabled) async {
    if (!canHostServer) {
      throw const ValidationException(
        'This terminal uses another office server. Run the server on the host '
        'terminal.',
      );
    }
    if (enabled) {
      await companionServer.start();
    } else {
      await companionServer.stop();
    }
    await settings.set(_companionServerKey, enabled ? '1' : '0');
  }

  static Future<AppServices> bootstrap(
    AppStorage storage, {
    int companionPort = 8787,
    bool canHostServer = true,
    String sessionScope = '',
  }) async {
    await storage.init();

    final users = UserRepository(storage);
    final deliveryMen = DeliveryManRepository(storage);
    final commissions = CommissionRepository(storage);
    final dailyPinRepo = DailyPinRepository(storage);
    final milestones = MilestoneRepository(storage);
    final cash = CashRepository(storage);
    final receipts = ReceiptRepository(storage);
    final printedReceipts = PrintedReceiptRepository(storage);
    final auditRepo = AuditRepository(storage);
    final settings = SettingsRepository(storage);
    final companionAccounts = CompanionAccountRepository(storage);
    final locations = LocationRepository(storage);
    final tripsRepo = TripRepository(storage);
    final callLogRepo = CallLogRepository(storage);

    await users.seedDefaults();
    await commissions.seedRules();
    await milestones.seedRules();

    final auth = AuthService(users, settings, sessionScope: sessionScope);
    await auth.restore();
    final audit = AuditService(auditRepo, auth);
    final cashService = CashService(
      cash: cash,
      commissions: commissions,
      milestones: milestones,
      audit: audit,
    );
    final trips = TripService(
      locations: locations,
      trips: tripsRepo,
      commissions: commissions,
    );
    final delivery = DeliveryService(
      commissions: commissions,
      deliveryMen: deliveryMen,
      milestones: milestones,
      audit: audit,
      cash: cashService,
      trips: trips,
    );
    final finance = FinanceService(
      cash: cash,
      commissions: commissions,
      milestones: milestones,
      deliveryMen: deliveryMen,
      audit: audit,
    );
    final reconciliation = ReconciliationService(
      receipts: receipts,
      commissions: commissions,
      deliveryMen: deliveryMen,
      audit: audit,
    );
    await cashService.repairMissingCommissionPayments();
    final sheetsConfig = await _loadSheetsConfig(settings);
    final sheets = GoogleSheetsService(
      storage: storage,
      commissions: commissions,
      receipts: receipts,
      audit: audit,
      client: _buildSheetsClient(sheetsConfig),
      config: sheetsConfig,
    );
    final dailyPins = DailyPinService(
      dailyPinRepo,
      users,
      settings,
      sheets,
      audit,
    );
    await dailyPins.ensureToday();
    final companion = CompanionService(
      accounts: companionAccounts,
      locations: locations,
      trips: trips,
      commissions: commissions,
      milestones: milestones,
      deliveryMen: deliveryMen,
      cash: cash,
      receipts: receipts,
      audit: audit,
      settings: settings,
    );
    final gateway = StoreGateway(storage, settings);
    final callLog = CallLogService(
      calls: callLogRepo,
      deliveryMen: deliveryMen,
    );
    final companionServer = CompanionApiServer(
      service: companion,
      gateway: gateway,
      port: companionPort,
    );
    // Start of day: drop raw fixes left over from a previous run that are
    // already past the retention window.
    await trips.purgeOldRawFixes();
    if (canHostServer) {
      // A host always has a key ready for office clients. Generated once.
      await gateway.ensureOfficeKey();
      // Bring the sync server back up if it was left running last time. A
      // failure (e.g. the port is busy) leaves it off; the admin screen
      // reports it.
      if (await settings.get(_companionServerKey) == '1') {
        try {
          await companionServer.start();
        } on Exception {
          // Leave it stopped.
        }
      }
    }

    return AppServices._(
      storage: storage,
      users: users,
      deliveryMen: deliveryMen,
      commissions: commissions,
      dailyPins: dailyPins,
      milestones: milestones,
      cash: cash,
      receipts: receipts,
      printedReceipts: printedReceipts,
      auditRepo: auditRepo,
      callLogRepo: callLogRepo,
      settings: settings,
      companionAccounts: companionAccounts,
      locations: locations,
      tripsRepo: tripsRepo,
      auth: auth,
      audit: audit,
      delivery: delivery,
      cashService: cashService,
      finance: finance,
      reconciliation: reconciliation,
      sheets: sheets,
      companion: companion,
      trips: trips,
      callLog: callLog,
      companionServer: companionServer,
      storeGateway: gateway,
      canHostServer: canHostServer,
    );
  }

  static Future<GoogleSheetsConfig> _loadSheetsConfig(
    SettingsRepository settings,
  ) async {
    return GoogleSheetsConfig(
      spreadsheetId: await settings.get('sheets.spreadsheetId') ?? '',
      sheetName: await settings.get('sheets.sheetName') ?? 'CommissionRecords',
      reconciliationSheetName:
          await settings.get('sheets.reconSheetName') ?? 'Reconciliation',
      serviceAccountJson: await settings.get('sheets.serviceAccountJson') ?? '',
    );
  }

  static SheetsClient _buildSheetsClient(GoogleSheetsConfig config) {
    if (config.isConfigured) {
      return ServiceAccountSheetsClient(
        serviceAccountJson: config.serviceAccountJson,
      );
    }
    return UnconfiguredSheetsClient();
  }

  Future<void> saveSheetsConfig(GoogleSheetsConfig config) async {
    final oldClient = sheets.client;
    sheets.config = config;
    sheets.client = _buildSheetsClient(config);
    if (oldClient is ServiceAccountSheetsClient && oldClient != sheets.client) {
      oldClient.close();
    }
    await settings.set('sheets.spreadsheetId', config.spreadsheetId);
    await settings.set('sheets.sheetName', config.sheetName);
    await settings.set('sheets.reconSheetName', config.reconciliationSheetName);
    await settings.set('sheets.serviceAccountJson', config.serviceAccountJson);
  }
}

class AppScope extends InheritedWidget {
  const AppScope({super.key, required this.services, required super.child});

  final AppServices services;

  static AppServices of(BuildContext context) {
    final scope = context.getInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope not found in widget tree');
    return scope!.services;
  }

  @override
  bool updateShouldNotify(AppScope oldWidget) => services != oldWidget.services;
}
