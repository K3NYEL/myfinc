import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';

import '../../../../core/database/database.dart';
import '../../../../core/errors/app_exception.dart';
import '../../../../core/utils/currency_utils.dart';
import '../../../auth/presentation/session_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

String _tr(BuildContext context, String spanish, String english) =>
    Localizations.localeOf(context).languageCode == 'en' ? english : spanish;

class FinancePlanningPage extends ConsumerStatefulWidget {
  const FinancePlanningPage({super.key});

  @override
  ConsumerState<FinancePlanningPage> createState() => _FinancePlanningPageState();
}

class _FinancePlanningPageState extends ConsumerState<FinancePlanningPage> {
  bool _loading = true;
  bool _saving = false;
  String? _error;
  Map<String, Object?>? _budget;
  double _spentThisMonth = 0;
  List<Map<String, Object?>> _goals = [];

  String get _period {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}';
  }

  String get _periodLabel {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}';
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final user = ref.read(sessionProvider);
    if (user == null) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = _tr(context, 'Inicia sesión para consultar tu planificación financiera.', 'Sign in to view your financial plan.');
        });
      }
      return;
    }
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final db = await AppDatabase.instance;
      final budgets = await db.query(
        'monthly_budgets',
        where: 'user_id = ? AND period_month = ?',
        whereArgs: [user.id, _period],
        limit: 1,
      );
      final now = DateTime.now();
      final start = DateTime(now.year, now.month, 1);
      final end = DateTime(now.year, now.month + 1, 1);
      final spendRows = await db.rawQuery('''
        SELECT COALESCE(SUM(amount), 0) AS total
        FROM transactions
        WHERE user_id = ? AND type = ? AND date >= ? AND date < ?
      ''', [
        user.id,
        'expense',
        start.toIso8601String().substring(0, 10),
        end.toIso8601String().substring(0, 10),
      ]);
      final goals = await db.query(
        'savings_goals',
        where: 'user_id = ?',
        whereArgs: [user.id],
        orderBy: 'created_at DESC',
      );
      if (!mounted) return;
      setState(() {
        _budget = budgets.isEmpty ? null : budgets.first;
        _spentThisMonth = (spendRows.first['total'] as num?)?.toDouble() ?? 0;
        _goals = goals;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _tr(context, 'No se pudo cargar la planificación financiera.', 'Could not load financial planning.');
      });
    }
  }

  int _minorUnits(String raw) {
    final amount = double.tryParse(raw.trim().replaceAll(',', '.'));
    if (amount == null || !amount.isFinite || amount <= 0 || amount > 90071992547409.91) {
      throw AppException(_tr(context, 'Introduce un monto válido mayor que cero.', 'Enter a valid amount greater than zero.'));
    }
    final scaled = amount * 100;
    final minor = scaled.round();
    if ((scaled - minor).abs() > 0.000001) {
      throw AppException(_tr(context, 'Usa como máximo dos decimales.', 'Use no more than two decimal places.'));
    }
    return minor;
  }

  Future<String?> _promptAmount({
    required String title,
    required String label,
    String initial = '',
  }) async {
    final controller = TextEditingController(text: initial);
    try {
      return await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(title),
          content: TextField(
            controller: controller,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: label),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(_tr(context, 'Cancelar', 'Cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, controller.text),
              child: Text(_tr(context, 'Guardar', 'Save')),
            ),
          ],
        ),
      );
    } finally {
      controller.dispose();
    }
  }

  Future<String?> _promptText({required String title, required String label}) async {
    final controller = TextEditingController();
    try {
      return await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(title),
          content: TextField(
            controller: controller,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(labelText: label),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(_tr(context, 'Cancelar', 'Cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, controller.text.trim()),
              child: Text(_tr(context, 'Continuar', 'Continue')),
            ),
          ],
        ),
      );
    } finally {
      controller.dispose();
    }
  }

  Future<void> _setBudget() async {
    if (_saving) return;
    final raw = await _promptAmount(
      title: _tr(context, 'Presupuesto mensual', 'Monthly budget'),
      label: _tr(context, 'Límite para $_periodLabel', 'Limit for $_periodLabel'),
      initial: _budget == null
          ? ''
          : (((_budget!['limit_minor'] as num).toInt()) / 100).toStringAsFixed(2),
    );
    if (raw == null || !mounted) return;
    try {
      final limit = _minorUnits(raw);
      final user = ref.read(sessionProvider);
      if (user == null) throw AppException(_tr(context, 'Inicia sesión e inténtalo de nuevo.', 'Sign in and try again.'));
      setState(() => _saving = true);
      final db = await AppDatabase.instance;
      final now = DateTime.now().toUtc().toIso8601String();
      await db.insert(
        'monthly_budgets',
        {
          'user_id': user.id,
          'period_month': _period,
          'limit_minor': limit,
          'created_at': now,
          'updated_at': now,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await _load();
    } catch (error) {
      if (mounted) _showError(error is AppException ? error.message : 'No se pudo guardar el presupuesto.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _addGoal() async {
    if (_saving) return;
    final title = await _promptText(title: _tr(context, 'Nueva meta de ahorro', 'New savings goal'), label: _tr(context, 'Nombre de la meta', 'Goal name'));
    if (title == null || title.trim().isEmpty || !mounted) return;
    final raw = await _promptAmount(title: _tr(context, 'Objetivo de ahorro', 'Savings goal'), label: _tr(context, 'Monto objetivo', 'Target amount'));
    if (raw == null || !mounted) return;
    try {
      final target = _minorUnits(raw);
      final user = ref.read(sessionProvider);
      if (user == null) throw const AppException('Inicia sesión e inténtalo de nuevo.');
      setState(() => _saving = true);
      final db = await AppDatabase.instance;
      final now = DateTime.now().toUtc().toIso8601String();
      await db.insert('savings_goals', {
        'user_id': user.id,
        'title': title.trim(),
        'target_minor': target,
        'saved_minor': 0,
        'due_date': null,
        'created_at': now,
        'updated_at': now,
      });
      await _load();
    } catch (error) {
      if (mounted) _showError(error is AppException ? error.message : 'No se pudo crear la meta.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _addContribution(Map<String, Object?> goal) async {
    if (_saving) return;
    final raw = await _promptAmount(
      title: _tr(context, 'Añadir ahorro', 'Add savings'),
      label: 'Cantidad para “${goal['title']}”',
    );
    if (raw == null || !mounted) return;
    try {
      final contribution = _minorUnits(raw);
      final user = ref.read(sessionProvider);
      if (user == null) throw const AppException('Inicia sesión e inténtalo de nuevo.');
      final id = goal['id'] as int;
      final current = (goal['saved_minor'] as num).toInt();
      setState(() => _saving = true);
      final db = await AppDatabase.instance;
      await db.update(
        'savings_goals',
        {
          'saved_minor': current + contribution,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        },
        where: 'id = ? AND user_id = ?',
        whereArgs: [id, user.id],
      );
      await _load();
    } catch (error) {
      if (mounted) _showError(error is AppException ? error.message : 'No se pudo actualizar la meta.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final limit = _budget == null ? null : (_budget!['limit_minor'] as num).toDouble() / 100;
    final ratio = limit == null || limit <= 0 ? 0.0 : (_spentThisMonth / limit).clamp(0.0, 1.0).toDouble();
    return Scaffold(
      appBar: AppBar(
        title: Text(_tr(context, 'Presupuestos y metas', 'Budgets and goals')),
        actions: [
          IconButton(
            tooltip: _tr(context, 'Actualizar', 'Refresh'),
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text(_error!, textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    FilledButton.icon(onPressed: _load, icon: const Icon(Icons.refresh), label: Text(_tr(context, 'Reintentar', 'Retry'))),
                  ]),
                ))
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(18),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(children: [
                              const Icon(Icons.account_balance_wallet_outlined),
                              const SizedBox(width: 10),
                              Expanded(child: Text(_tr(context, 'Presupuesto de $_periodLabel', 'Budget for $_periodLabel'), style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800))),
                              IconButton(onPressed: _saving ? null : _setBudget, tooltip: _tr(context, 'Configurar presupuesto', 'Set budget'), icon: const Icon(Icons.edit_outlined)),
                            ]),
                            const SizedBox(height: 12),
                            Text(_tr(context, 'Gastado este mes: ${money(_spentThisMonth)}', 'Spent this month: ${money(_spentThisMonth)}'), style: theme.textTheme.bodyLarge),
                            const SizedBox(height: 6),
                            Text(limit == null ? _tr(context, 'Aún no has establecido un límite mensual.', 'You have not set a monthly limit yet.') : _tr(context, 'Límite: ${money(limit)} · Disponible: ${money(limit - _spentThisMonth)}', 'Limit: ${money(limit)} · Remaining: ${money(limit - _spentThisMonth)}')),
                            if (limit != null) ...[
                              const SizedBox(height: 12),
                              LinearProgressIndicator(value: ratio, minHeight: 8),
                              const SizedBox(height: 6),
                              Text(_spentThisMonth > limit ? _tr(context, 'Has superado el presupuesto mensual.', 'You have exceeded your monthly budget.') : _tr(context, '${(ratio * 100).round()}% del presupuesto utilizado', '${(ratio * 100).round()}% of budget used'), style: theme.textTheme.bodySmall?.copyWith(color: _spentThisMonth > limit ? scheme.error : scheme.onSurfaceVariant)),
                            ],
                            if (limit == null) ...[
                              const SizedBox(height: 12),
                              FilledButton.icon(onPressed: _saving ? null : _setBudget, icon: const Icon(Icons.add_rounded), label: Text(_tr(context, 'Crear presupuesto', 'Create budget'))),
                            ],
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Row(children: [
                      Expanded(child: Text(_tr(context, 'Metas de ahorro', 'Savings goals'), style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800))),
                      FilledButton.tonalIcon(onPressed: _saving ? null : _addGoal, icon: const Icon(Icons.add_rounded), label: Text(_tr(context, 'Nueva meta', 'New goal'))),
                    ]),
                    const SizedBox(height: 8),
                    if (_goals.isEmpty)
                      Card(child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(children: [
                          const Icon(Icons.savings_outlined, size: 36),
                          const SizedBox(height: 8),
                          Text(_tr(context, 'Todavía no tienes metas de ahorro.', 'You do not have any savings goals yet.'), textAlign: TextAlign.center),
                          const SizedBox(height: 8),
                          Text(_tr(context, 'Crea una meta y registra tus aportes para seguir el progreso.', 'Create a goal and record contributions to track your progress.'), textAlign: TextAlign.center, style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                        ]),
                      ))
                    else
                      for (final goal in _goals) _goalCard(context, goal),
                    const SizedBox(height: 12),
                    Text(_tr(context, 'Los presupuestos y las metas se guardan localmente en esta cuenta. La moneda configurada cambia el formato mostrado; no convierte automáticamente los registros existentes.', 'Budgets and goals are stored locally in this account. The selected currency changes the display format; existing records are not automatically converted.'), style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                  ],
                ),
    );
  }

  Widget _goalCard(BuildContext context, Map<String, Object?> goal) {
    final theme = Theme.of(context);
    final target = (goal['target_minor'] as num).toDouble() / 100;
    final saved = (goal['saved_minor'] as num).toDouble() / 100;
    final ratio = (saved / target).clamp(0.0, 1.0).toDouble();
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.savings_outlined),
            const SizedBox(width: 10),
            Expanded(child: Text(goal['title'] as String, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700))),
            IconButton(tooltip: _tr(context, 'Añadir ahorro', 'Add savings'), onPressed: _saving ? null : () => _addContribution(goal), icon: const Icon(Icons.add_circle_outline_rounded)),
          ]),
          const SizedBox(height: 6),
          Text(_tr(context, '${money(saved)} de ${money(target)}', '${money(saved)} of ${money(target)}')),
          const SizedBox(height: 10),
          LinearProgressIndicator(value: ratio, minHeight: 8),
          const SizedBox(height: 6),
          Text(saved >= target ? 'Meta completada' : '${(ratio * 100).round()}% completado', style: theme.textTheme.bodySmall),
        ]),
      ),
    );
  }
}
