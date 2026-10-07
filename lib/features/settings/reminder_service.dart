import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// Daily study reminder. Local only: no push server, works offline.
abstract interface class ReminderService {
  Future<bool> requestPermission();

  /// Replaces pending reminders with one a day at [hour] local time; each
  /// day's text comes from [messages] in turn.
  Future<void> scheduleDaily({required int hour, required List<String> messages});

  Future<void> cancel();
}

final reminderServiceProvider = Provider<ReminderService>((ref) => NoopReminderService());

class NoopReminderService implements ReminderService {
  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<void> scheduleDaily({required int hour, required List<String> messages}) async {}

  @override
  Future<void> cancel() async {}
}

/// Schedules a week of one-shot notifications (re-created on every app
/// start), which lets each day carry a different, relevant message.
class LocalReminderService implements ReminderService {
  LocalReminderService([FlutterLocalNotificationsPlugin? plugin])
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  bool _ready = false;

  static const _days = 7;
  static const _baseId = 2000;
  static const _details = NotificationDetails(
    android: AndroidNotificationDetails(
      'study_reminders',
      'تذكير الدراسة',
      channelDescription: 'تذكير يومي بموعد الدراسة',
      importance: Importance.defaultImportance,
    ),
    iOS: DarwinNotificationDetails(),
  );

  Future<void> _init() async {
    if (_ready) return;
    tzdata.initializeTimeZones();
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
    );
    _ready = true;
  }

  @override
  Future<bool> requestPermission() async {
    await _init();
    if (defaultTargetPlatform == TargetPlatform.android) {
      final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      return await android?.requestNotificationsPermission() ?? true;
    }
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      final ios = _plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
      return await ios?.requestPermissions(alert: true, badge: false, sound: true) ?? false;
    }
    return true;
  }

  @override
  Future<void> scheduleDaily({required int hour, required List<String> messages}) async {
    await cancel();
    final now = DateTime.now();
    var first = DateTime(now.year, now.month, now.day, hour);
    if (!first.isAfter(now)) first = first.add(const Duration(days: 1));
    for (var i = 0; i < _days; i++) {
      final at = DateTime(first.year, first.month, first.day + i, hour);
      await _plugin.zonedSchedule(
        id: _baseId + i,
        title: 'مدرستي',
        body: messages[i % messages.length],
        scheduledDate: tz.TZDateTime.from(at, tz.UTC),
        notificationDetails: _details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
    }
  }

  @override
  Future<void> cancel() async {
    await _init();
    for (var i = 0; i < _days; i++) {
      await _plugin.cancel(id: _baseId + i);
    }
  }
}
