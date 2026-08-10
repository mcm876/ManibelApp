import 'package:flutter/material.dart';

/// Notification Data Model (Map this to your DB table/collection)
class AppNotification {
  final String id;
  final String title;
  final String body;
  final String time; // e.g., "9:48 AM" or formatted DateTime
  final String section; // e.g., "Today", "Yesterday", "Earlier"
  final bool isRead;
  final String type; // e.g., "report", "system", "trip"

  const AppNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.time,
    required this.section,
    this.isRead = false,
    this.type = 'report',
  });

  factory AppNotification.fromMap(Map<String, dynamic> map, String id) {
    return AppNotification(
      id: id,
      title: map['title'] ?? '',
      body: map['body'] ?? '',
      time: map['time'] ?? '',
      section: map['section'] ?? 'Today',
      isRead: map['isRead'] ?? false,
      type: map['type'] ?? 'report',
    );
  }
}

class NotificationsScreen extends StatefulWidget {
  final String driverId;

  const NotificationsScreen({super.key, required this.driverId});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  late Future<List<AppNotification>> _notificationsFuture;

  @override
  void initState() {
    super.initState();
    _notificationsFuture = _fetchNotificationsFromDatabase();
  }

  /// TODO: Replace this mock function with your actual database call
  /// (e.g., Firestore stream/get or Supabase select)
  Future<List<AppNotification>> _fetchNotificationsFromDatabase() async {
    await Future.delayed(const Duration(milliseconds: 600)); // Simulate DB latency

    // Example database payload for driver widget.driverId:
    return const [
      AppNotification(
        id: '1',
        title: 'Report Reviewed',
        body: 'Your report has been reviewed.\nNo violations found.',
        time: '9:48 AM',
        section: 'Today',
        isRead: false,
        type: 'report',
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. TOP BAR WITH BACK BUTTON & TITLE
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.08),
                            blurRadius: 10,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.arrow_back,
                        color: Colors.black87,
                        size: 24,
                      ),
                    ),
                  ),
                  const SizedBox(width: 20),
                  const Text(
                    'Notifications',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                      color: Colors.black,
                      letterSpacing: -0.5,
                    ),
                  ),
                ],
              ),
            ),

            // 2. DYNAMIC NOTIFICATIONS LIST
            Expanded(
              child: FutureBuilder<List<AppNotification>>(
                future: _notificationsFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(
                      child: CircularProgressIndicator(color: Color(0xFF0038FF)),
                    );
                  }

                  if (snapshot.hasError) {
                    return const Center(
                      child: Text(
                        'Failed to load notifications.',
                        style: TextStyle(fontWeight: FontWeight.w600, color: Colors.black45),
                      ),
                    );
                  }

                  final notifications = snapshot.data ?? [];

                  if (notifications.isEmpty) {
                    return const Center(
                      child: Text(
                        'No notifications yet.',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.black38),
                      ),
                    );
                  }

                  // Grouping notifications by section (e.g. "Today")
                  final Map<String, List<AppNotification>> grouped = {};
                  for (var item in notifications) {
                    grouped.putIfAbsent(item.section, () => []).add(item);
                  }

                  return ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    itemCount: grouped.keys.length,
                    itemBuilder: (context, index) {
                      final sectionKey = grouped.keys.elementAt(index);
                      final items = grouped[sectionKey]!;

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Section Label ("Today")
                          Text(
                            sectionKey,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w900,
                              color: Colors.black,
                            ),
                          ),
                          const SizedBox(height: 12),

                          // Cards under this section
                          ...items.map(
                            (notification) => Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: _NotificationCard(notification: notification),
                            ),
                          ),
                        ],
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NotificationCard extends StatelessWidget {
  final AppNotification notification;

  const _NotificationCard({required this.notification});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFEEEEEE), width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Shield Verified Icon
            Container(
              width: 44,
              height: 44,
              decoration: const BoxDecoration(
                color: Color(0xFF0038FF),
                shape: BoxShape.circle,
              ),
              child: Stack(
                alignment: Alignment.center,
                children: const [
                  Icon(Icons.shield, color: Color(0xFF0038FF), size: 30),
                  Icon(Icons.check_rounded, color: Colors.white, size: 24),
                ],
              ),
            ),
            const SizedBox(width: 14),

            // Content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        notification.title,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                          color: Colors.black,
                        ),
                      ),
                      Text(
                        notification.time,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: Colors.black38,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    notification.body,
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: Colors.black45,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}