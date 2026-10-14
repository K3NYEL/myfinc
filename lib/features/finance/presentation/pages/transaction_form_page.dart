import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/errors/app_exception.dart';
import '../../../../core/utils/amount_parser.dart';
import '../../../../shared/widgets/async_state_view.dart';
import '../providers.dart';
import '../../../../app/settings_provider.dart';

String _tr(BuildContext context, String es, String en) =>
    Localizations.localeOf(context).languageCode == 'en' ? en : es;

class TransactionFormPage extends ConsumerStatefulWidget {
  final String kind; // income | expense | transfer
  const TransactionFormPage({super.key, required this.kind});
  @override
  ConsumerState<TransactionFormPage> createState() => _State();
}

class _State extends ConsumerState<TransactionFormPage> {
  final _amount = TextEditingController(), _desc = TextEditingController();
  int? _acc, _dest, _cat;
  bool _busy = false;
  bool get _isTransfer => widget.kind == 'transfer';

  @override
  void dispose() {
    _amount.dispose();
    _desc.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy) return;
    setState(() => _busy = true);
    final repo = ref.read(repoProvider);
    final amount = parseAmount(_amount.text) ?? 0;
    String? error;
    try {
      final availableAccounts = ref.read(accountsProvider).value ?? [];
      final accountId = _acc ?? (availableAccounts.isNotEmpty ? availableAccounts.first.id : null);
      if (accountId == null) {
        throw AppException(_tr(context, 'No hay una cuenta disponible. Crea o restaura tu cuenta e inténtalo de nuevo.', 'No account is available. Create or restore an account and try again.'));
      }
      if (amount <= 0) {
        throw AppException(_tr(context, 'Escribe un monto válido mayor que cero.', 'Enter a valid amount greater than zero.'));
      }
      if (_isTransfer) {
        if (_dest == null) throw AppException(_tr(context, 'Elige la cuenta destino.', 'Choose the destination account.'));
        await repo.addTransfer(accountId, _dest!, amount, _desc.text);
      } else {
        await repo.addTransaction(
          accountId: accountId,
          categoryId: _cat,
          type: widget.kind,
          amount: amount,
          description: _desc.text,
        );
      }
    } on AppException catch (e) {
      error = e.message;
    } catch (e) {
      debugPrint('Error al guardar: $e');
      if (!mounted) return;
      error = _tr(context, 'No pudimos guardar el movimiento. Inténtalo nuevamente.', 'We could not save the transaction. Please try again.');
    }
    if (!mounted) return;
    setState(() => _busy = false);
    if (error != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error)));
      return;
    }
    refreshTransactions(ref);
    context.pop();
  }

  Widget _drop(String label, int? value, List<DropdownMenuItem<int>> items,
          ValueChanged<int?> on) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: DropdownButtonFormField<int>(
          initialValue: value,
          items: items,
          onChanged: on,
          decoration: InputDecoration(labelText: label),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final isEnglish = ref.watch(settingsProvider).languageCode == 'en';
    final accountsState = ref.watch(accountsProvider);
    final categoriesState =
        _isTransfer ? null : ref.watch(categoriesProvider(widget.kind));
    if (accountsState.hasError) {
      return Scaffold(
        appBar: AppBar(title: Text(_title(isEnglish))),
        body: AsyncStateView(
          error: accountsState.error,
          onRetry: () => ref.invalidate(accountsProvider),
        ),
      );
    }
    if (categoriesState?.hasError ?? false) {
      return Scaffold(
        appBar: AppBar(title: Text(_title(isEnglish))),
        body: AsyncStateView(
          error: categoriesState!.error,
          onRetry: () => ref.invalidate(categoriesProvider(widget.kind)),
        ),
      );
    }
    if (accountsState.isLoading || (categoriesState?.isLoading ?? false)) {
      return const Scaffold(body: AsyncStateView());
    }

    final accounts = accountsState.value ?? [];
    final categories = categoriesState?.value ?? [];
    final accountItems = [
      for (final account in accounts)
        DropdownMenuItem(value: account.id, child: Text(account.name)),
    ];
    final selectedAccountId = _acc ?? (accounts.isNotEmpty ? accounts.first.id : null);
    final selectedCategoryId = _cat ?? (categories.isNotEmpty ? categories.first.id : null);

    return Scaffold(
      appBar: AppBar(title: Text(_title(isEnglish))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _amount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: Theme.of(context).textTheme.headlineMedium,
            decoration: InputDecoration(labelText: isEnglish ? 'Amount (DOP)' : 'Monto (RD\$)'),
          ),
          const SizedBox(height: 12),
          _drop(
            _isTransfer ? (isEnglish ? 'Source account' : 'Cuenta origen') : (isEnglish ? 'Account' : 'Cuenta'),
            selectedAccountId,
            accountItems,
            (value) => setState(() => _acc = value),
          ),
          if (_isTransfer)
            _drop(
              isEnglish ? 'Destination account' : 'Cuenta destino',
              _dest,
              accountItems,
              (value) => setState(() => _dest = value),
            ),
          if (!_isTransfer)
            _drop(
              isEnglish ? 'Category' : 'Categoría',
              selectedCategoryId,
              [
                for (final category in categories)
                  DropdownMenuItem(
                    value: category.id,
                    child: Text(category.name),
                  ),
              ],
              (value) => setState(() => _cat = value),
            ),
          TextField(
            controller: _desc,
            decoration:
                InputDecoration(labelText: isEnglish ? 'Description (optional)' : 'Descripción (opcional)'),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _busy ? null : _save,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: _busy
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(isEnglish ? 'Save' : 'Guardar'),
            ),
          ),
        ],
      ),
    );
  }

  String _title(bool isEnglish) => {
        'income': isEnglish ? 'New income' : 'Nuevo ingreso',
        'expense': isEnglish ? 'New expense' : 'Nuevo gasto',
        'transfer': isEnglish ? 'Transfer' : 'Transferencia',
      }[widget.kind]!;
}
