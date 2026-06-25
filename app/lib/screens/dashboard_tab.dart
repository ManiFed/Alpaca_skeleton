import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/async_view.dart';

/// "Tonight" overview: cinematic hero stat + network summary.
class DashboardTab extends StatefulWidget {
  const DashboardTab({super.key});

  @override
  State<DashboardTab> createState() => _DashboardTabState();
}

class _DashboardTabState extends State<DashboardTab> {
  late Future<MemberStats> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<MemberStats> _load() {
    final state = context.read<AppState>();
    return state.api.stats().catchError((e) {
      state.handleAuthError(e);
      throw e;
    });
  }

  Future<void> _refresh() async => setState(() => _future = _load());

  @override
  Widget build(BuildContext context) {
    final name = context.select<AppState, String>(
      (s) => s.member?.displayName ?? 'stargazer',
    );
    final top = MediaQuery.of(context).padding.top + kToolbarHeight;
    final bottom = MediaQuery.of(context).padding.bottom + 64;

    return AsyncView<MemberStats>(
      future: _future,
      onRefresh: _refresh,
      builder: (context, stats) => ListView(
        padding: EdgeInsets.fromLTRB(0, top, 0, bottom + 16),
        children: [
          _HeroSection(name: name, stats: stats),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: _MetricsRow(stats: stats),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _NetworkCard(nodeCount: stats.nodeCount),
          ),
        ],
      ),
    );
  }
}

// ── Hero ──────────────────────────────────────────────────────────────────────

class _HeroSection extends StatelessWidget {
  const _HeroSection({required this.name, required this.stats});
  final String name;
  final MemberStats stats;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 28),
      child: Column(
        children: [
          const Text(
            'THE TELESCOPE NET · LIVE',
            style: TextStyle(
              fontFamily: 'Geist',
              fontSize: 9,
              fontWeight: FontWeight.w600,
              letterSpacing: 3.2,
              color: BSTheme.accent,
            ),
          ),
          const SizedBox(height: 28),
          _ObservationDial(count: stats.totalObservations),
          const SizedBox(height: 28),
          Text(
            'Good evening, $name.',
            style: const TextStyle(
              fontFamily: 'Geist',
              fontSize: 26,
              fontWeight: FontWeight.w600,
              letterSpacing: -1.2,
              color: BSTheme.ink,
              height: 1.1,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            stats.nodeCount == 0
                ? 'Connect a telescope to start contributing\nto real science.'
                : 'Your telescopes are gathering real\nmeasurements for astronomers worldwide.',
            style: const TextStyle(
              fontFamily: 'Geist',
              fontSize: 14,
              color: BSTheme.ink2,
              height: 1.55,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

// ── Observation dial ──────────────────────────────────────────────────────────

class _ObservationDial extends StatefulWidget {
  const _ObservationDial({required this.count});
  final int count;

  @override
  State<_ObservationDial> createState() => _ObservationDialState();
}

class _ObservationDialState extends State<_ObservationDial>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat(reverse: true);
    _pulse = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _pulse,
      builder: (_, __) => SizedBox(
        width: 200,
        height: 200,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Outer ambient glow
            Container(
              width: 200,
              height: 200,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    BSTheme.accent.withValues(alpha: _pulse.value * 0.12),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
            // Outer ring — breathes
            Container(
              width: 172,
              height: 172,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: BSTheme.accent
                      .withValues(alpha: 0.12 + _pulse.value * 0.12),
                  width: 1,
                ),
              ),
            ),
            // Inner ring — brighter
            Container(
              width: 132,
              height: 132,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: BSTheme.accent
                      .withValues(alpha: 0.28 + _pulse.value * 0.18),
                  width: 1,
                ),
                gradient: RadialGradient(
                  colors: [
                    BSTheme.accent
                        .withValues(alpha: 0.04 + _pulse.value * 0.06),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
            // Count + label
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${widget.count}',
                  style: const TextStyle(
                    fontFamily: 'Geist',
                    fontSize: 52,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -3.5,
                    color: BSTheme.ink,
                    height: 1.0,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'OBSERVATIONS',
                  style: TextStyle(
                    fontFamily: 'Geist',
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 2.5,
                    color: BSTheme.ink3,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Metrics row ───────────────────────────────────────────────────────────────

class _MetricsRow extends StatelessWidget {
  const _MetricsRow({required this.stats});
  final MemberStats stats;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            const Expanded(child: Divider(color: BSTheme.glassBorder)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                'NETWORK METRICS',
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ),
            const Expanded(child: Divider(color: BSTheme.glassBorder)),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _MetricTile(
                label: 'To AAVSO',
                value: '${stats.aavsoSubmitted}',
                icon: Icons.send_rounded,
                color: const Color(0xFF7DA9FF),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _MetricTile(
                label: 'Stars',
                value: '${stats.targetsObserved}',
                icon: Icons.star_rounded,
                color: const Color(0xFFFFC857),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _MetricTile(
                label: 'Clear nights',
                value: '${stats.clearNights}',
                icon: Icons.nights_stay_rounded,
                color: BSTheme.warm,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$value $label',
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 14, 12, 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: BSTheme.glassBg,
          border: Border.all(color: BSTheme.glassBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 15),
            const SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(
                fontFamily: 'Geist',
                fontSize: 28,
                fontWeight: FontWeight.w800,
                letterSpacing: -1.5,
                color: color,
                height: 1.0,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              label,
              style: Theme.of(context).textTheme.bodySmall,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Network card ──────────────────────────────────────────────────────────────

class _NetworkCard extends StatelessWidget {
  const _NetworkCard({required this.nodeCount});
  final int nodeCount;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: BSTheme.glassBg,
        border: Border.all(color: BSTheme.glassBorder),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: BSTheme.success.withValues(alpha: 0.12),
              border: Border.all(color: BSTheme.success.withValues(alpha: 0.3)),
            ),
            child: const Icon(
              Icons.satellite_alt,
              size: 20,
              color: BSTheme.success,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$nodeCount telescope${nodeCount == 1 ? '' : 's'} connected',
                  style: const TextStyle(
                    fontFamily: 'Geist',
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.3,
                    color: BSTheme.ink,
                  ),
                ),
                const SizedBox(height: 2),
                const Text(
                  'Tap Telescopes to manage your network',
                  style: TextStyle(
                    fontFamily: 'Geist',
                    fontSize: 12,
                    color: BSTheme.ink3,
                  ),
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right, color: BSTheme.ink3, size: 18),
        ],
      ),
    );
  }
}
