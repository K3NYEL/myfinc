import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../core/errors/app_exception.dart';
import '../../../../core/utils/amount_parser.dart';
import '../../../../core/utils/currency_utils.dart';
import 'currency_converter_page.dart';
import '../../../../shared/widgets/async_state_view.dart';
import '../../../../shared/widgets/movement_tile.dart';
import '../../../../shared/widgets/myfinc_skeleton.dart';
import '../../../auth/presentation/session_provider.dart';
import '../providers.dart';

String _tr(BuildContext context, String spanish, String english) =>
    Localizations.localeOf(context).languageCode == 'en' ? english : spanish;

TextStyle _muted(BuildContext context) => TextStyle(
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    );

class TransactionsPage extends ConsumerStatefulWidget {
  const TransactionsPage({super.key});

  @override
  ConsumerState<TransactionsPage> createState() => _TransactionsPageState();
}

class _TransactionsPageState extends ConsumerState<TransactionsPage> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filter = ref.watch(filterProvider);
    final movements = ref.watch(movementsProvider);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    if (movements.hasError) {
      return AsyncStateView(
        error: movements.error,
        onRetry: () => ref.invalidate(movementsProvider),
      );
    }
    if (movements.isLoading) return const TransactionsSkeleton();

    final all = movements.value ?? [];
    final income = all.where((m) => m.kind == 'income')
        .fold<double>(0, (sum, m) => sum + m.amount);
    final expenses = all.where((m) => m.kind == 'expense')
        .fold<double>(0, (sum, m) => sum + m.amount);
    final normalizedQuery = _query.trim().toLowerCase();
    final list = all.where((movement) {
      final matchesKind = filter == 'all' || movement.kind == filter;
      final searchable = '${movement.title} ${movement.subtitle} ${movement.date}'
          .toLowerCase();
      return matchesKind && (normalizedQuery.isEmpty || searchable.contains(normalizedQuery));
    }).toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_tr(context, 'Movimientos', 'Transactions'), style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        )),
                        const SizedBox(height: 3),
                        Text(_tr(context, '${all.length} movimientos cargados', '${all.length} transactions loaded'),
                          style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: _tr(context, 'Conversor de monedas', 'Currency converter'),
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const CurrencyConverterPage(),
                      ),
                    ),
                    icon: const Icon(Icons.currency_exchange_rounded),
                  ),
                  IconButton(
                    tooltip: _tr(context, 'Actualizar movimientos', 'Refresh transactions'),
                    onPressed: () => ref.invalidate(movementsProvider),
                    icon: const Icon(Icons.refresh_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _searchController,
                onChanged: (value) => setState(() => _query = value),
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: _tr(context, 'Buscar por concepto o detalle', 'Search by description or details'),
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: _query.isEmpty ? null : IconButton(
                    tooltip: _tr(context, 'Limpiar búsqueda', 'Clear search'),
                    onPressed: () {
                      _searchController.clear();
                      setState(() => _query = '');
                    },
                    icon: const Icon(Icons.close_rounded),
                  ),
                  filled: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: _MovementSummaryCard(
                      label: _tr(context, 'Ingresos recientes', 'Recent income'),
                      amount: income,
                      icon: Icons.south_west_rounded,
                      color: const Color(0xFF16A34A),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _MovementSummaryCard(
                      label: _tr(context, 'Gastos recientes', 'Recent expenses'),
                      amount: expenses,
                      icon: Icons.north_east_rounded,
                      color: scheme.error,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final (kind, label, icon) in [
                      ('all', 'Todos', Icons.swap_vert_rounded),
                      ('income', 'Ingresos', Icons.south_west_rounded),
                      ('expense', 'Gastos', Icons.north_east_rounded),
                    ])
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          avatar: Icon(icon, size: 17),
                          label: Text(label),
                          selected: filter == kind,
                          onSelected: (_) => ref.read(filterProvider.notifier).state = kind,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: list.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(28),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          normalizedQuery.isNotEmpty ? Icons.search_off_rounded : Icons.receipt_long_outlined,
                          size: 44,
                          color: scheme.onSurfaceVariant,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          normalizedQuery.isNotEmpty
                              ? _tr(context, 'No encontramos movimientos con esa búsqueda.', 'No transactions matched your search.')
                              : filter == 'all'
                                  ? _tr(context, 'Aún no hay movimientos.', 'No transactions yet.')
                                  : filter == 'income'
                                      ? _tr(context, 'Todavía no hay ingresos registrados.', 'No income recorded yet.')
                                      : _tr(context, 'Todavía no hay gastos registrados.', 'No expenses recorded yet.'),
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                        if (normalizedQuery.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          TextButton.icon(
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _query = '');
                            },
                            icon: const Icon(Icons.clear_rounded),
                            label: Text(_tr(context, 'Limpiar búsqueda', 'Clear search')),
                          ),
                        ],
                      ],
                    ),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                  itemCount: list.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) => MovementTile(list[index]),
                ),
        ),
      ],
    );
  }
}

class _MovementSummaryCard extends StatelessWidget {
  const _MovementSummaryCard({
    required this.label,
    required this.amount,
    required this.icon,
    required this.color,
  });

  final String label;
  final double amount;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(13),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: color),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(label, style: theme.textTheme.labelLarge?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  )),
                ),
              ],
            ),
            const SizedBox(height: 9),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                money(amount),
                style: theme.textTheme.titleMedium?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Widget _profileDetail(
  BuildContext context, {
  required IconData icon,
  required String label,
  required String value,
}) {
  return Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, size: 18, color: Theme.of(context).colorScheme.onSurfaceVariant),
      const SizedBox(width: 8),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: _muted(context)),
            const SizedBox(height: 2),
            Text(value, style: Theme.of(context).textTheme.bodyMedium),
          ],
        ),
      ),
    ],
  );
}

class AccountsPage extends ConsumerStatefulWidget {
  const AccountsPage({super.key});

  @override
  ConsumerState<AccountsPage> createState() => _AccountsPageState();
}

class _AccountsPageState extends ConsumerState<AccountsPage> {
  static const _profileColors = <Color>[
    Color(0xFF2563EB),
    Color(0xFF0D9488),
    Color(0xFF7C3AED),
    Color(0xFFDB2777),
    Color(0xFFEA580C),
    Color(0xFF16A34A),
    Color(0xFF475569),
    Color(0xFF0891B2),
  ];
  static const _profileAvatars = <IconData>[
    Icons.person_rounded,
    Icons.face_rounded,
    Icons.emoji_emotions_rounded,
    Icons.pets_rounded,
    Icons.spa_rounded,
    Icons.sports_esports_rounded,
    Icons.music_note_rounded,
    Icons.star_rounded,
  ];

  String? _profileName;
  String? _profileBio;
  int _profileColor = 0;
  int _profileAvatar = 0;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final user = ref.read(sessionProvider);
    if (user == null) return;
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString('profile_display_name:${user.id}') ?? user.fullName;
    final bio = prefs.getString('profile_bio:${user.id}') ?? '';
    final color = (prefs.getInt('profile_color:${user.id}') ?? 0)
        .clamp(0, _profileColors.length - 1).toInt();
    final avatar = (prefs.getInt('profile_avatar:${user.id}') ?? 0)
        .clamp(0, _profileAvatars.length - 1).toInt();
    if (!mounted) return;
    setState(() {
      _profileName = name;
      _profileBio = bio;
      _profileColor = color;
      _profileAvatar = avatar;
    });
  }

  Future<void> _new(BuildContext c, WidgetRef ref) async {
    final name = TextEditingController();
    final balance = TextEditingController();
    var type = 'bank';
    try {
      await showDialog(
        context: c,
        builder: (_) => StatefulBuilder(
          builder: (ctx, set) => AlertDialog(
            title: Text(_tr(context, 'Nueva cuenta', 'New account')),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: name,
                  decoration: InputDecoration(labelText: _tr(context, 'Nombre', 'Name')),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: type,
                  onChanged: (value) {
                    if (value != null) set(() => type = value);
                  },
                  items: [
                    DropdownMenuItem(value: 'cash', child: Text(_tr(context, 'Efectivo', 'Cash'))),
                    DropdownMenuItem(value: 'bank', child: Text(_tr(context, 'Banco', 'Bank'))),
                    DropdownMenuItem(value: 'savings', child: Text(_tr(context, 'Ahorros', 'Savings'))),
                    DropdownMenuItem(value: 'card', child: Text(_tr(context, 'Tarjeta', 'Card'))),
                    DropdownMenuItem(value: 'other', child: Text(_tr(context, 'Otra', 'Other'))),
                  ],
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: balance,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration:
                      InputDecoration(labelText: _tr(context, 'Balance inicial', 'Opening balance')),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(_tr(context, 'Cancelar', 'Cancel')),
              ),
              FilledButton(
                onPressed: () async {
                  try {
                    await ref.read(repoProvider).addAccount(
                          name.text,
                          type,
                          parseAmount(balance.text) ?? 0,
                        );
                    refreshAccounts(ref);
                    if (ctx.mounted) Navigator.of(ctx).pop();
                  } on AppException catch (e) {
                    if (ctx.mounted) {
                      ScaffoldMessenger.of(ctx).showSnackBar(
                        SnackBar(content: Text(e.message)),
                      );
                    }
                  }
                },
                child: Text(_tr(context, 'Guardar', 'Save')),
              ),
            ],
          ),
        ),
      );
    } finally {
      name.dispose();
      balance.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final accounts = ref.watch(accountsProvider);
    if (accounts.hasError) {
      return AsyncStateView(
        error: accounts.error,
        onRetry: () => ref.invalidate(accountsProvider),
      );
    }
    if (accounts.isLoading) return const AccountsSkeleton();
    final accountList = accounts.value ?? [];
    final total = accountList.fold<double>(0, (sum, account) => sum + account.balance);
    final user = ref.watch(sessionProvider);
    final localizations = MaterialLocalizations.of(context);

    String formatDateTime(DateTime? value) {
      if (value == null) return 'Sin registro';
      final local = value.toLocal();
      final date = localizations.formatMediumDate(local);
      final time = localizations.formatTimeOfDay(TimeOfDay.fromDateTime(local));
      return '$date · $time';
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(_tr(context, 'Mis cuentas', 'My accounts'), style: Theme.of(context).textTheme.titleLarge),
            IconButton(
              tooltip: _tr(context, 'Crear cuenta', 'Create account'),
              onPressed: () => _new(context, ref),
              icon: const Icon(Icons.add),
            ),
          ],
        ),
        Card(
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 27,
                      backgroundColor: _profileColors[_profileColor],
                      foregroundColor: Colors.white,
                      child: Icon(_profileAvatars[_profileAvatar], size: 30),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _profileName?.trim().isNotEmpty == true
                                ? _profileName!.trim()
                                : (user?.fullName.trim().isNotEmpty == true
                                    ? user!.fullName.trim()
                                    : 'Perfil local'),
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Perfil de este dispositivo',
                            style: _muted(context),
                          ),
                          if (_profileBio?.trim().isNotEmpty == true) ...[
                            const SizedBox(height: 6),
                            Text(
                              _profileBio!.trim(),
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      showDialog<void>(
                        context: context,
                        builder: (dialogContext) => AlertDialog(
                          title: Text(_tr(context, 'Detalles de la cuenta', 'Account details')),
                          content: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(_tr(context, 'ID de usuario', 'User ID'), style: _muted(dialogContext)),
                              const SizedBox(height: 4),
                              SelectableText(
                                user == null
                                    ? 'No disponible'
                                    : user.id.replaceFirst(RegExp(r'^usr_'), ''),
                                style: Theme.of(dialogContext).textTheme.bodyMedium?.copyWith(
                                      fontFamily: 'monospace',
                                    ),
                              ),
                              const SizedBox(height: 16),
                              _profileDetail(
                                dialogContext,
                                icon: Icons.event_outlined,
                                label: _tr(context, 'Cuenta creada', 'Account created'),
                                value: formatDateTime(user?.createdAt),
                              ),
                              const SizedBox(height: 8),
                              _profileDetail(
                                dialogContext,
                                icon: Icons.login_rounded,
                                label: _tr(context, 'Último acceso', 'Last sign-in'),
                                value: formatDateTime(user?.lastLogin),
                              ),
                            ],
                          ),
                          actions: [
                            if (user != null)
                              TextButton.icon(
                                onPressed: () async {
                                  await Clipboard.setData(
                                    ClipboardData(
                                      text: user.id.replaceFirst(RegExp(r'^usr_'), ''),
                                    ),
                                  );
                                  if (dialogContext.mounted) {
                                    Navigator.of(dialogContext).pop();
                                  }
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text(_tr(context, 'ID copiado', 'ID copied'))),
                                    );
                                  }
                                },
                                icon: const Icon(Icons.copy_rounded),
                                label: Text(_tr(context, 'Copiar ID', 'Copy ID')),
                              ),
                            TextButton(
                              onPressed: () => Navigator.of(dialogContext).pop(),
                              child: Text(_tr(context, 'Cerrar', 'Close')),
                            ),
                          ],
                        ),
                      );
                    },
                    icon: const Icon(Icons.info_outline_rounded),
                    label: Text(_tr(context, 'Ver detalles', 'View details')),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final messenger = ScaffoldMessenger.of(context);
                      final saved = await context.push<bool>('/settings/profile');
                      await _loadProfile();
                      if (!context.mounted) return;
                      if (saved == true) {
                        messenger.showSnackBar(
                          SnackBar(
                            content: Text(_tr(context, 'Personalización guardada y aplicada al perfil.', 'Profile customization saved and applied.')),
                          ),
                        );
                      }
                    },
                    icon: const Icon(Icons.manage_accounts_outlined),
                    label: Text(_tr(context, 'Personalizar perfil', 'Customize profile')),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (accountList.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: Text(_tr(context, 'Todavía no tienes cuentas.', 'You do not have any accounts yet.'), style: _muted(context)),
            ),
          ),
        for (final account in accountList)
          Card(
            child: ListTile(
              title: Text(account.name),
              subtitle: Text(account.type, style: _muted(context)),
              trailing: Text(money(account.balance)),
            ),
          ),
        const Divider(height: 32),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(_tr(context, 'Total', 'Total'), style: _muted(context)),
            Text(money(total), style: Theme.of(context).textTheme.titleLarge),
          ],
        ),
      ],
    );
  }
}

class StatisticsPage extends ConsumerWidget {
  const StatisticsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(summaryProvider);
    final categories = ref.watch(byCategoryProvider);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    if (summary.hasError || categories.hasError) {
      return AsyncStateView(
        error: summary.hasError ? summary.error : categories.error,
        onRetry: () {
          ref.invalidate(summaryProvider);
          ref.invalidate(byCategoryProvider);
        },
      );
    }
    if (summary.isLoading || categories.isLoading) {
      return const StatisticsSkeleton();
    }

    final data = summary.value;
    final income = data?.income ?? 0;
    final expenses = data?.expense ?? 0;
    final balance = data?.balance ?? 0;
    final categoryTotals = categories.value ?? [];
    final maxValue = categoryTotals.isEmpty
        ? 1.0
        : categoryTotals.map((entry) => entry.$2).reduce((a, b) => a > b ? a : b);
    final totalCategorySpend = categoryTotals.fold<double>(
      0,
      (sum, entry) => sum + entry.$2,
    );
    final comparisonTotal = income + expenses;
    final incomeRatio = comparisonTotal == 0 ? 0.0 : income / comparisonTotal;
    final expenseRatio = comparisonTotal == 0 ? 0.0 : expenses / comparisonTotal;

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(summaryProvider);
        ref.invalidate(byCategoryProvider);
        await Future.wait([
          ref.read(summaryProvider.future),
          ref.read(byCategoryProvider.future),
        ]);
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_tr(context, 'Estadísticas', 'Statistics'), style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    )),
                    const SizedBox(height: 4),
                    Text(
                      _tr(context, 'Resumen de este mes', "This month's summary"),
                      style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: _tr(context, 'Actualizar estadísticas', 'Refresh statistics'),
                onPressed: () {
                  ref.invalidate(summaryProvider);
                  ref.invalidate(byCategoryProvider);
                },
                icon: const Icon(Icons.refresh_rounded),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Card(
            clipBehavior: Clip.antiAlias,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    scheme.primaryContainer,
                    scheme.primaryContainer.withValues(alpha: 0.45),
                  ],
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.account_balance_wallet_outlined, color: scheme.onPrimaryContainer),
                      const SizedBox(width: 8),
                      Text(
                        'Balance del mes',
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: scheme.onPrimaryContainer,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      money(balance),
                      style: theme.textTheme.headlineMedium?.copyWith(
                        color: scheme.onPrimaryContainer,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    balance >= 0 ? _tr(context, 'Vas por encima de tus gastos', 'You are spending less than you earn') : _tr(context, 'Tus gastos superan tus ingresos', 'Your expenses exceed your income'),
                    style: theme.textTheme.bodySmall?.copyWith(color: scheme.onPrimaryContainer),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _StatisticsMetricCard(
                  label: _tr(context, 'Ingresos', 'Income'),
                  value: income,
                  icon: Icons.trending_up_rounded,
                  color: const Color(0xFF16A34A),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _StatisticsMetricCard(
                  label: _tr(context, 'Gastos', 'Expenses'),
                  value: expenses,
                  icon: Icons.trending_down_rounded,
                  color: scheme.error,
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_tr(context, 'Ingresos frente a gastos', 'Income vs. expenses'), style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  )),
                  const SizedBox(height: 6),
                  Text(
                    _tr(context, 'Comparación de los importes registrados este mes', 'Comparison of amounts recorded this month'),
                    style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 16),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Row(
                      children: [
                        Expanded(
                          flex: incomeRatio == 0 ? 1 : (incomeRatio * 1000).round().clamp(1, 1000).toInt(),
                          child: Container(height: 10, color: const Color(0xFF16A34A)),
                        ),
                        Expanded(
                          flex: expenseRatio == 0 ? 1 : (expenseRatio * 1000).round().clamp(1, 1000).toInt(),
                          child: Container(height: 10, color: scheme.error),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _LegendItem(color: const Color(0xFF16A34A), label: _tr(context, 'Ingresos', 'Income'), value: money(income)),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _LegendItem(color: scheme.error, label: _tr(context, 'Gastos', 'Expenses'), value: money(expenses)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 22),
          Row(
            children: [
              Expanded(
                child: Text(_tr(context, 'Gastos por categoría', 'Expenses by category'), style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                )),
              ),
              if (categoryTotals.isNotEmpty)
                Text(_tr(context, '${categoryTotals.length} categorías', '${categoryTotals.length} categories'),
                  style: theme.textTheme.labelMedium?.copyWith(color: scheme.onSurfaceVariant)),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            _tr(context, 'Dónde se concentra tu dinero', 'Where your money goes'),
            style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 10),
          if (categoryTotals.isEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(22),
                child: Column(
                  children: [
                    Icon(Icons.pie_chart_outline_rounded, size: 38, color: scheme.onSurfaceVariant),
                    const SizedBox(height: 10),
                    Text(_tr(context, 'Aún no hay gastos por categoría', 'No expenses by category yet'), style: theme.textTheme.titleSmall),
                    const SizedBox(height: 5),
                    Text(
                      _tr(context, 'Cuando registres gastos, aquí verás cómo se distribuyen.', 'Once you record expenses, you will see how they are distributed here.'),
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            )
          else
            Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
                child: Column(
                  children: [
                    for (var i = 0; i < categoryTotals.length; i++) ...[
                      if (i > 0) const Divider(height: 20),
                      _CategorySpendingRow(
                        name: categoryTotals[i].$1,
                        amount: categoryTotals[i].$2,
                        maximum: maxValue,
                        share: totalCategorySpend == 0 ? 0 : categoryTotals[i].$2 / totalCategorySpend,
                        index: i,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          const SizedBox(height: 8),
          Text(
            'Puedes deslizar hacia abajo para actualizar los datos.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _StatisticsMetricCard extends StatelessWidget {
  const _StatisticsMetricCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final double value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 21),
            const SizedBox(height: 8),
            Text(label, style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            )),
            const SizedBox(height: 3),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(money(value), style: theme.textTheme.titleMedium?.copyWith(
                color: color,
                fontWeight: FontWeight.w800,
              )),
            ),
          ],
        ),
      ),
    );
  }
}

class _LegendItem extends StatelessWidget {
  const _LegendItem({required this.color, required this.label, required this.value});

  final Color color;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 9,
          height: 9,
          margin: const EdgeInsets.only(top: 4, right: 7),
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3)),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              )),
              const SizedBox(height: 2),
              Text(value, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      ],
    );
  }
}

class _CategorySpendingRow extends StatelessWidget {
  const _CategorySpendingRow({
    required this.name,
    required this.amount,
    required this.maximum,
    required this.share,
    required this.index,
  });

  final String name;
  final double amount;
  final double maximum;
  final double share;
  final int index;

  static const _colors = [
    Color(0xFF0EA5E9),
    Color(0xFF8B5CF6),
    Color(0xFF14B8A6),
    Color(0xFFF59E0B),
    Color(0xFFEC4899),
    Color(0xFF64748B),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = _colors[index % _colors.length];
    final ratio = (amount / maximum).clamp(0.0, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(Icons.sell_outlined, size: 17, color: color),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(money(amount), style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text('${(share * 100).toStringAsFixed(0)}%',
                  style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              ],
            ),
          ],
        ),
        const SizedBox(height: 9),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: ratio,
            minHeight: 7,
            backgroundColor: theme.colorScheme.surfaceContainerHighest,
            color: color,
          ),
        ),
      ],
    );
  }
}
