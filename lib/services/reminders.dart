import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../models.dart';
import '../format.dart';

/// Phone notification at 9:00 am on the day a customer promised to pay.
/// Works with no internet (scheduled on the phone itself).
/// On Windows there are no notifications; the Credit tab shows the
/// "due today / overdue" list instead.
class Reminders {
  Reminders._();
  static final Reminders instance = Reminders._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _ready = false;

  Future<void> init() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      tzdata.initializeTimeZones();
      const settings = InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      );
      await _plugin.initialize(settings);
      await _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
      _ready = true;
    } catch (_) {
      _ready = false;
    }
  }

  Future<void> schedule(List<CreditRow> credits) async {
    if (!_ready) return;
    try {
      await _plugin.cancelAll();
      final now = DateTime.now();
      for (final c in credits) {
        if (c.isSettled) continue;
        final day = DateTime.tryParse(c.expectedDate);
        if (day == null) continue;
        final when = DateTime(day.year, day.month, day.day, 9);
        if (!when.isAfter(now)) continue;
        await _plugin.zonedSchedule(
          c.id.hashCode & 0x7fffffff,
          'Payment due today',
          '${c.customerName} owes ${rs(c.balance)} for ${c.productName}',
          tz.TZDateTime.from(when, tz.UTC),
          const NotificationDetails(
            android: AndroidNotificationDetails(
              'credit_due',
              'Credit reminders',
              channelDescription: 'Reminds you when a customer should pay',
              importance: Importance.high,
              priority: Priority.high,
            ),
          ),
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
        );
      }
    } catch (_) {
      // Reminders are a convenience; never crash the app because of them.
    }
  }
}
