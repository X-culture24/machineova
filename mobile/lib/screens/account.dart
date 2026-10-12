import 'package:flutter/material.dart';

import '../api/client.dart';
import 'package:local_auth/local_auth.dart';

import '../offline/sync.dart';
import '../security/app_lock.dart';
import 'lock_screen.dart';
import '../session.dart';
import 'sync_screen.dart';
import '../theme.dart';
import '../widgets/common.dart';

String roleName(String r) =>
    const {
      'owner': 'Owner',
      'executive': 'Executive',
      'admin': 'Admin',
      'chief_agent': 'Chief Agent',
      'manager': 'Manager',
      'agent': 'Agent',
      'member': 'Member',
      'viewer': 'Viewer',
    }[r] ??
    r;

class AccountScreen extends StatelessWidget {
  const AccountScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final me = session.me!;
    return Scaffold(
      appBar: AppBar(title: const Text('Account', style: TextStyle(fontWeight: FontWeight.w800))),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 96), children: [
        Card(
          child: ListTile(
            contentPadding: const EdgeInsets.all(14),
            leading: Avatar(me.name, size: 48),
            title: Text(me.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
            subtitle: Text('${me.email}\n${roleName(me.role)}${me.scopeLabel.isEmpty ? '' : ' · ${me.scopeLabel}'}'),
            isThreeLine: true,
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Column(children: [
            ListTile(
              leading: const Icon(Icons.apartment, color: AppColors.teal),
              title: const Text('Organization'),
              subtitle: Text(me.orgName ?? '—'),
              trailing: me.orgActive
                  ? const Pill('ACTIVE', fg: AppColors.green, bg: AppColors.greenSoft)
                  : const Pill('INACTIVE', fg: AppColors.red, bg: AppColors.redSoft),
            ),
            if (me.hasOps && me.hasCheckin) ...[
              const Divider(height: 1),
              SwitchListTile(
                secondary: const Icon(Icons.how_to_vote_outlined, color: AppColors.teal),
                title: const Text('Election Ops workspace'),
                subtitle: const Text('Stations, turnout, incidents and results'),
                value: session.opsMode,
                onChanged: session.setOpsMode,
              ),
            ],
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.lock_outline, color: AppColors.teal),
              title: const Text('Change password'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const _ChangePasswordScreen())),
            ),
            const Divider(height: 1),
            const _SecurityTiles(),
            const Divider(height: 1),
            ListenableBuilder(
              listenable: outbox,
              builder: (context, _) => ListTile(
                leading: const Icon(Icons.sync, color: AppColors.teal),
                title: const Text('Sync & offline data'),
                subtitle: Text(outbox.waitingCount + outbox.failed.length == 0
                    ? 'Everything is synced'
                    : '${outbox.waitingCount} waiting · ${outbox.failed.length} need attention'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SyncScreen())),
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.logout, color: AppColors.red),
              title: const Text('Sign out', style: TextStyle(color: AppColors.red)),
              onTap: () async {
                final unsynced = outbox.waitingCount + outbox.failed.length;
                if (unsynced > 0) {
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Records not synced yet'),
                      content: Text('$unsynced record${unsynced == 1 ? " hasn't" : "s haven't"} reached the server. '
                          "They stay on this phone and sync the next time you sign in — but you can't sign in again without signal."),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Stay signed in')),
                        TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Sign out')),
                      ],
                    ),
                  );
                  if (ok != true) return;
                }
                session.signOut();
              },
            ),
          ]),
        ),
        const SizedBox(height: 16),
        const Center(child: Text('Checkin · MachineNova', style: TextStyle(color: AppColors.muted, fontSize: 12))),
      ]),
    );
  }
}

class _ChangePasswordScreen extends StatefulWidget {
  const _ChangePasswordScreen();
  @override
  State<_ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<_ChangePasswordScreen> {
  final _form = GlobalKey<FormState>();
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await api.changePassword(_current.text, _next.text);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Password changed')));
      Navigator.of(context).pop();
    } catch (e) {
      setState(() => _error = errorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Change password')),
      body: Form(
        key: _form,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          if (_error != null) ...[
            Notice(_error!, fg: AppColors.red, bg: AppColors.redSoft, icon: Icons.error_outline),
            const SizedBox(height: 12),
          ],
          TextFormField(
            controller: _current,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'Current password'),
            validator: (v) => (v ?? '').isEmpty ? 'Required' : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _next,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'New password'),
            validator: (v) => (v ?? '').length < 8 ? 'At least 8 characters' : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _confirm,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'Confirm new password'),
            validator: (v) => v != _next.text ? "Passwords don't match" : null,
          ),
          const SizedBox(height: 20),
          FilledButton(onPressed: _busy ? null : _submit, child: Text(_busy ? 'Saving…' : 'Change password')),
        ]),
      ),
    );
  }
}

/// Lock now · Change PIN · fingerprint unlock, with the wipe policy spelled out.
class _SecurityTiles extends StatefulWidget {
  const _SecurityTiles();
  @override
  State<_SecurityTiles> createState() => _SecurityTilesState();
}

class _SecurityTilesState extends State<_SecurityTiles> {
  final _auth = LocalAuthentication();
  bool _bioSupported = false;
  bool _bioOn = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    var supported = false;
    try {
      supported = await _auth.isDeviceSupported() && await _auth.canCheckBiometrics;
    } catch (_) {}
    final on = await appLock.pins.biometricEnabled();
    if (mounted) {
      setState(() {
        _bioSupported = supported;
        _bioOn = on;
      });
    }
  }

  Future<void> _changePin() async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Current PIN'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          obscureText: true,
          keyboardType: TextInputType.number,
          maxLength: LockPolicy.pinMax,
          decoration: const InputDecoration(counterText: ''),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Continue')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final msg = await appLock.unlock(ctrl.text);
    if (!mounted) return;
    if (msg != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      return;
    }
    final changed =
        await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => const SetPinScreen(changing: true)));
    if (changed == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('PIN changed')));
    }
  }

  Future<void> _toggleBio(bool on) async {
    if (on) {
      try {
        final ok = await _auth.authenticate(
          localizedReason: 'Confirm to use your fingerprint for Checkin',
          options: const AuthenticationOptions(biometricOnly: true),
        );
        if (!ok) return;
      } catch (_) {
        return;
      }
    }
    await appLock.pins.setBiometric(on);
    if (mounted) setState(() => _bioOn = on);
  }

  @override
  Widget build(BuildContext context) => Column(children: [
        ListTile(
          leading: const Icon(Icons.lock_clock, color: AppColors.teal),
          title: const Text('Lock now'),
          subtitle: Text('Locks automatically after ${LockPolicy.lockAfter.inMinutes} min in the background. '
              '${LockPolicy.maxAttempts} wrong PINs, or ${LockPolicy.wipeAfter.inDays} days unused, erase this phone\'s data.'),
          isThreeLine: true,
          onTap: appLock.lockNow,
        ),
        const Divider(height: 1),
        ListTile(
          leading: const Icon(Icons.pin_outlined, color: AppColors.teal),
          title: const Text('Change PIN'),
          trailing: const Icon(Icons.chevron_right),
          onTap: _changePin,
        ),
        if (_bioSupported) ...[
          const Divider(height: 1),
          SwitchListTile(
            secondary: const Icon(Icons.fingerprint, color: AppColors.teal),
            title: const Text('Unlock with fingerprint / face'),
            value: _bioOn,
            onChanged: _toggleBio,
          ),
        ],
      ]);
}
