import 'package:flutter/material.dart';

import 'offline/prefetch.dart';
import 'offline/sync.dart';
import 'screens/lock_screen.dart';
import 'screens/login.dart';
import 'security/app_lock.dart';
import 'screens/ops/ops_shell.dart';
import 'screens/shell.dart';
import 'session.dart';
import 'theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  session.restore();
  runApp(const CheckinApp());
}

class CheckinApp extends StatefulWidget {
  const CheckinApp({super.key});
  @override
  State<CheckinApp> createState() => _CheckinAppState();
}

class _CheckinAppState extends State<CheckinApp> with WidgetsBindingObserver {
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

  /// Back in the foreground (often back in coverage): push queued records, refresh offline data.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) appLock.onBackground();
    if (state == AppLifecycleState.resumed && session.me != null) {
      appLock.onForeground(); // re-locks after LockPolicy.lockAfter in the background
      outbox.flush();
      prefetchForOffline();
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Checkin',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: ListenableBuilder(
        listenable: Listenable.merge([session, appLock]),
        builder: (context, _) {
          if (session.restoring) {
            return const Scaffold(body: Center(child: CircularProgressIndicator()));
          }
          if (session.me == null) return const LoginScreen();
          // Nothing with data is built until the PIN is set or entered.
          switch (appLock.state) {
            case AppLockState.needsPin:
              return const SetPinScreen();
            case AppLockState.locked:
              return const LockScreen();
            case AppLockState.open:
              return session.opsMode ? const OpsShell() : const Shell();
          }
        },
      ),
    );
  }
}
