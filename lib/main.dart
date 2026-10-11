import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'app/app.dart';
import 'core/notifications/fcm_service.dart';
import 'core/utils/currency_utils.dart';
import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeCurrency();

  if (Platform.isLinux) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  // Firebase options are currently configured for Android only.
  if (Platform.isAndroid) {
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      await FcmService.initialize();
    } catch (error) {
      // Push notifications must not prevent the offline-first app from opening.
      debugPrint('MyFinc FCM initialization failed: $error');
    }
  }

  runApp(const ProviderScope(child: MyFincApp()));
}
