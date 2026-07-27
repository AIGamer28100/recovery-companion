import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/router/app_router.dart';
import '../../../platform/camera/live_camera_stream.dart';
import '../../auth/application/auth_controller.dart';
import '../../profile/domain/user_profile.dart';
import '../application/live_session_controller.dart';
import '../domain/live_session_status.dart';
import '../domain/relapse_stage.dart';
import 'breathing_orb.dart';

/// The real, polished Live Call screen (M3, extended with camera + the
/// safety-tool incident banner in M4/M5). Wires the audio pipeline and
/// camera stream (`LiveSessionController`) to the crisis-screen UI spec in
/// `DESIGN.md` §1.3, as amended by `UX_AND_CLINICAL_GROUNDING.md` §A.5/§A.6.
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
      // A camera failure (e.g. permission blocked) must never look like the
      // call itself broke — surfaced as a one-shot snackbar, not the full
      // error state.
      final cameraError = next.cameraErrorMessage;
      if (cameraError != null && cameraError != previous?.cameraErrorMessage) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(cameraError)));
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
        body: Stack(
          children: [
            // Camera preview fills the screen when on, mirrored like a
            // selfie view (DESIGN.md §1.3) — sits behind everything else.
            if (state.cameraOn && controller.cameraController != null)
              Positioned.fill(
                child: Transform.flip(
                  flipX: true,
                  child: FittedBox(
                    fit: BoxFit.cover,
                    child: SizedBox(
                      width: controller.cameraController!.value.previewSize?.height ?? 1,
                      height: controller.cameraController!.value.previewSize?.width ?? 1,
                      child: LiveCameraPreview(controller: controller.cameraController!),
                    ),
                  ),
                ),
              ),
            // Scrim keeps text/controls legible over a live camera feed.
            if (state.cameraOn)
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        theme.colorScheme.surface.withValues(alpha: 0.55),
                        theme.colorScheme.surface.withValues(alpha: 0.15),
                        theme.colorScheme.surface.withValues(alpha: 0.75),
                      ],
                    ),
                  ),
                ),
              ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                // Found on a real device: rotating to landscape shrinks
                // available height far more than width, and the fixed-height
                // children below (top bar, headline, state line, captions,
                // incident banner, help pill, control row) could already
                // exceed that height on their own -- the single `Expanded`
                // orb region used to be the only flex to absorb it, which
                // just produced a hard `RenderFlex overflowed` error instead.
                // `LayoutBuilder` + `SingleChildScrollView` lets the same
                // content scroll on a too-short viewport rather than
                // overflow; `Expanded` is gone since a scrollable Column
                // can't give it the bounded height it requires, replaced
                // with fixed spacing around the (fixed-size) orb.
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    return SingleChildScrollView(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(minHeight: constraints.maxHeight),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const SizedBox(height: 8),
                            _TopBar(
                              isLive: state.status == LiveSessionStatus.live,
                              cameraOn: state.cameraOn,
                              reducedMotion: reducedMotion,
                              captionsOn: _captionsOn,
                              onToggleCaptions: () => setState(() => _captionsOn = !_captionsOn),
                              onOpenMenu: () => _openMenu(context),
                            ),
                            const SizedBox(height: 4),
                            Text('Soter Recovery', style: theme.textTheme.headlineSmall),
                            const SizedBox(height: 12),
                            _StateLine(state: state),
                            const SizedBox(height: 12),
                            Center(
                              child: AnimatedOpacity(
                                // The orb fades out entirely rather than floating
                                // over the person's own camera view (DESIGN.md
                                // §1.3, ported from `ReactiveOrb`'s `cameraOn`
                                // collapse) — never just dimmed, since a
                                // half-visible orb over a small screen's frame
                                // still covers real content.
                                opacity: state.cameraOn ? 0.0 : 1.0,
                                duration: const Duration(milliseconds: 700),
                                child: IgnorePointer(
                                  ignoring: state.cameraOn,
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
                            ),
                            const SizedBox(height: 12),
                            if (_captionsOn && state.status == LiveSessionStatus.live)
                              _CaptionLines(lines: state.lines, style: theme.textTheme.bodyMedium),
                            if (state.incidentStage != null)
                              _IncidentBanner(
                                stage: state.incidentStage!,
                                onDismiss: controller.dismissIncident,
                              ),
                            const SizedBox(height: 16),
                            _HelpNowPill(contact: profile?.emergencyContact),
                            const SizedBox(height: 12),
                            _ControlRow(
                              status: state.status,
                              cameraOn: state.cameraOn,
                              onStart: controller.startCall,
                              onToggleCamera: controller.toggleCamera,
                              onEndCall: () async {
                                final shouldEnd = await _confirmEndCall(context);
                                if (shouldEnd == true) await controller.endCall();
                              },
                            ),
                            const SizedBox(height: 16),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
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

  // A patient's Live Call screen is now their home screen (no separate
  // HomeScreen in between), so sign-out — previously only reachable from
  // that screen — needs a home here. A minimal bottom sheet rather than a
  // real Settings screen, which doesn't exist yet.
  void _openMenu(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.logout),
              title: const Text('Sign out'),
              onTap: () async {
                Navigator.of(sheetContext).pop();
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (dialogContext) => AlertDialog(
                    title: const Text('Sign out?'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(dialogContext).pop(false),
                        child: const Text('Cancel'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.of(dialogContext).pop(true),
                        child: const Text('Sign out'),
                      ),
                    ],
                  ),
                );
                if (confirmed == true) {
                  await ref.read(authControllerProvider.notifier).signOut();
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// Menu (Settings stub) top-left, captions toggle, the "●LIVE" indicator,
/// and — while the camera streams — the recording affordance, top-right.
/// Matches the wireframe row in DESIGN.md §1.3.
class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.isLive,
    required this.cameraOn,
    required this.reducedMotion,
    required this.captionsOn,
    required this.onToggleCaptions,
    required this.onOpenMenu,
  });

  final bool isLive;
  final bool cameraOn;
  final bool reducedMotion;
  final bool captionsOn;
  final VoidCallback onToggleCaptions;
  final VoidCallback onOpenMenu;

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
            onPressed: onOpenMenu,
            tooltip: 'Menu',
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
          // A live-recording affordance stays visible for the entire time
          // the camera streams (DESIGN.md §4.3/§4.4) — non-negotiable given
          // the privacy surface, and doubles as the in-app answer to "is
          // this actually still recording".
          if (cameraOn) ...[
            _CameraRecordingIndicator(reducedMotion: reducedMotion),
            const SizedBox(width: 12),
          ],
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

/// Small pulsing red dot + "camera on" label — the second, in-app layer of
/// recording disclosure beyond the OS's own camera-in-use indicator
/// (DESIGN.md §4.4). Reduced-motion users get a static dot instead of a
/// pulse; the disclosure itself is never optional.
class _CameraRecordingIndicator extends StatefulWidget {
  const _CameraRecordingIndicator({required this.reducedMotion});

  final bool reducedMotion;

  @override
  State<_CameraRecordingIndicator> createState() => _CameraRecordingIndicatorState();
}

class _CameraRecordingIndicatorState extends State<_CameraRecordingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
    if (!widget.reducedMotion) _pulse.repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const red = Colors.red;
    final dot = Container(
      width: 8,
      height: 8,
      decoration: const BoxDecoration(color: red, shape: BoxShape.circle),
    );
    return Semantics(
      label: 'Camera on. Recording indicator.',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          widget.reducedMotion
              ? dot
              : FadeTransition(
                  opacity: Tween<double>(begin: 0.35, end: 1.0).animate(_pulse),
                  child: dot,
                ),
          const SizedBox(width: 6),
          Text('camera on', style: theme.textTheme.labelSmall?.copyWith(color: red)),
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
      LiveSessionStatus.live =>
        state.cameraOn ? "I'm listening and watching. Cut in any time." : "I'm listening. Cut in any time.",
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

/// Slides up from above the control pill on a `flagRelapseRisk` disclosure —
/// exactly where the web puts it (`LiveApp.tsx`'s incident block), same copy.
/// **Difference from web** (DESIGN.md §1.3): on `stage == escalated` this is
/// non-dismissible for 5 seconds and paired with a single medium-strength
/// haptic pulse, so the person actually registers "my caregiver was told"
/// rather than reflexively tapping it away. On `stage == intervening` it
/// behaves like the web: dismissible immediately, no haptic.
class _IncidentBanner extends StatefulWidget {
  const _IncidentBanner({required this.stage, required this.onDismiss});

  final RelapseStage stage;
  final VoidCallback onDismiss;

  @override
  State<_IncidentBanner> createState() => _IncidentBannerState();
}

class _IncidentBannerState extends State<_IncidentBanner> {
  bool _canDismiss = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _arm();
  }

  @override
  void didUpdateWidget(covariant _IncidentBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.stage != widget.stage) _arm();
  }

  void _arm() {
    _timer?.cancel();
    if (widget.stage == RelapseStage.escalated) {
      _canDismiss = false;
      // A state change the user must not miss even if they're not looking
      // at the screen (DESIGN.md §1.4) — a single pulse, not a startle buzz.
      HapticFeedback.mediumImpact();
      _timer = Timer(const Duration(seconds: 5), () {
        if (mounted) setState(() => _canDismiss = true);
      });
    } else {
      _canDismiss = true;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final escalated = widget.stage == RelapseStage.escalated;
    final onColor = escalated ? theme.colorScheme.onErrorContainer : theme.colorScheme.onSecondaryContainer;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: escalated ? theme.colorScheme.errorContainer : theme.colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Semantics(
        liveRegion: true,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: RichText(
                text: TextSpan(
                  style: theme.textTheme.bodyMedium?.copyWith(color: onColor),
                  children: [
                    TextSpan(
                      text: escalated
                          ? 'A note was saved for your caregiver to see next time they open their dashboard. '
                          : 'Snapshot saved to your record. ',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    TextSpan(
                      text: escalated
                          ? 'A snapshot was saved to your record too.'
                          : 'Nobody else has been contacted.',
                    ),
                  ],
                ),
              ),
            ),
            if (_canDismiss)
              TextButton(
                onPressed: widget.onDismiss,
                style: TextButton.styleFrom(foregroundColor: onColor),
                child: const Text('Dismiss'),
              ),
          ],
        ),
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

/// The control pill: camera toggle (56dp), end call (72dp, red, center —
/// hardest to hit by accident, easiest on purpose), overflow (stub). Mirrors
/// DESIGN.md §1.3's layout exactly.
class _ControlRow extends StatelessWidget {
  const _ControlRow({
    required this.status,
    required this.cameraOn,
    required this.onStart,
    required this.onToggleCamera,
    required this.onEndCall,
  });

  final LiveSessionStatus status;
  final bool cameraOn;
  final VoidCallback onStart;
  final Future<void> Function() onToggleCamera;
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
          // Camera is opt-in every session, never remembered (DESIGN.md
          // §4.4) — this toggle is the only way it ever turns on.
          SizedBox(
            width: 56,
            height: 56,
            child: IconButton(
              onPressed: status == LiveSessionStatus.live ? () => onToggleCamera() : null,
              tooltip: cameraOn ? 'Turn camera off' : 'Turn camera on',
              icon: Icon(cameraOn ? Icons.videocam : Icons.videocam_outlined),
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
