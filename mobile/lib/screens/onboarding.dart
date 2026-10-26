import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme.dart';

/// First-run walkthrough (shown once, before sign-in).
class Onboarding {
  static const _key = 'onboarded_v1';

  static Future<bool> isDone() async {
    try {
      return (await SharedPreferences.getInstance()).getBool(_key) ?? false;
    } catch (_) {
      return true; // never trap the user on onboarding if storage misbehaves
    }
  }

  static Future<void> markDone() async {
    try {
      await (await SharedPreferences.getInstance()).setBool(_key, true);
    } catch (_) {}
  }
}

class _Page {
  final String title, body, image;
  const _Page(this.title, this.body, this.image);
}

const _pages = <_Page>[
  _Page(
    'Welcome to Checkin',
    "MachineNova's field app for mobilizing voters and running event check-ins — built for the ground game.",
    'assets/onboarding/welcome.png',
  ),
  _Page(
    'Scan an ID, find the voter',
    'Point the camera at any Kenyan ID card, front or back. Checkin reads the number and finds the person in seconds.',
    'assets/onboarding/scan.png',
  ),
  _Page(
    'Check in and mobilize',
    'Mark attendance at events and register voters door to door. Teal means check-in, amber means mobilize.',
    'assets/onboarding/jobs.png',
  ),
  _Page(
    'Works offline, stays secure',
    'No signal? Keep working — records sync when you\'re back online. A PIN and encryption protect everything on the phone.',
    'assets/onboarding/secure.png',
  ),
];

class OnboardingScreen extends StatefulWidget {
  final VoidCallback onDone;
  const OnboardingScreen({super.key, required this.onDone});
  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> with SingleTickerProviderStateMixin {
  final _pager = PageController();
  int _page = 0;
  late final AnimationController _float =
      AnimationController(vsync: this, duration: const Duration(seconds: 3))..repeat(reverse: true);

  bool get _last => _page == _pages.length - 1;

  Future<void> _finish() async {
    await Onboarding.markDone();
    widget.onDone();
  }

  void _next() => _last
      ? _finish()
      : _pager.nextPage(duration: const Duration(milliseconds: 420), curve: Curves.easeOutCubic);

  @override
  void dispose() {
    _pager.dispose();
    _float.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final floatAnim = CurvedAnimation(parent: _float, curve: Curves.easeInOut);
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 8, 0),
            child: Row(children: [
              Image.asset('assets/brand/mark.png', height: 30),
              const SizedBox(width: 8),
              const Text('Checkin', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              const Spacer(),
              AnimatedOpacity(
                opacity: _last ? 0 : 1,
                duration: const Duration(milliseconds: 200),
                child: TextButton(
                  key: const Key('onboarding-skip'),
                  onPressed: _last ? null : _finish,
                  child: const Text('Skip'),
                ),
              ),
            ]),
          ),
          Expanded(
            child: PageView.builder(
              controller: _pager,
              itemCount: _pages.length,
              onPageChanged: (i) => setState(() => _page = i),
              itemBuilder: (context, i) {
                final p = _pages[i];
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(children: [
                    const SizedBox(height: 12),
                    Expanded(flex: 6, child: Center(child: AspectRatio(aspectRatio: 1, child: _Art(p.image, float: floatAnim)))),
                    const SizedBox(height: 24),
                    Text(p.title,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700, height: 1.2)),
                    const SizedBox(height: 12),
                    Text(p.body,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 15, color: AppColors.muted, height: 1.55)),
                    const Spacer(flex: 1),
                  ]),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
            child: Column(children: [
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                for (var i = 0; i < _pages.length; i++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeOut,
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: i == _page ? 28 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      gradient: i == _page ? brandGradient : null,
                      color: i == _page ? null : AppColors.border,
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
              ]),
              const SizedBox(height: 24),
              _GradientButton(
                key: const Key('onboarding-next'),
                label: _last ? 'Get started' : 'Next',
                icon: _last ? Icons.arrow_forward : null,
                onPressed: _next,
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// Full-width pill button filled with the brand gradient.
class _GradientButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback onPressed;
  const _GradientButton({super.key, required this.label, required this.onPressed, this.icon});

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          gradient: brandGradient,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(color: AppColors.purple.withValues(alpha: .35), blurRadius: 18, offset: const Offset(0, 8))
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: onPressed,
            child: SizedBox(
              height: 56,
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Text(label, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
                if (icon != null) ...[const SizedBox(width: 8), Icon(icon, color: Colors.white, size: 20)],
              ]),
            ),
          ),
        ),
      );
}

// ── Illustrations ───────────────────────────────────────────────────────────

/// One onboarding illustration (assets/onboarding/*.png), drifting gently.
class _Art extends StatelessWidget {
  final String image;
  final Animation<double> float;
  const _Art(this.image, {required this.float});
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: float,
        builder: (_, child) => Transform.translate(offset: Offset(0, math.sin(float.value * math.pi) * 10 - 5), child: child),
        child: Image.asset(image, fit: BoxFit.contain, filterQuality: FilterQuality.medium),
      );
}
