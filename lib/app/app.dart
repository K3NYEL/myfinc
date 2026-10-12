import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/notifications/fcm_service.dart';
import '../features/auth/presentation/session_provider.dart';
import 'router.dart';
import 'settings_provider.dart';
import 'theme/app_theme.dart';

final _lightTheme = buildAppTheme(Brightness.light);
final _darkTheme = buildAppTheme(Brightness.dark);

class MyFincApp extends ConsumerStatefulWidget {
  const MyFincApp({super.key});

  @override
  ConsumerState<MyFincApp> createState() => _MyFincAppState();
}

class _MyFincAppState extends ConsumerState<MyFincApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Lock the app when it leaves the foreground. The remembered account is
    // kept, but the in-memory session is cleared so the password is required
    // again when MyFinc is opened.
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      final session = ref.read(sessionProvider);
      if (session != null) {
        ref.read(sessionProvider.notifier).clearSession();
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);

    return MaterialApp.router(
      title: 'MyFinc',
      scaffoldMessengerKey: FcmService.scaffoldMessengerKey,
      theme: _lightTheme,
      darkTheme: _darkTheme,
      themeMode: settings.themeMode,
      locale: Locale(settings.languageCode),
      supportedLocales: const [Locale('es'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      routerConfig: ref.watch(appRouterProvider),
      builder: (context, child) {
        final mediaQuery = MediaQuery.of(context);
        return MediaQuery(
          data: mediaQuery.copyWith(
            disableAnimations: !settings.animationsEnabled,
          ),
          child: LanguageTransition(
            languageCode: settings.languageCode,
            enabled: settings.animationsEnabled,
            child: child ?? const SizedBox.shrink(),
          ),
        );
      },
      debugShowCheckedModeBanner: false,
    );
  }
}

/// Briefly dims the existing route tree when the app language changes.
/// It deliberately keeps the same child mounted to avoid duplicating GoRouter keys.
class LanguageTransition extends StatefulWidget {
  const LanguageTransition({
    super.key,
    required this.languageCode,
    required this.enabled,
    required this.child,
  });

  final String languageCode;
  final bool enabled;
  final Widget child;

  @override
  State<LanguageTransition> createState() => _LanguageTransitionState();
}

class _LanguageTransitionState extends State<LanguageTransition> {
  double _opacity = 1;

  @override
  void didUpdateWidget(covariant LanguageTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.languageCode == widget.languageCode ||
        !widget.enabled ||
        MediaQuery.disableAnimationsOf(context)) {
      _opacity = 1;
      return;
    }

    _opacity = 0.62;
    Future<void>.delayed(const Duration(milliseconds: 90), () {
      if (mounted) setState(() => _opacity = 1);
    });
  }

  @override
  Widget build(BuildContext context) => AnimatedOpacity(
        opacity: _opacity,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        child: widget.child,
      );
}
