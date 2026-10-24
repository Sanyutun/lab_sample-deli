import 'dart:async';

import 'package:lab_commission_contract/lab_commission_contract.dart';
import 'package:lab_delivery_companion/core/app_services.dart';
import 'package:lab_delivery_companion/core/app_config.dart';
import 'package:lab_delivery_companion/core/auth_controller.dart';
import 'package:lab_delivery_companion/core/failure.dart';
import 'package:lab_delivery_companion/data/api/companion_api.dart';
import 'package:lab_delivery_companion/data/repositories/companion_repository.dart';
import 'package:lab_delivery_companion/data/services/delivery_watch.dart';
import 'package:lab_delivery_companion/data/services/location_service.dart';
import 'package:lab_delivery_companion/data/services/tracking_service.dart';
import 'package:lab_delivery_companion/data/storage/cache_store.dart';
import 'package:lab_delivery_companion/data/storage/config_store.dart';
import 'package:lab_delivery_companion/data/storage/location_queue.dart';
import 'package:lab_delivery_companion/data/storage/seen_store.dart';
import 'package:lab_delivery_companion/data/storage/session_store.dart';

/// In-memory companion API. Every data method records its name in [calls] and
/// throws [failure] when set, so a test can simulate the office server being
/// unreachable or a revoked session without any network.
class FakeApi implements CompanionApi {
  @override
  String? token;

  final List<String> calls = [];

  /// Thrown by every read method when set.
  AppFailure? failure;

  /// Thrown by [login] when set.
  AppFailure? loginFailure;

  DeliveryManProfileDto profile = const DeliveryManProfileDto(
    id: 'm1',
    name: 'Ko Aung',
    phone: '09991234567',
  );

  SummaryDto summaryValue = const SummaryDto(
    successfulDeliveries: 0,
    commissionEarned: 0,
    commissionPaid: 0,
    unpaidCommission: 0,
    rewardsEarned: 0,
    rewardsPaid: 0,
    unpaidRewards: 0,
  );

  List<CommissionDto> commissionList = [];
  CommissionDto? commissionValue;
  List<RewardDto> rewardsList = [];
  DeliveryBoardDto deliveryBoardValue = const DeliveryBoardDto(
    summary: BoardSummaryDto(
      successfulDeliveries: 0,
      totalSlots: 2000,
      commissionEarned: 0,
      commissionPaid: 0,
      unpaidCommission: 0,
      rewardsEarned: 0,
      rewardsPaid: 0,
      unpaidBalance: 0,
    ),
    groups: [],
    slotsPerGroup: 10,
    totalSlots: 2000,
  );
  QrIdentityDto qrValue = const QrIdentityDto(payload: 'lc1:abc', issuedAt: 0);
  GpsPolicyDto gpsPolicyValue = GpsPolicyDto.standard;
  List<GeoPointDto> locationsList = [];
  final List<GeoPointDto> recordedLocations = [];

  void _check() {
    final f = failure;
    if (f != null) throw f;
  }

  @override
  Future<AuthSessionDto> login({
    required String loginId,
    required String pin,
  }) async {
    calls.add('login');
    final f = loginFailure;
    if (f != null) throw f;
    return AuthSessionDto(
      token: 'session-token',
      expiresAt: DateTime.now().millisecondsSinceEpoch + 100000,
      profile: profile,
    );
  }

  @override
  Future<void> logout() async {
    calls.add('logout');
  }

  @override
  Future<DeliveryManProfileDto> me() async {
    calls.add('me');
    _check();
    return profile;
  }

  @override
  Future<SummaryDto> summary() async {
    calls.add('summary');
    _check();
    return summaryValue;
  }

  @override
  Future<List<CommissionDto>> commissions({
    String? from,
    String? to,
    String? status,
  }) async {
    calls.add('commissions:$from:$to:$status');
    _check();
    return commissionList;
  }

  @override
  Future<CommissionDto> commission(String id) async {
    calls.add('commission:$id');
    _check();
    final value = commissionValue;
    if (value == null) throw const ApiFailure('not_found', 'not found');
    return value;
  }

  @override
  Future<List<RewardDto>> rewards() async {
    calls.add('rewards');
    _check();
    return rewardsList;
  }

  @override
  Future<DeliveryBoardDto> deliveryBoard() async {
    calls.add('deliveryBoard');
    _check();
    return deliveryBoardValue;
  }

  @override
  Future<QrIdentityDto> qr() async {
    calls.add('qr');
    _check();
    return qrValue;
  }

  @override
  Future<GpsPolicyDto> gpsPolicy() async {
    calls.add('gpsPolicy');
    _check();
    return gpsPolicyValue;
  }

  @override
  Future<List<GeoPointDto>> locations() async {
    calls.add('locations');
    _check();
    return locationsList;
  }

  @override
  Future<GeoPointDto> recordLocation({
    required double latitude,
    required double longitude,
    double? accuracyM,
    int? capturedAt,
    String? barcode,
    String? clientId,
  }) async {
    calls.add('recordLocation');
    _check();
    final point = GeoPointDto(
      id: 'geo${recordedLocations.length + 1}',
      latitude: latitude,
      longitude: longitude,
      accuracyM: accuracyM,
      capturedAt: capturedAt ?? DateTime.now().millisecondsSinceEpoch,
      barcode: barcode,
      clientId: clientId,
    );
    recordedLocations.add(point);
    locationsList = [...locationsList, point];
    return point;
  }
}

/// Location service whose permission, fix and stream are fixed by the test.
class FakeLocationService implements LocationService {
  FakeLocationService({
    this.access = LocationAccess.granted,
    this.batteryIgnored = true,
  });

  LocationAccess access;
  AppFailure? fixFailure;
  Fix? fix = const Fix(
    latitude: 16.8409,
    longitude: 96.1735,
    capturedAt: 0,
    accuracyM: 7.5,
  );

  int accessRequests = 0;
  int fixRequests = 0;
  int settingsOpened = 0;
  int notificationRequests = 0;
  int batteryRequests = 0;

  /// What [isBatteryOptimizationIgnored] reports. False means Android may kill
  /// background tracking, which the Location tab tells the user about.
  bool batteryIgnored;

  /// Feeds [positionStream]; a test adds a fix with [emit].
  final StreamController<Fix> _positions = StreamController<Fix>.broadcast();

  /// The interval the tracking service asked the stream to use.
  Duration? requestedInterval;

  void emit(Fix fix) => _positions.add(fix);

  @override
  Future<LocationAccess> requestAccess() async {
    accessRequests++;
    return access;
  }

  @override
  Future<Fix> currentFix() async {
    fixRequests++;
    final f = fixFailure;
    if (f != null) throw f;
    return fix!;
  }

  @override
  Stream<Fix> positionStream(Duration interval) {
    requestedInterval = interval;
    return _positions.stream;
  }

  @override
  Future<void> openAppSettings() async => settingsOpened++;

  @override
  Future<bool> isBatteryOptimizationIgnored() async => batteryIgnored;

  @override
  Future<void> requestIgnoreBatteryOptimization() async => batteryRequests++;

  @override
  Future<void> requestNotificationPermission() async {
    notificationRequests++;
  }
}

/// Builds a fully faked service graph for widget and unit tests.
class TestHarness {
  TestHarness({FakeLocationService? location, MemoryLocationQueue? queue})
    : api = FakeApi(),
      cache = MemoryCacheStore(),
      sessions = MemorySessionStore(),
      configStore = MemoryConfigStore(),
      queue = queue ?? MemoryLocationQueue(),
      location = location ?? FakeLocationService() {
    repository = CompanionRepository(api: api, cache: cache);
    auth = AuthController(api: api, sessions: sessions, repository: repository);
    config = AppConfig(configStore);
    tracking = TrackingService(
      location: this.location,
      queue: this.queue,
      repository: repository,
      syncInterval: const Duration(days: 1),
    );
    auth.addListener(() => tracking.onSignedInChanged(auth.isLoggedIn));
    watch = DeliveryWatch(repository: repository, store: MemorySeenStore());
  }

  final FakeApi api;
  final MemoryCacheStore cache;
  final MemorySessionStore sessions;
  final MemoryConfigStore configStore;
  final MemoryLocationQueue queue;
  final FakeLocationService location;
  late final CompanionRepository repository;
  late final AuthController auth;
  late final AppConfig config;
  late final TrackingService tracking;
  late final DeliveryWatch watch;

  AppServices get services => AppServices(
    api: api,
    repository: repository,
    auth: auth,
    location: location,
    config: config,
    queue: queue,
    tracking: tracking,
    watch: watch,
  );
}
