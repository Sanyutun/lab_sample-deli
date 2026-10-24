import 'package:flutter/foundation.dart';
import 'package:lab_commission_contract/lab_commission_contract.dart';

import '../data/api/companion_api.dart';
import '../data/repositories/companion_repository.dart';
import '../data/storage/session_store.dart';
import 'failure.dart';

/// Owns the signed-in delivery man. Only this controller writes the bearer
/// token; every screen reads the profile from here.
class AuthController extends ChangeNotifier {
  AuthController({
    required this.api,
    required this.sessions,
    required this.repository,
  });

  final CompanionApi api;
  final SessionStore sessions;
  final CompanionRepository repository;

  DeliveryManProfileDto? _profile;
  bool _restoring = true;

  DeliveryManProfileDto? get profile => _profile;
  bool get isLoggedIn => _profile != null;
  bool get isRestoring => _restoring;

  /// Restores a previous session on launch. A revoked/expired token signs the
  /// user out; an unreachable server falls back to the cached profile so the
  /// app still opens offline.
  Future<void> restore() async {
    _restoring = true;
    final token = await sessions.readToken();
    if (token == null || token.isEmpty) {
      _restoring = false;
      notifyListeners();
      return;
    }
    api.token = token;
    try {
      _profile = (await repository.profile()).value;
    } on UnauthorizedFailure {
      await _clearLocal();
    } on AppFailure {
      // Offline with nothing cached — treat as signed out for this launch.
      _profile = null;
    }
    _restoring = false;
    notifyListeners();
  }

  Future<void> login({required String loginId, required String pin}) async {
    final session = await api.login(loginId: loginId, pin: pin);
    api.token = session.token;
    await sessions.writeToken(session.token);
    _profile = session.profile;
    notifyListeners();
  }

  Future<void> logout() async {
    try {
      await api.logout();
    } on AppFailure {
      // Best effort: even if the server is unreachable, sign out locally.
    }
    await _clearLocal();
    notifyListeners();
  }

  Future<void> _clearLocal() async {
    api.token = null;
    await sessions.clear();
    await repository.wipeCache();
    _profile = null;
  }
}
