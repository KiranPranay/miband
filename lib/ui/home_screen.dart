import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/ble_manager.dart';
import 'settings_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final ble = context.watch<BLEManager>();

    return Scaffold(
      backgroundColor: const Color(0xFF0F0F1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F0F1A),
        elevation: 0,
        title: const Text(
          'Mi Band',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 22,
            color: Colors.white,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined, color: Colors.white70),
            tooltip: 'Settings',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Reconnecting banner ──────────────────────────────────────
            if (ble.isReconnecting) ...[
              _ReconnectBanner(),
              const SizedBox(height: 12),
            ],

            // ── Hero Steps Card ──────────────────────────────────────────
            _StepsHeroCard(ble: ble),

            const SizedBox(height: 14),

            // ── Metrics Row ──────────────────────────────────────────────
            Row(
              children: [
                Expanded(
                    child: _MetricCard(
                  icon: Icons.straighten_rounded,
                  label: 'Distance',
                  value: _fmtDistance(ble.metrics.distanceMeters),
                  color: const Color(0xFF00D2FF),
                  gradient: const [Color(0xFF003D4F), Color(0xFF001F2F)],
                )),
                const SizedBox(width: 12),
                Expanded(
                    child: _MetricCard(
                  icon: Icons.timer_outlined,
                  label: 'Active Time',
                  value: '—',
                  color: const Color(0xFFB47AEA),
                  gradient: const [Color(0xFF2D1B4E), Color(0xFF1A0F2E)],
                )),
              ],
            ),

            const SizedBox(height: 14),

            // ── Heart Rate Card ──────────────────────────────────────────
            _HeartRateCard(ble: ble),

            const SizedBox(height: 14),

            // ── Last Sync Info ───────────────────────────────────────────
            if (ble.lastSyncTime != null) _SyncFooter(time: ble.lastSyncTime!),
          ],
        ),
      ),
    );
  }

  String _fmtDistance(int meters) {
    if (meters >= 1000) {
      return '${(meters / 1000).toStringAsFixed(2)} km';
    }
    return '$meters m';
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// Reconnect Banner
// ──────────────────────────────────────────────────────────────────────────────

class _ReconnectBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.amber.shade900.withOpacity(0.4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.amber.shade700.withOpacity(0.5)),
      ),
      child: Row(
        children: [
          const SizedBox(
            width: 16,
            height: 16,
            child:
                CircularProgressIndicator(strokeWidth: 2, color: Colors.amber),
          ),
          const SizedBox(width: 12),
          const Text(
            'Reconnecting to band…',
            style: TextStyle(color: Colors.amber, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// Hero Steps Card
// ──────────────────────────────────────────────────────────────────────────────

class _StepsHeroCard extends StatelessWidget {
  final BLEManager ble;
  const _StepsHeroCard({required this.ble});

  @override
  Widget build(BuildContext context) {
    final steps = ble.metrics.steps;
    final calories = ble.metrics.calories;
    // Daily step goal
    const int goal = 10000;
    final double progress = (steps / goal).clamp(0.0, 1.0);

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF5B2FD4), Color(0xFF2A1070)],
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF5B2FD4).withOpacity(0.4),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header ──────────────────────────────────────────
            Row(
              children: [
                const Text(
                  'Steps Today',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0.5,
                  ),
                ),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    'Goal: ${_fmt(goal)}',
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 20),

            // ── Illustration + Steps ──────────────────────────────
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Walking figure illustration
                _WalkingIllustration(),
                const SizedBox(width: 20),
                // Steps value
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _fmtFull(steps),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 46,
                          fontWeight: FontWeight.w800,
                          height: 1.0,
                          letterSpacing: -1,
                        ),
                      ),
                      const Text(
                        'steps',
                        style: TextStyle(
                          color: Colors.white60,
                          fontSize: 16,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                      const SizedBox(height: 12),
                      // Calories row
                      Row(
                        children: [
                          const Icon(
                            Icons.local_fire_department_rounded,
                            color: Color(0xFFFF7043),
                            size: 18,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '$calories kcal',
                            style: const TextStyle(
                              color: Color(0xFFFF7043),
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 20),

            // ── Progress bar ──────────────────────────────────────
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '${(progress * 100).toStringAsFixed(0)}% of daily goal',
                      style: const TextStyle(
                        color: Colors.white60,
                        fontSize: 12,
                      ),
                    ),
                    Text(
                      '${_fmt(goal - steps > 0 ? goal - steps : 0)} to go',
                      style: const TextStyle(
                        color: Colors.white60,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 7,
                    backgroundColor: Colors.white.withOpacity(0.15),
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      Color(0xFFA78BFA),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _fmt(int n) {
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}k';
    return n.toString();
  }

  String _fmtFull(int n) {
    // Show full number with comma separators: 2128 → "2,128"
    final s = n.toString();
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    return buf.toString();
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// Walking Illustration (custom painted silhouette)
// ──────────────────────────────────────────────────────────────────────────────

class _WalkingIllustration extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 100,
      height: 110,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.08),
        borderRadius: BorderRadius.circular(20),
      ),
      child: CustomPaint(
        painter: _WalkerPainter(),
      ),
    );
  }
}

class _WalkerPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withOpacity(0.85)
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.fill;

    final cx = size.width / 2;

    // ── Head ──
    canvas.drawCircle(Offset(cx + 4, 18), 11, paint);

    // ── Body ──
    final bodyPath = Path()
      ..moveTo(cx + 4, 30)
      ..lineTo(cx + 2, 58);
    canvas.drawPath(
      bodyPath,
      Paint()
        ..color = Colors.white.withOpacity(0.85)
        ..strokeWidth = 7
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke,
    );

    // ── Left arm (back, swinging forward) ──
    final leftArm = Path()
      ..moveTo(cx + 4, 38)
      ..quadraticBezierTo(cx - 12, 50, cx - 16, 58);
    canvas.drawPath(
      leftArm,
      Paint()
        ..color = Colors.white.withOpacity(0.85)
        ..strokeWidth = 5.5
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke,
    );

    // ── Right arm (forward) ──
    final rightArm = Path()
      ..moveTo(cx + 4, 38)
      ..quadraticBezierTo(cx + 18, 46, cx + 22, 56);
    canvas.drawPath(
      rightArm,
      Paint()
        ..color = Colors.white.withOpacity(0.85)
        ..strokeWidth = 5.5
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke,
    );

    // ── Left leg (forward stride) ──
    final leftLeg = Path()
      ..moveTo(cx + 2, 58)
      ..quadraticBezierTo(cx - 6, 78, cx - 18, 92);
    canvas.drawPath(
      leftLeg,
      Paint()
        ..color = Colors.white.withOpacity(0.85)
        ..strokeWidth = 6
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke,
    );
    // foot
    final leftFoot = Path()
      ..moveTo(cx - 18, 92)
      ..lineTo(cx - 26, 92);
    canvas.drawPath(
      leftFoot,
      Paint()
        ..color = Colors.white.withOpacity(0.85)
        ..strokeWidth = 5
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke,
    );

    // ── Right leg (back stride) ──
    final rightLeg = Path()
      ..moveTo(cx + 2, 58)
      ..quadraticBezierTo(cx + 10, 78, cx + 16, 92);
    canvas.drawPath(
      rightLeg,
      Paint()
        ..color = Colors.white.withOpacity(0.85)
        ..strokeWidth = 6
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke,
    );
    // foot
    final rightFoot = Path()
      ..moveTo(cx + 16, 92)
      ..lineTo(cx + 24, 88);
    canvas.drawPath(
      rightFoot,
      Paint()
        ..color = Colors.white.withOpacity(0.85)
        ..strokeWidth = 5
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke,
    );

    // ── Motion lines ──
    final dotPaint = Paint()
      ..color = Colors.white.withOpacity(0.3)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    for (int i = 0; i < 3; i++) {
      canvas.drawLine(
        Offset(cx - 28 - i * 6.0, 55 + i * 8.0),
        Offset(cx - 34 - i * 6.0, 55 + i * 8.0),
        dotPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ──────────────────────────────────────────────────────────────────────────────
// Generic Metric Card (Distance, Active Time, etc.)
// ──────────────────────────────────────────────────────────────────────────────

class _MetricCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final List<Color> gradient;

  const _MetricCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    required this.gradient,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: gradient,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 26),
          const SizedBox(height: 14),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 22,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white54,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// Heart Rate Card
// ──────────────────────────────────────────────────────────────────────────────

class _HeartRateCard extends StatelessWidget {
  final BLEManager ble;
  const _HeartRateCard({required this.ble});

  @override
  Widget build(BuildContext context) {
    // HR is currently firmware-locked on Mi Band 6 — shows '— bpm' as placeholder.
    // If a working protocol is found, live data will appear automatically.
    final heartRate = ble.heartRate;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF4A1025), Color(0xFF1F0510)],
        ),
      ),
      child: Row(
        children: [
          // Animated-ish heart icon
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: const Color(0xFFFF4060).withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.favorite_rounded,
              color: Color(0xFFFF4060),
              size: 28,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Heart Rate',
                  style: TextStyle(
                    color: Colors.white54,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                heartRate != null
                    ? RichText(
                        text: TextSpan(
                          children: [
                            TextSpan(
                              text: '$heartRate',
                              style: const TextStyle(
                                color: Color(0xFFFF4060),
                                fontSize: 32,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const TextSpan(
                              text: '  bpm',
                              style: TextStyle(
                                color: Colors.white54,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      )
                    : const Text(
                        '— bpm',
                        style: TextStyle(
                          color: Color(0xFFFF4060),
                          fontSize: 28,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
              ],
            ),
          ),
          // EKG-style wave decoration
          CustomPaint(
            size: const Size(60, 40),
            painter: _EKGPainter(),
          ),
        ],
      ),
    );
  }
}

// Simple EKG wave decoration
class _EKGPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFFF4060).withOpacity(0.5)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final path = Path();
    path.moveTo(0, size.height * 0.5);
    path.lineTo(size.width * 0.2, size.height * 0.5);
    path.lineTo(size.width * 0.3, size.height * 0.15);
    path.lineTo(size.width * 0.4, size.height * 0.85);
    path.lineTo(size.width * 0.55, size.height * 0.05);
    path.lineTo(size.width * 0.65, size.height * 0.9);
    path.lineTo(size.width * 0.75, size.height * 0.5);
    path.lineTo(size.width, size.height * 0.5);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ──────────────────────────────────────────────────────────────────────────────
// Last Sync Footer
// ──────────────────────────────────────────────────────────────────────────────

class _SyncFooter extends StatelessWidget {
  final DateTime time;
  const _SyncFooter({required this.time});

  String _ago() {
    final diff = DateTime.now().difference(time);
    if (diff.inSeconds < 60) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.sync, size: 12, color: Colors.white30),
          const SizedBox(width: 4),
          Text(
            'Last synced ${_ago()}',
            style: const TextStyle(color: Colors.white30, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
