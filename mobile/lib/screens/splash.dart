import 'package:flutter/material.dart';

import '../theme.dart';

/// Shown while the session restores on launch.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Container(
          decoration: const BoxDecoration(gradient: brandGradient),
          child: Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: 96,
                height: 96,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(30)),
                child: Image.asset('assets/brand/mark.png'),
              ),
              const SizedBox(height: 18),
              const Text('Checkin', style: TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.w700)),
              const Text('by MachineNova', style: TextStyle(color: Colors.white70, fontSize: 14)),
              const SizedBox(height: 36),
              const SizedBox(
                  width: 26, height: 26, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5)),
            ]),
          ),
        ),
      );
}
