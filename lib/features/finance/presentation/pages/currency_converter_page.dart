import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../../../core/settings/app_preferences.dart';
import '../../../../core/utils/currency_utils.dart';

String _tr(BuildContext context, String spanish, String english) =>
    Localizations.localeOf(context).languageCode == 'en' ? english : spanish;

/// Conversor informativo. Nunca modifica saldos ni transacciones guardados.
class CurrencyConverterPage extends StatefulWidget {
  const CurrencyConverterPage({super.key});

  @override
  State<CurrencyConverterPage> createState() => _CurrencyConverterPageState();
}

class _CurrencyConverterPageState extends State<CurrencyConverterPage> {
  static const _currencies = <String, String>{
    'DOP': 'Peso dominicano',
    'USD': 'Dólar estadounidense',
    'EUR': 'Euro',
    'GBP': 'Libra esterlina',
    'CAD': 'Dólar canadiense',
    'MXN': 'Peso mexicano',
    'COP': 'Peso colombiano',
    'ARS': 'Peso argentino',
    'BRL': 'Real brasileño',
    'JPY': 'Yen japonés',
    'CHF': 'Franco suizo',
    'CNY': 'Yuan chino',
    'PEN': 'Sol peruano',
    'CLP': 'Peso chileno',
    'CRC': 'Colón costarricense',
    'GTQ': 'Quetzal guatemalteco',
    'HNL': 'Lempira hondureño',
    'JMD': 'Dólar jamaiquino',
    'TTD': 'Dólar trinitense',
    'VES': 'Bolívar venezolano',
  };

  static const _englishCurrencies = <String, String>{'DOP':'Dominican peso','USD':'US dollar','EUR':'Euro','GBP':'British pound','CAD':'Canadian dollar','MXN':'Mexican peso','COP':'Colombian peso','ARS':'Argentine peso','BRL':'Brazilian real','JPY':'Japanese yen','CHF':'Swiss franc','CNY':'Chinese yuan','PEN':'Peruvian sol','CLP':'Chilean peso','CRC':'Costa Rican colón','GTQ':'Guatemalan quetzal','HNL':'Honduran lempira','JMD':'Jamaican dollar','TTD':'Trinidad and Tobago dollar','VES':'Venezuelan bolívar'};

  String _currencyName(String code) => Localizations.localeOf(context).languageCode == 'en' ? (_englishCurrencies[code] ?? code) : (_currencies[code] ?? code);

  final _amountController = TextEditingController(text: '1');
  String _from = 'DOP';
  String _to = 'USD';
  Map<String, dynamic> _rates = {};
  DateTime? _updatedAt;
  bool _loading = false;
  String? _error;
  String _displayCurrency = 'DOP';

  @override
  void initState() {
    super.initState();
    _loadRates();
    _loadDisplayCurrency();
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  double get _amount =>
      double.tryParse(_amountController.text.trim().replaceAll(',', '.')) ?? 0;

  double? get _rate {
    if (_from == _to) return 1;
    final value = _rates[_to];
    return value is num ? value.toDouble() : null;
  }

  double? get _converted {
    final rate = _rate;
    if (rate == null) return null;
    return _amount * rate;
  }

  Future<void> _loadDisplayCurrency() async {
    final currency = await AppPreferences.getCurrency();
    if (!mounted) return;
    setState(() => _displayCurrency = currency);
  }

  Future<void> _setDisplayCurrency(String code) async {
    if (code == _displayCurrency) return;
    if (convertDisplayAmount(1, from: 'DOP', to: code) == null) {
      final refreshed = await refreshDisplayExchangeRates();
      if (!mounted) return;
      if (!refreshed && convertDisplayAmount(1, from: 'DOP', to: code) == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_tr(context, 'No hay tasas de cambio disponibles. Conéctate a Internet e inténtalo de nuevo.', 'No exchange rates are available. Connect to the internet and try again.')),
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }
    }
    await AppPreferences.setCurrency(code);
    if (!mounted) return;
    setState(() => _displayCurrency = code);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_tr(context, 'Moneda de visualización cambiada a ${currencyLabel(code)}', 'Display currency changed to $code')),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _loadRates() async {
    final isEnglish = Localizations.localeOf(context).languageCode == 'en';
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final uri = Uri.https('open.er-api.com', '/v6/latest/$_from');
      final response = await http.get(uri).timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) {
        throw Exception(isEnglish ? 'The service returned status code ${response.statusCode}.' : 'El servicio respondió con código ${response.statusCode}.');
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic> || decoded['result'] != 'success') {
        throw Exception(isEnglish ? 'The provider did not return valid exchange rates.' : 'El proveedor no devolvió tasas válidas.');
      }
      final rates = decoded['rates'];
      if (rates is! Map<String, dynamic>) {
        throw Exception(isEnglish ? 'No conversion rates were found.' : 'No se encontraron tasas de conversión.');
      }
      if (!mounted) return;
      setState(() {
        _rates = rates;
        final updateUnix = decoded['time_last_update_unix'];
        _updatedAt = updateUnix is num
            ? DateTime.fromMillisecondsSinceEpoch(
                updateUnix.toInt() * 1000,
                isUtc: true,
              ).toLocal()
            : null;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = isEnglish ? 'Could not update rates. Check your connection and try again.' : 'No se pudieron actualizar las tasas. Comprueba tu conexión e inténtalo de nuevo.';
        });
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _format(double value) => value.toStringAsFixed(2).replaceAllMapped(
        RegExp(r'\B(?=(\d{3})+(?!\d))'),
        (match) => ',',
      );

  Future<void> _selectCurrency({required bool from}) async {
    final selected = from ? _from : _to;
    final result = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: Text(_tr(context, 'Seleccionar moneda', 'Select currency'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            ),
            for (final entry in _currencies.entries)
              ListTile(
                title: Text(entry.key),
                subtitle: Text(_currencyName(entry.key)),
                trailing: entry.key == selected ? const Icon(Icons.check_circle_rounded) : null,
                onTap: () => Navigator.pop(context, entry.key),
              ),
          ],
        ),
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      if (from) {
        _from = result;
      } else {
        _to = result;
      }
      if (_from == _to) {
        _rates = {_to: 1.0};
      }
    });
    await _loadRates();
  }

  void _swapCurrencies() {
    setState(() {
      final oldFrom = _from;
      _from = _to;
      _to = oldFrom;
    });
    _loadRates();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(_tr(context, 'Conversor de monedas', 'Currency converter')),
        actions: [
          IconButton(
            tooltip: _tr(context, 'Actualizar tasas', 'Refresh rates'),
            onPressed: _loading ? null : _loadRates,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_tr(context, 'Conversión rápida', 'Quick conversion'), style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 6),
                  Text(_tr(context, 'Consulta tasas de cambio actuales sin modificar tus cuentas ni movimientos.', 'Check current exchange rates without changing your accounts or transactions.'), style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
                  const SizedBox(height: 24),
                  TextField(
                    controller: _amountController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      labelText: _tr(context, 'Cantidad', 'Amount'),
                      prefixIcon: const Icon(Icons.payments_outlined),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => _selectCurrency(from: true),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(_tr(context, 'De', 'From')),
                              const SizedBox(height: 4),
                              Text(_from, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                              Text(_currencies[_from] ?? _from, maxLines: 2, overflow: TextOverflow.ellipsis, textAlign: TextAlign.left),
                            ],
                          ),
                        ),
                      ),
                      IconButton.filledTonal(
                        tooltip: 'Invertir monedas',
                        onPressed: _swapCurrencies,
                        icon: const Icon(Icons.swap_horiz_rounded),
                      ),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => _selectCurrency(from: false),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(_tr(context, 'A', 'To')),
                              const SizedBox(height: 4),
                              Text(_to, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                              Text(_currencies[_to] ?? _to, maxLines: 2, overflow: TextOverflow.ellipsis, textAlign: TextAlign.left),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 22),
                  if (_loading)
                    const Center(child: Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator()))
                  else if (_error != null)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_error!, style: TextStyle(color: scheme.error)),
                        const SizedBox(height: 8),
                        FilledButton.tonalIcon(
                          onPressed: _loadRates,
                          icon: const Icon(Icons.refresh_rounded),
                          label: Text(_tr(context, 'Reintentar', 'Retry')),
                        ),
                      ],
                    )
                  else
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: scheme.primaryContainer,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_tr(context, 'Resultado estimado', 'Estimated result'), style: TextStyle(color: scheme.onPrimaryContainer)),
                          const SizedBox(height: 6),
                          Text(
                            _converted == null ? '—' : '${_format(_converted!)} $_to',
                            style: theme.textTheme.headlineMedium?.copyWith(
                              color: scheme.onPrimaryContainer,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          if (_rate != null) ...[
                            const SizedBox(height: 8),
                            Text('1 $_from = ${_format(_rate!)} $_to', style: TextStyle(color: scheme.onPrimaryContainer)),
                          ],
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.tune_rounded, color: scheme.primary),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _tr(context, 'Moneda de visualización', 'Display currency'),
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _tr(context, 'Convierte automáticamente los importes de cuentas, movimientos y estadísticas. Los valores originales guardados no se modifican.', 'Automatically converts amounts in accounts, transactions, and statistics. Original saved values are not changed.'),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 14),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment<String>(
                        value: 'DOP',
                        label: Text('DOP'),
                        icon: Icon(Icons.south_america_rounded),
                      ),
                      ButtonSegment<String>(
                        value: 'USD',
                        label: Text('USD'),
                        icon: Icon(Icons.attach_money_rounded),
                      ),
                      ButtonSegment<String>(
                        value: 'EUR',
                        label: Text('EUR'),
                        icon: Icon(Icons.euro_rounded),
                      ),
                    ],
                    selected: {_displayCurrency},
                    onSelectionChanged: (values) =>
                        _setDisplayCurrency(values.first),
                    showSelectedIcon: false,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    currencyLabel(_displayCurrency),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          ListTile(
            leading: const Icon(Icons.info_outline_rounded),
            title: Text(_tr(context, 'Tipo de cambio informativo', 'Informational exchange rate')),
            subtitle: Text(
              _updatedAt == null
                  ? _tr(context, 'Las tasas pueden variar y el proveedor puede actualizarlas periódicamente.', 'Rates may vary and the provider may update them periodically.')
                  : _tr(context, 'Última actualización del proveedor: ${MaterialLocalizations.of(context).formatMediumDate(_updatedAt!)}.', 'Provider last updated: ${MaterialLocalizations.of(context).formatMediumDate(_updatedAt!)}.'),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _tr(context, 'La conversión es una estimación. Las comisiones bancarias y el tipo aplicado por tu entidad pueden ser distintos.', 'The conversion is an estimate. Bank fees and the rate applied by your provider may differ.'),
            style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
