import 'package:flutter_test/flutter_test.dart';
import 'package:lab_commission/companion/companion_api_server.dart';
import 'package:lab_commission/companion/store_gateway.dart';
import 'package:lab_commission/core/app_services.dart';
import 'package:lab_commission/data/repositories/settings_repository.dart';
import 'package:lab_commission/data/storage/app_storage.dart';
import 'package:lab_commission/data/storage/http_storage.dart';

void main() {
  group('StoreGateway', () {
    late MemoryStorage storage;
    late StoreGateway gateway;

    setUp(() {
      storage = MemoryStorage();
      gateway = StoreGateway(storage, SettingsRepository(storage));
    });

    test('rejects a table outside the app schema', () {
      expect(
        () => gateway.handle('find', {'table': 'sqlite_master'}),
        throwsA(isA<StoreRequestException>()),
      );
    });

    test('rejects an unknown operation', () {
      expect(
        () => gateway.handle('drop', {'table': 'users'}),
        throwsA(isA<StoreRequestException>()),
      );
    });

    test('rejects an orderBy that is not a plain column list', () {
      expect(
        () => gateway.handle('find', {
          'table': 'users',
          'orderBy': 'name; DROP TABLE users',
        }),
        throwsA(isA<StoreRequestException>()),
      );
    });

    test('accepts the orderBy forms the app actually uses', () async {
      for (final orderBy in [
        'name',
        'created_at DESC',
        'a ASC, b DESC',
        '-created_at',
      ]) {
        await gateway.handle('find', {'table': 'users', 'orderBy': orderBy});
      }
    });

    test('round-trips rows', () async {
      await gateway.handle('insert', {
        'table': 'users',
        'row': {'id': 'u1', 'name': 'Admin'},
      });
      await gateway.handle('insertMany', {
        'table': 'users',
        'rows': [
          {'id': 'u2', 'name': 'Staff'},
          {'id': 'u3', 'name': 'Other'},
        ],
      });
      expect(
        (await gateway.handle('find', {'table': 'users'}))['rows'],
        hasLength(3),
      );

      final one = await gateway.handle('findOne', {
        'table': 'users',
        'where': {'id': 'u2'},
      });
      expect((one['row'] as Map)['name'], 'Staff');

      await gateway.handle('update', {
        'table': 'users',
        'where': {'id': 'u2'},
        'values': {'name': 'Renamed'},
      });
      expect(
        ((await gateway.handle('findOne', {
              'table': 'users',
              'where': {'id': 'u2'},
            }))['row']
            as Map)['name'],
        'Renamed',
      );

      await gateway.handle('remove', {
        'table': 'users',
        'where': {'id': 'u3'},
      });
      expect(
        (await gateway.handle('find', {'table': 'users'}))['rows'],
        hasLength(2),
      );

      await gateway.handle('clear', {'table': 'users'});
      expect(
        (await gateway.handle('find', {'table': 'users'}))['rows'],
        isEmpty,
      );
    });

    test('findOne returns a null row when nothing matches', () async {
      final result = await gateway.handle('findOne', {
        'table': 'users',
        'where': {'id': 'nope'},
      });
      expect(result['row'], isNull);
    });

    test('the office key is generated once and can be rotated', () async {
      final first = await gateway.ensureOfficeKey();
      expect(first, isNotEmpty);
      expect(await gateway.ensureOfficeKey(), first);
      final rotated = await gateway.regenerateOfficeKey();
      expect(rotated, isNot(first));
      expect(await gateway.officeKey, rotated);
    });
  });

  group('HTTP office link', () {
    late AppServices host;
    late CompanionApiServer server;
    late String base;
    late String key;

    setUp(() async {
      host = await AppServices.bootstrap(MemoryStorage());
      key = (await host.storeGateway.officeKey)!;
      server = CompanionApiServer(
        service: host.companion,
        gateway: host.storeGateway,
        port: 0,
      );
      await server.start();
      base = 'http://127.0.0.1:${server.boundPort}';
    });

    tearDown(() => server.stop());

    HttpStorage connect({String? withKey}) {
      final storage = HttpStorage(baseUrl: base, key: withKey ?? key);
      addTearDown(storage.close);
      return storage;
    }

    test('a key-guarded round trip reaches the host database', () async {
      final storage = connect();
      await storage.insert('delivery_men', {
        'id': 'dm-link',
        'name': 'Ko Link',
        'active': 1,
        'created_at': 1,
      });
      expect(
        await host.storage.findOne('delivery_men', {'id': 'dm-link'}),
        isNotNull,
      );
      expect(
        await storage.find('delivery_men', where: {'id': 'dm-link'}),
        hasLength(1),
      );

      await storage.update(
        'delivery_men',
        {'id': 'dm-link'},
        {'name': 'Ko Renamed'},
      );
      expect(
        (await host.storage.findOne('delivery_men', {
          'id': 'dm-link',
        }))!['name'],
        'Ko Renamed',
      );

      await storage.remove('delivery_men', {'id': 'dm-link'});
      expect(
        await host.storage.findOne('delivery_men', {'id': 'dm-link'}),
        isNull,
      );
      expect(await storage.findOne('delivery_men', {'id': 'dm-link'}), isNull);

      await storage.clear('delivery_men');
      expect(await host.storage.find('delivery_men'), isEmpty);
    });

    test('the wrong key is refused', () async {
      await expectLater(
        connect(withKey: 'not-the-key').find('users'),
        throwsA(isA<StorageException>()),
      );
    });

    test('no gateway means the store routes do not exist', () async {
      final bare = CompanionApiServer(service: host.companion, port: 0);
      await bare.start();
      addTearDown(bare.stop);
      final storage = HttpStorage(
        baseUrl: 'http://127.0.0.1:${bare.boundPort}',
        key: key,
      );
      addTearDown(storage.close);
      await expectLater(
        storage.find('users'),
        throwsA(isA<StorageException>()),
      );
    });

    test('a second office terminal runs on the host database', () async {
      final client = await AppServices.bootstrap(
        connect(),
        canHostServer: false,
        sessionScope: 'term-a',
      );
      // The host's seeded staff are visible from the client, and can log in.
      final user = await client.auth.login('1111');
      expect(user.name, 'Staff');
      expect(client.auth.isAdmin, isFalse);

      // Newest-first queries used by the history and board screens.
      expect(await client.milestones.rewards(), isEmpty);
      final (run, results) = await client.reconciliation.latest();
      expect(run, isNull);
      expect(results, isEmpty);

      // Writes from the client land in the host database.
      await client.deliveryMen.create(name: 'Ko Remote');
      expect(
        await host.storage.find('delivery_men', where: {'name': 'Ko Remote'}),
        hasLength(1),
      );
    });

    test('a client cannot become a second server', () async {
      final client = await AppServices.bootstrap(
        connect(),
        canHostServer: false,
      );
      expect(client.canHostServer, isFalse);
      await expectLater(
        client.setCompanionServerEnabled(true),
        throwsA(isA<Exception>()),
      );
    });

    test('terminals keep separate staff sessions on one database', () async {
      await host.auth.login('1234'); // admin, local session key

      final client = await AppServices.bootstrap(
        connect(),
        canHostServer: false,
        sessionScope: 'term-a',
      );
      await client.auth.login('1111'); // staff, scoped to term-a

      // A fresh client with the same scope remembers *its* login...
      final again = await AppServices.bootstrap(
        connect(),
        canHostServer: false,
        sessionScope: 'term-a',
      );
      expect(again.auth.isLoggedIn, isTrue);
      expect(again.auth.isAdmin, isFalse);

      // ...another scope has its own empty session...
      final other = await AppServices.bootstrap(
        connect(),
        canHostServer: false,
        sessionScope: 'term-b',
      );
      expect(other.auth.isLoggedIn, isFalse);

      // ...and the host is still signed in as admin.
      final hostAgain = await AppServices.bootstrap(
        host.storage,
        companionPort: 0,
      );
      expect(hostAgain.auth.isAdmin, isTrue);
    });
  });
}
