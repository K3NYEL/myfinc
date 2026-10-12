import 'package:flutter/material.dart';

import '../platform/update_service.dart';
import 'myfinc_updates_service.dart';
import '../notifications/notification_inbox_service.dart';
import '../../shared/widgets/update_dialog.dart';

class NotificationsAndPatchesDialog extends StatefulWidget {
  const NotificationsAndPatchesDialog({super.key});

  @override
  State<NotificationsAndPatchesDialog> createState() =>
      _NotificationsAndPatchesDialogState();
}

class _NotificationsAndPatchesDialogState
    extends State<NotificationsAndPatchesDialog> {
  late Future<MyFincUpdatesManifest> _manifestFuture;

  @override
  void initState() {
    super.initState();
    _manifestFuture = _loadManifest();
  }

  Future<MyFincUpdatesManifest> _loadManifest() async {
    final inbox = NotificationInboxService.instance;
    await inbox.initialize();
    final manifest = await const MyFincUpdatesService().fetchManifest();
    await inbox.syncPublishedNotices(manifest.notifications);
    return manifest;
  }

  void _retry() {
    setState(() {
      _manifestFuture = _loadManifest();
    });
  }

  Future<void> _dismissNotification(String id) async {
    await NotificationInboxService.instance.dismiss(id);
    if (mounted) setState(() {});
  }

  Widget _notificationList(BuildContext context) {
    final isEnglish = Localizations.localeOf(context).languageCode == 'en';
    final items = NotificationInboxService.instance.items;
    if (items.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Text(isEnglish ? 'There are no pending notifications.' : 'No hay notificaciones pendientes.'),
      );
    }
    return Column(
      children: [
        for (final item in items)
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              contentPadding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
              leading: Icon(
                item.level == 'critical'
                    ? Icons.error_outline_rounded
                    : item.level == 'warning'
                        ? Icons.warning_amber_rounded
                        : item.source == 'push'
                            ? Icons.notifications_active_outlined
                            : Icons.campaign_outlined,
                color: item.level == 'critical'
                    ? Theme.of(context).colorScheme.error
                    : Theme.of(context).colorScheme.primary,
              ),
              title: Text(item.title),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('${item.message}\n${_dateLabel(item.receivedAt)}'),
              ),
              trailing: IconButton(
                tooltip: isEnglish ? 'Delete notification' : 'Eliminar notificación',
                onPressed: () => _dismissNotification(item.id),
                icon: const Icon(Icons.delete_outline_rounded),
              ),
              isThreeLine: true,
            ),
          ),
      ],
    );
  }

  Future<void> _checkAndOpenPatch() async {
    try {
      final update = await UpdateService.checkForUpdate();
      if (!mounted) return;
      if (update == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(Localizations.localeOf(context).languageCode == 'en' ? 'There is no pending installed update.' : 'No hay una actualización instalada pendiente.')),
        );
        return;
      }
      await showUpdateDialog(context, update);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(
          error is UpdateCheckException
              ? error.message
              : 'No se pudo comprobar la actualización.',
        )),
      );
    }
  }

  String _dateLabel(DateTime? value) {
    if (value == null) return 'Fecha no indicada';
    final date = value.toLocal();
    return '${date.day.toString().padLeft(2, '0')}/'
        '${date.month.toString().padLeft(2, '0')}/'
        '${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    final isEnglish = Localizations.localeOf(context).languageCode == 'en';
    final screenSize = MediaQuery.sizeOf(context);
    final dialogWidth =
        (screenSize.width - 32).clamp(0.0, 520.0).toDouble();
    final dialogHeight =
        (screenSize.height * 0.62).clamp(220.0, 560.0).toDouble();

    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      title: Text(isEnglish ? 'Notifications and patches' : 'Notificaciones y parches'),
      content: SizedBox(
        width: dialogWidth,
        height: dialogHeight,
        child: FutureBuilder<MyFincUpdatesManifest>(
          future: _manifestFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            if (snapshot.hasError || !snapshot.hasData) {
              return SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'No se pudieron cargar los avisos del servidor. Las notificaciones guardadas siguen disponibles.',
                    ),
                    const SizedBox(height: 12),
                    _notificationList(context),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: _retry,
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Volver a intentar'),
                    ),
                  ],
                ),
              );
            }

            final manifest = snapshot.data!;
            return SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Avisos',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 8),
                  _notificationList(context),
                  const SizedBox(height: 12),
                  Text(
                    'Parches y correcciones',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 8),
                  if (manifest.patches.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 12),
                      child: Text('No hay notas de parches publicadas.'),
                    )
                  else
                    for (final patch in manifest.patches)
                      Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: Text(
                                      '${patch.title} · v${patch.version}',
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleSmall
                                          ?.copyWith(fontWeight: FontWeight.w700),
                                    ),
                                  ),
                                  if (patch.required)
                                    const Chip(
                                      label: Text('Importante'),
                                      visualDensity: VisualDensity.compact,
                                    ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(patch.summary),
                              const SizedBox(height: 4),
                              Text(
                                _dateLabel(patch.publishedAt),
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                              if (patch.notes.isNotEmpty) ...[
                                const SizedBox(height: 8),
                                for (final note in patch.notes)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 4),
                                    child: Text('• $note'),
                                  ),
                              ],
                              const SizedBox(height: 8),
                              Align(
                                alignment: Alignment.centerRight,
                                child: TextButton.icon(
                                  onPressed: _checkAndOpenPatch,
                                  icon: const Icon(Icons.system_update_alt_rounded),
                                  label: const Text('Comprobar actualización'),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  const SizedBox(height: 8),
                  Text(
                    'Última actualización del listado: ${_dateLabel(manifest.updatedAt)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: _retry,
          child: const Text('Actualizar lista'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cerrar'),
        ),
      ],
    );
  }
}
