import 'package:lab_commission_contract/lab_commission_contract.dart';
import 'package:test/test.dart';

void main() {
  group('QR token payload', () {
    test('round-trips a raw token through the QR payload', () {
      final token = randomToken();
      final payload = qrPayloadFor(token);
      expect(payload, startsWith('$qrPayloadPrefix:'));
      expect(tokenFromQrPayload(payload), token);
    });

    test('rejects a receipt barcode and an empty token', () {
      expect(tokenFromQrPayload('100125'), isNull);
      expect(tokenFromQrPayload('$qrPayloadPrefix:'), isNull);
    });

    test('tokens are opaque, unique and carry no default secrets', () {
      final a = randomToken();
      final b = randomToken();
      expect(a, isNot(b));
      expect(a.length, greaterThan(20));
    });
  });

  group('Credential hashing', () {
    test('same PIN with different salts yields different digests', () {
      final s1 = newSalt();
      final s2 = newSalt();
      expect(s1, isNot(s2));
      expect(hashPin('1234', s1), isNot(hashPin('1234', s2)));
    });

    test('digest is stable for verification', () {
      final salt = newSalt();
      expect(hashPin('1234', salt), hashPin('1234', salt));
      expect(hashPin('1234', salt), isNot(hashPin('12345', salt)));
    });
  });

  group('DTO JSON', () {
    test('summary survives an encode/decode round trip', () {
      const summary = SummaryDto(
        successfulDeliveries: 12,
        commissionEarned: 24000,
        commissionPaid: 10000,
        unpaidCommission: 14000,
        rewardsEarned: 4000,
        rewardsPaid: 0,
        unpaidRewards: 4000,
      );
      final decoded = SummaryDto.fromJson(summary.toJson());
      expect(decoded.commissionEarned, 24000);
      expect(decoded.unpaidRewards, 4000);
    });

    test('commission keeps its payment history', () {
      const dto = CommissionDto(
        id: 'txn_1',
        barcode: '100125',
        commission: 2000,
        dateTime: 1700000000000,
        paymentStatus: 'paid',
        reconciliationStatus: 'match',
        paidAt: 1700000100000,
        payments: [
          PaymentEntryDto(
            type: 'commissionPayment',
            amount: -2000,
            date: '2026-01-02',
            note: 'cash out',
          ),
        ],
      );
      final decoded = CommissionDto.fromJson(dto.toJson());
      expect(decoded.isPaid, isTrue);
      expect(decoded.payments, hasLength(1));
      expect(decoded.payments.single.amount, -2000);
    });

    test('geopoint omits null fields and keeps accuracy', () {
      const g = GeoPointDto(
        id: 'geo_1',
        latitude: 16.84,
        longitude: 96.17,
        accuracyM: 8.5,
        capturedAt: 1700000000000,
      );
      final json = g.toJson();
      expect(json.containsKey('barcode'), isFalse);
      final decoded = GeoPointDto.fromJson(json);
      expect(decoded.accuracyM, 8.5);
    });

    test('trip history keeps the points, their times and their accuracy', () {
      const trip = TripHistoryDto(
        barcode: 'R1',
        commissionId: 'txn_1',
        verifiedAt: 1700000600000,
        points: [
          TripPointDto(
            id: 'trip_1',
            latitude: 16.84,
            longitude: 96.17,
            accuracyM: 9,
            capturedAt: 1700000000000,
          ),
          // No accuracy reported: the field must stay absent, not become 0.
          TripPointDto(
            id: 'trip_2',
            latitude: 16.85,
            longitude: 96.18,
            capturedAt: 1700000120000,
          ),
        ],
      );
      final json = trip.toJson();
      expect((json['points'] as List).length, 2);
      final decoded = TripHistoryDto.fromJson(json);
      expect(decoded.barcode, 'R1');
      expect(decoded.commissionId, 'txn_1');
      expect(decoded.verifiedAt, 1700000600000);
      expect(decoded.points, hasLength(2));
      expect(decoded.points.first.accuracyM, 9);
      expect(decoded.points.last.accuracyM, isNull);
      expect(
        decoded.points.map((p) => p.capturedAt),
        [1700000000000, 1700000120000],
      );
    });
  });

  group('Routes', () {
    test('a trip path keeps a barcode with a slash inside one segment', () {
      // The server matches the prefix and decodes the rest, so an unencoded
      // slash would be read as a second path segment and never find the trip.
      expect(ApiRoutes.trip('A/B'), '${ApiRoutes.trips}/A%2FB');
      expect(Uri.decodeComponent(ApiRoutes.trip('A/B').split('/').last), 'A/B');
    });
  });
}
