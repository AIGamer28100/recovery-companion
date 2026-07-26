import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/router/app_router.dart';
import '../../profile/domain/user_profile.dart';
import '../application/live_session_controller.dart';
import '../domain/live_session_status.dart';
import 'breathing_orb.dart';

/// The real, polished Live Call screen — voice-only for this milestone (M3).
/// Wires the M2 audio pipeline (`LiveSessionController`) to the crisis-screen
/// UI spec in `DESIGN.md` §1.3, as amended by
/// `UX_AND_CLINICAL_GROUNDING.md` §A.5/§A.6. Camera, the incident banner, and
/// Settings are explicitly out of scope — see the stubs below.
class LiveCallScreen extends ConsumerStatefulWidget {
  const LiveCallScreen({super.key});

  @override
  ConsumerState<LiveCallScreen> createState() => _LiveCallScreenState();
}

class _LiveCallScreenState extends ConsumerState<LiveCallScreen> {
  // Live captions are OFF by default (DESIGN.md §1.3) and, since there is no
  // Settings screen yet to persist a preference to, this is plain widget
  // state — resets to off every time the screen is reopened. Known
  // limitation, not a bug.
  bool _captionsOn = false;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(liveSessionControllerProvider);
    final controller = ref.read(liveSessionControllerProvider.notifier);
    final profile = ref.watch(appSessionProvider).valueOrNull?.profile;
    final theme = Theme.of(context);
    final reducedMotion = MediaQuery.of(context).disableAnimations;

    // A single confirmation pulse the instant the call connects (DESIGN.md
    // §1.4) — a state change the user must not miss even if they're not
    // looking at the screen.
    ref.listen<LiveSessionState>(liveSessionControllerProvider, (previous, next) {
      if (previous?.status != LiveSessionStatus.live && next.status == LiveSessionStatus.live) {
        HapticFeedback.lightImpact();
      }
    });

    final isConnectingOrLive =
        state.status == LiveSessionStatus.connecting || state.status == LiveSessionStatus.live;

    return PopScope<Object?>(
      // Never exit silently mid-conversation (DESIGN.md §1.2) — every other
      // screen lets back through untouched, but this one always asks first
      // while a call is connecting or live.
      canPop: !isConnectingOrLive,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop || !isConnectingOrLive) return;
        final shouldEnd = await _confirmEndCall(context);
        if (shouldEnd == true && context.mounted) {
          await controller.endCall();
          if (context.mounted) Navigator.of(context).maybePop();
        }
      },
      child: Scaffold(
        backgroundColor: theme.colorScheme.surface,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              children: [
                const SizedBox(height: 8),
                _TopBar(
                  isLive: state.status == LiveSessionStatus.live,
                  captionsOn: _captionsOn,
                  onToggleCaptions: () => setState(() => _captionsOn = !_captionsOn),
                ),
                const SizedBox(height: 4),
                Text('Soter Recovery', style: theme.textTheme.headlineSmall),
                const SizedBox(height: 12),
                _StateLine(state: state),
                Expanded(
                  child: Center(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: state.status == LiveSessionStatus.idle ? controller.startCall : null,
                      child: BreathingOrb(
                        phase: _phaseFor(state),
                        reducedMotion: reducedMotion,
                      ),
                    ),
                  ),
                ),
                if (_captionsOn && state.status == LiveSessionStatus.live)
                  _CaptionLines(lines: state.lines, style: theme.textTheme.bodyMedium),
                const SizedBox(height: 16),
                _HelpNowPill(contact: profile?.emergencyContact),
                const SizedBox(height: 12),
                _ControlRow(
                  status: state.status,
                  onStart: controller.startCall,
                  onEndCall: () async {
                    final shouldEnd = await _confirmEndCall(context);
                    if (shouldEnd == true) await controller.endCall();
                  },
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }

  OrbPhase _phaseFor(LiveSessionState state) {
    if (state.status != LiveSessionStatus.live) return OrbPhase.idle;
    return state.isModelSpeaking ? OrbPhase.speaking : OrbPhase.listening;
  }

  Future<bool?> _confirmEndCall(BuildContext context) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('End the conversation?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep talking'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('End call'),
          ),
        ],
      ),
    );
  }
}

/// Menu (Settings stub) top-left, captions toggle, and the "●LIVE" indicator
/// top-right — matches the wireframe row in DESIGN.md §1.3.
class _TopBar extends StatelessWidget {
  const _TopBar({required this.isLive, required this.captionsOn, required this.onToggleCaptions});

  final bool isLive;
  final bool captionsOn;
  final VoidCallback onToggleCaptions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      height: 56,
      child: Row(
        children: [
          // Placeholder only — there is no Settings screen yet. Kept as a
          // 56dp target so it's ready to wire up later without a layout
          // change.
          IconButton(
            iconSize: 24,
            constraints: const BoxConstraints(minWidth: 56, minHeight: 56),
            onPressed: () {},
            tooltip: 'Menu (coming soon)',
            icon: const Icon(Icons.menu),
          ),
          IconButton(
            iconSize: 22,
            constraints: const BoxConstraints(minWidth: 56, minHeight: 56),
            onPressed: onToggleCaptions,
            tooltip: captionsOn ? 'Hide captions' : 'Show captions',
            icon: Icon(captionsOn ? Icons.subtitles : Icons.subtitles_off_outlined),
          ),
          const Spacer(),
          if (isLive)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(color: theme.colorScheme.primary, shape: BoxShape.circle),
                ),
                const SizedBox(width: 6),
                Text(
                  'LIVE',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 2,
                  ),
                ),
              ],
            ),
          const SizedBox(width: 12),
        ],
      ),
    );
  }
}

/// The current-state line — always plain language, never a spinner-only
/// state (DESIGN.md §1.3), with the connecting copy pinned to concrete,
/// non-cheerful, non-clinical wording per §A.5.2.
class _StateLine extends StatelessWidget {
  const _StateLine({required this.state});

  final LiveSessionState state;

  @override
  Widget build(BuildContext context) {
    final text = switch (state.status) {
      LiveSessionStatus.idle => 'Tap to start talking. No typing, no forms — just talk.',
      LiveSessionStatus.connecting => 'Connecting…',
      LiveSessionStatus.live => "I'm listening. Cut in any time.",
      LiveSessionStatus.error => state.errorMessage ?? 'Something went wrong.',
    };
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: Theme.of(context)
            .textTheme
            .bodyMedium
            ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
      ),
    );
  }
}

/// The last ~2 lines of transcript, OFF by default and toggled via the top
/// bar. Body typography only, never the display font — captions must stay
/// legible precisely when legibility matters most (§A.5.4).
class _CaptionLines extends StatelessWidget {
  const _CaptionLines({required this.lines, required this.style});

  final List<TranscriptLine> lines;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    if (lines.isEmpty) return const SizedBox.shrink();
    final shown = lines.length > 2 ? lines.sublist(lines.length - 2) : lines;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final line in shown)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text(
                line.text,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: style,
              ),
            ),
        ],
      ),
    );
  }
}

/// Persistent, low-contrast pill above the control row — always present,
/// even mid-call (DESIGN.md §1.3). Opens a bottom sheet with the patient's
/// emergency contact and a real `tel:` link.
class _HelpNowPill extends StatelessWidget {
  const _HelpNowPill({required this.contact});

  final EmergencyContact? contact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      height: 44,
      child: TextButton.icon(
        onPressed: () => _showHelpSheet(context, contact),
        style: TextButton.styleFrom(foregroundColor: theme.colorScheme.onSurfaceVariant),
        icon: const Icon(Icons.arrow_upward, size: 16),
        label: const Text('Help now'),
      ),
    );
  }

  void _showHelpSheet(BuildContext context, EmergencyContact? contact) {
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Help now', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              if (contact != null) ...[
                Text(
                  'Your emergency contact is ${contact.name}.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () => _callNumber(contact.phone),
                    icon: const Icon(Icons.call),
                    label: Text('Call ${contact.name}'),
                  ),
                ),
              ] else ...[
                Text(
                  "No emergency contact is set up yet. If you're in immediate danger, "
                  'contact emergency services or a crisis line.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => _callNumber('112'),
                  icon: const Icon(Icons.local_hospital_outlined),
                  label: const Text('Call emergency services'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _callNumber(String phone) async {
    final uri = Uri(scheme: 'tel', path: phone);
    await launchUrl(uri);
  }
}

/// The control pill: camera toggle (stub, M4), end call (72dp, red, center —
/// hardest to hit by accident, easiest on purpose), overflow (stub). Mirrors
/// DESIGN.md §1.3's layout exactly.
class _ControlRow extends StatelessWidget {
  const _ControlRow({required this.status, required this.onStart, required this.onEndCall});

  final LiveSessionStatus status;
  final VoidCallback onStart;
  final Future<void> Function() onEndCall;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isLive = status == LiveSessionStatus.live || status == LiveSessionStatus.connecting;

    if (!isLive) {
      return SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          onPressed: onStart,
          icon: const Icon(Icons.mic),
          label: const Text('Start talking'),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(48),
        border: Border.all(color: theme.colorScheme.outline),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Camera is M4 — visually present, disabled, no-op.
          Tooltip(
            message: 'Coming soon',
            child: SizedBox(
              width: 56,
              height: 56,
              child: IconButton(
                onPressed: null,
                icon: const Icon(Icons.videocam_outlined),
              ),
            ),
          ),
          SizedBox(
            width: 72,
            height: 72,
            child: DecoratedBox(
              decoration: BoxDecoration(color: theme.colorScheme.error, shape: BoxShape.circle),
              child: IconButton(
                onPressed: onEndCall,
                tooltip: 'End conversation',
                icon: Icon(Icons.call_end, color: theme.colorScheme.onError),
              ),
            ),
          ),
          // Overflow — no-op stub for this milestone; nothing beyond camera
          // and end-call is a real action yet.
          SizedBox(
            width: 56,
            height: 56,
            child: IconButton(
              onPressed: () {},
              tooltip: 'More (coming soon)',
              icon: const Icon(Icons.more_horiz),
            ),
          ),
        ],
      ),
    );
  }
}
