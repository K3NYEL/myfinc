import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../updates/myfinc_updates_service.dart';

class InboxNotification {
  const InboxNotification({
    required this.id,
    required this.title,
    required this.message,
    required this.receivedAt,
    this.level = 'info',
    this.source = 'push',
  });

  final String id;
  final String title;
  final String message;
  final DateTime receivedAt;
  final String level;
  final String source;

  Map<String, Object?> toJson() => {
        'id': id,
        'title': title,
        'message': message,
        'receivedAt': receivedAt.toIso8601String(),
        'level': level,
        'source': source,
      };

  factory InboxNotification.fromJson(Map<String, dynamic> json) =>
      InboxNotification(
        id: json['id'] as String,
        title: json['title'] as String? ?? 'MyFinc',
        message: json['message'] as String? ?? '',
        receivedAt: DateTime.tryParse(json['receivedAt'] as String? ?? '') ??
            DateTime.now(),
        level: json['level'] as String? ?? 'info',
        source: json['source'] as String? ?? 'push',
      );
}

class NotificationInboxService extends ChangeNotifier {
  NotificationInboxService._();

  static final NotificationInboxService instance = NotificationInboxService._();
  static const _itemsKey = 'myfinc.notification_inbox.v1';
  static const _dismissedKey = 'myfinc.notification_inbox.dismissed.v1';

  final List<InboxNotification> _items = [];
  final Set<String> _dismissedIds = {};
  bool _initialized = false;

  List<InboxNotification> get items =>
      List<InboxNotification>.unmodifiable(_items);
  int get pendingCount => _items.length;
  bool get hasPending => _items.isNotEmpty;

  Future<void> initialize() async {
    if (_initialized) return;
    final prefs = await SharedPreferences.getInstance();
    _dismissedIds
      ..clear()
      ..addAll(prefs.getStringList(_dismissedKey) ?? const <String>[]);
    final rawItems = prefs.getStringList(_itemsKey) ?? const <String>[];
    _items.clear();
    for (final raw in rawItems) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) {
          final item = InboxNotification.fromJson(decoded);
          if (!_dismissedIds.contains(item.id)) _items.add(item);
        }
      } on FormatException {
        // Skip corrupt records and preserve the rest of the inbox.
      } on TypeError {
        // Skip records written by an incompatible schema.
      }
    }
    _items.sort((a, b) => b.receivedAt.compareTo(a.receivedAt));
    _initialized = true;
    notifyListeners();
  }

  Future<void> add({
    required String id,
    required String title,
    required String message,
    DateTime? receivedAt,
    String level = 'info',
    String source = 'push',
  }) async {
    await initialize();
    if (_dismissedIds.contains(id)) return;
    _items.removeWhere((item) => item.id == id);
    _items.insert(
      0,
      InboxNotification(
        id: id,
        title: title.trim().isEmpty ? 'MyFinc' : title.trim(),
        message: message,
        receivedAt: receivedAt ?? DateTime.now(),
        level: level,
        source: source,
      ),
    );
    if (_items.length > 100) _items.removeRange(100, _items.length);
    await _save();
    notifyListeners();
  }

  Future<void> syncPublishedNotices(List<MyFincNotice> notices) async {
    await initialize();
    for (final notice in notices) {
      await add(
        id: 'manifest:${notice.id}',
        title: notice.title,
        message: notice.message,
        receivedAt: notice.publishedAt ?? DateTime.now(),
        level: notice.level,
        source: 'notice',
      );
    }
  }

  Future<void> dismiss(String id) async {
    await initialize();
    _items.removeWhere((item) => item.id == id);
    _dismissedIds.add(id);
    await _save();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_dismissedKey, _dismissedIds.toList());
    notifyListeners();
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _itemsKey,
      _items.map((item) => jsonEncode(item.toJson())).toList(),
    );
  }
}
