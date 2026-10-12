import 'package:flutter/material.dart';

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
                  const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(Icons.shield_outlined, size: 16, color: AppColors.muted),
                    SizedBox(width: 6),
                    Flexible(
                      child: Text('Forgot your password? Ask your organization admin to reset it.',
                          textAlign: TextAlign.center, style: TextStyle(color: AppColors.muted, fontSize: 12)),
                    ),
                  ]),
                ]),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}
