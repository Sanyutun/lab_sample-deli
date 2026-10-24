import '../../domain/exceptions.dart';
import '../../domain/ids.dart';
import '../models/models.dart';
import '../storage/app_storage.dart';

class DeliveryManRepository {
  DeliveryManRepository(this._storage);
  final AppStorage _storage;

  static const String _table = 'delivery_men';

  Future<DeliveryMan> create({
    required String name,
    String phone = '',
    bool active = true,
    bool requireQr = false,
  }) async {
    final man = DeliveryMan(
      id: newId('dm'),
      name: name,
      phone: phone,
      active: active,
      requireQr: requireQr,
      createdAt: nowMs(),
    );
    await _storage.insert(_table, man.toMap());
    return man;
  }

  Future<void> update(DeliveryMan man) async {
    await _storage.update(_table, {'id': man.id}, man.toMap());
  }

  Future<DeliveryMan?> findById(String id) async {
    final m = await _storage.findOne(_table, {'id': id});
    return m == null ? null : DeliveryMan.fromMap(m);
  }

  Future<DeliveryMan> requireActive(String id) async {
    final man = await findById(id);
    if (man == null) throw const NotFoundException('Delivery man not found');
    if (!man.active) {
      throw const ValidationException('Delivery man is inactive');
    }
    return man;
  }

  Future<List<DeliveryMan>> all({bool includeInactive = true}) async {
    final rows = await _storage.find(_table, orderBy: 'name');
    return rows
        .map(DeliveryMan.fromMap)
        .where((d) => includeInactive || d.active)
        .toList();
  }

  Future<List<DeliveryMan>> search(
    String query, {
    bool includeInactive = false,
  }) async {
    final q = query.trim().toLowerCase();
    final list = await all(includeInactive: includeInactive);
    if (q.isEmpty) return list;
    return list
        .where(
          (d) =>
              d.name.toLowerCase().contains(q) ||
              d.phone.toLowerCase().contains(q) ||
              d.id.toLowerCase().contains(q),
        )
        .toList();
  }
}
