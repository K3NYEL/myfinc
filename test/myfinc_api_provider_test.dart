import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myfinc/core/network/providers.dart';

void main() {
  test('remote API remains optional for local-first builds', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(container.read(myfincApiConfiguredProvider), isFalse);
    expect(container.read(remoteAuthSessionProvider), isNull);
  });
}
