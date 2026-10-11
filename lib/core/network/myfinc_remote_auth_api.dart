import '../errors/app_exception.dart';
import 'api_client.dart';

class MyFincRemoteUser {
  const MyFincRemoteUser({
    required this.id,
    required this.username,
    required this.createdAt,
  });

  final String id;
  final String username;
  final DateTime createdAt;

  factory MyFincRemoteUser.fromJson(Object? value) {
    if (value is! Map<String, dynamic> ||
        value['id'] is! String ||
        (value['id'] as String).isEmpty ||
        value['username'] is! String ||
        (value['username'] as String).isEmpty ||
        value['createdAt'] is! String) {
      throw const AppException('El servidor devolvió un perfil de cuenta no válido.');
    }
    final createdAt = DateTime.tryParse(value['createdAt'] as String);
    if (createdAt == null) {
      throw const AppException('El servidor devolvió un perfil de cuenta no válido.');
    }
    return MyFincRemoteUser(
      id: value['id'] as String,
      username: value['username'] as String,
      createdAt: createdAt,
    );
  }
}

/// Remote session data. Persist it only through platform secure storage.
class MyFincRemoteSession {
  const MyFincRemoteSession({
    required this.user,
    required this.accessToken,
    required this.expiresAt,
  });

  final MyFincRemoteUser user;
  final String accessToken;
  final DateTime expiresAt;

  factory MyFincRemoteSession.fromJson(Map<String, dynamic> json) {
    final token = json['accessToken'];
    final tokenType = json['tokenType'];
    final expiresAtRaw = json['expiresAt'];
    if (token is! String ||
        !RegExp(r'^[A-Za-z0-9_-]{40,60}$').hasMatch(token) ||
        tokenType != 'Bearer' ||
        expiresAtRaw is! String) {
      throw const AppException('El servidor devolvió una sesión no válida.');
    }
    final expiresAt = DateTime.tryParse(expiresAtRaw);
    if (expiresAt == null || !expiresAt.isAfter(DateTime.now().toUtc())) {
      throw const AppException('La sesión remota ya expiró o tiene una fecha no válida.');
    }
    return MyFincRemoteSession(
      user: MyFincRemoteUser.fromJson(json['user']),
      accessToken: token,
      expiresAt: expiresAt.toUtc(),
    );
  }

  bool get isExpired => !expiresAt.isAfter(DateTime.now().toUtc());
}

class MyFincRemoteAuthApi {
  MyFincRemoteAuthApi(this._client);

  final MyFincApiClient _client;

  /// Registers a remote account without linking it to a local profile.
  Future<MyFincRemoteSession> register({
    required String username,
    required String password,
  }) async {
    final normalizedUsername = username.trim().toLowerCase();
    if (!RegExp(r'^[a-z0-9][a-z0-9._-]{2,31}$').hasMatch(normalizedUsername) ||
        password.length < 12 ||
        password.length > 128) {
      throw const AppException(
        'El usuario debe tener entre 3 y 32 caracteres válidos y la contraseña entre 12 y 128 caracteres.',
      );
    }
    final json = await _client.postJson(
      '/api/v1/auth/register',
      body: <String, Object?>{
        'username': normalizedUsername,
        'password': password,
      },
    );
    return MyFincRemoteSession.fromJson(json);
  }

  /// Authenticates an existing remote account without linking local data.
  Future<MyFincRemoteSession> login({
    required String username,
    required String password,
  }) async {
    final normalizedUsername = username.trim().toLowerCase();
    if (!RegExp(r'^[a-z0-9][a-z0-9._-]{2,31}$').hasMatch(normalizedUsername) ||
        password.length < 12 ||
        password.length > 128) {
      throw const AppException('Introduce credenciales válidas para la cuenta remota.');
    }
    final json = await _client.postJson(
      '/api/v1/auth/login',
      body: <String, Object?>{
        'username': normalizedUsername,
        'password': password,
      },
    );
    return MyFincRemoteSession.fromJson(json);
  }

  Future<MyFincRemoteUser> currentUser({required String bearerToken}) async {
    if (bearerToken.trim().isEmpty) {
      throw const AppException('Debes iniciar sesión en la cuenta remota.');
    }
    final json = await _client.getJson(
      '/api/v1/auth/me',
      bearerToken: bearerToken,
    );
    return MyFincRemoteUser.fromJson(json['user']);
  }

  Future<void> logout({required String bearerToken}) async {
    if (bearerToken.trim().isEmpty) {
      throw const AppException('Debes iniciar sesión en la cuenta remota.');
    }
    await _client.postJson(
      '/api/v1/auth/logout',
      body: const <String, Object?>{},
      bearerToken: bearerToken,
    );
  }

  void close() => _client.close();
}
