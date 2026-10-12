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
      if (_replaceDisplay) {
        _display = value == '.' ? '0.' : value;
        _replaceDisplay = false;
        _expression = _operator == null
            ? _display
            : '${_format(_firstOperand ?? 0)} $_operator $_display';
        return;
      }
      if (value == '.' && _display.contains('.')) return;
      if (_display == '0' && value != '.') {
        _display = value;
      } else if (_display == '-0' && value != '.') {
        _display = '-$value';
      } else {
        _display += value;
      }
      _expression = _operator == null
          ? _display
          : '${_firstOperand ?? ''} $_operator $_display';
    });
  }

  void _chooseOperator(String operator) {
    final current = double.tryParse(_display);
    if (current == null) return;
    setState(() {
      if (_firstOperand != null && _operator != null && !_replaceDisplay) {
        _calculate();
      }
      _firstOperand = double.tryParse(_display) ?? current;
      _operator = operator;
      _expression = '${_format(_firstOperand!)} $operator';
      _replaceDisplay = true;
    });
  }

  void _calculate() {
    final first = _firstOperand;
    final second = double.tryParse(_display);
    final operator = _operator;
    if (first == null || second == null || operator == null) return;
    final double? result = switch (operator) {
      '+' => first + second,
      '−' => first - second,
      '×' => first * second,
      '÷' when second != 0 => first / second,
      '%' when second != 0 => first % second,
      _ => null,
    };
    setState(() {
      _expression = '${_format(first)} $operator ${_format(second)} =';
      _display = result == null
          ? 'Error'
          : _format(result);
      _firstOperand = null;
      _operator = null;
      _replaceDisplay = true;
    });
  }

  String _format(double value) {
    if (!value.isFinite) return 'Error';
    if (value == value.truncateToDouble()) return value.toInt().toString();
    return value.toStringAsPrecision(10).replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
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
    if (_replaceDisplay) return;
    setState(() {
      _display = _display.length <= 1 ||
              (_display.length == 2 && _display.startsWith('-'))
          ? '0'
          : _display.substring(0, _display.length - 1);
      _expression = _operator == null
          ? _display
          : '${_format(_firstOperand ?? 0)} $_operator $_display';
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
      case '=':
        _calculate();
        break;
      case '+':
      case '−':
      case '×':
      case '÷':
      case '%':
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
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Expanded(
                    flex: 2,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerHighest.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Text(
                            _expression,
                            maxLines: 2,
                            textAlign: TextAlign.end,
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 12),
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 140),
                            transitionBuilder: (child, animation) =>
                                FadeTransition(opacity: animation, child: child),
                            child: FittedBox(
                              key: ValueKey(_display),
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerRight,
                              child: Text(
                                _display,
                                style: theme.textTheme.displayMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
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
                                        onTap: () {
                                          if (key == '±') {
                                            setState(() {
                                              if (_display.startsWith('-')) {
                                                _display = _display.substring(1);
                                              } else if (_display != '0') {
                                                _display = '-$_display';
                                              }
                                            });
                                          } else {
                                            _press(key);
                                          }
                                        },
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
                        ? 'For quick calculations only. Does not change your finances.'
                        : 'Para cálculos rápidos. No modifica tus finanzas.',
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
    return FilledButton.tonal(
      onPressed: onTap,
      style: FilledButton.styleFrom(
        backgroundColor: label == '='
            ? scheme.primary
            : isClear
                ? scheme.errorContainer
                : operator
                    ? scheme.secondaryContainer
                    : scheme.surfaceContainerHighest,
        foregroundColor: label == '='
            ? scheme.onPrimary
            : isClear
                ? scheme.onErrorContainer
                : scheme.onSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        padding: EdgeInsets.zero,
      ),
      child: Text(
        label,
        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
      ),
    );
  }
}
), '');
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
    if (_replaceDisplay) return;
    setState(() {
      _display = _display.length <= 1 ||
              (_display.length == 2 && _display.startsWith('-'))
          ? '0'
          : _display.substring(0, _display.length - 1);
      _expression = _operator == null
          ? _display
          : '${_format(_firstOperand ?? 0)} $_operator $_display';
    });
  }

  void _press(String key) {
    switch (key) {
      case 'AC':
        _clear();
      case '⌫':
        _backspace();
      case '=':
        _calculate();
      case '+':
      case '−':
      case '×':
      case '÷':
      case '%':
        _chooseOperator(key);
      default:
        _input(key);
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
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Expanded(
                    flex: 2,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerHighest.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Text(
                            _expression,
                            maxLines: 2,
                            textAlign: TextAlign.end,
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 12),
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 140),
                            transitionBuilder: (child, animation) =>
                                FadeTransition(opacity: animation, child: child),
                            child: FittedBox(
                              key: ValueKey(_display),
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerRight,
                              child: Text(
                                _display,
                                style: theme.textTheme.displayMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
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
                                        onTap: () {
                                          if (key == '±') {
                                            setState(() {
                                              if (_display.startsWith('-')) {
                                                _display = _display.substring(1);
                                              } else if (_display != '0') {
                                                _display = '-$_display';
                                              }
                                            });
                                          } else {
                                            _press(key);
                                          }
                                        },
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
                        ? 'For quick calculations only. Does not change your finances.'
                        : 'Para cálculos rápidos. No modifica tus finanzas.',
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
    return FilledButton.tonal(
      onPressed: onTap,
      style: FilledButton.styleFrom(
        backgroundColor: label == '='
            ? scheme.primary
            : isClear
                ? scheme.errorContainer
                : operator
                    ? scheme.secondaryContainer
                    : scheme.surfaceContainerHighest,
        foregroundColor: label == '='
            ? scheme.onPrimary
            : isClear
                ? scheme.onErrorContainer
                : scheme.onSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        padding: EdgeInsets.zero,
      ),
      child: Text(
        label,
        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
      ),
    );
  }
}
