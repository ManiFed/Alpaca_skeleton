import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../state/app_state.dart';
import '../theme.dart';

/// "Tonight" — live dashboard. No scrolling. Four panels fill the screen.
class DashboardTab extends StatefulWidget {
  const DashboardTab({super.key});

  @override
  State<DashboardTab> createState() => _DashboardTabState();
}

// ── Data bundle ───────────────────────────────────────────────────────────────

class _DashboardData {
  const _DashboardData({
    required this.nodes,
    required this.recentObs,
    required this.targets,
    required this.alerts,
  });

  final List<Node> nodes;
  final List<Observation> recentObs;
  final List<Target> targets;
  final List<AppNotification> alerts;
}

// ── State ─────────────────────────────────────────────────────────────────────

class _DashboardTabState extends State<DashboardTab> {
  late Future<_DashboardData> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_DashboardData> _load() async {
    final api = context.read<AppState>().api;

    // All four requests fire in parallel.
    final nodesFuture =
        api.nodes().catchError((_) => <Node>[]);
    final obsFuture =
        api.observations(days: 1, limit: 10).catchError((_) => <Observation>[]);
    final targetsFuture =
        api.targets().catchError((_) => <Target>[]);
    final notifsFuture = api.notifications(limit: 5);

    List<AppNotification> alerts;
    try {
      alerts = (await notifsFuture).$1;
    } catch (_) {
      alerts = [];
    }

    return _DashboardData(
      nodes: await nodesFuture,
      recentObs: await obsFuture,
      targets: await targetsFuture,
      alerts: alerts,
    );
  }

  Future<void> _refresh() async => setState(() => _future = _load());

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_DashboardData>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.cloud_off, size: 48, color: BSTheme.ink3),
                  const SizedBox(height: 12),
                  Text('${snap.error}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: BSTheme.ink2)),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: _refresh,
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),
          );
        }
        return _DashboardView(data: snap.data!, onRefresh: _refresh);
      },
    );
  }
}

// ── Dashboard view ────────────────────────────────────────────────────────────

class _DashboardView extends StatelessWidget {
  const _DashboardView({required this.data, required this.onRefresh});
  final _DashboardData data;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top + kToolbarHeight;
    final bottomPad = MediaQuery.of(context).padding.bottom + 64;

    // LayoutBuilder gives us the true available height so we can size the
    // column to exactly fill the screen — no normal scrolling.
    return LayoutBuilder(
      builder: (context, constraints) => RefreshIndicator(
        onRefresh: onRefresh,
        child: SingleChildScrollView(
          // AlwaysScrollableScrollPhysics enables pull-to-refresh even though
          // the content does not normally overflow.
          physics: const AlwaysScrollableScrollPhysics(),
          child: SizedBox(
            height: constraints.maxHeight,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(height: topPad),
                _NodeStrip(nodes: data.nodes),
                const Divider(height: 1, color: BSTheme.glassBorder),
                Expanded(
                  flex: 28,
                  child: ClipRect(
                    child: _ActivitySection(obs: data.recentObs),
                  ),
                ),
                const Divider(height: 1, color: BSTheme.glassBorder),
                Expanded(
                  flex: 38,
                  child: ClipRect(
                    child: _TargetsSection(targets: data.targets),
                  ),
                ),
                const Divider(height: 1, color: BSTheme.glassBorder),
                Expanded(
                  flex: 30,
                  child: ClipRect(
                    child: _AlertsSection(alerts: data.alerts),
                  ),
                ),
                SizedBox(height: bottomPad),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Node status strip ─────────────────────────────────────────────────────────

class _NodeStrip extends StatelessWidget {
  const _NodeStrip({required this.nodes});
  final List<Node> nodes;

  @override
  Widget build(BuildContext context) {
    final online = nodes.where((n) => n.online).length;
    final total = nodes.length;

    // Most-recent heartbeat across all nodes.
    String lastSeen = '';
    if (nodes.isNotEmpty) {
      final times = nodes
          .map((n) => DateTime.tryParse(n.lastHeartbeat))
          .whereType<DateTime>()
          .toList()
        ..sort((a, b) => b.compareTo(a));
      if (times.isNotEmpty) lastSeen = _ago(times.first);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
      child: Row(
        children: [
          // Node dots
          ...nodes.take(6).map(
                (n) => Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: _NodeDot(online: n.online),
                ),
              ),
          if (nodes.isEmpty)
            const _NodeDot(online: false, empty: true),
          const SizedBox(width: 8),
          // Status text
          Expanded(
            child: Text(
              total == 0
                  ? 'No telescopes connected'
                  : '$online of $total online',
              style: const TextStyle(
                fontFamily: 'Geist',
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: BSTheme.ink2,
              ),
            ),
          ),
          if (lastSeen.isNotEmpty)
            Text(
              lastSeen,
              style: const TextStyle(
                fontFamily: 'Geist',
                fontSize: 11,
                color: BSTheme.ink3,
              ),
            ),
        ],
      ),
    );
  }
}

class _NodeDot extends StatelessWidget {
  const _NodeDot({required this.online, this.empty = false});
  final bool online;
  final bool empty;

  @override
  Widget build(BuildContext context) {
    final color = empty
        ? BSTheme.ink3
        : online
            ? BSTheme.success
            : BSTheme.danger;
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: empty ? Colors.transparent : color,
        border: Border.all(color: color, width: 1.5),
        boxShadow: (!empty && online)
            ? [
                BoxShadow(
                  color: BSTheme.success.withValues(alpha: 0.5),
                  blurRadius: 6,
                ),
              ]
            : null,
      ),
    );
  }
}

// ── Recent activity section ───────────────────────────────────────────────────

class _ActivitySection extends StatelessWidget {
  const _ActivitySection({required this.obs});
  final List<Observation> obs;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SectionHeader(
          label: 'RECENT ACTIVITY',
          detail: 'last 24 h',
        ),
        if (obs.isEmpty)
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text(
              'No observations in the last 24 hours.',
              style: TextStyle(
                fontFamily: 'Geist',
                fontSize: 13,
                color: BSTheme.ink3,
              ),
            ),
          )
        else
          ...obs.take(4).map((o) => _ActivityRow(obs: o)),
      ],
    );
  }
}

class _ActivityRow extends StatelessWidget {
  const _ActivityRow({required this.obs});
  final Observation obs;

  @override
  Widget build(BuildContext context) {
    final target = obs.targetName.isEmpty ? '—' : obs.targetName;
    final magColor = obs.magnitude < 8
        ? BSTheme.warm
        : obs.magnitude < 11
            ? BSTheme.accent
            : BSTheme.ink2;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
      child: Row(
        children: [
          Icon(Icons.star_rounded, size: 13, color: magColor),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              target,
              style: const TextStyle(
                fontFamily: 'Geist',
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: BSTheme.ink,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            obs.magnitude.toStringAsFixed(2),
            style: TextStyle(
              fontFamily: 'Geist',
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: magColor,
            ),
          ),
          if (obs.filter.isNotEmpty) ...[
            const SizedBox(width: 6),
            _MiniChip(obs.filter.toUpperCase()),
          ],
          const SizedBox(width: 8),
          Text(
            _ago(DateTime.tryParse(obs.receivedAt)),
            style: const TextStyle(
              fontFamily: 'Geist',
              fontSize: 11,
              color: BSTheme.ink3,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Network targets section ───────────────────────────────────────────────────

class _TargetsSection extends StatelessWidget {
  const _TargetsSection({required this.targets});
  final List<Target> targets;

  @override
  Widget build(BuildContext context) {
    final sorted = [...targets]
      ..sort((a, b) => b.priority.compareTo(a.priority));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionHeader(
          label: 'NETWORK TARGETS',
          detail: '${targets.length} active',
        ),
        if (targets.isEmpty)
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text(
              'No active targets.',
              style: TextStyle(
                fontFamily: 'Geist',
                fontSize: 13,
                color: BSTheme.ink3,
              ),
            ),
          )
        else
          ...sorted.take(5).map((t) => _TargetRow(target: t)),
      ],
    );
  }
}

class _TargetRow extends StatelessWidget {
  const _TargetRow({required this.target});
  final Target target;

  @override
  Widget build(BuildContext context) {
    final p = target.priority.clamp(0.0, 1.0);
    final barColor = p > 0.7
        ? BSTheme.accent
        : p > 0.4
            ? BSTheme.warm
            : BSTheme.ink3;
    final typeLabel = target.targetType.isEmpty
        ? '—'
        : target.targetType.toUpperCase();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
      child: Row(
        children: [
          // Priority bar
          Column(
            children: [
              Container(
                width: 3,
                height: 28,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(2),
                  color: BSTheme.glassBorder,
                ),
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: FractionallySizedBox(
                    heightFactor: p,
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(2),
                        color: barColor,
                        boxShadow: [
                          BoxShadow(
                            color: barColor.withValues(alpha: 0.6),
                            blurRadius: 4,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: 12),
          // Name + type
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  target.name,
                  style: const TextStyle(
                    fontFamily: 'Geist',
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: BSTheme.ink,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  typeLabel,
                  style: const TextStyle(
                    fontFamily: 'Geist',
                    fontSize: 10,
                    letterSpacing: 0.8,
                    color: BSTheme.ink3,
                  ),
                ),
              ],
            ),
          ),
          // Measurement count
          Text(
            '${target.nMeasurements}',
            style: TextStyle(
              fontFamily: 'Geist',
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: barColor,
            ),
          ),
          const SizedBox(width: 4),
          const Text(
            'obs',
            style: TextStyle(
              fontFamily: 'Geist',
              fontSize: 10,
              color: BSTheme.ink3,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Alerts section ────────────────────────────────────────────────────────────

class _AlertsSection extends StatelessWidget {
  const _AlertsSection({required this.alerts});
  final List<AppNotification> alerts;

  @override
  Widget build(BuildContext context) {
    final unread = alerts.where((a) => !a.read).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionHeader(
          label: 'ALERTS',
          detail: unread > 0 ? '$unread unread' : 'all clear',
        ),
        if (alerts.isEmpty)
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text(
              'All quiet.',
              style: TextStyle(
                fontFamily: 'Geist',
                fontSize: 13,
                color: BSTheme.ink3,
              ),
            ),
          )
        else
          ...alerts.take(4).map((a) => _AlertRow(alert: a)),
      ],
    );
  }
}

class _AlertRow extends StatelessWidget {
  const _AlertRow({required this.alert});
  final AppNotification alert;

  @override
  Widget build(BuildContext context) {
    final unread = !alert.read;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
      child: Row(
        children: [
          // Unread dot
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: unread ? BSTheme.accent : Colors.transparent,
              border: Border.all(
                color: unread ? BSTheme.accent : BSTheme.ink3,
                width: 1,
              ),
              boxShadow: unread
                  ? [
                      BoxShadow(
                        color: BSTheme.accent.withValues(alpha: 0.5),
                        blurRadius: 4,
                      ),
                    ]
                  : null,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              alert.title,
              style: TextStyle(
                fontFamily: 'Geist',
                fontSize: 13,
                fontWeight: unread ? FontWeight.w500 : FontWeight.w400,
                color: unread ? BSTheme.ink : BSTheme.ink2,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            _ago(DateTime.tryParse(alert.sentAt)),
            style: const TextStyle(
              fontFamily: 'Geist',
              fontSize: 11,
              color: BSTheme.ink3,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Shared section header ─────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label, required this.detail});
  final String label;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Row(
        children: [
          Text(
            label,
            style: const TextStyle(
              fontFamily: 'Geist',
              fontSize: 9,
              fontWeight: FontWeight.w700,
              letterSpacing: 2.5,
              color: BSTheme.ink3,
            ),
          ),
          const Spacer(),
          Text(
            detail,
            style: const TextStyle(
              fontFamily: 'Geist',
              fontSize: 11,
              color: BSTheme.ink3,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Shared mini chip ──────────────────────────────────────────────────────────

class _MiniChip extends StatelessWidget {
  const _MiniChip(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(4),
        color: BSTheme.accent.withValues(alpha: 0.12),
        border: Border.all(color: BSTheme.accent.withValues(alpha: 0.3)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontFamily: 'Geist',
          fontSize: 9,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.6,
          color: BSTheme.accent,
        ),
      ),
    );
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

String _ago(DateTime? dt) {
  if (dt == null) return '';
  final diff = DateTime.now().difference(dt.toLocal());
  if (diff.inSeconds < 60) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  return DateFormat.MMMd().format(dt.toLocal());
}
