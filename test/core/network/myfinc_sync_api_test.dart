import 'package:flutter_test/flutter_test.dart';
import 'package:myfinc/core/network/myfinc_sync_api.dart';

void main() {
  group('MyFincSyncPage', () {
    test('parses a valid page without mutating the cursor', () {
      final page = MyFincSyncPage.fromJson({
        'changes': [
          {
            'resource': 'accounts',
            'data': {
              'id': '8e7f6b7a-1234-4234-8234-123456789abc',
              'syncVersion': 1,
              'syncCursor': 4,
              'name': 'Cuenta de prueba',
            },
          },
        ],
        'nextCursor': 4,
        'hasMore': false,
        'limit': 100,
      }, requestedCursor: 3);

      expect(page.changes, hasLength(1));
      expect(page.changes.single.resource, 'accounts');
      expect(page.nextCursor, 4);
      expect(page.hasMore, isFalse);
    });

    test('rejects a cursor that moves backwards', () {
      expect(
        () => MyFincSyncPage.fromJson({
          'changes': <Object>[],
          'nextCursor': 2,
          'hasMore': false,
          'limit': 100,
        }, requestedCursor: 3),
        throwsA(isA<Exception>()),
      );
    });

    test('rejects unknown resources and malformed change records', () {
      expect(
        () => MyFincRemoteChange.fromJson({
          'resource': 'users',
          'data': {'id': 'remote-id', 'syncVersion': 1, 'syncCursor': 1},
        }),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('MyFincSyncPushResult', () {
    test('parses a confirmed result', () {
      final result = MyFincSyncPushResult.fromJson({
        'applied': true,
        'results': [
          {
            'opId': 'op-123',
            'action': 'create',
            'resource': 'accounts',
            'id': '8e7f6b7a-1234-4234-8234-123456789abc',
            'syncVersion': 1,
          },
        ],
      });

      expect(result.applied, isTrue);
      expect(result.results.single.operationId, 'op-123');
      expect(result.results.single.syncVersion, 1);
    });

    test('rejects an unconfirmed batch', () {
      expect(
        () => MyFincSyncPushResult.fromJson({
          'applied': false,
          'results': <Object>[],
        }),
        throwsA(isA<Exception>()),
      );
    });
  });
}
