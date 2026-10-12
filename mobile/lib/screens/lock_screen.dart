import 'dart:async';

import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';

import '../api/client.dart';
import '../security/app_lock.dart';
import '../session.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// Numeric keypad with dot indicators; 56px keys for gloved, hurried thumbs.
class PinPad extends StatelessWidget {
  final int length;
  final int maxLength;
  final bool enabled;
  final void Function(String digit) onDigit;
  final VoidCallback onDelete;
  final Widget? leftKey;
  const PinPad({
    super.key,
    required this.length,
    required this.onDigit,
    required this.onDelete,
    this.maxLength = LockPolicy.pinMax,
    this.enabled = true,
    this.leftKey,
  });

  @override
  Widget build(BuildContext context) {
    Widget key(String label, VoidCallback? onTap, {Widget? child}) => SizedBox(
          width: 76,
          height: 64,
          child: TextButton(
            onPressed: enabled ? onTap : null,
            style: TextButton.styleFrom(shape: const CircleBorder(), foregroundColor: AppColors.teal),
            child: child ?? Text(label, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w600)),
          ),
        );
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Semantics(
        label: '$length digits entered',
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          for (var i = 0; i < maxLength; i++)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 7),
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: i < length ? AppColors.teal : Colors.transparent,
                border: Border.all(
                    color: i < LockPolicy.pinMin || i < length ? AppColors.teal : AppColors.muted, width: 1.5),
              ),
            ),
        ]),
      ),
      const SizedBox(height: 24),
      for (final row in [
        ['1', '2', '3'],
        ['4', '5', '6'],
        ['7', '8', '9']
      ])
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [for (final d in row) key(d, () => onDigit(d))]),
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        SizedBox(width: 76, height: 64, child: leftKey),
        key('0', () => onDigit('0')),
        key('', onDelete, child: const Icon(Icons.backspace_outlined, semanticLabel: 'Delete')),
      ]),
    ]);
  }
}

class _Frame extends StatelessWidget {
  final String title, subtitle;
  final String? message;
  final List<Widget> children;
  const _Frame({
    required this.title,
    required this.subtitle,
    required this.children,
    this.message,
  });

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(color: AppColors.tealSoft, borderRadius: BorderRadius.circular(16)),
                  child: const Icon(Icons.lock_outline, color: AppColors.teal, size: 30),
                ),
                const SizedBox(height: 14),
                Text(title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text(subtitle, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.muted)),
                SizedBox(
                  height: 48,
                  child: Center(
                    child: message == null
                        ? null
                        : Text(message!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: AppColors.red, fontWeight: FontWeight.w600)),
                  ),
                ),
                ...children,
              ]),
            ),
          ),
        ),
      );
}

/// First run after sign-in: choose a PIN (entered twice).
class SetPinScreen extends StatefulWidget {
  /// Shown when replacing an existing PIN from Account.
  final bool changing;
  const SetPinScreen({super.key, this.changing = false});
  @override
  State<SetPinScreen> createState() => _SetPinScreenState();
}

class _SetPinScreenState extends State<SetPinScreen> {
  String _pin = '';
  String? _first;
  String? _message;
  bool _busy = false;

  Future<void> _next() async {
    if (_first == null) {
      final problem = pinProblem(_pin);
      if (problem != null) {
        setState(() => _message = problem);
        return;
      }
      setState(() {
        _first = _pin;
        _pin = '';
        _message = null;
      });
      return;
    }
    if (_pin != _first) {
      setState(() {
        _first = null;
        _pin = '';
        _message = "PINs didn't match — start again";
      });
      return;
    }
    setState(() => _busy = true);
    await appLock.setPin(_pin);
    if (mounted && widget.changing) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final confirming = _first != null;
    return _Frame(
      title: confirming ? 'Confirm your PIN' : (widget.changing ? 'Choose a new PIN' : 'Set an app PIN'),
      subtitle: confirming
          ? 'Enter the same PIN again.'
          : 'You\'ll need it to open the app. ${LockPolicy.pinMin}–${LockPolicy.pinMax} digits. '
              '${LockPolicy.maxAttempts} wrong tries erase this phone\'s data.',
      message: _message,
      children: [
        PinPad(
          length: _pin.length,
          enabled: !_busy,
          onDigit: (d) => setState(() {
            if (_pin.length < LockPolicy.pinMax) _pin += d;
            _message = null;
          }),
          onDelete: () => setState(() => _pin = _pin.isEmpty ? '' : _pin.substring(0, _pin.length - 1)),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: 240,
          child: FilledButton(
            onPressed: _busy || _pin.length < LockPolicy.pinMin ? null : _next,
            child: Text(_busy ? 'Saving…' : (confirming ? 'Save PIN' : 'Continue')),
          ),
        ),
        if (!widget.changing)
          TextButton(onPressed: _busy ? null : session.signOut, child: const Text('Sign out instead')),
      ],
    );
  }
}

/// Shown on launch and after time in the background.
class LockScreen extends StatefulWidget {
  const LockScreen({super.key});
  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  final _auth = LocalAuthentication();
  String _pin = '';
  String? _message;
  bool _busy = false;
  bool _bioAvailable = false;
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _initBiometrics();
    // Refresh the countdown while a retry delay is running.
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (appLock.retryAt != null && mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _initBiometrics() async {
    try {
      final on = await appLock.pins.biometricEnabled();
      final can = on && await _auth.isDeviceSupported() && await _auth.canCheckBiometrics;
      if (!mounted) return;
      setState(() => _bioAvailable = can);
      if (can) _biometric();
    } catch (_) {
      // Not supported on this device/platform: PIN only.
    }
  }

  Future<void> _biometric() async {
    try {
      final ok = await _auth.authenticate(
        localizedReason: 'Unlock Checkin',
        options: const AuthenticationOptions(biometricOnly: true, stickyAuth: true),
      );
      if (ok) await appLock.unlockWithBiometric();
    } catch (_) {
      if (mounted) setState(() => _message = 'Fingerprint unavailable — use your PIN');
    }
  }

  Future<void> _submit() async {
    setState(() => _busy = true);
    final msg = await appLock.unlock(_pin);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _pin = '';
      _message = msg;
    });
  }

  @override
  Widget build(BuildContext context) {
    final retry = appLock.retryAt;
    final waiting = retry != null && DateTime.now().isBefore(retry);
    final secs = waiting ? retry.difference(DateTime.now()).inSeconds + 1 : 0;
    final me = session.me;
    return _Frame(
      title: 'Enter your PIN',
      subtitle: me == null ? '' : '${me.name}${me.orgName == null ? '' : ' · ${me.orgName}'}',
      message: waiting ? 'Too many tries — wait $secs s' : _message,
      children: [
        PinPad(
          length: _pin.length,
          enabled: !_busy && !waiting,
          onDigit: (d) {
            if (_pin.length >= LockPolicy.pinMax) return;
            setState(() {
              _pin += d;
              _message = null;
            });
          },
          onDelete: () => setState(() => _pin = _pin.isEmpty ? '' : _pin.substring(0, _pin.length - 1)),
          leftKey: _bioAvailable
              ? IconButton(
                  onPressed: _biometric,
                  icon: const Icon(Icons.fingerprint, size: 32, color: AppColors.teal),
                  tooltip: 'Use fingerprint',
                )
              : null,
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: 240,
          child: FilledButton(
            onPressed: _busy || waiting || _pin.length < LockPolicy.pinMin ? null : _submit,
            child: Text(_busy ? 'Checking…' : 'Unlock'),
          ),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ForgotPinScreen())),
          child: const Text('Forgot PIN?'),
        ),
      ],
    );
  }
}

/// Resets the PIN after confirming the account password online. Offline data is kept.
class ForgotPinScreen extends StatefulWidget {
  const ForgotPinScreen({super.key});
  @override
  State<ForgotPinScreen> createState() => _ForgotPinScreenState();
}

class _ForgotPinScreenState extends State<ForgotPinScreen> {
  final _password = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    final me = session.me;
    if (me == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await api.confirmPassword(me.email, _password.text);
      if (!mounted) return;
      Navigator.of(context).pop();
      await appLock.requireNewPin();
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = errorText(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Forgot PIN')),
        body: ListView(padding: const EdgeInsets.all(20), children: [
          const Text(
            'Confirm your account password to choose a new PIN. This needs signal. '
            'Records saved on this phone are kept.',
            style: TextStyle(color: AppColors.muted),
          ),
          const SizedBox(height: 16),
          if (_error != null) ...[
            Notice(_error!, fg: AppColors.red, bg: AppColors.redSoft, icon: Icons.error_outline),
            const SizedBox(height: 12),
          ],
          TextField(
            controller: _password,
            obscureText: true,
            autofocus: true,
            decoration: InputDecoration(labelText: 'Password for ${session.me?.email ?? ''}'),
            onSubmitted: (_) => _busy ? null : _confirm(),
          ),
          const SizedBox(height: 16),
          FilledButton(onPressed: _busy ? null : _confirm, child: Text(_busy ? 'Checking…' : 'Confirm')),
        ]),
      );
}
