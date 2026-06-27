import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/glass.dart';
import 'target_detail_screen.dart';

/// "Tonight" — live mission-control dashboard. No scrolling: a hero stat band
/// over the Aladin sky, then an asymmetric two-column glass layout.
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
    required this.timeline,
    required this.targets,
    required this.alerts,
  });

  final List<Node> nodes;
  final List<Observation> recentObs;
  final List<TimelineItem> timeline;
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

    final nodesFuture = api.nodes().catchError((_) => <Node>[]);
    final obsFuture =
        api.observations(days: 1, limit: 10).catchError((_) => <Observation>[]);
    final timelineFuture = api.timeline().catchError((_) => <TimelineItem>[]);
    final targetsFuture = api.targets().catchError((_) => <Target>[]);
    final notifsFuture = api.notifications(limit: 5);

    List<AppNotification> alerts;
    var unread = 0;
    try {
      final notifs = await notifsFuture;
      alerts = notifs.$1;
      unread = notifs.$2;
    } catch (_) {
      alerts = [];
    }

    if (mounted) {
      context.read<AppState>().setUnreadNotifications(unread);
    }

    return _DashboardData(
      nodes: await nodesFuture,
      recentObs: await obsFuture,
      timeline: await timelineFuture,
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
                  ElevatedButton(onPressed: _refresh, child: const Text('Retry')),
                ],
              ),
            ),
          );
        }
        return _DashboardView(
          data: snap.data!,
          onRefresh: _refresh,
          onOpenAlerts: () => context.read<AppState>().setPendingTab(3),
        );
      },
    );
  }
}

// ── Dashboard view — staggered entrance ──────────────────────────────────────

class _DashboardView extends StatefulWidget {
  const _DashboardView({
    required this.data,
    required this.onRefresh,
    required this.onOpenAlerts,
  });
  final _DashboardData data;
  final Future<void> Function() onRefresh;
  final VoidCallback onOpenAlerts;

  @override
  State<_DashboardView> createState() => _DashboardViewState();
}

class _DashboardViewState extends State<_DashboardView> {
  static const _delays = [0, 180, 300, 420];
  final List<bool> _visible = [false, false, false, false];

  @override
  void initState() {
    super.initState();
    for (var i = 0; i < _delays.length; i++) {
      Future.delayed(Duration(milliseconds: _delays[i]), () {
        if (mounted) setState(() => _visible[i] = true);
      });
    }
  }

  Widget _fadeUp(int index, Widget child) {
    return AnimatedOpacity(
      opacity: _visible[index] ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 700),
      curve: Curves.easeOutCubic,
      child: AnimatedSlide(
        offset: _visible[index] ? Offset.zero : const Offset(0, 0.04),
        duration: const Duration(milliseconds: 700),
        curve: Curves.easeOutCubic,
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top + kToolbarHeight;
    final bottomPad = MediaQuery.of(context).padding.bottom + 64;
    final name = context.select<AppState, String>(
      (s) => s.member?.displayName ?? '',
    );

    final online = widget.data.nodes.where((n) => n.online).length;
    final unread = widget.data.alerts.where((a) => !a.read).length;

    return Padding(
      padding: EdgeInsets.fromLTRB(14, topPad + 6, 14, bottomPad),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _fadeUp(
            0,
            _Hero(
              name: name,
              online: online,
              totalNodes: widget.data.nodes.length,
              obs24h: widget.data.recentObs.length,
              targets: widget.data.targets.length,
              unread: unread,
              onAlertsTap: widget.onOpenAlerts,
            ),
          ),
          const SizedBox(height: 12),
          // Asymmetric two-column panel layout
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Left: activity — visual anchor with full-height sparkline
                Expanded(
                  flex: 55,
                  child: _fadeUp(
                    1,
                    _ActivityPanel(
                      obs: widget.data.recentObs,
                      timeline: widget.data.timeline,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // Right: targets + alerts stacked
                Expanded(
                  flex: 45,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        flex: 60,
                        child: _fadeUp(
                          2,
                          _TargetsPanel(targets: widget.data.targets),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        flex: 40,
                        child: _fadeUp(
                          3,
                          _AlertsPanel(
                            alerts: widget.data.alerts,
                            onOpenAlerts: widget.onOpenAlerts,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Hero: greeting + stat orbs ────────────────────────────────────────────────

class _Hero extends StatelessWidget {
  const _Hero({
    required this.name,
    required this.online,
    required this.totalNodes,
    required this.obs24h,
    required this.targets,
    required this.unread,
    required this.onAlertsTap,
  });

  final String name;
  final int online;
  final int totalNodes;
  final int obs24h;
  final int targets;
  final int unread;
  final VoidCallback onAlertsTap;

  String get _greeting {
    final h = DateTime.now().hour;
    if (h < 5) return 'Clear skies';
    if (h < 12) return 'Good morning';
    if (h < 18) return 'Good afternoon';
    return 'Good evening';
  }

  @override
  Widget build(BuildContext context) {
    final first = name.trim().split(' ').first;
    final allOnline = totalNodes > 0 && online == totalNodes;
    final networkColor = totalNodes == 0
        ? BSTheme.ink3
        : allOnline
            ? BSTheme.success
            : BSTheme.warm;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    first.isEmpty ? _greeting : '$_greeting, $first',
                    style: const TextStyle(
                      fontFamily: 'Geist',
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.8,
                      color: BSTheme.ink,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    DateFormat('EEEE • d MMM').format(DateTime.now()),
                    style: const TextStyle(
                      fontFamily: 'Geist',
                      fontSize: 12,
                      color: BSTheme.ink3,
                      letterSpacing: 0.2,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(100),
                color: networkColor.withValues(alpha: 0.12),
                border: Border.all(color: networkColor.withValues(alpha: 0.32)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  LiveDot(color: networkColor),
                  const SizedBox(width: 7),
                  Text(
                    totalNodes == 0 ? 'No telescopes' : '$online/$totalNodes live',
                    style: TextStyle(
                      fontFamily: 'Geist',
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.2,
                      color: networkColor,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: StatOrb(
                value: online,
                label: 'Online',
                color: BSTheme.success,
                icon: Icons.satellite_alt,
              ),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: StatOrb(
                value: obs24h,
                label: 'Obs 24h',
                color: BSTheme.accent,
                icon: Icons.auto_graph,
              ),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: StatOrb(
                value: targets,
                label: 'Targets',
                color: BSTheme.warm,
                icon: Icons.my_location,
              ),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: StatOrb(
                value: unread,
                label: 'Alerts',
                color: unread > 0 ? BSTheme.danger : BSTheme.ink3,
                icon: Icons.notifications_active,
                onTap: onAlertsTap,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ── Recent activity panel — sparkline + rows ──────────────────────────────────

class _ActivityPanel extends StatelessWidget {
  const _ActivityPanel({required this.obs, required this.timeline});
  final List<Observation> obs;
  final List<TimelineItem> timeline;

  @override
  Widget build(BuildContext context) {
    final spark = obs.reversed.map((o) => o.magnitude).toList();

    return GlassPanel(
      glow: BSTheme.accent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const GlassSectionHeader(
            icon: Icons.show_chart,
            label: 'RECENT ACTIVITY',
            detail: 'last 24 h',
          ),
          if (obs.isEmpty && timeline.isEmpty)
            const Expanded(child: _EmptyLine('No observations in the last 24 hours.'))
          else if (obs.isEmpty) ...[
            const SizedBox(height: 10),
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: timeline.take(6).map((t) => _TimelineRow(item: t)).toList(),
              ),
            ),
          ]
          else ...[
            const SizedBox(height: 10),
            // Full-height sparkline — dominant visual in the left column.
            Expanded(
              child: LayoutBuilder(
                builder: (_, constraints) => Sparkline(
                  values: spark,
                  color: BSTheme.accent,
                  height: constraints.maxHeight,
                ),
              ),
            ),
            const SizedBox(height: 8),
            ...obs
                .take(4)
                .map((o) => _ActivityRow(obs: o, onTap: () => _openTarget(context, o.targetName))),
          ],
        ],
      ),
    );
  }
}

class _TimelineRow extends StatelessWidget {
  const _TimelineRow({required this.item});
  final TimelineItem item;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          const Icon(Icons.schedule, size: 13, color: BSTheme.accent),
          const SizedBox(width: 8),
          SizedBox(
            width: 42,
            child: Text(
              item.startTime,
              style: const TextStyle(
                fontFamily: 'Geist',
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: BSTheme.accent,
              ),
            ),
          ),
          Expanded(
            child: Text(
              item.target,
              style: const TextStyle(
                fontFamily: 'Geist',
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: BSTheme.ink,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (item.filter.isNotEmpty) GlowChip(item.filter.toUpperCase()),
        ],
      ),
    );
  }
}

class _ActivityRow extends StatelessWidget {
  const _ActivityRow({required this.obs, this.onTap});
  final Observation obs;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final target = obs.targetName.isEmpty ? '—' : obs.targetName;
    final magColor = obs.magnitude < 8
        ? BSTheme.warm
        : obs.magnitude < 11
            ? BSTheme.accent
            : BSTheme.ink2;

    return _DashboardTapRow(onTap: onTap, child: Row(
        children: [
          Icon(Icons.star_rounded, size: 13, color: magColor),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              target,
              style: const TextStyle(
                fontFamily: 'Geist',
                fontSize: 12,
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
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.3,
              fontFeatures: const [FontFeature.tabularFigures()],
              color: magColor,
            ),
          ),
          if (obs.filter.isNotEmpty) ...[
            const SizedBox(width: 5),
            GlowChip(obs.filter.toUpperCase()),
          ],
          const SizedBox(width: 6),
          Text(
            _ago(DateTime.tryParse(obs.receivedAt)),
            style: const TextStyle(
              fontFamily: 'Geist',
              fontSize: 10,
              color: BSTheme.ink3,
            ),
          ),
        ],
      ));
  }
}

// ── Network targets panel ─────────────────────────────────────────────────────

class _TargetsPanel extends StatelessWidget {
  const _TargetsPanel({required this.targets});
  final List<Target> targets;

  @override
  Widget build(BuildContext context) {
    final sorted = [...targets]
      ..sort((a, b) => b.priority.compareTo(a.priority));

    return GlassPanel(
      glow: BSTheme.warm,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GlassSectionHeader(
            icon: Icons.my_location,
            label: 'NETWORK TARGETS',
            detail: '${targets.length} active',
            color: BSTheme.warm,
          ),
          if (targets.isEmpty)
            const Expanded(child: _EmptyLine('No active targets.'))
          else ...[
            const SizedBox(height: 6),
            Expanded(
              child: ClipRect(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: sorted
                      .take(4)
                      .map((t) => _TargetRow(
                            target: t,
                            onTap: () => _openTarget(context, t.name),
                          ))
                      .toList(),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _TargetRow extends StatelessWidget {
  const _TargetRow({required this.target, this.onTap});
  final Target target;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = target.priority.clamp(0.0, 1.0);
    final barColor = p > 0.7
        ? BSTheme.accent
        : p > 0.4
            ? BSTheme.warm
            : BSTheme.ink3;
    final typeLabel =
        target.targetType.isEmpty ? '—' : target.targetType.toUpperCase();

    return _DashboardTapRow(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  target.name,
                  style: const TextStyle(
                    fontFamily: 'Geist',
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: BSTheme.ink,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 6),
              GlowChip(typeLabel, color: barColor),
              const SizedBox(width: 6),
              Text(
                '${target.nMeasurements}',
                style: TextStyle(
                  fontFamily: 'Geist',
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.3,
                  fontFeatures: const [FontFeature.tabularFigures()],
                  color: barColor,
                ),
              ),
              const SizedBox(width: 3),
              const Text(
                'obs',
                style: TextStyle(
                    fontFamily: 'Geist', fontSize: 9, color: BSTheme.ink3),
              ),
            ],
          ),
          const SizedBox(height: 5),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: Stack(
              children: [
                Container(height: 3, color: BSTheme.glassBorder),
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: p),
                  duration: const Duration(milliseconds: 900),
                  curve: Curves.easeOutCubic,
                  builder: (_, v, __) => FractionallySizedBox(
                    widthFactor: v,
                    child: Container(
                      height: 3,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(2),
                        gradient: LinearGradient(
                          colors: [
                            barColor.withValues(alpha: 0.5),
                            barColor,
                          ],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: barColor.withValues(alpha: 0.6),
                            blurRadius: 6,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Alerts panel ──────────────────────────────────────────────────────────────

class _AlertsPanel extends StatelessWidget {
  const _AlertsPanel({required this.alerts, required this.onOpenAlerts});
  final List<AppNotification> alerts;
  final VoidCallback onOpenAlerts;

  @override
  Widget build(BuildContext context) {
    final unread = alerts.where((a) => !a.read).length;

    return GlassPanel(
      glow: unread > 0 ? BSTheme.danger : BSTheme.accent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GlassSectionHeader(
            icon: Icons.notifications_active,
            label: 'ALERTS',
            detail: unread > 0 ? '$unread unread' : 'all clear',
            color: unread > 0 ? BSTheme.danger : BSTheme.success,
          ),
          if (alerts.isEmpty)
            const Expanded(child: _EmptyLine('All quiet.'))
          else ...[
            const SizedBox(height: 6),
            Expanded(
              child: ClipRect(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children:
                      alerts
                          .take(3)
                          .map((a) => _AlertRow(alert: a, onTap: onOpenAlerts))
                          .toList(),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _AlertRow extends StatelessWidget {
  const _AlertRow({required this.alert, this.onTap});
  final AppNotification alert;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final unread = !alert.read;
    return _DashboardTapRow(onTap: onTap, child: Row(
        children: [
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
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              alert.title,
              style: TextStyle(
                fontFamily: 'Geist',
                fontSize: 12,
                fontWeight: unread ? FontWeight.w500 : FontWeight.w400,
                color: unread ? BSTheme.ink : BSTheme.ink2,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            _ago(DateTime.tryParse(alert.sentAt)),
            style: const TextStyle(
              fontFamily: 'Geist',
              fontSize: 10,
              color: BSTheme.ink3,
            ),
          ),
        ],
      ));
  }
}

// ── Small helpers ─────────────────────────────────────────────────────────────

void _openTarget(BuildContext context, String name) {
  if (name.isEmpty) return;
  Navigator.push(
    context,
    MaterialPageRoute<void>(
      builder: (_) => TargetDetailScreen(targetName: name),
    ),
  );
}

class _DashboardTapRow extends StatelessWidget {
  const _DashboardTapRow({
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.symmetric(vertical: 4.5),
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    if (onTap == null) {
      return Padding(padding: padding, child: child);
    }
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

class _EmptyLine extends StatelessWidget {
  const _EmptyLine(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Text(
        text,
        style: const TextStyle(
          fontFamily: 'Geist',
          fontSize: 13,
          color: BSTheme.ink3,
        ),
      ),
    );
  }
}

String _ago(DateTime? dt) {
  if (dt == null) return '';
  final diff = DateTime.now().difference(dt.toLocal());
  if (diff.inSeconds < 60) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  return DateFormat.MMMd().format(dt.toLocal());
}
