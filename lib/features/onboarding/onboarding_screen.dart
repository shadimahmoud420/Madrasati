import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../data/models.dart';

/// Stage → grade → semester. Also used from settings to change grade.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key, this.editing = false});

  final bool editing;

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _name = TextEditingController();
  Stage? _stage;
  String? _gradeId;
  int _semester = 1;

  @override
  void initState() {
    super.initState();
    final profile = ref.read(profileProvider);
    if (profile != null) {
      _name.text = profile.name;
      _gradeId = profile.gradeId;
      _semester = profile.semester;
      _stage = ref.read(catalogProvider).grade(profile.gradeId)?.stage;
    }
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    await ref
        .read(profileProvider.notifier)
        .save(StudentProfile(name: _name.text.trim(), gradeId: _gradeId!, semester: _semester));
    ref.read(contentSyncProvider).pull(_gradeId!);
    if (!mounted) return;
    if (widget.editing) {
      context.pop();
    } else {
      context.go('/home');
    }
  }

  @override
  Widget build(BuildContext context) {
    final catalog = ref.watch(catalogProvider);
    final text = Theme.of(context).textTheme;
    final grades = _stage == null ? const <GradeInfo>[] : catalog.gradesOf(_stage!);
    return Scaffold(
      appBar: widget.editing ? AppBar(title: const Text('الصف الدراسي')) : null,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
          children: [
            if (!widget.editing) ...[
              Icon(Icons.school, size: 64, color: Theme.of(context).colorScheme.primary),
              const SizedBox(height: 12),
              Text('أهلًا بك في مدرستي', style: text.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              const Text('مدرستك الرقمية: كتبك ودروسك واختباراتك في مكان واحد، وتعمل بدون إنترنت بعد التحميل.'),
              const SizedBox(height: 24),
            ],
            TextField(
              key: const Key('name_field'),
              controller: _name,
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(labelText: 'اسمك (اختياري)', prefixIcon: Icon(Icons.person_outline)),
            ),
            const SizedBox(height: 24),
            Text('اختر المرحلة', style: text.titleMedium),
            const SizedBox(height: 8),
            for (final s in catalog.stages)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _ChoiceTile(
                  key: Key('stage_${s.stage.name}'),
                  title: s.name,
                  subtitle: s.hint,
                  selected: _stage == s.stage,
                  onTap: () => setState(() {
                    _stage = s.stage;
                    _gradeId = null;
                  }),
                ),
              ),
            if (grades.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text('اختر الصف', style: text.titleMedium),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final g in grades)
                    ChoiceChip(
                      key: Key('grade_${g.id}'),
                      label: Text(g.fullName),
                      selected: _gradeId == g.id,
                      onSelected: (_) => setState(() => _gradeId = g.id),
                    ),
                ],
              ),
            ],
            if (_gradeId != null) ...[
              const SizedBox(height: 24),
              Text('الفصل الدراسي', style: text.titleMedium),
              const SizedBox(height: 8),
              SegmentedButton<int>(
                segments: const [
                  ButtonSegment(value: 1, label: Text('الفصل الأول')),
                  ButtonSegment(value: 2, label: Text('الفصل الثاني')),
                ],
                selected: {_semester},
                onSelectionChanged: (v) => setState(() => _semester = v.first),
              ),
            ],
            const SizedBox(height: 32),
            FilledButton.icon(
              key: const Key('start_button'),
              onPressed: _gradeId == null ? null : _save,
              icon: const Icon(Icons.arrow_forward),
              label: Text(widget.editing ? 'حفظ' : 'ابدأ التعلّم'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChoiceTile extends StatelessWidget {
  const _ChoiceTile({
    super.key,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: selected ? scheme.primaryContainer : null,
      child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(subtitle),
        trailing: Icon(selected ? Icons.radio_button_checked : Icons.radio_button_off, color: scheme.primary),
        onTap: onTap,
      ),
    );
  }
}
