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

class KpiTile extends StatelessWidget {
  final String label, value;
  final String? caption;
  final Color accent;
  const KpiTile({super.key, required this.label, required this.value, this.caption, this.accent = AppColors.teal});

  @override
  Widget build(BuildContext context) => Card(
        clipBehavior: Clip.antiAlias,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(border: Border(top: BorderSide(color: accent, width: 3))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label.toUpperCase(),
                style: const TextStyle(
                    fontSize: 11, color: AppColors.muted, fontWeight: FontWeight.w600, letterSpacing: .5)),
            const SizedBox(height: 6),
            Text(value, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
            if (caption != null) Text(caption!, style: const TextStyle(fontSize: 12, color: AppColors.muted)),
          ]),
        ),
      );
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
