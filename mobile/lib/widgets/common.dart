import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../theme.dart';

final _num = NumberFormat.decimalPattern('en_US');
String fmtNum(num n) => _num.format(n);
String fmtPct(double f) => '${(f * 100).round()}%';
String fmtTime(DateTime t) => DateFormat.jm().format(t);
String fmtDateTime(DateTime t) => DateFormat('d MMM, h:mm a').format(t);
String hourLabel(int h) => '${h % 12 == 0 ? 12 : h % 12}${h < 12 ? 'am' : 'pm'}';
String initials(String name) =>
    name.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).take(2).map((p) => p[0].toUpperCase()).join();

/// National ID numbers are never shown in full — last 3 digits only (•••••390).
String maskId(String? id) {
  final d = (id ?? '').replaceAll(RegExp(r'\s'), '');
  if (d.isEmpty) return '—';
  final hidden = d.length - 3 < 3 ? 3 : d.length - 3;
  return '${'•' * hidden}${d.length > 3 ? d.substring(d.length - 3) : d}';
}

String errorText(Object e) => e.toString().replaceFirst('Exception: ', '');

class Avatar extends StatelessWidget {
  final String name;
  final Color color;
  final double size;
  const Avatar(this.name, {super.key, this.color = AppColors.teal, this.size = 40});

  @override
  Widget build(BuildContext context) => CircleAvatar(
        radius: size / 2,
        backgroundColor: color.withValues(alpha: 0.14),
        child: Text(initials(name), style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: size * 0.34)),
      );
}

class Pill extends StatelessWidget {
  final String text;
  final Color fg, bg;
  const Pill(this.text, {super.key, required this.fg, required this.bg});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(99)),
        child: Text(text, style: TextStyle(color: fg, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: .3)),
      );
}

class RegionPill extends StatelessWidget {
  final bool inRegion;
  const RegionPill(this.inRegion, {super.key});
  @override
  Widget build(BuildContext context) => inRegion
      ? const Pill('IN REGION', fg: AppColors.green, bg: AppColors.greenSoft)
      : const Pill('OUT REGION', fg: AppColors.amber, bg: AppColors.amberSoft);
}

/// KPI tile: a wash of the accent colour, a glowing icon orb and a large watermark of the icon.
/// The icon is picked from the label unless one is given.
class KpiTile extends StatelessWidget {
  final String label, value;
  final String? caption;
  final Color accent;
  final IconData? icon;
  const KpiTile(
      {super.key, required this.label, required this.value, this.caption, this.accent = AppColors.purple, this.icon});

  static IconData iconFor(String label) {
    final l = label.toLowerCase();
    const rules = <(String, IconData)>[
      ('need', Icons.priority_high_rounded),
      ('issue', Icons.priority_high_rounded),
      ('turnout', Icons.how_to_vote_rounded),
      ('report', Icons.insights_rounded),
      ('open', Icons.storefront_rounded),
      ('check-in', Icons.verified_rounded),
      ('unique', Icons.fingerprint_rounded),
      ('mobiliz', Icons.campaign_rounded),
      ('remaining', Icons.flag_rounded),
      ('target', Icons.track_changes_rounded),
      ('team', Icons.groups_rounded),
      ('voter', Icons.badge_rounded),
      ('region', Icons.place_rounded),
      ('peak', Icons.schedule_rounded),
    ];
    for (final (key, ic) in rules) {
      if (l.contains(key)) return ic;
    }
    return Icons.bar_chart_rounded;
  }

  @override
  Widget build(BuildContext context) {
    final ic = icon ?? iconFor(label);
    final deep = Color.lerp(accent, Colors.black, .22)!;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Color.lerp(AppColors.border, accent, .22)!),
        gradient: LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [Color.lerp(Colors.white, accent, .13)!, Colors.white],
          stops: const [0, .7],
        ),
        boxShadow: [BoxShadow(color: accent.withValues(alpha: .16), blurRadius: 18, offset: const Offset(0, 8))],
      ),
      child: Stack(children: [
        Positioned(
          right: -14,
          bottom: -18,
          child: Transform.rotate(angle: -.2, child: Icon(ic, size: 84, color: accent.withValues(alpha: .08))),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Text(label.toUpperCase(),
                      style: const TextStyle(
                          fontSize: 10.5, color: AppColors.muted, fontWeight: FontWeight.w600, letterSpacing: .6)),
                ),
              ),
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(11),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color.lerp(accent, Colors.white, .25)!, accent, deep],
                  ),
                  boxShadow: [BoxShadow(color: accent.withValues(alpha: .4), blurRadius: 10, offset: const Offset(0, 4))],
                ),
                child: Icon(ic, size: 18, color: Colors.white),
              ),
            ]),
            const SizedBox(height: 8),
            Text(value, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: -.3)),
            if (caption != null)
              Text(caption!, style: const TextStyle(fontSize: 12, color: AppColors.muted)),
          ]),
        ),
      ]),
    );
  }
}

/// Two KPI tiles per row.
class KpiGrid extends StatelessWidget {
  final List<Widget> tiles;
  const KpiGrid(this.tiles, {super.key});

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < tiles.length; i += 2) {
      rows.add(Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Expanded(child: tiles[i]),
            const SizedBox(width: 10),
            Expanded(child: i + 1 < tiles.length ? tiles[i + 1] : const SizedBox()),
          ]),
        ),
      ));
    }
    return Column(children: rows);
  }
}

class ProgressLine extends StatelessWidget {
  final double value;
  final Color color;
  const ProgressLine(this.value, {super.key, this.color = AppColors.amber});
  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(99),
        child: LinearProgressIndicator(
            value: value.clamp(0, 1).toDouble(),
            minHeight: 8,
            color: color,
            backgroundColor: color.withValues(alpha: .15)),
      );
}

/// Simple vertical bar chart; [highlight] index renders amber (e.g. peak hour).
class MiniBarChart extends StatelessWidget {
  final List<MapEntry<String, int>> data;
  final int? highlight;
  final Color color;
  const MiniBarChart({super.key, required this.data, this.highlight, this.color = AppColors.teal});

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) return const EmptyNote('No activity yet.');
    final maxV = data.map((e) => e.value).fold<int>(1, (a, b) => a > b ? a : b);
    return SizedBox(
      height: 150,
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        for (var i = 0; i < data.length; i++)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                Text('${data[i].value}', style: const TextStyle(fontSize: 10, color: AppColors.muted)),
                const SizedBox(height: 2),
                Flexible(
                  child: FractionallySizedBox(
                    heightFactor: data[i].value / maxV,
                    child: Container(
                      constraints: const BoxConstraints(minHeight: 2, maxWidth: 36),
                      decoration: BoxDecoration(
                        color: i == highlight ? AppColors.amber : color,
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(data[i].key, style: const TextStyle(fontSize: 9, color: AppColors.muted), maxLines: 1),
              ]),
            ),
          ),
      ]),
    );
  }
}

class SectionCard extends StatelessWidget {
  final String title;
  final Widget child;
  final Widget? trailing;
  const SectionCard({super.key, required this.title, required this.child, this.trailing});

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15))),
              if (trailing != null) trailing!,
            ]),
            const SizedBox(height: 12),
            child,
          ]),
        ),
      );
}

class EmptyNote extends StatelessWidget {
  final String text;
  const EmptyNote(this.text, {super.key});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Center(child: Text(text, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.muted))),
      );
}

class Notice extends StatelessWidget {
  final String text;
  final Color fg, bg;
  final IconData icon;
  const Notice(this.text, {super.key, required this.fg, required this.bg, required this.icon});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, color: fg, size: 20),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: TextStyle(color: fg, fontWeight: FontWeight.w600))),
        ]),
      );
}

/// The tappable Event (teal) / Drive (amber) selector banner at the top of a flow.
class GroupBanner extends StatelessWidget {
  final String kicker, title, subtitle;
  final Color color, soft;
  final VoidCallback? onTap;
  const GroupBanner(
      {super.key,
      required this.kicker,
      required this.title,
      required this.subtitle,
      required this.color,
      required this.soft,
      this.onTap});

  @override
  Widget build(BuildContext context) => Material(
        color: soft,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14), border: Border.all(color: color.withValues(alpha: .35))),
            child: Row(children: [
              Icon(Icons.event_available, color: color),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(kicker,
                      style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: .5)),
                  Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                  if (subtitle.isNotEmpty) Text(subtitle, style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                ]),
              ),
              if (onTap != null) Icon(Icons.expand_more, color: color),
            ]),
          ),
        ),
      );
}

/// Bottom-sheet picker for events or drives.
Future<T?> pickFrom<T>(
    BuildContext context, String title, List<T> items, String Function(T) label, String Function(T) sub) {
  return showModalBottomSheet<T>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: ListView(shrinkWrap: true, children: [
        Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(title, style: Theme.of(ctx).textTheme.titleMedium)),
        for (final it in items)
          ListTile(title: Text(label(it)), subtitle: Text(sub(it)), onTap: () => Navigator.pop(ctx, it)),
      ]),
    ),
  );
}
