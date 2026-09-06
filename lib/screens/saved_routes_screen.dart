import 'package:flutter/material.dart';

import '../models/trip_models.dart';
import '../services/saved_route_repository.dart';
import '../theme/app_theme.dart';
import '../widgets/ui_kit.dart';
import 'trip_calculation_screen.dart';

class SavedRoutesScreen extends StatelessWidget {
  const SavedRoutesScreen({super.key});

  Future<void> _openRoute(
      BuildContext context,
      SavedRoute route, {
        bool startEditing = false,
      }) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => TripCalculationScreen(
          mode: route.mode,
          initialRoute: route,
          startEditing: startEditing,
        ),
      ),
    );
  }


  Future<void> _closeRenameDialog(BuildContext dialogContext,
      [String? result]) async {
    FocusScope.of(dialogContext).unfocus();
    await Future<void>.delayed(const Duration(milliseconds: 220));
    if (!dialogContext.mounted) return;
    Navigator.pop(dialogContext, result);
  }

  Future<void> _rename(BuildContext context, SavedRoute route) async {
    final controller = TextEditingController(text: route.name);
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: CircleAvatar(
          radius: 24,
          backgroundColor: AppColors.primaryBlue.withValues(alpha: .1),
          child: const Icon(Icons.drive_file_rename_outline,
              color: AppColors.primaryBlue),
        ),
        title: const Text('Rename Route'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Choose a clear name for this saved journey.'),
            const SizedBox(height: 14),
            TextField(
              controller: controller,
              autofocus: true,
              maxLength: 60,
              decoration: const InputDecoration(
                labelText: 'Route name',
                prefixIcon: Icon(Icons.edit_outlined),
              ),
              onSubmitted: (value) {
                if (value.trim().isNotEmpty) {
                  _closeRenameDialog(dialogContext, value.trim());
                }
              },
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => _closeRenameDialog(dialogContext),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                _closeRenameDialog(dialogContext, controller.text.trim());
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || !context.mounted) {
      return;
    }
    try {
      await SavedRouteRepository.rename(route.id, name);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle_outline, color: Colors.white, size: 21),
                SizedBox(width: 10),
                Text('Route renamed successfully.'),
              ],
            ),
          ),
        );
      }
    } on SavedRouteRepositoryException catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
      }
    }
  }

  Future<void> _delete(BuildContext context, SavedRoute route) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const CircleAvatar(
          radius: 24,
          backgroundColor: Color(0xFFFFEBEE),
          child: Icon(Icons.delete_outline, color: Colors.red),
        ),
        title: const Text('Delete saved route?'),
        content: Text(
            '“${route.name}” will be permanently removed. This action cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel')),
          FilledButton.icon(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            icon: const Icon(Icons.delete_outline, size: 18),
            label: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await SavedRouteRepository.delete(route.id);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                Icon(Icons.delete_outline, color: Colors.white, size: 21),
                SizedBox(width: 10),
                Text('Saved route deleted.'),
              ],
            ),
          ),
        );
      }
    } on SavedRouteRepositoryException catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Saved Routes',
            style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: StreamBuilder<List<SavedRoute>>(
        stream: SavedRouteRepository.watchMine(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const AppLoadingState();
          }
          if (snapshot.hasError) {
            return const _MessageState(
              icon: Icons.cloud_off_outlined,
              title: 'Could not load saved routes',
              message:
              'Check your connection and Firestore permissions, then try again.',
            );
          }
          final routes = snapshot.data ?? const [];
          if (routes.isEmpty) {
            return const _MessageState(
              icon: Icons.route_outlined,
              title: 'No saved routes yet',
              message:
              'Calculate a trip and choose Save Route to keep it here.',
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(20),
            itemCount: routes.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final route = routes[index];
              final option =
                  route.chargingProvider ?? route.fuelType ?? 'Select option';
              return InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => _openRoute(context, route),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(16, 14, 6, 14),
                  decoration: BoxDecoration(
                    color: Theme.of(context).cardColor,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Theme.of(context).dividerColor),
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                        backgroundColor:
                        AppColors.primaryBlue.withValues(alpha: .1),
                        child: const Icon(Icons.route,
                            color: AppColors.primaryBlue),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(route.name,
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold, fontSize: 15)),
                            const SizedBox(height: 3),
                            Text(
                                '${route.origin.name} → ${route.destination.name}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontSize: 12, color: AppColors.textGrey)),
                            const SizedBox(height: 3),
                            Text('${route.vehicleLabelSnapshot} · $option',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontSize: 11, color: AppColors.textGrey)),
                          ],
                        ),
                      ),
                      PopupMenuButton<String>(
                        tooltip: 'Route actions',
                        onSelected: (value) {
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (!context.mounted) return;
                            if (value == 'edit') {
                              _openRoute(context, route, startEditing: true);
                            }
                            if (value == 'rename') {
                              _rename(context, route);
                            }
                            if (value == 'delete') {
                              _delete(context, route);
                            }
                          });
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(
                              value: 'edit', child: Text('Edit settings')),
                          PopupMenuItem(value: 'rename', child: Text('Rename')),
                          PopupMenuItem(value: 'delete', child: Text('Delete')),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _MessageState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  const _MessageState(
      {required this.icon, required this.title, required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 46, color: AppColors.textGrey),
            const SizedBox(height: 12),
            Text(title,
                style:
                const TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
            const SizedBox(height: 6),
            Text(message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textGrey, height: 1.4)),
          ],
        ),
      ),
    );
  }
}