import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../theme.dart';
import '../../widgets/common.dart';

const _statusColors = {
  'not_open': (AppColors.muted, Color(0xFFEFF2F1)),
  'open': (AppColors.green, AppColors.greenSoft),
  'reporting': (AppColors.teal, AppColors.tealSoft),
  'closed': (AppColors.muted, Color(0xFFEFF2F1)),
  'issue': (AppColors.red, AppColors.redSoft),
};

class StatusPill extends StatelessWidget {
  final String status;
  const StatusPill(this.status, {super.key});
  @override
  Widget build(BuildContext context) {
    final (fg, bg) = _statusColors[status] ?? (AppColors.muted, const Color(0xFFEFF2F1));
    const labels = {
      'not_open': 'NOT OPEN',
      'open': 'OPEN',
      'reporting': 'REPORTING',
      'closed': 'CLOSED',
      'issue': '● ISSUE'
    };
    return Pill(labels[status] ?? status.toUpperCase(), fg: fg, bg: bg);
  }
}

class CoveragePill extends StatelessWidget {
  final int agents;
  const CoveragePill(this.agents, {super.key});
  @override
  Widget build(BuildContext context) => agents == 0
      ? const Pill('UNCOVERED', fg: AppColors.red, bg: AppColors.redSoft)
      : Pill('$agents AGENT${agents > 1 ? 'S' : ''}', fg: AppColors.green, bg: AppColors.greenSoft);
}

/// Call + WhatsApp buttons — contact stays one tap away.
class ContactButtons extends StatelessWidget {
  final String? phone;
  const ContactButtons(this.phone, {super.key});

  Future<void> _open(BuildContext context, Uri uri) async {
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication) && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Couldn't open ${uri.scheme}")));
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = phone;
    if (p == null || p.isEmpty) return const SizedBox.shrink();
    final digits = p.replaceAll(RegExp(r'[^0-9]'), '');
    return Row(mainAxisSize: MainAxisSize.min, children: [
      IconButton.outlined(
        tooltip: 'Call',
        icon: const Icon(Icons.call, size: 20),
        onPressed: () => _open(context, Uri(scheme: 'tel', path: p.replaceAll(' ', ''))),
      ),
      const SizedBox(width: 6),
      IconButton.filledTonal(
        tooltip: 'WhatsApp',
        style: IconButton.styleFrom(backgroundColor: AppColors.greenSoft, foregroundColor: AppColors.green),
        icon: const Icon(Icons.chat, size: 20),
        onPressed: () => _open(context, Uri.parse('https://wa.me/$digits')),
      ),
    ]);
  }
}

class StatTile extends StatelessWidget {
  final String label, value;
  final String? caption;
  final Color? valueColor;
  const StatTile(this.label, this.value, {super.key, this.caption, this.valueColor});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAF9),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE3E9E7)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label,
              style: const TextStyle(
                  fontSize: 11, color: AppColors.muted, fontWeight: FontWeight.w600, letterSpacing: .5)),
          const SizedBox(height: 4),
          Text(value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: valueColor)),
          if (caption != null) Text(caption!, style: const TextStyle(fontSize: 12, color: AppColors.muted)),
        ]),
      );
}

class NoActiveElection extends StatelessWidget {
  final VoidCallback onRetry;
  const NoActiveElection({super.key, required this.onRetry});
  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(24), children: [
        const SizedBox(height: 40),
        const Icon(Icons.how_to_vote_outlined, size: 48, color: AppColors.muted),
        const EmptyNote('No active election yet.\nYour admin activates it from the dashboard.'),
        OutlinedButton(onPressed: onRetry, child: const Text('Check again')),
      ]);
}
