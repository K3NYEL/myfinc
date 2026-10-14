import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../../features/auth/presentation/session_provider.dart';
import '../../../../app/settings_provider.dart';
import '../../../../core/platform/update_service.dart';
import '../../../../core/notifications/notification_permission_service.dart';
import '../../../../core/database/database.dart';
import '../../../../core/database/backup_service.dart';
import '../../../../core/network/myfinc_api_client.dart';
import '../../../../core/network/providers.dart';
import '../../../../core/errors/app_exception.dart';
import '../../../../core/database/migrations/legacy_data_migration_service.dart';
import '../../../finance/presentation/providers.dart';
import '../../../finance/presentation/pages/currency_converter_page.dart';
import '../../../finance/presentation/pages/finance_planning_page.dart';
import '../../../../core/settings/app_preferences.dart';
import '../../../../shared/widgets/update_dialog.dart';
import '../../../../shared/widgets/myfinc_logo.dart';

String _tr(BuildContext context, String spanish, String english) =>
    Localizations.localeOf(context).languageCode == 'en' ? english : spanish;

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  bool _checkingForUpdate = false;
  bool _dataOperationInProgress = false;
  String? _currentVersion;
  String _autoBackupFrequency = 'disabled';

  @override
  void initState() {
    super.initState();
    _loadCurrentVersion();
    _loadAutoBackupFrequency();
  }

  Future<void> _changeLanguage(String languageCode) async {
    if (languageCode == ref.read(settingsProvider).languageCode) return;
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierLabel: languageCode == 'en' ? 'Changing language' : 'Cambiando idioma',
      barrierColor: Theme.of(context).scaffoldBackgroundColor,
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (dialogContext, animation, secondaryAnimation) =>
          _LanguageChangeScreen(
        languageCode: languageCode,
        applyLanguage: () =>
            ref.read(settingsProvider.notifier).setLanguage(languageCode),
      ),
      transitionBuilder: (context, animation, secondaryAnimation, child) =>
          FadeTransition(opacity: animation, child: child),
    );
  }

  Future<void> _loadCurrentVersion() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();

      if (!mounted) return;

      setState(() {
        _currentVersion = packageInfo.version;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _currentVersion = Localizations.localeOf(context).languageCode == 'en' ? 'Unknown' : 'Desconocida';
      });
    }
  }

  Future<void> _loadAutoBackupFrequency() async {
    final frequency = await AppPreferences.getAutoBackupFrequency();
    if (!mounted) return;
    setState(() => _autoBackupFrequency = frequency);
  }

  String _autoBackupLabel(String frequency, String languageCode) {
    final isEnglish = languageCode == 'en';
    switch (frequency) {
      case 'daily':
        return isEnglish ? 'Daily at sign-in' : 'Diaria al iniciar sesión';
      case 'weekly':
        return isEnglish ? 'Weekly at sign-in' : 'Semanal al iniciar sesión';
      default:
        return isEnglish ? 'Disabled' : 'Desactivada';
    }
  }

  Future<void> _configureAutoBackup() async {
    final selected = await showDialog<String>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: Text(_tr(context, 'Copia automática', 'Automatic backup')),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
            child: Text(
              _tr(context, 'MyFinc guardará una copia local cuando inicies sesión y haya pasado el intervalo elegido. No se ejecuta en segundo plano con la app cerrada. Los archivos JSON no están cifrados y contienen datos financieros legibles; guárdalos en un lugar privado.', 'MyFinc will save a local backup at sign-in once the selected interval has passed. It does not run in the background while the app is closed. JSON files are not encrypted and contain readable financial data; keep them somewhere private.'),
            ),
          ),
          for (final option in [
            ('disabled', _tr(context, 'Desactivada', 'Disabled')),
            ('daily', _tr(context, 'Cada 24 horas al iniciar sesión', 'Every 24 hours at sign-in')),
            ('weekly', _tr(context, 'Cada 7 días al iniciar sesión', 'Every 7 days at sign-in')),
          ])
            SimpleDialogOption(
              onPressed: () => Navigator.pop(dialogContext, option.$1),
              child: Row(
                children: [
                  Icon(_autoBackupFrequency == option.$1 ? Icons.radio_button_checked : Icons.radio_button_unchecked),
                  const SizedBox(width: 12),
                  Expanded(child: Text(option.$2)),
                ],
              ),
            ),
        ],
      ),
    );
    if (selected == null || !mounted) return;
    await AppPreferences.setAutoBackupFrequency(selected);
    if (!mounted) return;
    setState(() => _autoBackupFrequency = selected);
    await _showUpdateMessage(
      title: _tr(context, 'Copia automática actualizada', 'Automatic backup updated'),
      message: selected == 'disabled'
          ? _tr(context, 'La creación automática de copias quedó desactivada.', 'Automatic backups have been disabled.')
          : _tr(context, 'MyFinc intentará crear una copia cada ${selected == 'daily' ? '24 horas' : '7 días'} al iniciar sesión. Si no se puede guardar, el inicio de sesión seguirá funcionando y se volverá a intentar en el siguiente inicio.', 'MyFinc will try to create a backup every ${selected == 'daily' ? '24 hours' : '7 days'} at sign-in. If saving fails, sign-in will continue normally and the backup will be retried next time.'),
      icon: Icons.backup_outlined,
    );
  }

  Future<void> _deleteAllData() async {
    if (_dataOperationInProgress) return;
    final user = ref.read(sessionProvider);
    if (user == null) {
      await _showUpdateMessage(
        title: _tr(context, 'Inicia sesión', 'Sign in'),
        message: _tr(context, 'Debes iniciar sesión para eliminar tus datos financieros.', 'You must sign in to delete your financial data.'),
        icon: Icons.lock_outline_rounded,
      );
      return;
    }

    final controller = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text(_tr(context, 'Eliminar todos los datos financieros', 'Delete all financial data')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_tr(context, 'Esta acción eliminará de esta cuenta todas las cuentas financieras, movimientos, transferencias y categorías personalizadas. No elimina tu cuenta de acceso ni los datos de otras cuentas.', 'This action deletes all financial accounts, transactions, transfers, and custom categories from this account. It does not delete your sign-in account or data belonging to other accounts.')),
                const SizedBox(height: 12),
                Text(_tr(context, 'Antes de continuar, MyFinc guardará una copia de seguridad. Si no puede crearla, no eliminará nada.', 'Before continuing, MyFinc will create a backup. If it cannot create one, nothing will be deleted.')),
                const SizedBox(height: 12),
                Text(_tr(context, 'Para confirmar, escribe exactamente: ELIMINAR MIS DATOS', 'To confirm, type exactly: DELETE MY DATA'), style: TextStyle(color: Theme.of(dialogContext).colorScheme.error, fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                TextField(
                  controller: controller,
                  autofocus: true,
                  onChanged: (_) => setDialogState(() {}),
                  decoration: InputDecoration(labelText: _tr(context, 'Confirmación', 'Confirmation'), border: const OutlineInputBorder()),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: Text(_tr(context, 'Cancelar', 'Cancel'))),
            FilledButton(
              onPressed: controller.text == 'ELIMINAR MIS DATOS' ? () => Navigator.pop(dialogContext, true) : null,
              child: Text(_tr(context, 'Crear copia y eliminar', 'Back up and delete')),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    if (confirmed != true || !mounted) return;

    setState(() => _dataOperationInProgress = true);
    var loadingOpen = false;
    Future<void>? loadingRoute;
    Future<void> closeLoading() async {
      if (loadingOpen && mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        loadingOpen = false;
        if (loadingRoute != null) await loadingRoute;
      }
    }
    try {
      loadingRoute = showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _OperationLoadingDialog(
          title: _tr(context, 'Protegiendo tus datos', 'Protecting your data'),
          message: _tr(context, 'Creando una copia preventiva antes de eliminar…', 'Creating a safety backup before deletion…'),
        ),
      );
      loadingOpen = true;
      await Future<void>.delayed(Duration.zero);
      final jsonText = await const BackupService().createBackup(user.id);
      final safetyFile = await _saveBackupFile(jsonText, user.id);
      await closeLoading();
      if (!mounted) return;

      loadingRoute = showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _OperationLoadingDialog(
          title: _tr(context, 'Eliminando datos financieros', 'Deleting financial data'),
          message: _tr(context, 'Eliminando únicamente los registros de esta cuenta…', 'Deleting records for this account only…'),
        ),
      );
      loadingOpen = true;
      await Future<void>.delayed(Duration.zero);
      final deleted = await const BackupService().deleteUserData(user.id);
      await closeLoading();
      ref.invalidate(accountsProvider);
      ref.invalidate(movementsProvider);
      ref.invalidate(summaryProvider);
      ref.invalidate(byCategoryProvider);
      ref.invalidate(categoriesProvider('income'));
      ref.invalidate(categoriesProvider('expense'));
      if (!mounted) return;
      await _showUpdateMessage(
        title: _tr(context, 'Datos eliminados', 'Data deleted'),
        message: _tr(context, 'Se eliminaron ${deleted['accounts']} cuentas, ${deleted['transactions']} movimientos y ${deleted['transfers']} transferencias. La copia preventiva está guardada como ${p.basename(safetyFile.path)}.', 'Deleted ${deleted['accounts']} accounts, ${deleted['transactions']} transactions, and ${deleted['transfers']} transfers. The safety backup is saved as ${p.basename(safetyFile.path)}.'),
        icon: Icons.check_circle_outline_rounded,
      );
    } catch (error) {
      await closeLoading();
      if (!mounted) return;
      await _showUpdateMessage(
        title: _tr(context, 'No se pudieron eliminar los datos', 'Could not delete data'),
        message: error is AppException ? error.message : _tr(context, 'No se completó la eliminación. Si falló la copia preventiva, tus datos no se eliminaron.', 'Deletion was not completed. If the safety backup failed, your data was not deleted.'),
        icon: Icons.error_outline_rounded,
      );
    } finally {
      await closeLoading();
      if (mounted) setState(() => _dataOperationInProgress = false);
    }
  }

  Future<void> _showCategoryManager() async {
    await showDialog<void>(
      context: context,
      builder: (_) => const _CategoryManagerDialog(),
    );
  }

  Future<void> _checkForUpdate() async {
    if (_checkingForUpdate) return;

    setState(() {
      _checkingForUpdate = true;
    });

    try {
      final update = await UpdateService.checkForUpdate();

      if (!mounted) return;

      if (update != null) {
        await showUpdateDialog(context, update);
      } else {
        await _showUpdateMessage(
          title: _tr(context, 'MyFinc está actualizada', 'MyFinc is up to date'),
          message: _tr(context, 'No hay una versión nueva disponible para este dispositivo.', 'No new version is available for this device.'),
          icon: Icons.check_circle_outline_rounded,
        );
      }
    } on UpdateCheckException catch (e) {
      if (!mounted) return;

      await _showUpdateMessage(
        title: _tr(context, 'No se pudo comprobar', 'Could not check for updates'),
        message: e.message,
        icon: Icons.cloud_off_outlined,
      );
    } catch (e) {
      if (!mounted) return;

      await _showUpdateMessage(
        title: _tr(context, 'No se pudo comprobar', 'Could not check for updates'),
        message: _tr(context, 'Ocurrió un error inesperado al comprobar actualizaciones.', 'An unexpected error occurred while checking for updates.'),
        icon: Icons.error_outline_rounded,
      );
    } finally {
      if (mounted) {
        setState(() {
          _checkingForUpdate = false;
        });
      }
    }
  }

  Future<void> _showUpdateMessage({
    required String title,
    required String message,
    required IconData icon,
  }) async {
    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Row(
            children: [
              Icon(
                icon,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(title),
              ),
            ],
          ),
          content: Text(message),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(_tr(context, 'Aceptar', 'OK')),
            ),
          ],
        );
      },
    );
  }


  Future<File> _saveBackupFile(String jsonText, String userId) async {
    final baseDirectory = await getDownloadsDirectory() ??
        await getApplicationDocumentsDirectory();
    final backupDirectory =
        Directory(p.join(baseDirectory.path, 'MyFinc', 'backups'));
    await backupDirectory.create(recursive: true);

    final stamp = DateTime.now().toUtc().millisecondsSinceEpoch;
    final userKey = sha256.convert(utf8.encode(userId)).toString().substring(0, 16);
    final file = File(p.join(backupDirectory.path, 'myfinc-backup-$userKey-$stamp.json'));
    await file.writeAsString(jsonText, encoding: utf8, flush: true);

    // Keep only the five newest MyFinc backup files in this directory.
    final backups = backupDirectory
        .listSync(followLinks: false)
        .whereType<File>()
        .where((candidate) =>
            p.basename(candidate.path).startsWith('myfinc-backup-$userKey-') &&
            p.basename(candidate.path).endsWith('.json'))
        .toList();
    backups.sort((a, b) =>
        b.lastModifiedSync().compareTo(a.lastModifiedSync()));
    for (final oldBackup in backups.skip(5)) {
      await oldBackup.delete();
    }
    return file;
  }

  Future<void> _backupData() async {
    if (_dataOperationInProgress) return;
    final user = ref.read(sessionProvider);
    if (user == null) {
      await _showUpdateMessage(
        title: _tr(context, 'Inicia sesión', 'Sign in'),
        message: _tr(context, 'Debes iniciar sesión para crear una copia de tus datos.', 'You must sign in to back up your data.'),
        icon: Icons.lock_outline_rounded,
      );
      return;
    }
    setState(() => _dataOperationInProgress = true);
    var loadingOpen = false;
    Future<void>? loadingRoute;
    try {
      loadingRoute = showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _OperationLoadingDialog(
          title: _tr(context, 'Creando copia de seguridad', 'Creating backup'),
          message: _tr(context, 'Preparando tus datos y guardando el archivo localmente…', 'Preparing your data and saving the file locally…'),
        ),
      );
      loadingOpen = true;
      await Future<void>.delayed(Duration.zero);
      final jsonText = await const BackupService().createBackup(user.id);
      final file = await _saveBackupFile(jsonText, user.id);
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      loadingOpen = false;
      await loadingRoute;
      if (!mounted) return;
      await _showUpdateMessage(
        title: _tr(context, 'Copia guardada', 'Backup saved'),
        message: _tr(context, 'La copia se guardó localmente.\n\nRuta:\n${file.path}\n\nImportante: el archivo JSON no está cifrado y contiene datos financieros legibles. Guárdalo en un lugar privado. No contiene contraseñas ni hashes de acceso.', 'The backup was saved locally.\n\nPath:\n${file.path}\n\nImportant: the JSON file is not encrypted and contains readable financial data. Keep it somewhere private. It does not contain passwords or sign-in hashes.'),
        icon: Icons.check_circle_outline_rounded,
      );
    } catch (error) {
      if (!mounted) return;
      if (loadingOpen) {
        Navigator.of(context, rootNavigator: true).pop();
        loadingOpen = false;
        if (loadingRoute != null) await loadingRoute;
      }
      if (!mounted) return;
      await _showUpdateMessage(
        title: _tr(context, 'No se pudo crear la copia', 'Could not create backup'),
        message: error is AppException ? error.message : _tr(context, 'Ocurrió un error al generar o guardar la copia de seguridad.', 'An error occurred while creating or saving the backup.'),
        icon: Icons.error_outline_rounded,
      );
    } finally {
      if (loadingOpen && mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        if (loadingRoute != null) await loadingRoute;
      }
      if (mounted) setState(() => _dataOperationInProgress = false);
    }
  }

  Future<Directory> _getBackupDirectory() async {
    final baseDirectory = await getDownloadsDirectory() ??
        await getApplicationDocumentsDirectory();
    return Directory(p.join(baseDirectory.path, 'MyFinc', 'backups'));
  }

  Future<List<File>> _findLocalBackups(String userId) async {
    final userKey = sha256.convert(utf8.encode(userId)).toString().substring(0, 16);
    final directory = await _getBackupDirectory();
    if (!await directory.exists()) return <File>[];
    final backups = directory
        .listSync(followLinks: false)
        .whereType<File>()
        .where((file) {
          final name = p.basename(file.path);
          return name.startsWith('myfinc-backup-$userKey-') &&
              name.endsWith('.json');
        })
        .toList();
    backups.sort((a, b) =>
        b.lastModifiedSync().compareTo(a.lastModifiedSync()));
    return backups;
  }

  Future<String?> _chooseBackup(List<File> backups) {
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(_tr(context, 'Restaurar copia', 'Restore backup')),
        content: SizedBox(
          width: 460,
          child: backups.isEmpty
              ? Text(
                  _tr(context, 'No se encontraron copias de MyFinc en la carpeta habitual. Puedes buscar una copia guardada en otra ubicación.', 'No MyFinc backups were found in the usual folder. You can look for a backup saved elsewhere.'),
                )
              : ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 360),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: backups.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final backup = backups[index];
                      final modified = backup.lastModifiedSync().toLocal();
                      final date = '${modified.year.toString().padLeft(4, '0')}-'
                          '${modified.month.toString().padLeft(2, '0')}-'
                          '${modified.day.toString().padLeft(2, '0')} '
                          '${modified.hour.toString().padLeft(2, '0')}:'
                          '${modified.minute.toString().padLeft(2, '0')}';
                      return ListTile(
                        leading: const Icon(Icons.backup_outlined),
                        title: Text(
                          p.basename(backup.path),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(_tr(context, 'Última modificación: $date', 'Last modified: $date')),
                        onTap: () =>
                            Navigator.of(dialogContext).pop(backup.path),
                      );
                    },
                  ),
                ),
        ),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop('__external__'),
            child: Text(_tr(context, 'Buscar otro archivo…', 'Choose another file…')),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(_tr(context, 'Cancelar', 'Cancel')),
          ),
        ],
      ),
    );
  }

  Future<void> _restoreData() async {
    if (_dataOperationInProgress) return;
    final user = ref.read(sessionProvider);
    if (user == null) {
      await _showUpdateMessage(
        title: _tr(context, 'Inicia sesión', 'Sign in'),
        message: _tr(context, 'Debes iniciar sesión para restaurar una copia.', 'You must sign in to restore a backup.'),
        icon: Icons.lock_outline_rounded,
      );
      return;
    }

    setState(() => _dataOperationInProgress = true);
    var restoreLoadingOpen = false;
    Future<void>? restoreLoadingRoute;
    Future<void> closeRestoreLoading() async {
      if (restoreLoadingOpen && mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        restoreLoadingOpen = false;
        if (restoreLoadingRoute != null) await restoreLoadingRoute;
      }
    }
    try {
      final localBackups = await _findLocalBackups(user.id);
      if (!mounted) return;
      final selectedPath = await _chooseBackup(localBackups);
      if (!mounted || selectedPath == null) return;

      List<int> bytes;
      String fileName;
      if (selectedPath == '__external__') {
        final externalFile = await FilePicker.pickFile(
          dialogTitle: 'Seleccionar copia de seguridad de MyFinc',
          type: FileType.custom,
          allowedExtensions: ['json'],
        );
        if (!mounted || externalFile == null) return;
        bytes = await externalFile.readAsBytes();
        fileName = externalFile.name;
      } else {
        final localFile = File(selectedPath);
        bytes = await localFile.readAsBytes();
        fileName = p.basename(localFile.path);
      }
      if (!mounted) return;
      if (bytes.length > BackupService.maxBackupBytes) {
        throw const AppException('La copia supera el límite de 10 MB.');
      }
      final jsonText = utf8.decode(bytes, allowMalformed: false);

      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(_tr(context, 'Restaurar copia de seguridad', 'Restore backup')),
          content: Text(
            'Se importarán los datos de "$fileName" a la cuenta actual. '
            'Los datos existentes no se borrarán; las cuentas y movimientos '
            'se agregarán a los que ya tienes. Antes de importar, MyFinc '
            'creará una copia preventiva de tus datos actuales. La misma '
            'copia no puede restaurarse dos veces en esta cuenta.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(_tr(context, 'Cancelar', 'Cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(_tr(context, 'Restaurar', 'Restore')),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;

      restoreLoadingRoute = showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _OperationLoadingDialog(
          title: _tr(context, 'Restaurando copia de seguridad', 'Restoring backup'),
          message: _tr(context, 'Validando e importando los datos. No cierres MyFinc…', 'Validating and importing data. Do not close MyFinc…'),
        ),
      );
      restoreLoadingOpen = true;
      await Future<void>.delayed(Duration.zero);

      // Do not begin importing unless the current account's data has first
      // been saved successfully. This protects against accidental merges
      // and gives the user a rollback file if they selected the wrong copy.
      final currentData = await const BackupService().createBackup(user.id);
      final safetyFile = await _saveBackupFile(currentData, user.id);

      final counts = await const BackupService().restoreBackup(
        userId: user.id,
        jsonText: jsonText,
      );
      await closeRestoreLoading();
      ref.invalidate(accountsProvider);
      ref.invalidate(movementsProvider);
      ref.invalidate(summaryProvider);
      ref.invalidate(byCategoryProvider);

      if (!mounted) return;
      await _showUpdateMessage(
        title: _tr(context, 'Restauración completada', 'Restore completed'),
        message: 'Se importaron ${counts['accounts']} cuentas, '
            '${counts['transactions']} movimientos y '
            '${counts['transfers']} transferencias. '
            'Tus datos anteriores se conservaron. Copia preventiva: '
            '${p.basename(safetyFile.path)}.',
        icon: Icons.check_circle_outline_rounded,
      );
    } on AppException catch (error) {
      await closeRestoreLoading();
      if (!mounted) return;
      await _showUpdateMessage(
        title: _tr(context, 'No se pudo restaurar', 'Could not restore backup'),
        message: error.message,
        icon: Icons.error_outline_rounded,
      );
    } on FormatException {
      await closeRestoreLoading();
      if (!mounted) return;
      await _showUpdateMessage(
        title: _tr(context, 'Archivo no válido', 'Invalid file'),
        message: _tr(context, 'El archivo no contiene texto UTF-8 válido.', 'The file does not contain valid UTF-8 text.'),
        icon: Icons.error_outline_rounded,
      );
    } catch (_) {
      await closeRestoreLoading();
      if (!mounted) return;
      await _showUpdateMessage(
        title: _tr(context, 'No se pudo restaurar', 'Could not restore backup'),
        message: _tr(context, 'Ocurrió un error. No se completó la importación.', 'An error occurred. The import was not completed.'),
        icon: Icons.error_outline_rounded,
      );
    } finally {
      await closeRestoreLoading();
      if (mounted) setState(() => _dataOperationInProgress = false);
    }
  }

  Future<void> _migrateBackupToCloud() async {
    if (_dataOperationInProgress) return;
    final remoteSession = ref.read(remoteAuthSessionProvider);
    if (remoteSession == null) {
      await _showUpdateMessage(
        title: _tr(context, 'Inicia sesión en la nube', 'Sign in to the cloud'),
        message: 'Para migrar una copia, activa la cuenta en la nube desde el '
            'inicio de sesión. Tus datos locales no se enviarán hasta que '
            'selecciones una copia y confirmes la importación.',
        icon: Icons.cloud_off_outlined,
      );
      return;
    }

    setState(() => _dataOperationInProgress = true);
    try {
      final file = await FilePicker.pickFile(
        dialogTitle: 'Seleccionar copia de MyFinc para migrar',
        type: FileType.custom,
        allowedExtensions: ['json'],
      );
      if (!mounted || file == null) return;

      final bytes = await file.readAsBytes();
      if (!mounted) return;
      // The API enforces a 4 MB JSON payload limit.
      if (bytes.length > 4 * 1024 * 1024) {
        throw const AppException(
          'La copia supera el límite de 4 MB permitido para la migración.',
        );
      }
      final backupJson = utf8.decode(bytes, allowMalformed: false);
      final api = ref.read(myfincApiClientProvider);
      final preview = await api.previewBackup(
        accessToken: remoteSession.accessToken,
        backupJson: backupJson,
        currencyCode: 'DOP',
      );

      if (!mounted) return;
      if (preview.alreadyImported) {
        await _showUpdateMessage(
          title: _tr(context, 'Copia ya importada', 'Backup already imported'),
          message: 'Esta copia ya fue importada en la cuenta en la nube. '
              'No se enviaron registros nuevos.',
          icon: Icons.info_outline_rounded,
        );
        return;
      }

      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(_tr(context, 'Revisar migración a la nube', 'Review cloud migration')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_tr(context, 'Archivo: ${file.name}', 'File: ${file.name}')),
                const SizedBox(height: 12),
                Text(_tr(context, 'Cuentas: ${preview.accounts}', 'Accounts: ${preview.accounts}')),
                Text(_tr(context, 'Categorías: ${preview.categories}', 'Categories: ${preview.categories}')),
                Text(_tr(context, 'Movimientos: ${preview.transactions}', 'Transactions: ${preview.transactions}')),
                Text(_tr(context, 'Transferencias: ${preview.transfers}', 'Transfers: ${preview.transfers}')),
                const SizedBox(height: 12),
                Text(_tr(context, 'Moneda asignada: ${preview.currencyCode}', 'Assigned currency: ${preview.currencyCode}')),
                const SizedBox(height: 12),
                const Text(
                  'Al confirmar, estos datos financieros se enviarán por '
                  'HTTPS a la API de MyFinc y se importarán a la cuenta en '
                  'la nube. La copia local y los datos actuales de este '
                  'dispositivo no se borrarán ni se reemplazarán.',
                ),
                const SizedBox(height: 8),
                Text(
                  'Comprueba que has elegido la copia correcta. Esta misma '
                  'copia no se puede importar dos veces en la misma cuenta.',
                  style: TextStyle(
                    color: Theme.of(dialogContext).colorScheme.error,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(_tr(context, 'Cancelar', 'Cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(_tr(context, 'Confirmar migración', 'Confirm migration')),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;

      final result = await api.importBackup(
        accessToken: remoteSession.accessToken,
        backupJson: backupJson,
        currencyCode: preview.currencyCode,
        confirm: true,
      );
      if (!mounted) return;

      final counts = result['counts'];
      final importedAccounts = counts is Map ? counts['accounts'] : null;
      final importedTransactions =
          counts is Map ? counts['transactions'] : null;
      final importedTransfers = counts is Map ? counts['transfers'] : null;
      await _showUpdateMessage(
        title: _tr(context, 'Migración completada', 'Migration completed'),
        message: 'La API confirmó la importación de '
            '${importedAccounts ?? preview.accounts} cuentas, '
            '${importedTransactions ?? preview.transactions} movimientos y '
            '${importedTransfers ?? preview.transfers} transferencias. '
            'Los datos locales se conservaron sin cambios.',
        icon: Icons.cloud_done_outlined,
      );
    } on MyFincApiException catch (error) {
      if (!mounted) return;
      await _showUpdateMessage(
        title: _tr(context, 'No se pudo migrar la copia', 'Could not migrate backup'),
        message: error.message,
        icon: Icons.cloud_off_outlined,
      );
    } on AppException catch (error) {
      if (!mounted) return;
      await _showUpdateMessage(
        title: _tr(context, 'No se pudo leer la copia', 'Could not read backup'),
        message: error.message,
        icon: Icons.error_outline_rounded,
      );
    } on FormatException {
      if (!mounted) return;
      await _showUpdateMessage(
        title: _tr(context, 'Archivo no válido', 'Invalid file'),
        message: _tr(context, 'El archivo no contiene texto UTF-8 válido.', 'The file does not contain valid UTF-8 text.'),
        icon: Icons.error_outline_rounded,
      );
    } catch (_) {
      if (!mounted) return;
      await _showUpdateMessage(
        title: _tr(context, 'No se pudo migrar la copia', 'Could not migrate backup'),
        message: _tr(context, 'Ocurrió un error inesperado. No se confirmó la importación.', 'An unexpected error occurred. The import was not confirmed.'),
        icon: Icons.error_outline_rounded,
      );
    } finally {
      if (mounted) setState(() => _dataOperationInProgress = false);
    }
  }

  Future<void> _showSyncInfo() async {
    await _showUpdateMessage(
      title: _tr(context, 'Sincronización en la nube', 'Cloud sync'),
      message: 'La sincronización todavía no está disponible porque MyFinc '
          'no tiene un backend de sincronización configurado. Tus datos '
          'siguen guardándose localmente. Mientras tanto, usa Copia de '
          'seguridad para moverlos manualmente entre dispositivos.',
      icon: Icons.cloud_off_outlined,
    );
  }

  Future<void> _recoverLegacyData() async {
    if (_dataOperationInProgress) return;
    final user = ref.read(sessionProvider);
    if (user == null) {
      await _showUpdateMessage(
        title: _tr(context, 'Inicia sesión', 'Sign in'),
        message: _tr(context, 'Debes iniciar sesión para recuperar datos antiguos.', 'You must sign in to recover older data.'),
        icon: Icons.lock_outline_rounded,
      );
      return;
    }

    setState(() => _dataOperationInProgress = true);
    TextEditingController? confirmationController;
    var loadingOpen = false;
    Future<void>? loadingRoute;
    Future<void> closeLoading() async {
      if (loadingOpen && mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        loadingOpen = false;
        if (loadingRoute != null) await loadingRoute;
      }
    }

    try {
      final database = await AppDatabase.instance;
      final migration = LegacyDataMigrationService(database);
      final status = await migration.getStatus();
      final accounts = (status['unassigned_accounts'] as num?)?.toInt() ?? 0;
      final transactions =
          (status['unassigned_transactions'] as num?)?.toInt() ?? 0;
      final transfers = (status['unassigned_transfers'] as num?)?.toInt() ?? 0;
      final total = accounts + transactions + transfers;

      if (!mounted) return;
      if (total == 0) {
        await _showUpdateMessage(
          title: _tr(context, 'No hay datos pendientes', 'No pending data'),
          message: 'No se encontraron cuentas, movimientos ni transferencias '
              'antiguas pendientes de recuperar.',
          icon: Icons.check_circle_outline_rounded,
        );
        return;
      }

      final controller = TextEditingController();
      confirmationController = controller;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (dialogContext, setDialogState) => AlertDialog(
            title: Text(_tr(context, 'Recuperar datos antiguos', 'Recover older data')),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'MyFinc encontró datos financieros sin propietario '
                    'asignado en esta instalación:',
                  ),
                  const SizedBox(height: 12),
                  Text('• Cuentas: $accounts'),
                  Text('• Movimientos: $transactions'),
                  Text('• Transferencias: $transfers'),
                  const SizedBox(height: 12),
                  const Text(
                    'Si continúas, las cuentas antiguas sin propietario se '
                    'asignarán a tu perfil y los movimientos compatibles se '
                    'vincularán a esas cuentas. Los registros que entren en '
                    'conflicto permanecerán sin asignar.',
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'No continúes si este dispositivo fue compartido y esos '
                    'datos podrían pertenecer a otra persona. Esta acción no '
                    'se puede deshacer desde la aplicación.',
                    style: TextStyle(
                      color: Theme.of(dialogContext).colorScheme.error,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Escribe exactamente: '
                    '${LegacyDataMigrationService.confirmationPhrase}',
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: controller,
                    autofocus: true,
                    onChanged: (_) => setDialogState(() {}),
                    decoration: InputDecoration(
                      labelText: _tr(context, 'Confirmación', 'Confirmation'),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: Text(_tr(context, 'Cancelar', 'Cancel')),
              ),
              FilledButton(
                onPressed: controller.text ==
                        LegacyDataMigrationService.confirmationPhrase
                    ? () => Navigator.of(dialogContext).pop(true)
                    : null,
                child: Text(_tr(context, 'Recuperar datos', 'Recover data')),
              ),
            ],
          ),
        ),
      );
      final confirmation = controller.text;
      if (confirmed != true || !mounted) return;

      loadingRoute = showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _OperationLoadingDialog(
          title: _tr(context, 'Recuperando datos antiguos', 'Recovering older data'),
          message: _tr(context, 'Comprobando relaciones y asignando registros…', 'Checking relationships and assigning records…'),
        ),
      );
      loadingOpen = true;
      await Future<void>.delayed(Duration.zero);
      await migration.adoptLegacyData(
        userId: user.id,
        confirmation: confirmation,
      );
      await closeLoading();

      ref.invalidate(accountsProvider);
      ref.invalidate(movementsProvider);
      ref.invalidate(summaryProvider);
      ref.invalidate(byCategoryProvider);

      if (!mounted) return;
      await _showUpdateMessage(
        title: _tr(context, 'Revisión completada', 'Review completed'),
        message: 'MyFinc procesó los datos antiguos. Si quedaron registros '
            'en conflicto, permanecerán sin asignar para proteger la '
            'privacidad de las cuentas.',
        icon: Icons.check_circle_outline_rounded,
      );
    } catch (error) {
      await closeLoading();
      if (!mounted) return;
      await _showUpdateMessage(
        title: _tr(context, 'No se pudieron recuperar los datos', 'Could not recover data'),
        message: error is AppException
            ? error.message
            : 'Ocurrió un error inesperado. No se confirmó la recuperación.',
        icon: Icons.error_outline_rounded,
      );
    } finally {
      confirmationController?.dispose();
      await closeLoading();
      if (mounted) setState(() => _dataOperationInProgress = false);
    }
  }

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(_tr(context, 'Cerrar sesión', 'Sign out')),
          content: const Text(
            '¿Seguro que quieres cerrar tu sesión? '
            'Tus datos permanecerán guardados en este dispositivo.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(_tr(context, 'Cancelar', 'Cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(_tr(context, 'Cerrar sesión', 'Sign out')),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) return;

    await ref.read(sessionProvider.notifier).clearSession();

    if (!mounted) return;

    context.go('/auth');
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            IconButton(
              tooltip: _tr(context, 'Volver', 'Back'),
              onPressed: () {
                if (context.canPop()) {
                  context.pop();
                } else {
                  context.go('/');
                }
              },
              icon: const Icon(Icons.arrow_back_rounded),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      settings.languageCode == 'en' ? 'Settings' : 'Configuración',
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),

                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),

        // =========================
        // APARIENCIA
        // =========================
        _SettingsSection(
          title: settings.languageCode == 'en' ? 'Appearance' : 'Apariencia',
          children: [
            _SettingsTile(
              icon: Icons.palette_outlined,
              title: settings.languageCode == 'en' ? 'Theme' : 'Tema',
              subtitle: _themeLabel(settings.theme, settings.languageCode),
              onTap: () => _showThemeSelector(context, ref),
            ),
            _SettingsTile(
              icon: Icons.animation_outlined,
              title: settings.languageCode == 'en' ? 'Animations' : 'Animaciones',
              subtitle:
                  settings.languageCode == 'en'
                      ? (settings.animationsEnabled ? 'Enabled' : 'Disabled')
                      : (settings.animationsEnabled ? 'Activadas' : 'Desactivadas'),
              trailing: Switch(
                value: settings.animationsEnabled,
                onChanged: (value) {
                  ref.read(settingsProvider.notifier).setAnimations(value);
                },
              ),
            ),
          ],
        ),

        _SettingsSection(
          title: settings.languageCode == 'en' ? 'Language' : 'Idioma',
          children: [
            _SettingsTile(
              icon: Icons.language_rounded,
              title: settings.languageCode == 'en' ? 'App language' : 'Idioma de la aplicación',
              subtitle: settings.languageCode == 'en' ? 'English' : 'Español',
              trailing: DropdownButton<String>(
                value: settings.languageCode,
                underline: const SizedBox.shrink(),
                items: [
                  DropdownMenuItem(value: 'es', child: Text(_tr(context, 'Español', 'Spanish'))),
                  DropdownMenuItem(value: 'en', child: Text(_tr(context, 'English', 'English'))),
                ],
                onChanged: (value) {
                  if (value != null) {
                    _changeLanguage(value);
                  }
                },
              ),
            ),
          ],
        ),

        // =========================
        // FINANZAS
        // =========================
        _SettingsSection(
          title: settings.languageCode == 'en' ? 'Finances' : 'Finanzas',
          children: [
            _SettingsTile(
              icon: Icons.currency_exchange_rounded,
              title: settings.languageCode == 'en' ? 'Currencies and converter' : 'Monedas y conversor',
              subtitle: settings.languageCode == 'en' ? 'Convert currencies and set the display currency' : 'Convierte divisas y configura la moneda de visualización',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const CurrencyConverterPage(),
                ),
              ),
            ),
            _SettingsTile(
              icon: Icons.savings_outlined,
              title: settings.languageCode == 'en' ? 'Budgets and savings goals' : 'Presupuestos y metas de ahorro',
              subtitle: settings.languageCode == 'en' ? 'Track monthly limits and savings progress' : 'Controla el límite mensual y el progreso de tus metas',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const FinancePlanningPage(),
                ),
              ),
            ),
            _SettingsTile(
              icon: Icons.category_outlined,
              title: settings.languageCode == 'en' ? 'Categories' : 'Categorías',
              subtitle: settings.languageCode == 'en' ? 'Manage income and expense categories' : 'Administrar categorías de ingresos y gastos',
              onTap: _showCategoryManager,
            ),
          ],
        ),

        _SettingsSection(
          title: settings.languageCode == 'en' ? 'Account' : 'Cuenta',
          children: [
            _SettingsTile(
              icon: Icons.cloud_sync_outlined,
              title: settings.languageCode == 'en' ? 'Link MyFinc account' : 'Vincular cuenta MyFinc',
              subtitle: settings.languageCode == 'en' ? 'Connect a remote account for future sync' : 'Conectar una cuenta remota para preparar la futura sincronización',
              onTap: () => context.push('/settings/cloud-account'),
            ),
            _SettingsTile(
              icon: Icons.logout_rounded,
              title: _tr(context, 'Cerrar sesión', 'Sign out'),
              subtitle: _tr(context, 'Salir de tu cuenta en este dispositivo', 'Sign out on this device'),
              onTap: _logout,
            ),
          ],
        ),

        // =========================
        // DATOS
        // =========================
        _SettingsSection(
          title: _tr(context, 'Datos', 'Data'),
          children: [
            _SettingsTile(
              icon: Icons.backup_outlined,
              title: _tr(context, 'Copia de seguridad', 'Backup'),
              subtitle: _dataOperationInProgress
                  ? _tr(context, 'Preparando operación...', 'Preparing operation...')
                  : _tr(context, 'Exportar cuentas y movimientos a un archivo JSON', 'Export accounts and transactions to a JSON file'),
              onTap: _dataOperationInProgress ? null : _backupData,
            ),
            _SettingsTile(
              icon: Icons.restore_outlined,
              title: _tr(context, 'Restaurar datos', 'Restore data'),
              subtitle: _dataOperationInProgress
                  ? _tr(context, 'Preparando operación...', 'Preparing operation...')
                  : _tr(context, 'Importar una copia JSON sin borrar los datos actuales', 'Import a JSON backup without deleting current data'),
              onTap: _dataOperationInProgress ? null : _restoreData,
            ),
            _SettingsTile(
              icon: Icons.cloud_upload_outlined,
              title: _tr(context, 'Migrar copia a la nube', 'Migrate backup to cloud'),
              subtitle: _dataOperationInProgress
                  ? _tr(context, 'Preparando operación...', 'Preparing operation...')
                  : ref.watch(remoteAuthSessionProvider) == null
                      ? _tr(context, 'Requiere una sesión de cuenta en la nube', 'Requires a signed-in cloud account')
                      : _tr(context, 'Previsualizar e importar una copia a tu cuenta remota', 'Preview and import a backup to your remote account'),
              onTap: _dataOperationInProgress ? null : _migrateBackupToCloud,
            ),
            _SettingsTile(
              icon: Icons.history_rounded,
              title: _tr(context, 'Recuperar datos antiguos', 'Recover older data'),
              subtitle: _dataOperationInProgress
                  ? _tr(context, 'Preparando operación...', 'Preparing operation...')
                  : _tr(context, 'Revisar y recuperar datos sin propietario asignado', 'Review and recover data without an assigned owner'),
              onTap: _dataOperationInProgress ? null : _recoverLegacyData,
            ),
            _SettingsTile(
              icon: Icons.backup_table_outlined,
              title: _tr(context, 'Copia automática', 'Automatic backup'),
              subtitle: _autoBackupLabel(_autoBackupFrequency, settings.languageCode),
              onTap: _dataOperationInProgress ? null : _configureAutoBackup,
            ),
            _SettingsTile(
              icon: Icons.delete_forever_outlined,
              title: _tr(context, 'Eliminar todos los datos', 'Delete all data'),
              subtitle: _dataOperationInProgress
                  ? _tr(context, 'Operación en curso…', 'Operation in progress…')
                  : _tr(context, 'Borrar los datos financieros de esta cuenta tras crear una copia', 'Delete this account’s financial data after creating a backup'),
              onTap: _dataOperationInProgress ? null : _deleteAllData,
            ),
            _SettingsTile(
              icon: Icons.sync_outlined,
              title: _tr(context, 'Sincronización', 'Synchronization'),
              subtitle: _tr(context, 'No disponible: falta configurar el servidor', 'Unavailable: server setup is required'),
              onTap: _showSyncInfo,
            ),
          ],
        ),

        // =========================
        // ACTUALIZACIONES
        // =========================
        _SettingsSection(
          title: settings.languageCode == 'en' ? 'Updates' : 'Actualizaciones',
          children: [
            _SettingsTile(
              icon: Icons.notifications_outlined,
              title: settings.languageCode == 'en' ? 'Notification permissions' : 'Permisos de notificación',
              subtitle: settings.languageCode == 'en' ? 'Check or change device permissions' : 'Consultar o cambiar el permiso del dispositivo',
              onTap: () async {
                if (!NotificationPermissionService.isAndroid) {
                  await _showUpdateMessage(
                    title: _tr(context, 'Permiso no disponible', 'Permission unavailable'),
                    message: _tr(context, 'La gestión de permisos de notificación del sistema está disponible en Android.', 'System notification permissions can be managed on Android.'),
                    icon: Icons.info_outline_rounded,
                  );
                  return;
                }
                final granted = await NotificationPermissionService.requestPermission();
                if (!mounted) return;
                if (!granted) {
                  await NotificationPermissionService.openSettings();
                  return;
                }
                if (!mounted) return;
                await _showUpdateMessage(
                    title: _tr(context, 'Notificaciones permitidas', 'Notifications allowed'),
                    message: _tr(context, 'El permiso del dispositivo está activo. Los avisos de versión se consultan dentro del centro de notificaciones de MyFinc.', 'Device notification permission is enabled. Version announcements are available in the MyFinc notification center.'),
                    icon: Icons.check_circle_outline_rounded,
                );
              },
            ),
            _SettingsTile(
              icon: Icons.system_update_outlined,
              title: settings.languageCode == 'en' ? 'Check for updates' : 'Buscar actualizaciones',
              subtitle: _checkingForUpdate
                  ? (settings.languageCode == 'en' ? 'Checking latest version...' : 'Comprobando la última versión...')
                  : (settings.languageCode == 'en' ? 'Check for a newer version' : 'Comprobar si existe una nueva versión'),
              trailing: _checkingForUpdate
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                      ),
                    )
                  : const Icon(Icons.chevron_right_rounded),
              onTap: _checkingForUpdate ? null : _checkForUpdate,
            ),
            _SettingsTile(
              icon: Icons.info_outline,
              title: settings.languageCode == 'en' ? 'Current version' : 'Versión actual',
              subtitle:
                  _currentVersion == null ? _tr(context, 'Cargando...', 'Loading...') : 'v$_currentVersion',
            ),
          ],
        ),

        // =========================
        // ACERCA DE
        // =========================
        _SettingsSection(
          title: settings.languageCode == 'en' ? 'About' : 'Acerca de',
          children: [
            _SettingsTile(
              icon: Icons.auto_graph_rounded,
              title: _tr(context, 'Acerca de MyFinc', 'About MyFinc'),
              subtitle: _tr(context, 'Información sobre la aplicación', 'App information'),
              onTap: () async {
                final packageInfo = await PackageInfo.fromPlatform();
                if (!context.mounted) return;

                await showDialog<void>(
                  context: context,
                  builder: (dialogContext) => AlertDialog(
                    content: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          const MyFincLogo(size: 76),
                          const SizedBox(height: 14),
                          Text(
                            'MyFinc',
                            style: Theme.of(dialogContext).textTheme.headlineSmall?.copyWith(
                                  fontWeight: FontWeight.w800,
                                ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _tr(context, 'Gestión financiera personal', 'Personal finance management'),
                            textAlign: TextAlign.center,
                            style: Theme.of(dialogContext).textTheme.titleSmall?.copyWith(
                                  color: Theme.of(dialogContext).colorScheme.primary,
                                ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            _tr(context, 'MyFinc te ayuda a organizar tus finanzas en un solo lugar. Administra tus cuentas, registra ingresos, gastos y transferencias, consulta estadísticas y personaliza tus categorías. Su enfoque local-first mantiene tus datos financieros principalmente en el dispositivo.', 'MyFinc helps you organize your finances in one place. Manage accounts, record income, expenses and transfers, review statistics, and customize categories. Its local-first approach keeps your financial data primarily on your device.'),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 18),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              _tr(context, 'Funciones principales', 'Key features'),
                              style: Theme.of(dialogContext).textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(_tr(context, '• Cuentas, balances y movimientos financieros', '• Accounts, balances, and transactions')),
                                Text(_tr(context, '• Estadísticas y categorías personalizadas', '• Statistics and custom categories')),
                                Text(_tr(context, '• Copias de seguridad y restauración', '• Backups and restore')),
                                Text(_tr(context, '• Temas claro, oscuro y del sistema', '• Light, dark, and system themes')),
                                Text(_tr(context, '• Comprobación de actualizaciones', '• Update checks')),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            _tr(context, 'Versión ${packageInfo.version}', 'Version ${packageInfo.version}'),
                            style: Theme.of(dialogContext).textTheme.labelMedium,
                          ),
                        ],
                      ),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(dialogContext).pop(),
                        child: Text(_tr(context, 'Cerrar', 'Close')),
                      ),
                    ],
                  ),
                );
              },
            ),
            _SettingsTile(
              icon: Icons.description_outlined,
              title: _tr(context, 'Licencias', 'Licenses'),
              subtitle: _tr(context, 'Licencias de código abierto', 'Open-source licenses'),
              onTap: () async {
                final packageInfo = await PackageInfo.fromPlatform();

                if (!context.mounted) return;

                showLicensePage(
                  context: context,
                  applicationName: 'MyFinc',
                  applicationVersion: packageInfo.version,
                );
              },
            ),
          ],
        ),

        const SizedBox(height: 24),

      ],
    );
  }

  String _themeLabel(ThemePreference theme, String languageCode) {
    switch (theme) {
      case ThemePreference.system:
        return languageCode == 'en' ? 'System default' : 'Usar configuración del sistema';
      case ThemePreference.light:
        return languageCode == 'en' ? 'Light theme' : 'Tema claro';
      case ThemePreference.dark:
        return languageCode == 'en' ? 'Dark theme' : 'Tema oscuro';
    }
  }

  Future<void> _showThemeSelector(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final current = ref.read(settingsProvider).theme;

    final selected = await showModalBottomSheet<ThemePreference>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Tema',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              _ThemeOption(
                value: ThemePreference.system,
                current: current,
                title: _tr(context, 'Sistema', 'System'),
                subtitle: _tr(context, 'Usar la configuración de apariencia del dispositivo', 'Use device appearance settings'),
                onSelected: (value) {
                  Navigator.pop(context, value);
                },
              ),
              _ThemeOption(
                value: ThemePreference.light,
                current: current,
                title: _tr(context, 'Claro', 'Light'),
                subtitle: _tr(context, 'Usar siempre el tema claro', 'Always use the light theme'),
                onSelected: (value) {
                  Navigator.pop(context, value);
                },
              ),
              _ThemeOption(
                value: ThemePreference.dark,
                current: current,
                title: _tr(context, 'Oscuro', 'Dark'),
                subtitle: _tr(context, 'Usar siempre el tema oscuro', 'Always use the dark theme'),
                onSelected: (value) {
                  Navigator.pop(context, value);
                },
              ),
            ],
          ),
        );
      },
    );

    if (selected != null) {
      await ref.read(settingsProvider.notifier).setTheme(selected);
    }
  }
}




class _OperationLoadingDialog extends StatelessWidget {
  const _OperationLoadingDialog({
    required this.title,
    required this.message,
  });

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Dialog(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 48,
                height: 48,
                child: CircularProgressIndicator(strokeWidth: 3),
              ),
              const SizedBox(height: 24),
              Text(
                title,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 8),
              Text(message, textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    );
  }
}

class _CategoryManagerDialog extends ConsumerStatefulWidget {
  const _CategoryManagerDialog();

  @override
  ConsumerState<_CategoryManagerDialog> createState() =>
      _CategoryManagerDialogState();
}

class _CategoryManagerDialogState
    extends ConsumerState<_CategoryManagerDialog> {
  String _type = 'expense';
  bool _busy = false;

  Future<void> _addCategory() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(_type == 'income' ? _tr(context, 'Nueva categoría de ingreso', 'New income category') : _tr(context, 'Nueva categoría de gasto', 'New expense category')),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 40,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            labelText: _tr(context, 'Nombre', 'Name'),
            hintText: _tr(context, 'Ej. Salario o Transporte', 'e.g. Salary or Transport'),
            border: const OutlineInputBorder(),
          ),
          onSubmitted: (value) => Navigator.pop(dialogContext, value.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(_tr(context, 'Cancelar', 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text.trim()),
            child: Text(_tr(context, 'Agregar', 'Add')),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.trim().isEmpty || !mounted) return;

    setState(() => _busy = true);
    try {
      await ref.read(repoProvider).addCategory(name, _type);
      ref.invalidate(categoriesProvider(_type));
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error is AppException ? error.message : _tr(context, 'No se pudo agregar la categoría.', 'Could not add category.'))),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteCategory(int id, String name) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(_tr(context, 'Eliminar categoría', 'Delete category')),
        content: Text(_tr(context, '¿Quieres eliminar "$name"? Las categorías predeterminadas están protegidas y no se pueden eliminar.', 'Delete "$name"? Default categories are protected and cannot be deleted.')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(_tr(context, 'Cancelar', 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    try {
      await ref.read(repoProvider).deleteCategory(id);
      ref.invalidate(categoriesProvider(_type));
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error is AppException ? error.message : _tr(context, 'No se pudo eliminar la categoría.', 'Could not delete category.'))),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final categories = ref.watch(categoriesProvider(_type));
    return AlertDialog(
      title: Text(_tr(context, 'Categorías financieras', 'Financial categories')),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SegmentedButton<String>(
              segments: [
                ButtonSegment(value: 'expense', label: Text(_tr(context, 'Gastos', 'Expenses')), icon: const Icon(Icons.south_west_rounded)),
                ButtonSegment(value: 'income', label: Text(_tr(context, 'Ingresos', 'Income')), icon: const Icon(Icons.north_east_rounded)),
              ],
              selected: {_type},
              onSelectionChanged: _busy ? null : (value) => setState(() => _type = value.first),
            ),
            const SizedBox(height: 12),
            Flexible(
              child: categories.when(
                loading: () => Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: const CircularProgressIndicator(),
                  ),
                ),
                error: (_, __) => Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(_tr(context, 'No se pudieron cargar las categorías.', 'Could not load categories.')),
                ),
                data: (items) => items.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(20),
                        child: Text(_tr(context, 'Todavía no hay categorías. Agrega la primera.', 'There are no categories yet. Add the first one.')),
                      )
                    : ListView(
                        shrinkWrap: true,
                        children: [
                          for (final category in items)
                            ListTile(
                              dense: true,
                              title: Text(category.name),
                              trailing: IconButton(
                                tooltip: _tr(context, 'Eliminar categoría personalizada', 'Delete custom category'),
                                onPressed: _busy ? null : () => _deleteCategory(category.id, category.name),
                                icon: const Icon(Icons.delete_outline_rounded),
                              ),
                            ),
                        ],
                      ),
              ),
            ),
            if (_busy) const LinearProgressIndicator(),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: Text(_tr(context, 'Cerrar', 'Close')),
        ),
        FilledButton.icon(
          onPressed: _busy ? null : _addCategory,
          icon: const Icon(Icons.add_rounded),
          label: Text(_tr(context, 'Agregar', 'Add')),
        ),
      ],
    );
  }
}

class _ThemeOption extends StatelessWidget {
  const _ThemeOption({
    required this.value,
    required this.current,
    required this.title,
    required this.subtitle,
    required this.onSelected,
  });

  final ThemePreference value;
  final ThemePreference current;
  final String title;
  final String subtitle;
  final ValueChanged<ThemePreference> onSelected;

  @override
  Widget build(BuildContext context) {
    final selected = value == current;

    return ListTile(
      leading: Icon(
        selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
        color: selected ? Theme.of(context).colorScheme.primary : null,
      ),
      title: Text(title),
      subtitle: Text(subtitle),
      onTap: () => onSelected(value),
    );
  }
}

class _SettingsSection extends StatelessWidget {
  const _SettingsSection({
    required this.title,
    required this.children,
  });

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Text(
              title.toUpperCase(),
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                  ),
            ),
          ),
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: _withDividers(children),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _withDividers(List<Widget> items) {
    final result = <Widget>[];

    for (var i = 0; i < items.length; i++) {
      result.add(items[i]);

      if (i < items.length - 1) {
        result.add(const Divider(height: 1));
      }
    }

    return result;
  }
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.trailing,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      minVerticalPadding: 12,
      leading: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(
          icon,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
      title: Text(
        title,
        style: const TextStyle(
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 3),
        child: Text(subtitle),
      ),
      trailing: trailing ??
          (onTap != null ? const Icon(Icons.chevron_right_rounded) : null),
      onTap: onTap,
    );
  }
}

class _LanguageChangeScreen extends StatefulWidget {
  const _LanguageChangeScreen({
    required this.languageCode,
    required this.applyLanguage,
  });

  final String languageCode;
  final Future<void> Function() applyLanguage;

  @override
  State<_LanguageChangeScreen> createState() => _LanguageChangeScreenState();
}

class _LanguageChangeScreenState extends State<_LanguageChangeScreen> {
  int _stage = 0;
  Object? _error;

  bool get _isEnglish => widget.languageCode == 'en';

  @override
  void initState() {
    super.initState();
    _runTransition();
  }

  Future<void> _runTransition() async {
    // Give the first loading message time to render before applying the locale.
    await Future<void>.delayed(const Duration(milliseconds: 450));
    try {
      await widget.applyLanguage();
      if (!mounted) return;
      setState(() => _stage = 1);
      await Future<void>.delayed(const Duration(milliseconds: 500));
      if (!mounted) return;
      setState(() => _stage = 2);
      await Future<void>.delayed(const Duration(milliseconds: 650));
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final messages = _isEnglish
        ? const ['Loading', 'Almost ready', 'Done, language changed successfully']
        : const ['Cargando', 'Ya casi listo', 'Listo, idioma cambiado correctamente'];

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 88,
                    height: 88,
                    decoration: BoxDecoration(
                      color: scheme.primaryContainer,
                      borderRadius: BorderRadius.circular(28),
                    ),
                    child: Icon(
                      _error != null
                          ? Icons.error_outline_rounded
                          : _stage == 2
                              ? Icons.check_rounded
                              : Icons.translate_rounded,
                      size: 44,
                      color: scheme.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(height: 28),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    child: Text(
                      _error != null
                          ? (_isEnglish ? 'Could not change language' : 'No se pudo cambiar el idioma')
                          : messages[_stage],
                      key: ValueKey('$_stage-$_error'),
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  if (_error == null && _stage < 2)
                    const SizedBox(
                      width: 34,
                      height: 34,
                      child: CircularProgressIndicator(strokeWidth: 3),
                    )
                  else
                    Icon(
                      _error != null ? Icons.info_outline_rounded : Icons.check_circle_rounded,
                      size: 34,
                      color: _error != null ? scheme.error : scheme.primary,
                    ),
                  if (_error != null) ...[
                    const SizedBox(height: 18),
                    Text(
                      _isEnglish
                          ? 'Please try again from Settings.'
                          : 'Inténtalo de nuevo desde Configuración.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 18),
                    FilledButton(
                      onPressed: () => Navigator.of(context, rootNavigator: true).pop(),
                      child: Text(_isEnglish ? 'Close' : 'Cerrar'),
                    ),
                  ],
                  const SizedBox(height: 32),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(99),
                    child: LinearProgressIndicator(
                      minHeight: 5,
                      value: _error != null ? null : (_stage + 1) / 3,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'MyFinc',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2,
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
}
