import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'myfinc_api_client.dart';

final myfincApiClientProvider = Provider<MyFincApiClient>((ref) {
  final client = MyFincApiClient();
  ref.onDispose(client.close);
  return client;
});

/// Indicates whether this build was configured with a remote API URL.
/// Local-first mode remains available when no URL is configured.
final myfincApiConfiguredProvider = Provider<bool>(
  (ref) => ref.watch(myfincApiClientProvider).isConfigured,
);

/// Holds the short-lived remote session in memory only. It is never persisted.
final remoteAuthSessionProvider = StateProvider<MyFincApiSession?>((ref) => null);
