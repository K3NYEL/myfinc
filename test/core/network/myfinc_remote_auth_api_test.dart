import 'package:flutter_test/flutter_test.dart';
import 'package:myfinc/core/network/api_client.dart';
import 'package:myfinc/core/network/myfinc_remote_auth_api.dart';

void main() {
  group('MyFincRemoteAuthApi registration validation', () {
    test('rejects usernames outside the server contract before networking', () async {
      final client = MyFincApiClient();
      final api = MyFincRemoteAuthApi(client);
      addTearDown(client.close);

      await expectLater(
        api.register(username: 'x', password: 'correct-horse-battery'),
        throwsA(isA<Exception>()),
      );
    });

    test('rejects passwords shorter than the server contract before networking', () async {
      final client = MyFincApiClient();
      final api = MyFincRemoteAuthApi(client);
      addTearDown(client.close);

      await expectLater(
        api.register(username: 'myfinc_user', password: 'short'),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('MyFincRemoteSession', () {
    test('parses a valid in-memory session', () {
      final session = MyFincRemoteSession.fromJson({
        'user': {
          'id': '8e7f6b7a-1234-4234-8234-123456789abc',
          'username': 'myfinc_user',
          'createdAt': '2026-10-01T12:00:00.000Z',
        },
        'accessToken': List.filled(43, 'a').join(),
        'tokenType': 'Bearer',
        'expiresAt': '2099-01-01T00:00:00.000Z',
      });

      expect(session.user.username, 'myfinc_user');
      expect(session.accessToken, hasLength(43));
      expect(session.isExpired, isFalse);
    });

    test('rejects the legacy firstName/lastName API response contract', () {
      expect(
        () => MyFincRemoteSession.fromJson({
          'user': {
            'id': 'remote-user',
            'firstName': 'MyFinc',
            'lastName': 'User',
            'loginIdentifier': 'myfinc_user',
          },
          'accessToken': List.filled(43, 'a').join(),
          'tokenType': 'Bearer',
          'expiresAt': '2099-01-01T00:00:00.000Z',
        }),
        throwsA(isA<Exception>()),
      );
    });

    test('rejects non-Bearer token types from the API', () {
      expect(
        () => MyFincRemoteSession.fromJson({
          'user': {
            'id': 'remote-user',
            'username': 'myfinc_user',
            'createdAt': '2026-10-01T12:00:00.000Z',
          },
          'accessToken': List.filled(43, 'a').join(),
          'tokenType': 'Basic',
          'expiresAt': '2099-01-01T00:00:00.000Z',
        }),
        throwsA(isA<Exception>()),
      );
    });

    test('rejects malformed bearer tokens', () {
      expect(
        () => MyFincRemoteSession.fromJson({
          'user': {
            'id': 'remote-user',
            'username': 'myfinc_user',
            'createdAt': '2026-10-01T12:00:00.000Z',
          },
          'accessToken': 'not-a-token',
          'tokenType': 'Bearer',
          'expiresAt': '2099-01-01T00:00:00.000Z',
        }),
        throwsA(isA<Exception>()),
      );
    });

    test('rejects expired sessions', () {
      expect(
        () => MyFincRemoteSession.fromJson({
          'user': {
            'id': 'remote-user',
            'username': 'myfinc_user',
            'createdAt': '2026-10-01T12:00:00.000Z',
          },
          'accessToken': List.filled(43, 'a').join(),
          'tokenType': 'Bearer',
          'expiresAt': '2000-01-01T00:00:00.000Z',
        }),
        throwsA(isA<Exception>()),
      );
    });
  });
}
