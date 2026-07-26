import 'package:flutter/material.dart';

/// The three states the orb can be in, per `DESIGN.md` §1.3/§1.4 and
/// `UX_AND_CLINICAL_GROUNDING.md` §A.5.1/§A.5.3. `idle` covers both the
/// pre-connection resting state and `connecting` — the amendment's own
/// parenthetical ("idle, pre-connection") treats those as one tier, distinct
/// from the in-call listening/speaking split.
enum OrbPhase { idle, listening, speaking }

/// The breathing orb at the center of the Live Call screen. Speed and
/// amplitude are driven by [phase], strictly ordered idle ≤ listening ≤
/// speaking by perceived calm — an invariant per §A.5.1, not just a default,
/// so it's kept explicit here rather than derived from arbitrary tunable
/// numbers elsewhere.
///
/// [reducedMotion] (wired from `MediaQuery.of(context).disableAnimations`)
/// collapses all three phases to the exact same static glow — no partial
/// distinction survives — per §A.6.2.
class BreathingOrb extends StatefulWidget {
  const BreathingOrb({super.key, required this.phase, required this.reducedMotion});

  final OrbPhase phase;
  final bool reducedMotion;

  @override
  State<BreathingOrb> createState() => _BreathingOrbState();
}

class _BreathingOrbState extends State<BreathingOrb> with SingleTickerProviderStateMixin {
  // Strictly increasing speed (decreasing duration) idle -> listening ->
  // speaking, per the calmness-ordering invariant. Curves are ease-in-out
  // only, matching DESIGN.md §1.4's explicit rejection of springy/bouncy
  // motion.
  static const _idleDuration = Duration(milliseconds: 4400);
  static const _listeningDuration = Duration(milliseconds: 2600);
  static const _speakingDuration = Duration(milliseconds: 1300);

  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: _durationFor(widget.phase));
    if (!widget.reducedMotion) _controller.repeat(reverse: true);
  }

  Duration _durationFor(OrbPhase phase) => switch (phase) {
        OrbPhase.idle => _idleDuration,
        OrbPhase.listening => _listeningDuration,
        OrbPhase.speaking => _speakingDuration,
      };

  @override
  void didUpdateWidget(covariant BreathingOrb oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.reducedMotion) {
      _controller.stop();
      return;
    }
    if (oldWidget.phase != widget.phase) {
      // Same-frame shape shift is handled by the phase value feeding the
      // painter directly (see build) — retuning the loop's duration here
      // only affects the ongoing breathing cadence, not the instantaneous
      // shape, so a barge-in's visible acknowledgment (§A.5.3) isn't waiting
      // on this to take effect.
      _controller.duration = _durationFor(widget.phase);
    }
    if (oldWidget.reducedMotion && !widget.reducedMotion) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  double _amplitudeFor(OrbPhase phase) => switch (phase) {
        OrbPhase.idle => 0.025,
        OrbPhase.listening => 0.06,
        // Even at its busiest the orb should read as *present*, not
        // *excited* (§A.5.1) — kept modest rather than a dramatic swing.
        OrbPhase.speaking => 0.12,
      };

  double _glowFor(OrbPhase phase) => switch (phase) {
        OrbPhase.idle => 0.28,
        OrbPhase.listening => 0.4,
        OrbPhase.speaking => 0.55,
      };

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;

    if (widget.reducedMotion) {
      // Collapses idle/listening/speaking to the identical static glow — no
      // residual distinction, per §A.6.2.
      return _OrbGlow(scale: 1.0, glowOpacity: 0.35, color: color);
    }

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = Curves.easeInOut.transform(_controller.value);
        final amplitude = _amplitudeFor(widget.phase);
        final glowBase = _glowFor(widget.phase);
        return _OrbGlow(
          scale: 1.0 + amplitude * t,
          glowOpacity: glowBase + (0.15 * t),
          color: color,
        );
      },
    );
  }
}

class _OrbGlow extends StatelessWidget {
  const _OrbGlow({required this.scale, required this.glowOpacity, required this.color});

  final double scale;
  final double glowOpacity;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 220,
      height: 220,
      child: Center(
        child: Transform.scale(
          scale: scale,
          child: Container(
            width: 140,
            height: 140,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  color.withValues(alpha: 0.95),
                  color.withValues(alpha: 0.6),
                ],
              ),
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: glowOpacity.clamp(0.0, 1.0)),
                  blurRadius: 70,
                  spreadRadius: 18,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
