import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/providers.dart';
import 'core/router.dart';
import 'core/theme.dart';
import 'features/books/library.dart';

class MadrasatiApp extends ConsumerStatefulWidget {
  const MadrasatiApp({super.key});

  @override
  ConsumerState<MadrasatiApp> createState() => _MadrasatiAppState();
}

class _MadrasatiAppState extends ConsumerState<MadrasatiApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Automatic synchronization: whenever the app comes back to the
  /// foreground, try to pull new content and push offline results.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.read(contentSyncProvider).syncAll();
      ref.read(autoBookDownloaderProvider).run();
    }
  }

  @override
  Widget build(BuildContext context) {
    final stage = ref.watch(currentGradeProvider)?.stage;
    ref.watch(autoBookDownloaderProvider);
    return MaterialApp.router(
      title: 'مدرستي',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(stage),
      darkTheme: AppTheme.dark(stage),
      themeMode: ref.watch(settingsProvider).themeMode,
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      routerConfig: ref.watch(routerProvider),
      builder: (context, child) {
        final scale = AppTheme.textScaleFor(stage);
        if (scale == 1.0) return child!;
        final media = MediaQuery.of(context);
        return MediaQuery(
          data: media.copyWith(textScaler: _ScaledTextScaler(media.textScaler, scale)),
          child: child!,
        );
      },
    );
  }
}

class _ScaledTextScaler extends TextScaler {
  const _ScaledTextScaler(this.base, this.factor);

  final TextScaler base;
  final double factor;

  @override
  double scale(double fontSize) => base.scale(fontSize) * factor;

  @override
  double get textScaleFactor => base.scale(14) / 14 * factor;

  @override
  bool operator ==(Object other) => other is _ScaledTextScaler && other.base == base && other.factor == factor;

  @override
  int get hashCode => Object.hash(base, factor);
}
