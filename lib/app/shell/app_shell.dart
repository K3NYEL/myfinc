import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../settings_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class AppShell extends ConsumerWidget {
  final Widget child;
  const AppShell({super.key, required this.child});

  static const _tabs = ['/', '/statistics', '/transactions', '/accounts'];

  void _add(BuildContext context, bool isEnglish) => showModalBottomSheet(
        context: context,
        builder: (_) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(isEnglish ? 'What would you like to add?' : '¿Qué quieres registrar?'),
              ),
              for (final (kind, label, icon) in [
                ('income', isEnglish ? 'Income' : 'Ingreso', Icons.arrow_upward),
                ('expense', isEnglish ? 'Expense' : 'Gasto', Icons.arrow_downward),
                ('transfer', isEnglish ? 'Transfer' : 'Transferir', Icons.swap_horiz),
              ])
                ListTile(
                  leading: Icon(icon),
                  title: Text(label),
                  onTap: () {
                    Navigator.pop(context);
                    context.push('/transactions/new/$kind');
                  },
                ),
            ],
          ),
        ),
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isEnglish = ref.watch(settingsProvider).languageCode == 'en';
    final path = GoRouterState.of(context).uri.path;
    final selectedIndex = _tabs.indexOf(path).clamp(0, _tabs.length - 1);
    final isDesktop = MediaQuery.sizeOf(context).width >= 900;
    return Scaffold(
      body: ColoredBox(
        color: Theme.of(context).scaffoldBackgroundColor,
        child: SafeArea(
          child: Row(
          children: [
            if (isDesktop) _desktopNavigation(context, selectedIndex, isEnglish),
            // GoRouter owns the page subtree and its GlobalKey. Keeping the
            // previous route alive in AnimatedSwitcher can duplicate that key
            // when the next ShellRoute child is mounted.
            Expanded(
              child: ColoredBox(
                color: Theme.of(context).scaffoldBackgroundColor,
                child: child,
              ),
            ),
          ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _add(context, isEnglish),
        tooltip: isEnglish ? 'Add transaction' : 'Agregar movimiento',
        child: const Icon(Icons.add),
      ),
      bottomNavigationBar:
          isDesktop ? null : _mobileNavigation(context, selectedIndex, isEnglish),
    );
  }

  Widget _mobileNavigation(BuildContext context, int selectedIndex, bool isEnglish) =>
      NavigationBar(
        selectedIndex: selectedIndex,
        onDestinationSelected: (index) => context.go(_tabs[index]),
        destinations: _destinations(isEnglish),
      );

  Widget _desktopNavigation(BuildContext context, int selectedIndex, bool isEnglish) =>
      NavigationRail(
        selectedIndex: selectedIndex,
        onDestinationSelected: (index) => context.go(_tabs[index]),
        labelType: NavigationRailLabelType.all,
        leading: Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Text(
            'MyFinc',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
        ),
        destinations: [
          for (final destination in _destinations(isEnglish))
            NavigationRailDestination(
              icon: destination.icon,
              label: Text(destination.label),
            ),
        ],
      );

  static List<NavigationDestination> _destinations(bool isEnglish) => [
    NavigationDestination(icon: const Icon(Icons.home_outlined), label: isEnglish ? 'Home' : 'Inicio'),
    NavigationDestination(
        icon: const Icon(Icons.pie_chart_outline), label: isEnglish ? 'Statistics' : 'Estadísticas'),
    NavigationDestination(
        icon: const Icon(Icons.receipt_long_outlined), label: isEnglish ? 'Transactions' : 'Movimientos'),
    NavigationDestination(
        icon: const Icon(Icons.account_balance_wallet_outlined), label: isEnglish ? 'Accounts' : 'Cuentas'),
  ];
}
