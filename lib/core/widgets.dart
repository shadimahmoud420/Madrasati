import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
    child: Row(
      children: [
        Expanded(
          child: Text(text, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
        ),
        ?trailing,
      ],
    ),
  );
}

class LabeledProgress extends StatelessWidget {
  const LabeledProgress({super.key, required this.label, required this.value, this.color, this.trailing});

  final String label;
  final double value;
  final Color? color;
  final String? trailing;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Expanded(child: Text(label)),
          Text(trailing ?? '${(value * 100).round()}%', style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
      const SizedBox(height: 6),
      ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: LinearProgressIndicator(value: value.clamp(0, 1), minHeight: 10, color: color),
      ),
    ],
  );
}

/// Shown wherever a feature needs a connection, so students know in advance.
class OnlineOnlyNote extends StatelessWidget {
  const OnlineOnlyNote(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(color: scheme.tertiaryContainer, borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          Icon(Icons.wifi, size: 18, color: scheme.onTertiaryContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text, style: TextStyle(color: scheme.onTertiaryContainer)),
          ),
        ],
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, this.message, this.action});

  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 56, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 12),
          Text(title, style: Theme.of(context).textTheme.titleMedium, textAlign: TextAlign.center),
          if (message != null) ...[const SizedBox(height: 8), Text(message!, textAlign: TextAlign.center)],
          if (action != null) ...[const SizedBox(height: 16), action!],
        ],
      ),
    ),
  );
}

/// Renders an [AsyncValue] with shared loading and error states.
class AsyncView<T> extends StatelessWidget {
  const AsyncView({super.key, required this.value, required this.builder});

  final AsyncValue<T> value;
  final Widget Function(T data) builder;

  @override
  Widget build(BuildContext context) => switch (value) {
    AsyncData(:final value) => builder(value),
    AsyncError(:final error) => EmptyState(icon: Icons.error_outline, title: 'حدث خطأ', message: '$error'),
    _ => const Center(child: CircularProgressIndicator()),
  };
}

/// Question/lesson image: bundled asset (`images/…`) or URL. Always on a
/// white card so line drawings stay visible in dark mode.
class ContentImage extends StatelessWidget {
  const ContentImage(this.source, {super.key, this.height = 180});

  final String source;
  final double height;

  @override
  Widget build(BuildContext context) {
    final image = source.startsWith('http')
        ? Image.network(
            source,
            height: height,
            errorBuilder: (_, _, _) => const OnlineOnlyNote('تعذّر تحميل الصورة، تحتاج إلى إنترنت.'),
          )
        : Image.asset('assets/content/$source', height: height);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
      child: Center(child: image),
    );
  }
}

String formatDuration(Duration d) {
  final m = d.inMinutes;
  final s = d.inSeconds % 60;
  if (m >= 60) return '${m ~/ 60} س ${m % 60} د';
  return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
}
