import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/settings_provider.dart';

class CalculatorPage extends ConsumerStatefulWidget {
  const CalculatorPage({super.key});

  @override
  ConsumerState<CalculatorPage> createState() => _CalculatorPageState();
}

class _CalculatorPageState extends ConsumerState<CalculatorPage> {
  String _expression = '';
  String _display = '0';
  double? _firstOperand;
  String? _operator;
  bool _replaceDisplay = false;

  bool get _isEnglish => ref.watch(settingsProvider).languageCode == 'en';

  void _input(String value) {
    setState(() {
      if (_replaceDisplay || _display == 'Error') {
        _display = value == '.' ? '0.' : value;
        _replaceDisplay = false;
      } else if (value == '.' && _display.contains('.')) {
        return;
      } else if (_display == '0' && value != '.') {
        _display = value;
      } else if (_display == '-0' && value != '.') {
        _display = '-$value';
      } else {
        _display += value;
      }
      _updateExpression();
    });
  }

  void _updateExpression() {
    if (_operator == null) {
      _expression = _display;
    } else {
      _expression = '${_format(_firstOperand ?? 0)} $_operator $_display';
    }
  }

  void _chooseOperator(String nextOperator) {
    final current = double.tryParse(_display);
    if (current == null) return;

    setState(() {
      if (_firstOperand != null && _operator != null && !_replaceDisplay) {
        final result = _perform(_firstOperand!, current, _operator!);
        if (result == null) {
          _showError();
          return;
        }
        _firstOperand = result;
        _display = _format(result);
      } else if (_firstOperand == null || _operator == null) {
        _firstOperand = current;
      }
      _operator = nextOperator;
      _expression = '${_format(_firstOperand!)} $nextOperator';
      _replaceDisplay = true;
    });
  }

  double? _perform(double first, double second, String operator) {
    final result = switch (operator) {
      '+' => first + second,
      '−' => first - second,
      '×' => first * second,
      '÷' when second != 0 => first / second,
      _ => null,
    };
    if (result == null || !result.isFinite) return null;
    return result;
  }

  void _calculate() {
    final first = _firstOperand;
    final second = double.tryParse(_display);
    final operator = _operator;
    if (first == null || second == null || operator == null) return;

    final result = _perform(first, second, operator);
    setState(() {
      _expression = '${_format(first)} $operator ${_format(second)} =';
      _display = result == null ? 'Error' : _format(result);
      _firstOperand = null;
      _operator = null;
      _replaceDisplay = true;
    });
  }

  void _showError() {
    _expression = ref.read(settingsProvider).languageCode == 'en' ? 'Cannot divide by zero' : 'No se puede dividir entre cero';
    _display = 'Error';
    _firstOperand = null;
    _operator = null;
    _replaceDisplay = true;
  }

  String _format(double value) {
    if (!value.isFinite) return 'Error';
    if (value.abs() >= 1e12 || (value != 0 && value.abs() < 1e-8)) {
      return value.toStringAsExponential(5);
    }
    if (value == value.truncateToDouble()) return value.toInt().toString();
    return value.toStringAsPrecision(10)
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');
  }

  void _clear() {
    setState(() {
      _expression = '';
      _display = '0';
      _firstOperand = null;
      _operator = null;
      _replaceDisplay = false;
    });
  }

  void _backspace() {
    if (_replaceDisplay) {
      _clear();
      return;
    }
    setState(() {
      _display = _display.length <= 1 ||
              (_display.length == 2 && _display.startsWith('-'))
          ? '0'
          : _display.substring(0, _display.length - 1);
      _updateExpression();
    });
  }

  void _toggleSign() {
    setState(() {
      if (_display.startsWith('-')) {
        _display = _display.substring(1);
      } else if (_display != '0') {
        _display = '-$_display';
      }
      _replaceDisplay = false;
      _updateExpression();
    });
  }

  void _percent() {
    final current = double.tryParse(_display);
    if (current == null) return;
    setState(() {
      _expression = '${_format(current)}%';
      _display = _format(current / 100);
      _replaceDisplay = true;
    });
  }

  void _press(String key) {
    switch (key) {
      case 'AC':
        _clear();
        break;
      case '⌫':
        _backspace();
        break;
      case '%':
        _percent();
        break;
      case '=':
        _calculate();
        break;
      case '+':
      case '−':
      case '×':
      case '÷':
        _chooseOperator(key);
        break;
      default:
        _input(key);
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final rows = <List<String>>[
      ['AC', '⌫', '%', '÷'],
      ['7', '8', '9', '×'],
      ['4', '5', '6', '−'],
      ['1', '2', '3', '+'],
      ['±', '0', '.', '='],
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEnglish ? 'Calculator' : 'Calculadora'),
        actions: [
          IconButton(
            tooltip: _isEnglish ? 'Clear all' : 'Borrar todo',
            onPressed: _clear,
            icon: const Icon(Icons.restart_alt_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Column(
                children: [
                  Expanded(
                    flex: 2,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            scheme.primaryContainer.withValues(alpha: 0.75),
                            scheme.surfaceContainerHighest.withValues(alpha: 0.65),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(28),
                        border: Border.all(
                          color: scheme.outlineVariant.withValues(alpha: 0.55),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 180),
                            child: Align(
                              key: ValueKey(_expression),
                              alignment: Alignment.centerRight,
                              child: Text(
                                _expression,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.end,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 150),
                            transitionBuilder: (child, animation) => FadeTransition(
                              opacity: animation,
                              child: ScaleTransition(
                                scale: Tween<double>(begin: 0.97, end: 1).animate(animation),
                                child: child,
                              ),
                            ),
                            child: SizedBox(
                              key: ValueKey(_display),
                              width: double.infinity,
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerRight,
                                child: Text(
                                  _display,
                                  style: theme.textTheme.displayMedium?.copyWith(
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: -1.2,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Expanded(
                    flex: 5,
                    child: Column(
                      children: [
                        for (final row in rows)
                          Expanded(
                            child: Row(
                              children: [
                                for (final key in row)
                                  Expanded(
                                    child: Padding(
                                      padding: const EdgeInsets.all(4),
                                      child: _keyButton(
                                        key,
                                        scheme,
                                        operator: const {'+', '−', '×', '÷', '%', '='}.contains(key),
                                        onTap: () => key == '±' ? _toggleSign() : _press(key),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _isEnglish
                        ? 'For quick calculations only. Your financial records are never changed.'
                        : 'Solo para cálculos rápidos. No modifica tus registros financieros.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _keyButton(
    String label,
    ColorScheme scheme, {
    required bool operator,
    required VoidCallback onTap,
  }) {
    final isClear = label == 'AC' || label == '⌫';
    final isEquals = label == '=';
    return FilledButton.tonal(
      onPressed: onTap,
      style: FilledButton.styleFrom(
        backgroundColor: isEquals
            ? scheme.primary
            : isClear
                ? scheme.errorContainer
                : operator
                    ? scheme.secondaryContainer
                    : scheme.surfaceContainerHighest,
        foregroundColor: isEquals
            ? scheme.onPrimary
            : isClear
                ? scheme.onErrorContainer
                : scheme.onSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        padding: EdgeInsets.zero,
        elevation: isEquals ? 2 : 0,
      ),
      child: Text(
        label,
        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
      ),
    );
  }
}
