import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

class NotificationService {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static const String _channelId = 'samy_expiry_channel';
  static const String _channelName = 'تنبيهات انتهاء الصلاحية';
  static const String _channelDesc = 'إشعارات للمنتجات القريبة من الانتهاء';

  /// تهيئة الإشعارات
  static Future<void> init() async {
    tz.initializeTimeZones();

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidInit);

    await _plugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (response) {},
    );

    final androidImpl = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await androidImpl?.requestNotificationsPermission();
    await androidImpl?.requestExactAlarmsPermission();
  }

  /// جدولة الإشعارات — تدعم الأيام المخصصة
  static Future<void> scheduleExpiryNotifications({
    required int id,
    required String productName,
    required DateTime expiryDate,
    int notifyDaysBefore = 7,
  }) async {
    // 1. إشعار الأيام المخصصة (يختاره التاجر)
    // 2. إشعارات إضافية تلقائية: 3 أيام، 1 يوم، يوم الانتهاء
    final Set<int> days = {notifyDaysBefore, 3, 1, 0};

    // ترتيب تنازلي
    final sortedDays = days.toList()..sort((a, b) => b.compareTo(a));

    for (final daysBefore in sortedDays) {
      final notifyDate = expiryDate.subtract(Duration(days: daysBefore));

      // لا نجدول إشعارًا في الماضي
      if (notifyDate.isBefore(DateTime.now())) continue;

      final scheduled = DateTime(
        notifyDate.year,
        notifyDate.month,
        notifyDate.day,
        9,
        0,
      );

      final notificationId = id * 100 + daysBefore;
      final label = _labelFor(daysBefore);

      await _plugin.zonedSchedule(
        notificationId,
        '⚠️ تنبيه انتهاء صلاحية',
        '$productName — $label (ينتهي ${expiryDate.year}/${expiryDate.month}/${expiryDate.day})',
        tz.TZDateTime.from(scheduled, tz.local),
        const NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            _channelName,
            channelDescription: _channelDesc,
            importance: Importance.max,
            priority: Priority.high,
            playSound: true,
            enableVibration: true,
            fullScreenIntent: true,
            category: AndroidNotificationCategory.alarm,
            styleInformation: BigTextStyleInformation(''),
            color: Color(0xFFD32F2F),
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
    }
  }

  /// إلغاء جميع إشعارات منتج معين
  static Future<void> cancelForProduct(int id) async {
    // نلغي كل الاحتمالات المحتملة
    for (int daysBefore = 0; daysBefore <= 100; daysBefore++) {
      await _plugin.cancel(id * 100 + daysBefore);
    }
  }

  /// نص الإشعار حسب عدد الأيام
  static String _labelFor(int days) {
    if (days == 0) return 'ينتهي اليوم!';
    if (days == 1) return 'باقي يوم واحد';
    if (days == 2) return 'باقي يومان';
    if (days <= 10) return 'باقي $days أيام';
    return 'باقي $days يومًا';
  }
}
