import 'package:flutter/widgets.dart';

import '../data/api/companion_api.dart';
import '../data/api/http_companion_api.dart';
import '../data/repositories/companion_repository.dart';
import '../data/services/delivery_watch.dart';
import '../data/services/location_service.dart';
import '../data/services/tracking_service.dart';
import '../data/storage/cache_store.dart';
import '../data/storage/config_store.dart';
import '../data/storage/location_queue.dart';
import '../data/storage/seen_store.dart';
import '../data/storage/session_store.dart';
import 'app_config.dart';
import 'auth_controller.dart';

/// Composition root: the single place the app decides which concrete services
/// to use. Tests build one with fakes instead.
class AppServices {
  const AppServices({
    required this.api,
    required this.repository,
    required this.auth,
    required this.location,
    required this.config,
    required this.queue,
    required this.tracking,
    required this.watch,
  });

  final CompanionApi api;
  final CompanionRepository repository;
  final AuthController auth;
  final LocationService location;
  final AppConfig config;
  final LocationQueue queue;
  final TrackingService tracking;
  final DeliveryWatch watch;

  static Future<AppServices> bootstrap() async {
    final config = AppConfig(PrefsConfigStore());
    await config.load();

    final api = HttpCompanionApi(baseUrlProvider: () => config.serverUrl);
    final repository = CompanionRepository(api: api, cache: PrefsCacheStore());
    final auth = AuthController(
      api: api,
      sessions: SecureSessionStore(),
      repository: repository,
    );
    await auth.restore();

    final queue = SqliteLocationQueue();
    await queue.init();
    final tracking = TrackingService(
      location: const GeolocatorLocationService(),
      queue: queue,
      repository: repository,
    );
    final watch = DeliveryWatch(
      repository: repository,
      store: PrefsSeenStore(),
    );

    // Location tracking follows sign-in: it starts when the man is signed in
    // and stops when he signs out. The new-delivery watch is cleared on
    // sign-out so the next man never sees the previous man's deliveries.
    auth.addListener(() {
      tracking.onSignedInChanged(auth.isLoggedIn);
      if (!auth.isLoggedIn) watch.reset();
    });
    await tracking.onSignedInChanged(auth.isLoggedIn);

    return AppServices(
      api: api,
      repository: repository,
      auth: auth,
      location: const GeolocatorLocationService(),
      config: config,
      queue: queue,
      tracking: tracking,
      watch: watch,
    );
  }
}

class AppScope extends InheritedWidget {
  const AppScope({super.key, required this.services, required super.child});

  final AppServices services;

  static AppServices of(BuildContext context) {
    final scope = context.getInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope not found in the widget tree');
    return scope!.services;
  }

  @override
  bool updateShouldNotify(AppScope oldWidget) => services != oldWidget.services;
}
