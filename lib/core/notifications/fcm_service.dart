import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';

import '../../firebase_options.dart';
import 'notification_permission_service.dart';
import 'notification_inbox_service.dart';

/// Must be top-level so Firebase can invoke it in a background isolate.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  final title = message.notification?.title ??
      message.data['title']?.toString() ??
      'MyFinc';
  final body = message.notification?.body ??
      message.data['body']?.toString() ??
      'Tienes una nueva notificación.';
  await NotificationInboxService.instance.add(
    id: message.data['id']?.toString() ??
        message.messageId ??
        'push:${message.sentTime?.millisecondsSinceEpoch ?? DateTime.now().millisecondsSinceEpoch}',
    title: title,
    message: body,
    receivedAt: message.sentTime,
    level: message.data['level']?.toString() ?? 'info',
    source: message.data['source']?.toString() ?? 'push',
  );
}

class FcmService {
  FcmService._();

  static const String _announcementsTopic = 'myfinc_announcements';

  static final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey =
      GlobalKey<ScaffoldMessengerState>();

  static final StreamController<RemoteMessage> _openedMessages =
      StreamController<RemoteMessage>.broadcast();

  static Stream<RemoteMessage> get openedMessages => _openedMessages.stream;

  static StreamSubscription<String>? _tokenRefreshSubscription;
  static StreamSubscription<RemoteMessage>? _foregroundSubscription;
  static StreamSubscription<RemoteMessage>? _openedSubscription;
  static String? _token;

  /// Current installation token. Do not log it or commit it to the repository.
  static String? get token => _token;

  static Future<void> initialize() async {
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    // Reuse MyFinc's existing Android permission flow to avoid competing prompts.
    await NotificationPermissionService.requestPermission();

    final messaging = FirebaseMessaging.instance;
    try {
      // Broadcast announcements published from the MyFinc admin panel.
      await messaging.subscribeToTopic(_announcementsTopic);
      _token = await messaging.getToken();
    } catch (error) {
      // Token retrieval can fail temporarily; keep message listeners active.
      debugPrint('MyFinc could not retrieve the FCM token: $error');
    }

    _tokenRefreshSubscription ??= messaging.onTokenRefresh.listen((token) async {
      _token = token;
      // Reapply the broadcast subscription when Firebase rotates the token.
      try {
        await messaging.subscribeToTopic(_announcementsTopic);
      } catch (error) {
        debugPrint('MyFinc could not refresh its FCM topic subscription: $error');
      }
    });

    _foregroundSubscription ??=
        FirebaseMessaging.onMessage.listen(_showForegroundMessage);

    _openedSubscription ??=
        FirebaseMessaging.onMessageOpenedApp.listen(_handleOpenedMessage);

    final initialMessage = await messaging.getInitialMessage();
    if (initialMessage != null) {
      _handleOpenedMessage(initialMessage);
    }
  }

  static String _messageTitle(RemoteMessage message) =>
      message.notification?.title ??
      message.data['title']?.toString() ??
      'MyFinc';

  static String _messageBody(RemoteMessage message) =>
      message.notification?.body ??
      message.data['body']?.toString() ??
      'Tienes una nueva notificación.';

  static void _storeMessage(RemoteMessage message) {
    final id = message.data['id']?.toString() ??
        message.messageId ??
        'push:${message.sentTime?.millisecondsSinceEpoch ?? DateTime.now().millisecondsSinceEpoch}';
    unawaited(NotificationInboxService.instance.add(
      id: id,
      title: _messageTitle(message),
      message: _messageBody(message),
      receivedAt: message.sentTime,
      level: message.data['level']?.toString() ?? 'info',
      source: message.data['source']?.toString() ?? 'push',
    ));
  }

  static void _showForegroundMessage(RemoteMessage message) {
    _storeMessage(message);
    final title = _messageTitle(message);
    final body = _messageBody(message);

    scaffoldMessengerKey.currentState
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 5),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(body),
            ],
          ),
        ),
      );
  }

  static void _handleOpenedMessage(RemoteMessage message) {
    _storeMessage(message);
    _openedMessages.add(message);
    _showForegroundMessage(message);
  }
}
