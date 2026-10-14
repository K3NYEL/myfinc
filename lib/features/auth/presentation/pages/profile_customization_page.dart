import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../session_provider.dart';
import '../../../../app/settings_provider.dart';

class ProfileCustomizationPage extends ConsumerStatefulWidget {
  const ProfileCustomizationPage({super.key});

  @override
  ConsumerState<ProfileCustomizationPage> createState() =>
      _ProfileCustomizationPageState();
}

class _ProfileCustomizationPageState
    extends ConsumerState<ProfileCustomizationPage> {
  static const _colors = <Color>[
    Color(0xFF2563EB),
    Color(0xFF0D9488),
    Color(0xFF7C3AED),
    Color(0xFFDB2777),
    Color(0xFFEA580C),
    Color(0xFF16A34A),
    Color(0xFF475569),
    Color(0xFF0891B2),
  ];
  static const _avatars = <IconData>[
    Icons.person_rounded,
    Icons.face_rounded,
    Icons.emoji_emotions_rounded,
    Icons.pets_rounded,
    Icons.spa_rounded,
    Icons.sports_esports_rounded,
    Icons.music_note_rounded,
    Icons.star_rounded,
  ];

  final _displayNameController = TextEditingController();
  final _bioController = TextEditingController();
  String? _userId;
  int _selectedColor = 0;
  int _selectedAvatar = 0;
  bool _loading = true;
  bool _saving = false;

  String _key(String field) => 'profile_$field:${_userId ?? ''}';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final user = ref.read(sessionProvider);
    if (user == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    _userId = user.id;
    final prefs = await SharedPreferences.getInstance();
    _displayNameController.text =
        prefs.getString(_key('display_name')) ?? user.fullName;
    _bioController.text = prefs.getString(_key('bio')) ?? '';
    _selectedColor = (prefs.getInt(_key('color')) ?? 0).clamp(0, _colors.length - 1).toInt();
    _selectedAvatar = (prefs.getInt(_key('avatar')) ?? 0).clamp(0, _avatars.length - 1).toInt();
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save() async {
    if (_userId == null || _saving) return;
    final name = _displayNameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(Localizations.localeOf(context).languageCode == 'en' ? 'Display name cannot be empty.' : 'El nombre visible no puede estar vacío.')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key('display_name'), name);
      await prefs.setString(_key('bio'), _bioController.text.trim());
      await prefs.setInt(_key('color'), _selectedColor);
      await prefs.setInt(_key('avatar'), _selectedAvatar);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(Localizations.localeOf(context).languageCode == 'en' ? 'Could not save profile customization.' : 'No se pudo guardar la personalización.')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _displayNameController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(sessionProvider);
    final isEnglish = ref.watch(settingsProvider).languageCode == 'en';
    final theme = Theme.of(context);
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (user == null) {
      return Scaffold(
        appBar: AppBar(title: Text(isEnglish ? 'Customize profile' : 'Personalizar perfil')),
        body: Center(child: Text(isEnglish ? 'Sign in to edit your profile.' : 'Inicia sesión para editar tu perfil.')),
      );
    }

    final accent = _colors[_selectedColor];
    return Scaffold(
      appBar: AppBar(title: const Text('Personalizar perfil')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [accent.withValues(alpha: 0.18), accent.withValues(alpha: 0.06)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: accent.withValues(alpha: 0.35)),
              ),
              child: Column(
                children: [
                  CircleAvatar(
                    radius: 42,
                    backgroundColor: accent,
                    child: Icon(_avatars[_selectedAvatar], size: 42, color: Colors.white),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _displayNameController.text.trim().isEmpty
                        ? user.fullName
                        : _displayNameController.text.trim(),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  if (_bioController.text.trim().isNotEmpty) ...[
                    const SizedBox(height: 5),
                    Text(_bioController.text.trim(), textAlign: TextAlign.center),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 24),
            Text(isEnglish ? 'Profile information' : 'Información del perfil', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            TextField(
              controller: _displayNameController,
              maxLength: 50,
              textCapitalization: TextCapitalization.words,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: isEnglish ? 'Display name' : 'Nombre visible',
                hintText: isEnglish ? 'What should we call you?' : '¿Cómo quieres que te llamen?',
                prefixIcon: const Icon(Icons.badge_outlined),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _bioController,
              maxLength: 120,
              minLines: 2,
              maxLines: 3,
              textCapitalization: TextCapitalization.sentences,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: isEnglish ? 'Bio (optional)' : 'Descripción (opcional)',
                hintText: isEnglish ? 'A short sentence about you' : 'Una frase sobre ti',
                prefixIcon: const Icon(Icons.short_text_rounded),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 20),
            Text(isEnglish ? 'Avatar' : 'Avatar', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (var i = 0; i < _avatars.length; i++)
                  ChoiceChip(
                    label: Icon(_avatars[i]),
                    selected: _selectedAvatar == i,
                    onSelected: (_) => setState(() => _selectedAvatar = i),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            Text(isEnglish ? 'Profile color' : 'Color del perfil', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (var i = 0; i < _colors.length; i++)
                  InkWell(
                    onTap: () => setState(() => _selectedColor = i),
                    customBorder: const CircleBorder(),
                    child: Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: _colors[i],
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: _selectedColor == i ? theme.colorScheme.onSurface : Colors.transparent,
                          width: 3,
                        ),
                      ),
                      child: _selectedColor == i
                          ? const Icon(Icons.check_rounded, color: Colors.white)
                          : null,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 28),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.save_outlined),
              label: Text(_saving ? (isEnglish ? 'Saving…' : 'Guardando…') : (isEnglish ? 'Save profile' : 'Guardar personalización')),
            ),
            const SizedBox(height: 10),
            Text(
              isEnglish
                  ? 'These changes are stored on this installation and do not affect your financial data or sign-in name.'
                  : 'Estos cambios son locales a esta instalación y no modifican tus datos financieros ni tu nombre de acceso.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
