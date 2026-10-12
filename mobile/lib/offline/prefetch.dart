// Downloads what a field user needs before they lose signal, so every screen they rely on
// opens offline: their events/drives (Checkin) or their stations and result forms (Election Ops).
import '../api/client.dart';
import '../api/ops_api.dart';
import '../session.dart';
import 'sync.dart';

bool _running = false;
DateTime? lastPrefetchAt;

/// Most stations whose full record is kept for offline use (a ward has a handful).
const _maxStationRecords = 25;

/// Result forms are prefetched only for small areas (agents and ward managers).
const _maxStationsWithForms = 10;

Future<void> prefetchForOffline() async {
  final me = session.me;
  if (_running || me == null || !netStatus.online) return;
  _running = true;
  try {
    if (session.opsMode && me.hasOps) {
      final overview = opsApi.overview();
      final (stations, _) = await opsApi.stations();
      await overview;
      await opsApi.people(role: 'agent');
      final detailed = stations.take(_maxStationRecords).toList();
      for (final s in detailed) {
        final d = await opsApi.station(s.code);
        if (stations.length <= _maxStationsWithForms && d.canAct) {
          for (final p in d.positions) {
            await opsApi.stationResults(s.code, p.id);
          }
          if (d.canAssign) await opsApi.agentPool(s.code);
        }
      }
    } else if (me.hasCheckin) {
      await Future.wait([
        api.home(),
        api.events(activeOnly: true),
        api.drives(activeOnly: true),
        api.events(),
        api.drives(),
        api.checkins(),
        api.mobilizations(),
      ]);
    }
    lastPrefetchAt = DateTime.now();
  } catch (_) {
    // Best effort: whatever was fetched is already cached.
  } finally {
    _running = false;
  }
}
