import '../../domain/exceptions.dart';
import '../../domain/ids.dart';
import '../models/models.dart';
import '../storage/app_storage.dart';

class MilestoneRepository {
  MilestoneRepository(this._storage);
  final AppStorage _storage;

  static const String rulesTable = 'milestone_rules';
  static const String rewardsTable = 'milestone_rewards';

  Future<void> seedRules() async {
    if ((await rules()).isEmpty) {
      await addRule(everyN: 10, rewardAmount: 4000);
      await addRule(everyN: 150, rewardAmount: 150000);
    }
  }

  Future<MilestoneRule> addRule({
    required int everyN,
    required int rewardAmount,
  }) async {
    final rule = MilestoneRule(
      id: newId('mrule'),
      everyN: everyN,
      rewardAmount: rewardAmount,
    );
    await _storage.insert(rulesTable, rule.toMap());
    return rule;
  }

  Future<List<MilestoneRule>> rules({bool activeOnly = false}) async {
    final rows = await _storage.find(rulesTable, orderBy: 'every_n');
    final list = rows.map(MilestoneRule.fromMap).toList();
    return activeOnly ? list.where((r) => r.active).toList() : list;
  }

  /// Rejects a rule the reward engine cannot use: it computes
  /// `deliveryCount % everyN`, so the count must be positive, and a reward is
  /// money, so the amount must be too.
  Future<void> updateRule(MilestoneRule rule) async {
    if (rule.everyN < 1) {
      throw const ValidationException('Every N deliveries must be 1 or more');
    }
    if (rule.rewardAmount < 1) {
      throw const ValidationException('Reward amount must be 1 MMK or more');
    }
    await _storage.update(rulesTable, {'id': rule.id}, rule.toMap());
  }

  Future<bool> rewardExists(
    String deliveryManId,
    int everyN,
    int milestoneCount,
  ) async {
    final rows = await _storage.find(
      rewardsTable,
      where: {
        'delivery_man_id': deliveryManId,
        'every_n': everyN,
        'milestone_count': milestoneCount,
      },
    );
    return rows.isNotEmpty;
  }

  Future<void> insertReward(MilestoneReward reward) async {
    await _storage.insert(rewardsTable, reward.toMap());
  }

  Future<void> updateReward(MilestoneReward reward) async {
    await _storage.update(rewardsTable, {'id': reward.id}, reward.toMap());
  }

  Future<MilestoneReward?> findReward(String id) async {
    final m = await _storage.findOne(rewardsTable, {'id': id});
    return m == null ? null : MilestoneReward.fromMap(m);
  }

  Future<List<MilestoneReward>> rewards({
    String? deliveryManId,
    PaymentStatus? paymentStatus,
  }) async {
    final rows = await _storage.find(rewardsTable, orderBy: '-created_at');
    var list = rows.map(MilestoneReward.fromMap).toList();
    if (deliveryManId != null) {
      list = list.where((r) => r.deliveryManId == deliveryManId).toList();
    }
    if (paymentStatus != null) {
      list = list.where((r) => r.paymentStatus == paymentStatus).toList();
    }
    return list;
  }

  Future<int> rewardCountFor(String deliveryManId) async =>
      (await rewards(deliveryManId: deliveryManId)).length;
}
