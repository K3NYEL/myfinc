import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class MyFincNotice {
  const MyFincNotice({
    required this.id,
    required this.title,
    required this.message,
    required this.publishedAt,
    this.level = 'info',
  });

  final String id;
  final String title;
  final String message;
  final DateTime? publishedAt;
  final String level;

  factory MyFincNotice.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final title = json['title'];
    final message = json['message'];
    if (id is! String || id.trim().isEmpty ||
        title is! String || title.trim().isEmpty ||
        message is! String || message.trim().isEmpty) {
      throw const FormatException('Aviso incompleto en el manifiesto.');
    }
    return MyFincNotice(
      id: id,
      title: title,
      message: message,
      publishedAt: DateTime.tryParse(json['publishedAt'] as String? ?? ''),
      level: json['level'] as String? ?? 'info',
    );
  }
}

class MyFincPatch {
  const MyFincPatch({
    required this.id,
    required this.version,
    required this.title,
    required this.summary,
    required this.notes,
    required this.releaseUrl,
    required this.publishedAt,
    required this.required,
  });

  final String id;
  final String version;
  final String title;
  final String summary;
  final List<String> notes;
  final Uri? releaseUrl;
  final DateTime? publishedAt;
  final bool required;

  factory MyFincPatch.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final version = json['version'];
    final title = json['title'];
    final summary = json['summary'];
    if (id is! String || id.trim().isEmpty ||
        version is! String || version.trim().isEmpty ||
        title is! String || title.trim().isEmpty ||
        summary is! String || summary.trim().isEmpty) {
      throw const FormatException('Parche incompleto en el manifiesto.');
    }
    final rawNotes = json['notes'];
    final notes = rawNotes is List
        ? rawNotes.whereType<String>().take(30).toList(growable: false)
        : const <String>[];
    final rawUrl = Uri.tryParse(json['releaseUrl'] as String? ?? '');
    final releaseUrl = rawUrl != null &&
            rawUrl.scheme == 'https' &&
            rawUrl.host == 'github.com' &&
            rawUrl.path.startsWith('/K3NYEL/myfinc/releases/')
        ? rawUrl
        : null;
    return MyFincPatch(
      id: id,
      version: version,
      title: title,
      summary: summary,
      notes: notes,
      releaseUrl: releaseUrl,
      publishedAt: DateTime.tryParse(json['publishedAt'] as String? ?? ''),
      required: json['required'] == true,
    );
  }
}

class MyFincUpdatesManifest {
  const MyFincUpdatesManifest({
    required this.updatedAt,
    required this.notifications,
    required this.patches,
  });

  final DateTime? updatedAt;
  final List<MyFincNotice> notifications;
  final List<MyFincPatch> patches;

  factory MyFincUpdatesManifest.fromJson(Map<String, dynamic> json) {
    if (json['schemaVersion'] != 1) {
      throw const FormatException('Versión del manifiesto no compatible.');
    }
    final rawNotifications = json['notifications'];
    final rawPatches = json['patches'];
    if (rawNotifications is! List || rawPatches is! List) {
      throw const FormatException('El manifiesto no contiene listas válidas.');
    }
    return MyFincUpdatesManifest(
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? ''),
      notifications: rawNotifications
          .whereType<Map<String, dynamic>>()
          .take(50)
          .map(MyFincNotice.fromJson)
          .toList(growable: false),
      patches: rawPatches
          .whereType<Map<String, dynamic>>()
          .take(30)
          .map(MyFincPatch.fromJson)
          .toList(growable: false),
    );
  }
}

class MyFincUpdatesService {
  const MyFincUpdatesService();

  static final Uri _manifestUri = Uri.parse(
    'https://k3nyel.github.io/myfinc/updates/manifest.json',
  );

  Future<MyFincUpdatesManifest> fetchManifest() async {
    try {
      final response = await http.get(
        _manifestUri.replace(queryParameters: {
          'v': DateTime.now().millisecondsSinceEpoch.toString(),
        }),
        headers: const {
          'Accept': 'application/json',
          'Cache-Control': 'no-cache',
        },
      ).timeout(const Duration(seconds: 12));

      if (response.statusCode != 200) {
        throw MyFincUpdatesException(
          'El servidor de avisos respondió HTTP ${response.statusCode}.',
        );
      }
      if (response.bodyBytes.length > 256 * 1024) {
        throw const MyFincUpdatesException(
          'El manifiesto supera el tamaño permitido.',
        );
      }

      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! Map<String, dynamic>) {
        throw const MyFincUpdatesException(
          'El manifiesto de MyFinc no tiene un formato válido.',
        );
      }
      return MyFincUpdatesManifest.fromJson(decoded);
    } on TimeoutException {
      throw const MyFincUpdatesException(
        'La consulta de avisos agotó el tiempo de espera.',
      );
    } on FormatException {
      throw const MyFincUpdatesException(
        'El manifiesto de avisos contiene datos inválidos.',
      );
    } on MyFincUpdatesException {
      rethrow;
    } catch (error) {
      debugPrint('[MYFINC NOTICES] No se pudo consultar el manifiesto: $error');
      throw const MyFincUpdatesException(
        'No fue posible conectar con el servicio de notificaciones y parches.',
      );
    }
  }
}

class MyFincUpdatesException implements Exception {
  const MyFincUpdatesException(this.message);

  final String message;

  @override
  String toString() => message;
}
