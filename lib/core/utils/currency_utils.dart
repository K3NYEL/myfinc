import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _f = NumberFormat('#,##0.##');
String _currencyCode = 'DOP';
Map<String, double> _ratesFromDop = {'DOP': 1};
DateTime? _ratesUpdatedAt;
bool _ratesLoading = false;
const _ratesCacheKey = 'finance_exchange_rates_dop';
const _ratesUpdatedKey = 'finance_exchange_rates_updated_at';

String get selectedCurrencyCode => _currencyCode;

String currencyLabel(String code) {
  switch (code) {
    case 'USD':
      return 'USD — Dólar estadounidense';
    case 'EUR':
      return 'EUR — Euro';
    default:
      return 'DOP — Peso dominicano';
  }
}

/// Load the saved display currency before the app builds.
Future<void> initializeCurrency() async {
  final prefs = await SharedPreferences.getInstance();
  final saved = prefs.getString('finance_currency') ?? 'DOP';
  _currencyCode = const {'DOP', 'USD', 'EUR'}.contains(saved) ? saved : 'DOP';
  final cachedRates = prefs.getString(_ratesCacheKey);
  if (cachedRates != null) {
    try {
      final decoded = jsonDecode(cachedRates);
      if (decoded is Map<String, dynamic>) {
        final parsed = <String, double>{'DOP': 1};
        for (final entry in decoded.entries) {
          if (entry.value is num && (entry.value as num) > 0) {
            parsed[entry.key] = (entry.value as num).toDouble();
          }
        }
        _ratesFromDop = parsed;
      }
    } catch (_) {}
  }
  final updated = prefs.getString(_ratesUpdatedKey);
  _ratesUpdatedAt = updated == null ? null : DateTime.tryParse(updated);
}

Future<bool> refreshDisplayExchangeRates() async {
  if (_ratesLoading) return false;
  _ratesLoading = true;
  try {
    final response = await http.get(Uri.https('open.er-api.com', '/v6/latest/DOP')).timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) return false;
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic> || decoded['result'] != 'success') return false;
    final rawRates = decoded['rates'];
    if (rawRates is! Map<String, dynamic>) return false;
    final parsed = <String, double>{'DOP': 1};
    for (final entry in rawRates.entries) {
      if (entry.value is num && (entry.value as num) > 0) {
        parsed[entry.key] = (entry.value as num).toDouble();
      }
    }
    if (!parsed.containsKey('USD') || !parsed.containsKey('EUR')) return false;
    _ratesFromDop = parsed;
    final unix = decoded['time_last_update_unix'];
    _ratesUpdatedAt = unix is num
        ? DateTime.fromMillisecondsSinceEpoch(unix.toInt() * 1000, isUtc: true)
        : DateTime.now().toUtc();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_ratesCacheKey, jsonEncode(parsed));
    await prefs.setString(_ratesUpdatedKey, _ratesUpdatedAt!.toIso8601String());
    return true;
  } catch (_) {
    return false;
  } finally {
    _ratesLoading = false;
  }
}

DateTime? get displayExchangeRatesUpdatedAt => _ratesUpdatedAt;

double? convertDisplayAmount(double value, {String? from, String? to}) {
  final sourceRate = _ratesFromDop[from ?? 'DOP'];
  final targetRate = _ratesFromDop[to ?? _currencyCode];
  if (sourceRate == null || targetRate == null || sourceRate <= 0) return null;
  return value / sourceRate * targetRate;
}

/// Updates the selected display currency; values are converted for display only.
void setCurrencyCodeInMemory(String code) {
  if (const {'DOP', 'USD', 'EUR'}.contains(code)) {
    _currencyCode = code;
  }
}

String money(double value) {
  final symbol = switch (_currencyCode) {
    'USD' => r'USD$ ',
    'EUR' => '€ ',
    _ => r'RD$ ',
  };
  final converted = convertDisplayAmount(value);
  if (converted == null) return '$symbol—';
  return symbol + _f.format(converted);
}
