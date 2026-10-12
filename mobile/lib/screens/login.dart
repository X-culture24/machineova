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
      backgroundColor: AppColors.teal,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
                child: const Icon(Icons.how_to_reg, color: AppColors.teal, size: 36),
              ),
              const SizedBox(height: 12),
              const Text('Checkin', style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w800)),
              const SizedBox(height: 28),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: AutofillGroup(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      const Text('Sign in', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 16),
                      if (session.wiped != null && _error == null) ...[
                        Notice(wipeMessage(session.wiped!),
                            fg: AppColors.amber, bg: AppColors.amberSoft, icon: Icons.delete_sweep),
                        const SizedBox(height: 12),
                      ],
                      if (_error != null) ...[
                        Notice(_error!, fg: AppColors.red, bg: AppColors.redSoft, icon: Icons.error_outline),
                        const SizedBox(height: 12),
                      ],
                      TextField(
                        controller: _login,
                        keyboardType: TextInputType.emailAddress,
                        autofillHints: const [AutofillHints.username, AutofillHints.email],
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(labelText: 'Email or user ID'),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _password,
                        obscureText: _obscure,
                        autofillHints: const [AutofillHints.password],
                        onSubmitted: (_) => _busy ? null : _submit(),
                        decoration: InputDecoration(
                          labelText: 'Password',
                          suffixIcon: IconButton(
                            icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
                            onPressed: () => setState(() => _obscure = !_obscure),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      FilledButton(
                        onPressed: _busy ? null : _submit,
                        child: Text(_busy ? 'Signing in…' : 'Sign In'),
                      ),
                    ]),
                  ),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
