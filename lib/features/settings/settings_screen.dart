import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/avatars.dart';
import '../../core/providers.dart';
import '../progress/learner_stats.dart';
import 'reminder_service.dart';

/// Educational, non-intrusive reminder texts based on the student's state.
List<String> reminderMessages(LearnerStats? stats) {
  final messages = <String>['حان وقت مراجعة درس اليوم 📚', 'تحدي اليوم ينتظرك: 5 أسئلة فقط!'];
  final weak = stats?.recommendations.firstOrNull;
  if (weak != null) messages.add('درس «${weak.lesson.title}» يحتاج إلى مراجعة قصيرة.');
  final next = stats?.nextLesson;
  if (next != null) messages.add('الدرس التالي: «${next.title}». 10 دقائق تكفي!');
  final up = stats?.improvement;
  if (up != null && up > 0) messages.add('تحسّن مستواك بنسبة $up% هذا الأسبوع، استمر!');
  return messages;
}

class ReminderScheduler {
  ReminderScheduler(this.ref);

  final Ref ref;

  /// Re-creates the week of reminders; called at start-up and on changes.
  Future<void> reschedule() async {
    final settings = ref.read(settingsProvider);
    final service = ref.read(reminderServiceProvider);
    try {
      if (!settings.remindersOn) return await service.cancel();
      final stats = await ref.read(statsProvider.future);
      await service.scheduleDaily(hour: settings.reminderHour, messages: reminderMessages(stats));
    } on Exception {
      // Notifications are best-effort; never block the app on them.
    }
  }
}

final reminderSchedulerProvider = Provider<ReminderScheduler>(ReminderScheduler.new);

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final profile = ref.watch(profileProvider);
    final grade = ref.watch(currentGradeProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('الإعدادات')),
      body: ListView(
        children: [
          ListTile(
            leading: StudentAvatar(profile?.avatar ?? 0, radius: 22),
            title: Text(profile?.name ?? '', style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: const Text('الطالب الحالي'),
            trailing: TextButton.icon(
              key: const Key('switch_student'),
              onPressed: () async {
                await ref.read(profilesProvider.notifier).signOut();
                if (context.mounted) context.go('/profiles');
              },
              icon: const Icon(Icons.logout),
              label: const Text('تبديل الطالب'),
            ),
          ),
          ListTile(
            key: const Key('change_grade'),
            leading: const Icon(Icons.school),
            title: const Text('الاسم والصف والفصل'),
            subtitle: Text('${grade?.fullName ?? ''} • الفصل ${profile?.semester == 2 ? 'الثاني' : 'الأول'}'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/settings/grade'),
          ),
          ListTile(
            leading: const Icon(Icons.download_for_offline),
            title: const Text('المحتوى والعمل بدون إنترنت'),
            subtitle: const Text('تحديث الدروس ومزامنة التقدّم'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/downloads'),
          ),
          const Divider(),
          SwitchListTile(
            secondary: const Icon(Icons.notifications_active_outlined),
            title: const Text('تذكير يومي بالدراسة'),
            subtitle: Text(settings.remindersOn ? 'الساعة ${settings.reminderHour}:00' : 'متوقف'),
            value: settings.remindersOn,
            onChanged: (on) async {
              if (on && !await ref.read(reminderServiceProvider).requestPermission()) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context)
                      .showSnackBar(const SnackBar(content: Text('اسمح بالإشعارات من إعدادات الجهاز لتفعيل التذكير.')));
                }
                return;
              }
              await ref.read(settingsProvider.notifier).setReminders(on: on);
              await ref.read(reminderSchedulerProvider).reschedule();
            },
          ),
          if (settings.remindersOn)
            ListTile(
              leading: const SizedBox(width: 24),
              title: const Text('وقت التذكير'),
              trailing: DropdownButton<int>(
                value: settings.reminderHour,
                items: [for (var h = 7; h <= 21; h++) DropdownMenuItem(value: h, child: Text('$h:00'))],
                onChanged: (h) async {
                  await ref.read(settingsProvider.notifier).setReminders(on: true, hour: h);
                  await ref.read(reminderSchedulerProvider).reschedule();
                },
              ),
            ),
          ListTile(
            leading: const Icon(Icons.dark_mode_outlined),
            title: const Text('المظهر'),
            trailing: DropdownButton<ThemeMode>(
              value: settings.themeMode,
              items: const [
                DropdownMenuItem(value: ThemeMode.system, child: Text('حسب الجهاز')),
                DropdownMenuItem(value: ThemeMode.light, child: Text('فاتح')),
                DropdownMenuItem(value: ThemeMode.dark, child: Text('داكن')),
              ],
              onChanged: (m) => ref.read(settingsProvider.notifier).setThemeMode(m!),
            ),
          ),
          const Divider(),
          const ListTile(
            leading: Icon(Icons.family_restroom),
            title: Text('حساب ولي الأمر'),
            subtitle: Text('قريبًا: متابعة مستوى الطالب ونتائجه'),
            enabled: false,
          ),
          const ListTile(
            leading: Icon(Icons.co_present),
            title: Text('حساب المعلم'),
            subtitle: Text('قريبًا: الصفوف والواجبات والاختبارات'),
            enabled: false,
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.privacy_tip_outlined),
            title: const Text('الخصوصية'),
            onTap: () => context.push('/privacy'),
          ),
          ListTile(
            leading: Icon(Icons.delete_outline, color: Theme.of(context).colorScheme.error),
            title: const Text('حذف سجل نشاطي'),
            subtitle: const Text('يحذف التقدّم والنتائج من هذا الجهاز'),
            onTap: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('حذف سجل النشاط؟'),
                  content: const Text('ستُحذف الدروس المكتملة والنتائج والنقاط من هذا الجهاز. لا يمكن التراجع.'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
                    TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('حذف')),
                  ],
                ),
              );
              if (ok != true) return;
              await ref.read(progressRepositoryProvider).clear();
              ref.read(progressRevisionProvider.notifier).bump();
            },
          ),
          const AboutListTile(
            icon: Icon(Icons.info_outline),
            applicationName: 'مدرستي',
            applicationVersion: '1.0.0',
            aboutBoxChildren: [
              Text('مدرسة رقمية متكاملة لطلاب غزة: اقرأ، افهم، اسأل، تدرّب، اختبر نفسك وتابع تقدّمك.'),
            ],
            child: Text('عن التطبيق'),
          ),
        ],
      ),
    );
  }
}

class PrivacyScreen extends StatelessWidget {
  const PrivacyScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('الخصوصية')),
    body: const SingleChildScrollView(
      padding: EdgeInsets.all(16),
      child: Text(
        'نحمي بيانات الطلاب لأن معظم مستخدمينا من القاصرين:\n\n'
        '• لا نطلب رقم هاتف أو بريدًا إلكترونيًا أو صورة. الاسم اختياري ويبقى على جهازك.\n'
        '• التقدّم والنتائج تُحفظ على جهازك أولًا. عند ربط التطبيق بالخادم تُرسل نتائج الاختبارات '
        'تحت معرّف مجهول لمزامنتها فقط، ولا تظهر لأي مستخدم آخر.\n'
        '• أسئلة المعلم الذكي تُرسل مع مقاطع من الدروس إلى الخادم للحصول على إجابة، ولا تُستخدم لأي غرض آخر. '
        'لا تكتب معلومات شخصية في أسئلتك.\n'
        '• لا إعلانات ولا أدوات تتبّع.\n'
        '• يمكنك حذف سجل نشاطك في أي وقت من الإعدادات.',
        style: TextStyle(height: 1.8),
      ),
    ),
  );
}
