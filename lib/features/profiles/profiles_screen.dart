import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/avatars.dart';
import '../../core/providers.dart';
import '../../data/database.dart';

/// "Who is studying now?" – each student taps their own card. No passwords;
/// every student sees only their own progress.
class ProfilesScreen extends ConsumerWidget {
  const ProfilesScreen({super.key});

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref, Profile p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('حذف ${p.name}؟'),
        content: const Text('سيُحذف الطالب وكل تقدّمه ونتائجه من هذا الجهاز. لا يمكن التراجع.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('حذف')),
        ],
      ),
    );
    if (ok == true) await ref.read(profilesProvider.notifier).delete(p.id);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profiles = ref.watch(profilesProvider).profiles;
    final catalog = ref.watch(catalogProvider);
    final text = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 32, 20, 24),
          children: [
            Icon(Icons.school, size: 56, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 12),
            Text(
              'من يدرس الآن؟',
              textAlign: TextAlign.center,
              style: text.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            const Text('اختر اسمك للدخول. لكل طالب تقدّمه الخاص ولا يرى بيانات غيره.', textAlign: TextAlign.center),
            const SizedBox(height: 24),
            for (final p in profiles)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Card(
                  child: ListTile(
                    key: Key('profile_${p.id}'),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    leading: StudentAvatar(p.avatar),
                    title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                    subtitle: Text(catalog.grade(p.gradeId)?.fullName ?? ''),
                    trailing: PopupMenuButton<String>(
                      tooltip: 'خيارات',
                      onSelected: (_) => _confirmDelete(context, ref, p),
                      itemBuilder: (_) => const [PopupMenuItem(value: 'delete', child: Text('حذف الطالب'))],
                    ),
                    onTap: () async {
                      await ref.read(profilesProvider.notifier).switchTo(p.id);
                      if (context.mounted) context.go('/home');
                    },
                  ),
                ),
              ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              key: const Key('add_student'),
              onPressed: () => context.push('/onboarding'),
              icon: const Icon(Icons.person_add_alt_1),
              label: const Text('إضافة طالب'),
            ),
          ],
        ),
      ),
    );
  }
}
