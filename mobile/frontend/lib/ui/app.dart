import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'record/record_screen.dart';
import 'settings/settings_screen.dart';
import 'tasks/tasks_screen.dart';
import 'theme.dart';

/// The app is portrait only (the manifest and Info.plist say so too).
Future<void> keepPortrait() => SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

/// The app: three tabs, Record first.
class VoiceDeskApp extends StatelessWidget {
  const VoiceDeskApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Voice Desk',
      // The desktop app's look, light or dark as the phone is set.
      theme: vdTheme(Brightness.light),
      darkTheme: vdTheme(Brightness.dark),
      home: const _Tabs(),
    );
  }
}

class _Tabs extends StatefulWidget {
  const _Tabs();

  @override
  State<_Tabs> createState() => _TabsState();
}

class _TabsState extends State<_Tabs> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: IndexedStack(index: _tab, children: const [RecordScreen(), TasksScreen(), SettingsScreen()]),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.mic_none), selectedIcon: Icon(Icons.mic), label: 'Record'),
          NavigationDestination(icon: Icon(Icons.checklist), label: 'Tasks'),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}
