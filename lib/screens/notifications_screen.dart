import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../widgets/ui_kit.dart';
import '../services/fuel_price_service.dart';
import '../services/notice_service.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});
  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  late Future<List<Notice>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<Notice>> _load() async {
    final data = await FuelPriceService.fetchLatest();
    // Clears the red dot on Home's bell icon now that these have been seen.
    await NoticeService.markSeen(data);
    return NoticeService.fromPriceSnapshot(data);
  }

  void _retry() => setState(() => _future = _load());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F9FC),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: AppColors.textDark,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Notifications', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: SafeArea(
        child: FutureBuilder<List<Notice>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const AppLoadingState();
            }
            if (snapshot.hasError) {
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.wifi_off_rounded, size: 40, color: AppColors.textGrey),
                    const SizedBox(height: 12),
                    const Text('Could not load notifications.', style: TextStyle(color: AppColors.textGrey)),
                    const SizedBox(height: 12),
                    ElevatedButton(onPressed: _retry, child: const Text('Retry')),
                  ],
                ),
              );
            }
            final notices = snapshot.data ?? const [];
            if (notices.isEmpty) {
              return const Center(child: Text('No notifications yet', style: TextStyle(color: AppColors.textGrey)));
            }
            return ListView.separated(
              padding: const EdgeInsets.all(20),
              itemCount: notices.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, i) {
                final n = notices[i];
                return Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.cardBorder),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CircleAvatar(backgroundColor: n.color.withValues(alpha: 0.12), child: Icon(n.icon, color: n.color)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(n.title, style: const TextStyle(fontWeight: FontWeight.w600)),
                            const SizedBox(height: 2),
                            Text(n.subtitle, style: const TextStyle(fontSize: 12, color: AppColors.textGrey)),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
