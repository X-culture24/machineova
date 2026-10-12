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
  final String title, body;
  final Widget Function(Animation<double> float) art;
  const _Page(this.title, this.body, this.art);
}

final _pages = <_Page>[
  _Page(
    'Welcome to Checkin',
    "MachineNova's field app for mobilizing voters and running event check-ins — built for the ground game.",
    (f) => _WelcomeArt(float: f),
  ),
  _Page(
    'Scan an ID, find the voter',
    'Point the camera at any Kenyan ID card, front or back. Checkin reads the number and finds the person in seconds.',
    (f) => _ScanArt(float: f),
  ),
  _Page(
    'Check in and mobilize',
    'Mark attendance at events and register voters door to door. Teal means check-in, amber means mobilize.',
    (f) => _JobsArt(float: f),
  ),
  _Page(
    'Works offline, stays secure',
    'No signal? Keep working — records sync when you\'re back online. A PIN and encryption protect everything on the phone.',
    (f) => _SecureArt(float: f),
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
                    Expanded(flex: 6, child: Center(child: AspectRatio(aspectRatio: 1, child: p.art(floatAnim)))),
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

/// Soft brand-tinted disc every illustration sits on.
class _Stage extends StatelessWidget {
  final List<Widget> children;
  const _Stage({required this.children});
  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, c) {
        final s = c.biggest.shortestSide;
        return Stack(alignment: Alignment.center, clipBehavior: Clip.none, children: [
          Container(
            width: s * .92,
            height: s * .92,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(colors: [
                AppColors.purple.withValues(alpha: .16),
                AppColors.magenta.withValues(alpha: .06),
                Colors.white.withValues(alpha: 0),
              ], stops: const [0, .6, 1]),
            ),
          ),
          ...children,
        ]);
      });
}

Widget _floating(Animation<double> f, double amp, Widget child, {double phase = 0}) => AnimatedBuilder(
      animation: f,
      builder: (_, c) => Transform.translate(offset: Offset(0, math.sin((f.value + phase) * math.pi) * amp - amp / 2), child: c),
      child: child,
    );

class _Bubble extends StatelessWidget {
  final IconData icon;
  final Color color;
  final double size;
  const _Bubble(this.icon, this.color, {this.size = 56});
  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(size * .32),
          boxShadow: [BoxShadow(color: color.withValues(alpha: .25), blurRadius: 20, offset: const Offset(0, 8))],
        ),
        child: Icon(icon, color: color, size: size * .48),
      );
}

class _WelcomeArt extends StatelessWidget {
  final Animation<double> float;
  const _WelcomeArt({required this.float});
  @override
  Widget build(BuildContext context) => _Stage(children: [
        _floating(
          float,
          10,
          Container(
            width: 150,
            height: 150,
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(44),
              boxShadow: [
                BoxShadow(color: AppColors.purple.withValues(alpha: .28), blurRadius: 40, offset: const Offset(0, 18))
              ],
            ),
            child: Image.asset('assets/brand/mark.png'),
          ),
        ),
        Positioned(top: 30, left: 18, child: _floating(float, 8, const _Bubble(Icons.how_to_reg, AppColors.teal), phase: .3)),
        Positioned(top: 50, right: 14, child: _floating(float, 8, const _Bubble(Icons.campaign, AppColors.amber), phase: .7)),
        Positioned(
            bottom: 34, left: 40, child: _floating(float, 8, const _Bubble(Icons.insights, AppColors.purple, size: 50), phase: .5)),
        Positioned(
            bottom: 24, right: 46, child: _floating(float, 8, const _Bubble(Icons.groups, AppColors.magenta, size: 48), phase: .1)),
      ]);
}

class _ScanArt extends StatelessWidget {
  final Animation<double> float;
  const _ScanArt({required this.float});
  @override
  Widget build(BuildContext context) => _Stage(children: [
        _floating(
          float,
          8,
          SizedBox(
            width: 240,
            height: 151,
            child: Stack(children: [
              // the card
              Container(
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [Color(0xFFFFFFFF), Color(0xFFF1ECFA)]),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: AppColors.border),
                  boxShadow: [
                    BoxShadow(color: AppColors.purple.withValues(alpha: .22), blurRadius: 30, offset: const Offset(0, 14))
                  ],
                ),
                padding: const EdgeInsets.all(16),
                child: Row(children: [
                  Container(
                    width: 62,
                    height: 78,
                    decoration: BoxDecoration(color: AppColors.purpleSoft, borderRadius: BorderRadius.circular(10)),
                    child: const Icon(Icons.person, color: AppColors.purple, size: 40),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                      const Text('ID NUMBER', style: TextStyle(fontSize: 9, color: AppColors.muted, letterSpacing: 1)),
                      const Text('2755 3390', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, letterSpacing: 1)),
                      const SizedBox(height: 8),
                      for (final w in [.9, .65, .8])
                        Padding(
                          padding: const EdgeInsets.only(top: 5),
                          child: FractionallySizedBox(
                            widthFactor: w,
                            child: Container(height: 6, decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(3))),
                          ),
                        ),
                    ]),
                  ),
                ]),
              ),
              // scan line
              AnimatedBuilder(
                animation: float,
                builder: (_, __) => Positioned(
                  left: 8,
                  right: 8,
                  top: 10 + float.value * 128,
                  child: Container(
                    height: 3,
                    decoration: BoxDecoration(
                      gradient: brandGradient,
                      borderRadius: BorderRadius.circular(2),
                      boxShadow: [BoxShadow(color: AppColors.magenta.withValues(alpha: .6), blurRadius: 12)],
                    ),
                  ),
                ),
              ),
            ]),
          ),
        ),
        Positioned(
          bottom: 30,
          right: 30,
          child: _floating(float, 6, const _Bubble(Icons.verified, AppColors.teal, size: 54), phase: .6),
        ),
        Positioned(top: 34, left: 28, child: _floating(float, 6, const _Bubble(Icons.photo_camera, AppColors.purple, size: 50), phase: .2)),
      ]);
}

class _JobsArt extends StatelessWidget {
  final Animation<double> float;
  const _JobsArt({required this.float});

  Widget _tile(String kicker, String title, IconData icon, Color color, Color soft) => Container(
        width: 200,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [BoxShadow(color: color.withValues(alpha: .22), blurRadius: 24, offset: const Offset(0, 10))],
        ),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: soft, borderRadius: BorderRadius.circular(14)),
            child: Icon(icon, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(kicker, style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w700, letterSpacing: .8)),
              Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
            ]),
          ),
        ]),
      );

  @override
  Widget build(BuildContext context) => _Stage(children: [
        Positioned(
          top: 50,
          left: 10,
          child: _floating(float, 8, _tile('CHECK-IN', 'Kibra Unity Rally', Icons.how_to_reg, AppColors.teal, AppColors.tealSoft)),
        ),
        Positioned(
          bottom: 60,
          right: 6,
          child: _floating(float, 8, _tile('MOBILIZE', 'Langata Drive', Icons.campaign, AppColors.amber, AppColors.amberSoft),
              phase: .5),
        ),
      ]);
}

class _SecureArt extends StatelessWidget {
  final Animation<double> float;
  const _SecureArt({required this.float});
  @override
  Widget build(BuildContext context) => _Stage(children: [
        _floating(
          float,
          10,
          Container(
            width: 140,
            height: 160,
            decoration: BoxDecoration(
              gradient: brandGradient,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(36), bottom: Radius.circular(70)),
              boxShadow: [
                BoxShadow(color: AppColors.purple.withValues(alpha: .35), blurRadius: 40, offset: const Offset(0, 18))
              ],
            ),
            child: const Icon(Icons.lock_outline, color: Colors.white, size: 64),
          ),
        ),
        Positioned(top: 40, right: 24, child: _floating(float, 8, const _Bubble(Icons.cloud_off, AppColors.amber), phase: .4)),
        Positioned(bottom: 40, left: 26, child: _floating(float, 8, const _Bubble(Icons.sync, AppColors.teal), phase: .8)),
        Positioned(bottom: 70, right: 30, child: _floating(float, 6, const _Bubble(Icons.pin, AppColors.purple, size: 46), phase: .2)),
      ]);
}
