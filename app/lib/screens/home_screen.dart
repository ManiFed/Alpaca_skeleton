import 'dart:ui';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/aladin_sky.dart';
import '../widgets/glass.dart' show GrainOverlay, LiveDot;
import 'dashboard_tab.dart';
import 'me_screen.dart';
import 'nodes_tab.dart';
import 'notifications_tab.dart';
import 'observations_tab.dart';

/// The signed-in shell: Aladin sky behind every tab, frosted-glass chrome.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _index = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final state = context.read<AppState>();
    if (state.pendingTab != null) {
      final tab = state.pendingTab!;
      state.pendingTab = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _index = tab);
      });
    }
  }

  static const _tabs = [
    (title: 'Tonight', icon: Icons.nightlight_outlined, sel: Icons.nightlight),
    (
      title: 'Telescopes',
      icon: Icons.satellite_alt_outlined,
      sel: Icons.satellite_alt
    ),
    (
      title: 'Observations',
      icon: Icons.show_chart_outlined,
      sel: Icons.show_chart
    ),
    (
      title: 'Alerts',
      icon: Icons.notifications_outlined,
      sel: Icons.notifications
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final name = context.select<AppState, String>(
      (s) => s.member?.displayName ?? '',
    );

    final pages = const [
      DashboardTab(),
      NodesTab(),
      ObservationsTab(),
      NotificationsTab(),
    ];

    return Stack(
      children: [
        // Live sky or painted glow background — shared by every tab.
        Positioned.fill(
          child: kIsWeb
              ? const AladinSky()
              : CustomPaint(painter: _NightGlowPainter()),
        ),
        // Dark veil — heavier than login so content stays readable.
        Positioned.fill(
          child: Container(color: const Color(0xBB000814)),
        ),
        // Film grain — organic texture over everything.
        const Positioned.fill(child: GrainOverlay()),
        Scaffold(
          backgroundColor: Colors.transparent,
          extendBodyBehindAppBar: true,
          extendBody: true,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            flexibleSpace: ClipRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                child: Container(
                  decoration: const BoxDecoration(
                    color: Color(0x1A060E1E),
                    border: Border(
                      bottom: BorderSide(color: BSTheme.glassBorder, width: 0.5),
                    ),
                  ),
                ),
              ),
            ),
            centerTitle: false,
            titleSpacing: 20,
            title: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const LiveDot(color: BSTheme.accent, size: 7),
                const SizedBox(width: 10),
                Text(
                  _tabs[_index].title,
                  style: const TextStyle(
                    fontFamily: 'Geist',
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.5,
                    color: BSTheme.ink,
                  ),
                ),
              ],
            ),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 16),
                child: PopupMenuButton<String>(
                  icon: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: BSTheme.glassBorder),
                      color: const Color(0x14A0B9FF),
                    ),
                    child: const Icon(
                      Icons.person_outline,
                      size: 17,
                      color: BSTheme.ink2,
                    ),
                  ),
                  tooltip: 'Account',
                  onSelected: (v) {
                    if (v == 'me') {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const MeScreen(),
                        ),
                      );
                    } else if (v == 'signout') {
                      context.read<AppState>().signOut();
                    }
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem<String>(
                      enabled: false,
                      child: Text(name.isEmpty ? 'Signed in' : name),
                    ),
                    const PopupMenuItem<String>(
                      value: 'me',
                      child: ListTile(
                        leading: Icon(Icons.person_outline),
                        title: Text('Me'),
                      ),
                    ),
                    const PopupMenuItem<String>(
                      value: 'signout',
                      child: ListTile(
                        leading: Icon(Icons.logout),
                        title: Text('Sign out'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          body: IndexedStack(index: _index, children: pages),
          bottomNavigationBar: ClipRect(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
              child: Container(
                decoration: const BoxDecoration(
                  color: Color(0x1A060E1E),
                  border: Border(
                    top: BorderSide(color: BSTheme.glassBorder, width: 0.5),
                  ),
                ),
                child: SafeArea(
                  top: false,
                  child: SizedBox(
                    height: 64,
                    child: Row(
                      children: List.generate(_tabs.length, (i) {
                        final selected = _index == i;
                        final tab = _tabs[i];
                        return Expanded(
                          child: GestureDetector(
                            onTap: () => setState(() => _index = i),
                            behavior: HitTestBehavior.opaque,
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              curve: Curves.easeOut,
                              margin: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                                color: selected
                                    ? BSTheme.accent.withValues(alpha: 0.14)
                                    : Colors.transparent,
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    selected ? tab.sel : tab.icon,
                                    color:
                                        selected ? BSTheme.accent : BSTheme.ink3,
                                    size: 20,
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    tab.title,
                                    style: TextStyle(
                                      fontFamily: 'Geist',
                                      fontSize: 10,
                                      fontWeight: FontWeight.w500,
                                      letterSpacing: 0.3,
                                      color: selected
                                          ? BSTheme.accent
                                          : BSTheme.ink3,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      }),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _NightGlowPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = RadialGradient(
          center: Alignment.topCenter,
          radius: 0.9,
          colors: [
            const Color(0xFF8FD9FF).withValues(alpha: 0.08),
            Colors.transparent,
          ],
        ).createShader(Offset.zero & size),
    );
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-1.0, 1.2),
          radius: 0.8,
          colors: [
            const Color(0xFFFFC07A).withValues(alpha: 0.05),
            Colors.transparent,
          ],
        ).createShader(Offset.zero & size),
    );
  }

  @override
  bool shouldRepaint(_NightGlowPainter old) => false;
}
