import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'models/app_settings.dart';
import 'state/providers.dart';
import 'ui/feed_page.dart';
import 'ui/theme.dart';

class ApexScrollingApp extends ConsumerWidget {
  const ApexScrollingApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppSettings settings = ref.watch(settingsControllerProvider);
    return MaterialApp(
      title: 'ApexScrolling',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.build(Brightness.light),
      darkTheme: AppTheme.build(Brightness.dark),
      themeMode: switch (settings.theme) {
        AppThemeOption.system => ThemeMode.system,
        AppThemeOption.light => ThemeMode.light,
        AppThemeOption.dark => ThemeMode.dark,
      },
      home: const FeedPage(),
    );
  }
}
