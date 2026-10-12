import 'package:flutter/material.dart';

import '../api/client.dart';
import '../security/app_lock.dart';
import '../session.dart';
import '../theme.dart';
import '../widgets/common.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _login = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  bool _obscure = true;
  String? _error;

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await session.signIn(_login.text.trim(), _password.text);
    } catch (e) {
      if (mounted) setState(() => _error = errorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Asks for the account email and has the server email a reset link (opens on the web).
  Future<void> _forgot() async {
    final ctl = TextEditingController(text: _login.text.trim());
    final message = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        var sending = false;
        String? err;
        return StatefulBuilder(
          builder: (ctx, setSheet) => Padding(
            padding: EdgeInsets.fromLTRB(24, 20, 24, 24 + MediaQuery.viewInsetsOf(ctx).bottom),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Text('Reset your password', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              const Text("We'll email a link to set a new password. It works once and expires in 1 hour.",
                  style: TextStyle(color: AppColors.muted)),
              const SizedBox(height: 16),
              if (err != null) ...[
                Notice(err!, fg: AppColors.red, bg: AppColors.redSoft, icon: Icons.error_outline),
                const SizedBox(height: 12),
              ],
              TextField(
                controller: ctl,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: 'Email or user ID', prefixIcon: Icon(Icons.mail_outline)),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: sending
                    ? null
                    : () async {
                        setSheet(() => sending = true);
                        try {
                          final msg = await api.forgotPassword(ctl.text.trim());
                          if (ctx.mounted) Navigator.pop(ctx, msg);
                        } catch (e) {
                          setSheet(() {
                            sending = false;
                            err = errorText(e);
                          });
                        }
                      },
                child: Text(sending ? 'Sending…' : 'Email me a reset link'),
              ),
            ]),
          ),
        );
      },
    );
    ctl.dispose();
    if (message != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message), duration: const Duration(seconds: 6)));
    }
  }

  @override
  void dispose() {
    _login.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(children: [
        // Brand header
        Container(
          width: double.infinity,
          decoration: const BoxDecoration(
            gradient: brandGradient,
            borderRadius: BorderRadius.vertical(bottom: Radius.circular(36)),
          ),
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 28, 24, 36),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(
                  width: 64,
                  height: 64,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
                  child: Image.asset('assets/brand/mark.png'),
                ),
                const SizedBox(height: 20),
                const Text('Karibu 👋', style: TextStyle(color: Colors.white70, fontSize: 15)),
                const SizedBox(height: 4),
                const Text('Sign in to Checkin',
                    style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w700, height: 1.15)),
                const SizedBox(height: 6),
                const Text('Use the account your organization admin created for you.',
                    style: TextStyle(color: Colors.white70, fontSize: 13)),
              ]),
            ),
          ),
        ),
        Expanded(
          child: SafeArea(
            top: false,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
              child: AutofillGroup(
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  if (session.wiped != null && _error == null) ...[
                    Notice(wipeMessage(session.wiped!),
                        fg: AppColors.amber, bg: AppColors.amberSoft, icon: Icons.delete_sweep),
                    const SizedBox(height: 16),
                  ],
                  if (_error != null) ...[
                    Notice(_error!, fg: AppColors.red, bg: AppColors.redSoft, icon: Icons.error_outline),
                    const SizedBox(height: 16),
                  ],
                  TextField(
                    key: const Key('login-user'),
                    controller: _login,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.username, AutofillHints.email],
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                        labelText: 'Email or user ID', prefixIcon: Icon(Icons.person_outline)),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    key: const Key('login-password'),
                    controller: _password,
                    obscureText: _obscure,
                    autofillHints: const [AutofillHints.password],
                    onSubmitted: (_) => _busy ? null : _submit(),
                    decoration: InputDecoration(
                      labelText: 'Password',
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
                        onPressed: () => setState(() => _obscure = !_obscure),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    key: const Key('login-submit'),
                    onPressed: _busy ? null : _submit,
                    child: _busy
                        ? const SizedBox(
                            width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                        : const Text('Sign in'),
                  ),
                  const SizedBox(height: 20),
                  TextButton(
                    key: const Key('forgot-password'),
                    onPressed: _busy ? null : _forgot,
                    child: const Text('Forgot password?'),
                  ),
                ]),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}
