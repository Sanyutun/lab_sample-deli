import '../models/models.dart';
import '../storage/app_storage.dart';

/// Raw storage for the calls that reached the lab from delivery men.
class CallLogRepository {
  CallLogRepository(this._storage);
  final AppStorage _storage;

  static const String table = 'delivery_calls';

  Future<void> insert(DeliveryManCall call) =>
      _storage.insert(table, call.toMap());

  /// Newest first, optionally only one man's calls.
  Future<List<DeliveryManCall>> all({String? deliveryManId}) async {
    final rows = await _storage.find(table, orderBy: '-received_at');
    final list = rows.map(DeliveryManCall.fromMap).toList();
    if (deliveryManId == null) return list;
    return list.where((c) => c.deliveryManId == deliveryManId).toList();
  }
}
