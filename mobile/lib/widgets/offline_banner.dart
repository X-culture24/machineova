import 'package:flutter/material.dart';

import '../offline/sync.dart';
import '../screens/sync_screen.dart';
import '../theme.dart';
import 'common.dart';

/// Thin status strip: offline / waiting to sync / needs attention. Hidden when all is well.
class OfflineBanner extends StatelessWidget {
  const OfflineBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([netStatus, outbox]),
      builder: (context, _) {
        final waiting = outbox.waitingCount;
        final failed = outbox.failed.length;
        final (Color fg, Color bg, IconData icon, String text)? state = failed > 0
            ? (
                AppColors.red,
                AppColors.redSoft,
                Icons.error_outline,
                '$failed record${failed == 1 ? '' : 's'} need attention'
              )
            : !netStatus.online
                ? (
                    AppColors.amber,
                    AppColors.amberSoft,
                    Icons.cloud_off,
                    [
                      'Offline',
                      if (netStatus.showingCacheFrom != null) 'saved data from ${fmtTime(netStatus.showingCacheFrom!)}',
                      if (waiting > 0) '$waiting waiting to sync',
                    ].join(' · ')
                  )
                : waiting > 0
                    ? (
                        AppColors.teal,
                        AppColors.tealSoft,
                        Icons.sync,
                        outbox.syncing ? 'Syncing $waiting…' : '$waiting waiting to sync'
                      )
                    : null;
        if (state == null) return const SizedBox.shrink();
        final (fg, bg, icon, text) = state;
        return Material(
          color: bg,
          child: InkWell(
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SyncScreen())),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
              child: Row(children: [
                Icon(icon, size: 18, color: fg),
                const SizedBox(width: 10),
                Expanded(child: Text(text, style: TextStyle(color: fg, fontWeight: FontWeight.w600))),
                Icon(Icons.chevron_right, size: 18, color: fg),
              ]),
            ),
          ),
        );
      },
    );
  }
}
