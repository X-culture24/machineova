import 'package:flutter/material.dart';

import '../offline/prefetch.dart';
import '../offline/sync.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// Everything recorded on this phone that hasn't reached the server, plus recent syncs.
class SyncScreen extends StatelessWidget {
  const SyncScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sync & offline data')),
      body: ListenableBuilder(
        listenable: Listenable.merge([netStatus, outbox]),
        builder: (context, _) {
          final failed = outbox.failed, pending = outbox.pending, recent = outbox.recent;
          Widget head(String t) => Padding(
                padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
                child: Text(t,
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.muted, fontWeight: FontWeight.w700, letterSpacing: .6)),
              );
          return ListView(padding: const EdgeInsets.all(16), children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Icon(netStatus.online ? Icons.cloud_done : Icons.cloud_off,
                        color: netStatus.online ? AppColors.green : AppColors.amber),
                    const SizedBox(width: 10),
                    Text(netStatus.online ? 'Online' : 'Offline',
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                  ]),
                  const SizedBox(height: 8),
                  Text(
                    netStatus.online
                        ? 'Records sync automatically.'
                        : 'Keep working — check-ins, mobilizations and station updates are saved on this phone and sync when you\'re back online.',
                    style: const TextStyle(color: AppColors.muted),
                  ),
                  if (outbox.lastSyncAt != null)
                    Text('Last synced ${fmtDateTime(outbox.lastSyncAt!)}',
                        style: const TextStyle(color: AppColors.muted)),
                  if (lastPrefetchAt != null)
                    Text('Offline data downloaded ${fmtDateTime(lastPrefetchAt!)}',
                        style: const TextStyle(color: AppColors.muted)),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: outbox.syncing
                        ? null
                        : () async {
                            await outbox.flush();
                            await prefetchForOffline();
                          },
                    icon: const Icon(Icons.sync),
                    label: Text(outbox.syncing ? 'Syncing…' : 'Sync now'),
                  ),
                ]),
              ),
            ),
            if (failed.isNotEmpty) ...[
              head('NEEDS ATTENTION'),
              const Text('The server rejected these. Fix the issue (e.g. ask your admin), then retry — or discard.',
                  style: TextStyle(color: AppColors.muted)),
              const SizedBox(height: 8),
              for (final i in failed)
                Card(
                  color: AppColors.redSoft,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(i.label, style: const TextStyle(fontWeight: FontWeight.w700)),
                      Text('Recorded ${fmtDateTime(i.recordedAt)}',
                          style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                      const SizedBox(height: 4),
                      Text(i.error ?? 'Rejected', style: const TextStyle(color: AppColors.red)),
                      Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                        TextButton(
                          onPressed: () async {
                            final ok = await showDialog<bool>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: const Text('Discard this record?'),
                                content: Text('"${i.label}" will not be sent. This cannot be undone.'),
                                actions: [
                                  TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep')),
                                  TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Discard')),
                                ],
                              ),
                            );
                            if (ok == true) outbox.discard(i);
                          },
                          child: const Text('Discard'),
                        ),
                        if (i.path == '/api/checkins' || i.path == '/api/mobilizations')
                          TextButton(
                              onPressed: () => _editDetails(context, i), child: const Text('Add details & retry'))
                        else
                          TextButton(onPressed: () => outbox.retry(i), child: const Text('Retry')),
                      ]),
                    ]),
                  ),
                ),
            ],
            head('WAITING TO SYNC · ${pending.length}'),
            if (pending.isEmpty) const Text('Nothing waiting.', style: TextStyle(color: AppColors.muted)),
            for (final i in pending)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.schedule, color: AppColors.amber),
                title: Text(i.label),
                subtitle: Text(
                    'Recorded ${fmtDateTime(i.recordedAt)}${i.attempts > 0 ? ' · ${i.attempts} attempt${i.attempts == 1 ? '' : 's'}' : ''}'),
              ),
            head('RECENTLY SYNCED'),
            if (recent.isEmpty) const Text('Nothing yet.', style: TextStyle(color: AppColors.muted)),
            for (final e in recent.take(30))
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(e.duplicate ? Icons.content_copy : Icons.check_circle,
                    color: e.duplicate ? AppColors.muted : AppColors.green),
                title: Text(e.label),
                subtitle: Text(e.duplicate
                    ? 'Already recorded on the server — not counted twice'
                    : 'Recorded ${fmtDateTime(e.recordedAt)} · synced ${fmtTime(e.syncedAt)}'),
              ),
          ]);
        },
      ),
    );
  }

  /// Voter not on the register (or details missing): let the operator complete the record.
  Future<void> _editDetails(BuildContext context, OutboxItem item) async {
    final b = item.body ?? {};
    final c = {
      for (final k in ['name', 'county', 'constituency', 'ward', 'phone'])
        k: TextEditingController(text: '${b[k] ?? ''}'),
    };
    var sex = b['sex'] as String?;
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.of(ctx).viewInsets.bottom),
        child: StatefulBuilder(
          builder: (ctx, setSheet) => SingleChildScrollView(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
              Text('Complete: ID ${maskId(b['national_id'] as String?)}',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              Text(item.error ?? '', style: const TextStyle(color: AppColors.red)),
              const SizedBox(height: 12),
              TextField(controller: c['name'], decoration: const InputDecoration(labelText: 'Full name')),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: sex,
                decoration: const InputDecoration(labelText: 'Sex'),
                items: const [
                  DropdownMenuItem(value: 'F', child: Text('Female')),
                  DropdownMenuItem(value: 'M', child: Text('Male')),
                ],
                onChanged: (v) => setSheet(() => sex = v),
              ),
              const SizedBox(height: 10),
              TextField(controller: c['county'], decoration: const InputDecoration(labelText: 'County')),
              const SizedBox(height: 10),
              TextField(controller: c['constituency'], decoration: const InputDecoration(labelText: 'Constituency')),
              const SizedBox(height: 10),
              TextField(controller: c['ward'], decoration: const InputDecoration(labelText: 'Ward')),
              const SizedBox(height: 10),
              TextField(
                  controller: c['phone'],
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(labelText: 'Phone')),
              const SizedBox(height: 16),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save & retry')),
            ]),
          ),
        ),
      ),
    );
    if (ok == true) {
      await outbox.editAndRetry(item, {
        for (final e in c.entries)
          if (e.value.text.trim().isNotEmpty) e.key: e.value.text.trim(),
        if (sex != null) 'sex': sex,
      });
    }
    for (final t in c.values) {
      t.dispose();
    }
  }
}
