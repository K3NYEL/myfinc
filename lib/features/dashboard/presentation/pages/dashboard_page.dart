import 'package:go_router/go_router.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/settings_provider.dart';
import '../../../../core/utils/currency_utils.dart';
import '../../../../core/updates/notifications_and_patches_dialog.dart';
import '../../../../core/notifications/notification_permission_service.dart';
import '../../../../core/notifications/notification_inbox_service.dart';
import '../../../../core/updates/myfinc_updates_service.dart';
import '../../../../core/settings/app_preferences.dart';
import '../../../../shared/widgets/movement_tile.dart';
import '../../../../shared/widgets/async_value_view.dart';
import '../../../../shared/widgets/myfinc_skeleton.dart';
import '../../../finance/presentation/providers.dart';

class DashboardStat extends StatelessWidget {
  final String label;
  final double value;
  final Color color;

  const DashboardStat(this.label, this.value, this.color, {super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              money(value),
              style: TextStyle(color: color, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}

class DashboardPage extends ConsumerStatefulWidget {
  const DashboardPage({super.key});

  @override
  ConsumerState<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends ConsumerState<DashboardPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _askForNotificationPermissionIfNeeded();
      _refreshPublishedNotices();
    });
  }

  Future<void> _refreshPublishedNotices() async {
    final inbox = NotificationInboxService.instance;
    await inbox.initialize();
    try {
      final manifest = await const MyFincUpdatesService().fetchManifest();
      await inbox.syncPublishedNotices(manifest.notifications);
    } catch (error) {
      debugPrint('[MYFINC INBOX] No se pudieron sincronizar los avisos: $error');
    }
  }

  Future<void> _askForNotificationPermissionIfNeeded() async {
    if (!NotificationPermissionService.isAndroid) return;
    if (await AppPreferences.getNotificationPermissionPrompted()) return;
    await AppPreferences.setNotificationPermissionPrompted(true);
    if (!mounted) return;

    final wantsNotifications = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.notifications_active_outlined),
        title: Text(ref.read(settingsProvider).languageCode == 'en' ? 'Enable notifications' : 'Activa las notificaciones'),
        content: Text(
          (ref.read(settingsProvider).languageCode == 'en' ? 'Allow notifications to receive MyFinc updates. You can change this permission at any time in your phone settings.' : 'Permite las notificaciones para recibir avisos de MyFinc. Puedes cambiar este permiso en cualquier momento desde la configuración del teléfono.'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(ref.read(settingsProvider).languageCode == 'en' ? 'Not now' : 'Ahora no'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(ref.read(settingsProvider).languageCode == 'en' ? 'Continue' : 'Continuar'),
          ),
        ],
      ),
    );
    if (wantsNotifications != true || !mounted) return;
    try {
      await NotificationPermissionService.requestPermission();
    } on PlatformException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ref.read(settingsProvider).languageCode == 'en' ? 'Could not request permission. You can review it in Settings.' : 'No se pudo solicitar el permiso. Puedes revisarlo en Configuración.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEnglish = ref.watch(settingsProvider).languageCode == 'en';
    final accountsState = ref.watch(accountsProvider);
    final summaryState = ref.watch(summaryProvider);
    final movementsState = ref.watch(movementsProvider);
    final theme = Theme.of(context);
    final mutedStyle = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'MyFinc',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(isEnglish ? 'Your financial overview' : 'Tu resumen financiero', style: mutedStyle),
                ],
              ),
            ),
            AnimatedBuilder(
              animation: NotificationInboxService.instance,
              builder: (context, _) => Stack(
                clipBehavior: Clip.none,
                children: [
                  IconButton(
                    tooltip: isEnglish ? 'Notifications and patches' : 'Notificaciones y parches',
                    onPressed: () => showDialog<void>(
                      context: context,
                      builder: (_) => const NotificationsAndPatchesDialog(),
                    ),
                    icon: const Icon(Icons.notifications_active_outlined),
                  ),
                  if (NotificationInboxService.instance.hasPending)
                    Positioned(
                      top: 7,
                      right: 7,
                      child: Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: const Color(0xFFEF4444),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Theme.of(context).scaffoldBackgroundColor,
                            width: 1.5,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            IconButton(
              tooltip: isEnglish ? 'Settings' : 'Configuración',
              onPressed: () => context.push('/settings'),
              icon: const Icon(Icons.settings_outlined),
            ),
            IconButton(
              tooltip: isEnglish ? 'Calculator' : 'Calculadora',
              onPressed: () => context.push('/calculator'),
              icon: const Icon(Icons.calculate_outlined),
            ),
          ],
        ),
        const SizedBox(height: 20),
        AsyncValueView(
          state: summaryState,
          onRetry: () => ref.invalidate(summaryProvider),
          loading: const Row(
            children: [
              Expanded(child: SkeletonCard(height: 82)),
              SizedBox(width: 12),
              Expanded(child: SkeletonCard(height: 82)),
            ],
          ),
          data: (summary) => Row(
            children: [
              Expanded(
                child: DashboardStat(
                  isEnglish ? 'Income' : 'Ingresos',
                  summary.income,
                  theme.brightness == Brightness.dark
                      ? AppColors.success
                      : const Color(0xFF15803D),
                ),
              ),
              Expanded(
                child: DashboardStat(
                  isEnglish ? 'Expenses' : 'Gastos',
                  summary.expense,
                  theme.colorScheme.error,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Text(isEnglish ? 'Accounts' : 'Cuentas', style: theme.textTheme.titleMedium),
        AsyncValueView(
          state: accountsState,
          onRetry: () => ref.invalidate(accountsProvider),
          loading: const Column(
            children: [
              SizedBox(height: 12),
              SkeletonCard(height: 64),
              SizedBox(height: 8),
              SkeletonCard(height: 64),
            ],
          ),
          data: (accounts) => accounts.isEmpty
              ? Text(
                  isEnglish ? 'Create your first account in the Accounts tab.' : 'Crea tu primera cuenta en la pestaña Cuentas.',
                  style: mutedStyle,
                )
              : Column(
                  children: [
                    for (final account in accounts)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(account.name),
                        trailing: Text(money(account.balance)),
                      ),
                  ],
                ),
        ),
        const SizedBox(height: 16),
        Text(isEnglish ? 'Recent transactions' : 'Movimientos recientes', style: theme.textTheme.titleMedium),
        AsyncValueView(
          state: movementsState,
          onRetry: () => ref.invalidate(movementsProvider),
          loading: const Column(
            children: [
              SizedBox(height: 12),
              SkeletonCard(height: 68),
              SizedBox(height: 8),
              SkeletonCard(height: 68),
              SizedBox(height: 8),
              SkeletonCard(height: 68),
            ],
          ),
          data: (movements) => movements.isEmpty
              ? Text(isEnglish ? 'No transactions yet.' : 'Aún no hay movimientos.', style: mutedStyle)
              : Column(
                  children: [
                    for (final movement in movements.take(5))
                      MovementTile(movement),
                  ],
                ),
        ),
      ],
    );
  }
}
