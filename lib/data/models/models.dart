import 'package:intl/intl.dart';

enum UserRole { admin, staff }

class User {
  const User({
    required this.id,
    required this.name,
    required this.pin,
    required this.role,
    this.active = true,
    this.email = '',
  });

  final String id;
  final String name;
  final String pin;
  final UserRole role;
  final bool active;

  /// Legacy delivery address for the old daily-PIN email. The current build
  /// asks for the Admin PIN instead, so this is only kept for backups.
  final String email;

  bool get isAdmin => role == UserRole.admin;

  User copyWith({String? name, String? pin, String? email, bool? active}) =>
      User(
        id: id,
        name: name ?? this.name,
        pin: pin ?? this.pin,
        role: role,
        active: active ?? this.active,
        email: email ?? this.email,
      );

  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'pin': pin,
    'role': role.name,
    'active': active ? 1 : 0,
    'email': email,
  };

  factory User.fromMap(Map<String, dynamic> m) => User(
    id: m['id'] as String,
    name: m['name'] as String,
    pin: m['pin'] as String,
    role: UserRole.values.firstWhere((r) => r.name == m['role']),
    active: (m['active'] as int? ?? 1) == 1,
    email: (m['email'] as String?) ?? '',
  );
}

/// One user's PIN for one calendar day, used only for money-changing actions.
class DailyPin {
  const DailyPin({
    required this.userId,
    required this.pin,
    required this.date,
    required this.generatedAt,
  });

  final String userId;
  final String pin;

  /// Local calendar day, `yyyy-MM-dd`.
  final String date;
  final int generatedAt;

  Map<String, dynamic> toMap() => {
    'user_id': userId,
    'pin': pin,
    'date': date,
    'generated_at': generatedAt,
  };

  factory DailyPin.fromMap(Map<String, dynamic> m) => DailyPin(
    userId: m['user_id'] as String,
    pin: m['pin'] as String,
    date: m['date'] as String,
    generatedAt: (m['generated_at'] as num).toInt(),
  );
}

class DeliveryMan {
  const DeliveryMan({
    required this.id,
    required this.name,
    this.phone = '',
    this.active = true,
    this.requireQr = false,
    required this.createdAt,
  });

  final String id;
  final String name;
  final String phone;
  final bool active;

  /// When true, the man must be chosen by scanning their QR code. Picking them
  /// from the manual list needs an admin PIN.
  final bool requireQr;

  final int createdAt;

  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'phone': phone,
    'active': active ? 1 : 0,
    'require_qr': requireQr ? 1 : 0,
    'created_at': createdAt,
  };

  factory DeliveryMan.fromMap(Map<String, dynamic> m) => DeliveryMan(
    id: m['id'] as String,
    name: m['name'] as String,
    phone: (m['phone'] as String?) ?? '',
    active: (m['active'] as int? ?? 1) == 1,
    requireQr: (m['require_qr'] as int? ?? 0) == 1,
    createdAt: (m['created_at'] as num).toInt(),
  );
}

/// One incoming call from a delivery man's phone to the lab, kept as evidence:
/// a man who sent a patient in calls the lab to say so, and the call with its
/// date and time backs his commission later.
class DeliveryManCall {
  const DeliveryManCall({
    required this.id,
    required this.deliveryManId,
    required this.phone,
    required this.receivedAt,
    required this.answered,
  });

  final String id;
  final String deliveryManId;

  /// The number exactly as the phone reported it.
  final String phone;

  /// When the call started ringing (device clock), ms since epoch.
  final int receivedAt;

  /// True when the lab picked up; false for a ring that was never answered.
  final bool answered;

  Map<String, dynamic> toMap() => {
    'id': id,
    'delivery_man_id': deliveryManId,
    'phone': phone,
    'received_at': receivedAt,
    'answered': answered ? 1 : 0,
  };

  factory DeliveryManCall.fromMap(Map<String, dynamic> m) => DeliveryManCall(
    id: m['id'] as String,
    deliveryManId: m['delivery_man_id'] as String,
    phone: (m['phone'] as String?) ?? '',
    receivedAt: (m['received_at'] as num).toInt(),
    answered: (m['answered'] as int? ?? 0) == 1,
  );
}

/// A companion-app login for one delivery man. Kept in its own table so the
/// office's own [DeliveryMan] record (used everywhere else) is untouched. The
/// PIN is stored only as a salted hash and the QR token only as a hash, so
/// reading the database does not reveal either secret.
class DeliveryManAccount {
  const DeliveryManAccount({
    required this.id,
    required this.deliveryManId,
    required this.loginId,
    required this.pinHash,
    required this.salt,
    this.active = true,
    this.qrTokenHash,
    this.qrIssuedAt,
    required this.createdAt,
    this.lastLoginAt,
  });

  final String id;
  final String deliveryManId;
  final String loginId;
  final String pinHash;
  final String salt;
  final bool active;
  final String? qrTokenHash;
  final int? qrIssuedAt;
  final int createdAt;
  final int? lastLoginAt;

  DeliveryManAccount copyWith({
    String? loginId,
    String? pinHash,
    String? salt,
    bool? active,
    String? qrTokenHash,
    int? qrIssuedAt,
    int? lastLoginAt,
    bool clearQr = false,
  }) => DeliveryManAccount(
    id: id,
    deliveryManId: deliveryManId,
    loginId: loginId ?? this.loginId,
    pinHash: pinHash ?? this.pinHash,
    salt: salt ?? this.salt,
    active: active ?? this.active,
    qrTokenHash: clearQr ? null : (qrTokenHash ?? this.qrTokenHash),
    qrIssuedAt: clearQr ? null : (qrIssuedAt ?? this.qrIssuedAt),
    createdAt: createdAt,
    lastLoginAt: lastLoginAt ?? this.lastLoginAt,
  );

  Map<String, dynamic> toMap() => {
    'id': id,
    'delivery_man_id': deliveryManId,
    'login_id': loginId,
    'pin_hash': pinHash,
    'salt': salt,
    'active': active ? 1 : 0,
    'qr_token_hash': qrTokenHash,
    'qr_issued_at': qrIssuedAt,
    'created_at': createdAt,
    'last_login_at': lastLoginAt,
  };

  factory DeliveryManAccount.fromMap(Map<String, dynamic> m) =>
      DeliveryManAccount(
        id: m['id'] as String,
        deliveryManId: m['delivery_man_id'] as String,
        loginId: m['login_id'] as String,
        pinHash: m['pin_hash'] as String,
        salt: m['salt'] as String,
        active: (m['active'] as int? ?? 1) == 1,
        qrTokenHash: m['qr_token_hash'] as String?,
        qrIssuedAt: m['qr_issued_at'] == null
            ? null
            : (m['qr_issued_at'] as num).toInt(),
        createdAt: (m['created_at'] as num).toInt(),
        lastLoginAt: m['last_login_at'] == null
            ? null
            : (m['last_login_at'] as num).toInt(),
      );
}

/// A bearer session issued to a companion app after login. Stored as a hash and
/// revocable, so staff can cut off a lost phone.
class DeliverySession {
  const DeliverySession({
    required this.id,
    required this.accountId,
    required this.tokenHash,
    required this.createdAt,
    required this.expiresAt,
    this.revokedAt,
  });

  final String id;
  final String accountId;
  final String tokenHash;
  final int createdAt;
  final int expiresAt;
  final int? revokedAt;

  bool isLiveAt(int now) => revokedAt == null && now < expiresAt;

  Map<String, dynamic> toMap() => {
    'id': id,
    'account_id': accountId,
    'token_hash': tokenHash,
    'created_at': createdAt,
    'expires_at': expiresAt,
    'revoked_at': revokedAt,
  };

  factory DeliverySession.fromMap(Map<String, dynamic> m) => DeliverySession(
    id: m['id'] as String,
    accountId: m['account_id'] as String,
    tokenHash: m['token_hash'] as String,
    createdAt: (m['created_at'] as num).toInt(),
    expiresAt: (m['expires_at'] as num).toInt(),
    revokedAt: m['revoked_at'] == null
        ? null
        : (m['revoked_at'] as num).toInt(),
  );
}

/// A GPS fix captured by the companion app. Always filed against the delivery
/// man the server authenticated — never a client-supplied id.
class DeliveryLocation {
  const DeliveryLocation({
    required this.id,
    required this.deliveryManId,
    required this.latitude,
    required this.longitude,
    this.accuracyM,
    required this.capturedAt,
    required this.receivedAt,
    this.barcode,
    this.clientId,
  });

  final String id;
  final String deliveryManId;
  final double latitude;
  final double longitude;
  final double? accuracyM;
  final int capturedAt;

  /// When the office stored the fix. Used for retention: a phone with a wrong
  /// clock cannot make the office keep — or drop — a fix early.
  final int receivedAt;
  final String? barcode;

  /// Id the phone gave the fix; used to ignore a repeated upload.
  final String? clientId;

  Map<String, dynamic> toMap() => {
    'id': id,
    'delivery_man_id': deliveryManId,
    'latitude': latitude,
    'longitude': longitude,
    'accuracy_m': accuracyM,
    'captured_at': capturedAt,
    'received_at': receivedAt,
    'barcode': barcode,
    'client_id': clientId,
  };

  factory DeliveryLocation.fromMap(Map<String, dynamic> m) => DeliveryLocation(
    id: m['id'] as String,
    deliveryManId: m['delivery_man_id'] as String,
    latitude: (m['latitude'] as num).toDouble(),
    longitude: (m['longitude'] as num).toDouble(),
    accuracyM: m['accuracy_m'] == null
        ? null
        : (m['accuracy_m'] as num).toDouble(),
    capturedAt: (m['captured_at'] as num).toInt(),
    // Older backups have no received_at; the fix's own time is the best guess.
    receivedAt:
        (m['received_at'] as num?)?.toInt() ??
        (m['captured_at'] as num).toInt(),
    barcode: m['barcode'] as String?,
    clientId: m['client_id'] as String?,
  );
}

/// A GPS point kept as part of one delivered receipt's route. Copied out of
/// [DeliveryLocation] when staff record the delivery, because the raw fixes are
/// deleted once they are 20 minutes old; this copy survives so the route can be
/// reviewed later. A route is evidence of where the phone was — not proof that a
/// test was performed, so it never decides a commission on its own.
class DeliveryTripPoint {
  const DeliveryTripPoint({
    required this.id,
    required this.barcode,
    required this.commissionId,
    required this.deliveryManId,
    required this.latitude,
    required this.longitude,
    this.accuracyM,
    required this.capturedAt,
    required this.createdAt,
    this.sourceId,
  });

  final String id;
  final String barcode;
  final String commissionId;
  final String deliveryManId;
  final double latitude;
  final double longitude;
  final double? accuracyM;

  /// When the delivery man's phone recorded the fix (device clock).
  final int capturedAt;

  /// When the office preserved it.
  final int createdAt;

  /// Id of the raw fix this point was copied from, when there was one. A fix
  /// that arrived after the delivery was recorded is attached by this id, so it
  /// is never attached twice.
  final String? sourceId;

  Map<String, dynamic> toMap() => {
    'id': id,
    'barcode': barcode,
    'commission_id': commissionId,
    'delivery_man_id': deliveryManId,
    'latitude': latitude,
    'longitude': longitude,
    'accuracy_m': accuracyM,
    'captured_at': capturedAt,
    'created_at': createdAt,
    'source_id': sourceId,
  };

  factory DeliveryTripPoint.fromMap(Map<String, dynamic> m) =>
      DeliveryTripPoint(
        id: m['id'] as String,
        barcode: m['barcode'] as String,
        commissionId: m['commission_id'] as String,
        deliveryManId: m['delivery_man_id'] as String,
        latitude: (m['latitude'] as num).toDouble(),
        longitude: (m['longitude'] as num).toDouble(),
        accuracyM: m['accuracy_m'] == null
            ? null
            : (m['accuracy_m'] as num).toDouble(),
        capturedAt: (m['captured_at'] as num).toInt(),
        createdAt: (m['created_at'] as num).toInt(),
        sourceId: m['source_id'] as String?,
      );
}

/// The fields read off a printed receipt when the print spooler detected it.
///
/// Kept in its own table, keyed by barcode, so the board and history screens can
/// show who the sample belongs to. Fields are empty when the job carried none.
class PrintedReceipt {
  const PrintedReceipt({
    required this.barcode,
    this.patient = '',
    this.ageSex = '',
    this.refer = '',
    this.receiptDate = '',
    this.totalAmount = '',
    required this.detectedAt,
  });

  final String barcode;
  final String patient;
  final String ageSex;
  final String refer;
  final String receiptDate;
  final String totalAmount;

  /// When the office detected the print job, ms since epoch.
  final int detectedAt;

  /// One line for list rows; empty when the job carried none of the fields.
  String get summary => [
    if (patient.isNotEmpty) 'Patient: $patient',
    if (ageSex.isNotEmpty) 'Age/Sex: $ageSex',
    if (refer.isNotEmpty) 'Refer: $refer',
    if (receiptDate.isNotEmpty) 'Date: $receiptDate',
    if (totalAmount.isNotEmpty) 'Total: $totalAmount',
  ].join(' · ');

  Map<String, dynamic> toMap() => {
    'barcode': barcode,
    'patient': patient,
    'age_sex': ageSex,
    'refer': refer,
    'receipt_date': receiptDate,
    'total_amount': totalAmount,
    'detected_at': detectedAt,
  };

  factory PrintedReceipt.fromMap(Map<String, dynamic> m) => PrintedReceipt(
    barcode: m['barcode'] as String,
    patient: (m['patient'] as String?) ?? '',
    ageSex: (m['age_sex'] as String?) ?? '',
    refer: (m['refer'] as String?) ?? '',
    receiptDate: (m['receipt_date'] as String?) ?? '',
    totalAmount: (m['total_amount'] as String?) ?? '',
    detectedAt: (m['detected_at'] as num).toInt(),
  );
}

/// What the board and history screens show for each receipt: the fields the
/// print job carried, with anything it missed taken from the official export
/// imported for reconciliation.
Map<String, PrintedReceipt> receiptDetailsByBarcode(
  Map<String, PrintedReceipt> printed,
  Map<String, OfficialReceipt> official,
) {
  PrintedReceipt merged(PrintedReceipt? p, OfficialReceipt? o) =>
      PrintedReceipt(
        barcode: p?.barcode ?? o!.barcode,
        patient: _firstNonEmpty(p?.patient, o?.patient),
        ageSex: p?.ageSex ?? '',
        refer: _firstNonEmpty(p?.refer, o?.refer),
        receiptDate: _firstNonEmpty(p?.receiptDate, o?.receiptDate),
        totalAmount: _firstNonEmpty(
          p?.totalAmount,
          o == null ? null : '${o.totalAmount}',
        ),
        detectedAt: p?.detectedAt ?? 0,
      );

  final out = <String, PrintedReceipt>{};
  for (final entry in printed.entries) {
    out[entry.key] = merged(entry.value, official[entry.key]);
  }
  for (final entry in official.entries) {
    out.putIfAbsent(entry.key, () => merged(null, entry.value));
  }
  return out;
}

String _firstNonEmpty(String? first, String? second) =>
    (first != null && first.isNotEmpty) ? first : (second ?? '');

class CommissionRule {
  const CommissionRule({
    required this.id,
    required this.minAmount,
    required this.maxAmount,
    required this.commissionAmount,
    this.active = true,
  });

  final String id;
  final int minAmount;
  final int? maxAmount;
  final int commissionAmount;
  final bool active;

  bool matches(int receiptTotal) =>
      active &&
      receiptTotal >= minAmount &&
      (maxAmount == null || receiptTotal <= maxAmount!);

  Map<String, dynamic> toMap() => {
    'id': id,
    'min_amount': minAmount,
    'max_amount': maxAmount,
    'commission_amount': commissionAmount,
    'active': active ? 1 : 0,
  };

  factory CommissionRule.fromMap(Map<String, dynamic> m) => CommissionRule(
    id: m['id'] as String,
    minAmount: (m['min_amount'] as num).toInt(),
    maxAmount: m['max_amount'] == null
        ? null
        : (m['max_amount'] as num).toInt(),
    commissionAmount: (m['commission_amount'] as num).toInt(),
    active: (m['active'] as int? ?? 1) == 1,
  );
}

enum RecordStatus { active, reversed }

enum PaymentStatus { unpaid, paid }

class CommissionRecord {
  const CommissionRecord({
    required this.id,
    required this.barcode,
    required this.deliveryManId,
    required this.commission,
    required this.dateTime,
    required this.staffUserId,
    this.status = RecordStatus.active,
    this.paymentStatus = PaymentStatus.unpaid,
    required this.createdAt,
    this.reversedAt,
    this.reversedBy,
    this.reversalReason,
    this.paidAt,
    this.paidBy,
    this.deliveryManName,
  });

  final String id;
  final String barcode;
  final String deliveryManId;
  final int commission;
  final int dateTime;
  final String staffUserId;
  final RecordStatus status;
  final PaymentStatus paymentStatus;
  final int createdAt;
  final int? reversedAt;
  final String? reversedBy;
  final String? reversalReason;
  final int? paidAt;
  final String? paidBy;

  /// Denormalised name for display; filled by repository lookups.
  final String? deliveryManName;

  bool get isActive => status == RecordStatus.active;
  bool get isPaid => paymentStatus == PaymentStatus.paid;

  String get dateTimeLocal =>
      DateFormat('dd/MM/yyyy HH:mm')
          .format(DateTime.fromMillisecondsSinceEpoch(dateTime));
  String get createdLocal =>
      DateFormat('dd/MM/yyyy HH:mm')
          .format(DateTime.fromMillisecondsSinceEpoch(createdAt));

  CommissionRecord copyWith({
    RecordStatus? status,
    PaymentStatus? paymentStatus,
    int? reversedAt,
    String? reversedBy,
    String? reversalReason,
    int? paidAt,
    String? paidBy,
    String? deliveryManId,
    String? deliveryManName,
    bool clearPaid = false,
  }) => CommissionRecord(
    id: id,
    barcode: barcode,
    deliveryManId: deliveryManId ?? this.deliveryManId,
    commission: commission,
    dateTime: dateTime,
    staffUserId: staffUserId,
    status: status ?? this.status,
    paymentStatus: paymentStatus ?? this.paymentStatus,
    createdAt: createdAt,
    reversedAt: reversedAt ?? this.reversedAt,
    reversedBy: reversedBy ?? this.reversedBy,
    reversalReason: reversalReason ?? this.reversalReason,
    paidAt: clearPaid ? null : (paidAt ?? this.paidAt),
    paidBy: clearPaid ? null : (paidBy ?? this.paidBy),
    deliveryManName: deliveryManName ?? this.deliveryManName,
  );

  Map<String, dynamic> toMap() => {
    'id': id,
    'barcode': barcode,
    'delivery_man_id': deliveryManId,
    'commission': commission,
    'date_time': dateTime,
    'staff_user_id': staffUserId,
    'status': status.name,
    'payment_status': paymentStatus.name,
    'created_at': createdAt,
    'reversed_at': reversedAt,
    'reversed_by': reversedBy,
    'reversal_reason': reversalReason,
    'paid_at': paidAt,
    'paid_by': paidBy,
  };

  factory CommissionRecord.fromMap(Map<String, dynamic> m) => CommissionRecord(
    id: m['id'] as String,
    barcode: m['barcode'] as String,
    deliveryManId: m['delivery_man_id'] as String,
    commission: (m['commission'] as num).toInt(),
    dateTime: (m['date_time'] as num).toInt(),
    staffUserId: m['staff_user_id'] as String,
    status: RecordStatus.values.firstWhere((s) => s.name == m['status']),
    paymentStatus: PaymentStatus.values.firstWhere(
      (s) => s.name == m['payment_status'],
    ),
    createdAt: (m['created_at'] as num).toInt(),
    reversedAt: m['reversed_at'] == null
        ? null
        : (m['reversed_at'] as num).toInt(),
    reversedBy: m['reversed_by'] as String?,
    reversalReason: m['reversal_reason'] as String?,
    paidAt: m['paid_at'] == null ? null : (m['paid_at'] as num).toInt(),
    paidBy: m['paid_by'] as String?,
    deliveryManName: m['delivery_man_name'] as String?,
  );
}

class MilestoneRule {
  const MilestoneRule({
    required this.id,
    required this.everyN,
    required this.rewardAmount,
    this.active = true,
  });

  final String id;
  final int everyN;
  final int rewardAmount;
  final bool active;

  Map<String, dynamic> toMap() => {
    'id': id,
    'every_n': everyN,
    'reward_amount': rewardAmount,
    'active': active ? 1 : 0,
  };

  factory MilestoneRule.fromMap(Map<String, dynamic> m) => MilestoneRule(
    id: m['id'] as String,
    everyN: (m['every_n'] as num).toInt(),
    rewardAmount: (m['reward_amount'] as num).toInt(),
    active: (m['active'] as int? ?? 1) == 1,
  );
}

class MilestoneReward {
  const MilestoneReward({
    required this.id,
    required this.deliveryManId,
    required this.everyN,
    required this.milestoneCount,
    required this.rewardAmount,
    this.status = RecordStatus.active,
    this.paymentStatus = PaymentStatus.unpaid,
    required this.createdAt,
    this.paidAt,
    this.paidBy,
    this.deliveryManName,
  });

  final String id;
  final String deliveryManId;
  final int everyN;
  final int milestoneCount;
  final int rewardAmount;
  final RecordStatus status;
  final PaymentStatus paymentStatus;
  final int createdAt;
  final int? paidAt;
  final String? paidBy;
  final String? deliveryManName;

  String get label => 'Every $everyN deliveries ($milestoneCount)';
  bool get isPaid => paymentStatus == PaymentStatus.paid;

  MilestoneReward copyWith({
    RecordStatus? status,
    PaymentStatus? paymentStatus,
    int? paidAt,
    String? paidBy,
    String? deliveryManName,
    bool clearPaid = false,
  }) => MilestoneReward(
    id: id,
    deliveryManId: deliveryManId,
    everyN: everyN,
    milestoneCount: milestoneCount,
    rewardAmount: rewardAmount,
    status: status ?? this.status,
    paymentStatus: paymentStatus ?? this.paymentStatus,
    createdAt: createdAt,
    paidAt: clearPaid ? null : (paidAt ?? this.paidAt),
    paidBy: clearPaid ? null : (paidBy ?? this.paidBy),
    deliveryManName: deliveryManName ?? this.deliveryManName,
  );

  Map<String, dynamic> toMap() => {
    'id': id,
    'delivery_man_id': deliveryManId,
    'every_n': everyN,
    'milestone_count': milestoneCount,
    'reward_amount': rewardAmount,
    'status': status.name,
    'payment_status': paymentStatus.name,
    'created_at': createdAt,
    'paid_at': paidAt,
    'paid_by': paidBy,
  };

  factory MilestoneReward.fromMap(Map<String, dynamic> m) => MilestoneReward(
    id: m['id'] as String,
    deliveryManId: m['delivery_man_id'] as String,
    everyN: (m['every_n'] as num).toInt(),
    milestoneCount: (m['milestone_count'] as num).toInt(),
    rewardAmount: (m['reward_amount'] as num).toInt(),
    status: RecordStatus.values.firstWhere((s) => s.name == m['status']),
    paymentStatus: PaymentStatus.values.firstWhere(
      (s) => s.name == m['payment_status'],
    ),
    createdAt: (m['created_at'] as num).toInt(),
    paidAt: m['paid_at'] == null ? null : (m['paid_at'] as num).toInt(),
    paidBy: m['paid_by'] as String?,
    deliveryManName: m['delivery_man_name'] as String?,
  );
}

class CashAdvance {
  const CashAdvance({
    required this.id,
    required this.date,
    required this.amount,
    this.note = '',
    required this.createdBy,
    required this.createdAt,
  });

  final String id;
  final String date; // yyyy-MM-dd
  final int amount;
  final String note;
  final String createdBy;
  final int createdAt;

  Map<String, dynamic> toMap() => {
    'id': id,
    'date': date,
    'amount': amount,
    'note': note,
    'created_by': createdBy,
    'created_at': createdAt,
  };

  factory CashAdvance.fromMap(Map<String, dynamic> m) => CashAdvance(
    id: m['id'] as String,
    date: m['date'] as String,
    amount: (m['amount'] as num).toInt(),
    note: (m['note'] as String?) ?? '',
    createdBy: m['created_by'] as String,
    createdAt: (m['created_at'] as num).toInt(),
  );
}

enum CashTxnType {
  advance,
  commissionPayment,
  rewardPayment,
  otherIn,
  otherOut,
}

class CashTransaction {
  const CashTransaction({
    required this.id,
    required this.type,
    required this.amount,
    this.refType,
    this.refId,
    required this.date,
    this.note = '',
    required this.createdBy,
    required this.createdAt,
  });

  final String id;
  final CashTxnType type;
  final int amount; // signed: + in, - out
  final String? refType;
  final String? refId;
  final String date;
  final String note;
  final String createdBy;
  final int createdAt;

  bool get isIncoming => amount >= 0;

  Map<String, dynamic> toMap() => {
    'id': id,
    'type': type.name,
    'amount': amount,
    'ref_type': refType,
    'ref_id': refId,
    'date': date,
    'note': note,
    'created_by': createdBy,
    'created_at': createdAt,
  };

  factory CashTransaction.fromMap(Map<String, dynamic> m) => CashTransaction(
    id: m['id'] as String,
    type: CashTxnType.values.firstWhere((t) => t.name == m['type']),
    amount: (m['amount'] as num).toInt(),
    refType: m['ref_type'] as String?,
    refId: m['ref_id'] as String?,
    date: m['date'] as String,
    note: (m['note'] as String?) ?? '',
    createdBy: m['created_by'] as String,
    createdAt: (m['created_at'] as num).toInt(),
  );
}

class OfficialReceipt {
  const OfficialReceipt({
    required this.id,
    required this.barcode,
    required this.receiptDate,
    required this.totalAmount,
    required this.batchId,
    required this.importedAt,
    this.refer = '',
    this.patient = '',
  });

  final String id;
  final String barcode;
  final String
  receiptDate; // yyyy-MM-dd (or yyyy-MM-dd HH:mm when time is read)
  final int totalAmount;
  final String batchId;
  final int importedAt;

  /// Who referred the receipt (the "Refer / Refer by" export column).
  final String refer;

  /// Patient name from the official export's "Patient / Patient Name" column.
  final String patient;

  Map<String, dynamic> toMap() => {
    'id': id,
    'barcode': barcode,
    'receipt_date': receiptDate,
    'total_amount': totalAmount,
    'batch_id': batchId,
    'imported_at': importedAt,
    'refer': refer,
    'patient': patient,
  };

  factory OfficialReceipt.fromMap(Map<String, dynamic> m) => OfficialReceipt(
    id: m['id'] as String,
    barcode: m['barcode'] as String,
    receiptDate: m['receipt_date'] as String,
    totalAmount: (m['total_amount'] as num).toInt(),
    batchId: m['batch_id'] as String,
    importedAt: (m['imported_at'] as num).toInt(),
    refer: (m['refer'] as String?) ?? '',
    patient: (m['patient'] as String?) ?? '',
  );
}

enum ReconciliationStatus {
  match,
  mismatch,
  notFound,
  duplicateStaff,
  duplicateOfficial,
  unclaimed,
}

class ReconciliationResult {
  const ReconciliationResult({
    required this.id,
    required this.runId,
    required this.barcode,
    this.receiptAmount,
    this.deliveryManId,
    this.enteredCommission,
    this.expectedCommission,
    required this.status,
    required this.createdAt,
    this.deliveryManName,
    this.receiptDate,
    this.refer = '',
    this.patient = '',
    this.commissionAt,
  });

  final String id;
  final String runId;
  final String barcode;
  final int? receiptAmount;
  final String? deliveryManId;
  final int? enteredCommission;
  final int? expectedCommission;
  final ReconciliationStatus status;
  final int createdAt;
  final String? deliveryManName;
  final String? receiptDate;

  /// Who referred the receipt, carried over from the official export.
  final String refer;

  /// Patient name, carried over from the official export.
  final String patient;

  /// When the matched commission was entered (the record's DateTime), null
  /// for unclaimed rows.
  final int? commissionAt;

  /// Difference between receipt time and commission entry, or null when it
  /// cannot be trusted — no commission time, or a receipt export whose Date
  /// column carried no Time (comparing against midnight would flag every
  /// morning entry).
  Duration? get timeGap {
    final raw = receiptDate;
    if (raw == null || commissionAt == null) return null;
    if (!raw.contains(' ')) return null;
    final receipt = DateTime.tryParse(raw);
    if (receipt == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(commissionAt!)
        .difference(receipt)
        .abs();
  }

  /// Only the values a backfill or a display tweak needs to change; the rest
  /// of a stored result is fixed once the run is written. Pass
  /// [clearCommissionAt] to drop the time (used to simulate a run written
  /// before the column existed).
  ReconciliationResult copyWith({
    int? commissionAt,
    bool clearCommissionAt = false,
  }) => ReconciliationResult(
    id: id,
    runId: runId,
    barcode: barcode,
    receiptAmount: receiptAmount,
    deliveryManId: deliveryManId,
    enteredCommission: enteredCommission,
    expectedCommission: expectedCommission,
    status: status,
    createdAt: createdAt,
    deliveryManName: deliveryManName,
    receiptDate: receiptDate,
    refer: refer,
    patient: patient,
    commissionAt: clearCommissionAt
        ? null
        : (commissionAt ?? this.commissionAt),
  );

  String get statusLabel => switch (status) {
    ReconciliationStatus.match => 'MATCH',
    ReconciliationStatus.mismatch => 'MISMATCH',
    ReconciliationStatus.notFound => 'NOT FOUND',
    ReconciliationStatus.duplicateStaff => 'DUPLICATE',
    ReconciliationStatus.duplicateOfficial => 'DUPLICATE',
    ReconciliationStatus.unclaimed => 'UNCLAIMED',
  };

  Map<String, dynamic> toMap() => {
    'id': id,
    'run_id': runId,
    'barcode': barcode,
    'receipt_amount': receiptAmount,
    'delivery_man_id': deliveryManId,
    'entered_commission': enteredCommission,
    'expected_commission': expectedCommission,
    'status': status.name,
    'created_at': createdAt,
    'delivery_man_name': deliveryManName,
    'receipt_date': receiptDate,
    'refer': refer,
    'patient': patient,
    'commission_at': commissionAt,
  };

  factory ReconciliationResult.fromMap(Map<String, dynamic> m) =>
      ReconciliationResult(
        id: m['id'] as String,
        runId: m['run_id'] as String,
        barcode: m['barcode'] as String,
        receiptAmount: m['receipt_amount'] == null
            ? null
            : (m['receipt_amount'] as num).toInt(),
        deliveryManId: m['delivery_man_id'] as String?,
        enteredCommission: m['entered_commission'] == null
            ? null
            : (m['entered_commission'] as num).toInt(),
        expectedCommission: m['expected_commission'] == null
            ? null
            : (m['expected_commission'] as num).toInt(),
        status: ReconciliationStatus.values.firstWhere(
          (s) => s.name == m['status'],
        ),
        createdAt: (m['created_at'] as num).toInt(),
        deliveryManName: m['delivery_man_name'] as String?,
        receiptDate: m['receipt_date'] as String?,
        refer: (m['refer'] as String?) ?? '',
        patient: (m['patient'] as String?) ?? '',
        commissionAt: (m['commission_at'] as num?)?.toInt(),
      );
}

class ReconciliationRun {
  const ReconciliationRun({
    required this.id,
    required this.officialCount,
    required this.staffCount,
    required this.matchCount,
    required this.mismatchCount,
    required this.notFoundCount,
    required this.duplicateCount,
    required this.unclaimedCount,
    required this.createdBy,
    required this.createdAt,
  });

  final String id;
  final int officialCount;
  final int staffCount;
  final int matchCount;
  final int mismatchCount;
  final int notFoundCount;
  final int duplicateCount;
  final int unclaimedCount;
  final String createdBy;
  final int createdAt;

  Map<String, dynamic> toMap() => {
    'id': id,
    'official_count': officialCount,
    'staff_count': staffCount,
    'match_count': matchCount,
    'mismatch_count': mismatchCount,
    'not_found_count': notFoundCount,
    'duplicate_count': duplicateCount,
    'unclaimed_count': unclaimedCount,
    'created_by': createdBy,
    'created_at': createdAt,
  };

  factory ReconciliationRun.fromMap(Map<String, dynamic> m) =>
      ReconciliationRun(
        id: m['id'] as String,
        officialCount: (m['official_count'] as num).toInt(),
        staffCount: (m['staff_count'] as num).toInt(),
        matchCount: (m['match_count'] as num).toInt(),
        mismatchCount: (m['mismatch_count'] as num).toInt(),
        notFoundCount: (m['not_found_count'] as num).toInt(),
        duplicateCount: (m['duplicate_count'] as num).toInt(),
        unclaimedCount: (m['unclaimed_count'] as num).toInt(),
        createdBy: m['created_by'] as String,
        createdAt: (m['created_at'] as num).toInt(),
      );
}

class AuditLog {
  const AuditLog({
    required this.id,
    required this.userId,
    required this.userName,
    required this.action,
    this.refId,
    this.oldValue,
    this.newValue,
    required this.createdAt,
  });

  final String id;
  final String userId;
  final String userName;
  final String action;
  final String? refId;
  final String? oldValue;
  final String? newValue;
  final int createdAt;

  String get createdLocal =>
      DateFormat('dd/MM/yyyy HH:mm')
          .format(DateTime.fromMillisecondsSinceEpoch(createdAt));

  Map<String, dynamic> toMap() => {
    'id': id,
    'user_id': userId,
    'user_name': userName,
    'action': action,
    'ref_id': refId,
    'old_value': oldValue,
    'new_value': newValue,
    'created_at': createdAt,
  };

  factory AuditLog.fromMap(Map<String, dynamic> m) => AuditLog(
    id: m['id'] as String,
    userId: m['user_id'] as String,
    userName: m['user_name'] as String,
    action: m['action'] as String,
    refId: m['ref_id'] as String?,
    oldValue: m['old_value'] as String?,
    newValue: m['new_value'] as String?,
    createdAt: (m['created_at'] as num).toInt(),
  );
}

class MonthlyClosing {
  const MonthlyClosing({
    required this.id,
    required this.month,
    required this.openingBalance,
    required this.cashReceived,
    required this.commissionEarned,
    required this.commissionPaid,
    required this.rewardsPaid,
    required this.otherPayments,
    this.otherIncome = 0,
    required this.expectedRemaining,
    required this.actualCounted,
    required this.difference,
    this.note = '',
    required this.countedBy,
    required this.createdAt,
  });

  final String id;
  final String month; // yyyy-MM
  final int openingBalance; // carried forward from previous month
  final int cashReceived;
  final int commissionEarned;
  final int commissionPaid;
  final int rewardsPaid;
  final int otherPayments;
  final int otherIncome;
  final int expectedRemaining;
  final int actualCounted;
  final int difference;
  final String note;
  final String countedBy;
  final int createdAt;

  bool get isShortage => difference < 0;
  bool get isOverage => difference > 0;

  Map<String, dynamic> toMap() => {
    'id': id,
    'month': month,
    'opening_balance': openingBalance,
    'cash_received': cashReceived,
    'commission_earned': commissionEarned,
    'commission_paid': commissionPaid,
    'rewards_paid': rewardsPaid,
    'other_payments': otherPayments,
    'other_income': otherIncome,
    'expected_remaining': expectedRemaining,
    'actual_counted': actualCounted,
    'difference': difference,
    'note': note,
    'counted_by': countedBy,
    'created_at': createdAt,
  };

  factory MonthlyClosing.fromMap(Map<String, dynamic> m) => MonthlyClosing(
    id: m['id'] as String,
    month: m['month'] as String,
    openingBalance: (m['opening_balance'] as num).toInt(),
    cashReceived: (m['cash_received'] as num).toInt(),
    commissionEarned: (m['commission_earned'] as num).toInt(),
    commissionPaid: (m['commission_paid'] as num).toInt(),
    rewardsPaid: (m['rewards_paid'] as num).toInt(),
    otherPayments: (m['other_payments'] as num).toInt(),
    otherIncome: (m['other_income'] as num?)?.toInt() ?? 0,
    expectedRemaining: (m['expected_remaining'] as num).toInt(),
    actualCounted: (m['actual_counted'] as num).toInt(),
    difference: (m['difference'] as num).toInt(),
    note: (m['note'] as String?) ?? '',
    countedBy: m['counted_by'] as String,
    createdAt: (m['created_at'] as num).toInt(),
  );
}
