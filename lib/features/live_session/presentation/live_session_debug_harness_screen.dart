import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/live_session_controller.dart';
import '../domain/live_session_status.dart';

/// A scratch harness for manually exercising the audio pipeline end to end
/// (mic -> Live session -> playback, barge-in, focus handling) without the
/// polished crisis-screen UI from DESIGN.md §1.3, which is a separate
/// milestone. Deliberately plain and only reachable via a debug-only route
/// (see `core/router/app_router.dart`) — this is not part of the real app's
/// navigation.
class LiveSessionDebugHarnessScreen extends ConsumerWidget {
  const LiveSessionDebugHarnessScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(liveSessionControllerProvider);
    final controller = ref.read(liveSessionControllerProvider.notifier);
    final isLive = state.status == LiveSessionStatus.live ||
        state.status == LiveSessionStatus.connecting;

    return Scaffold(
      appBar: AppBar(title: const Text('Live audio pipeline (debug harness)')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Status: ${state.status.name}', style: Theme.of(context).textTheme.titleMedium),
            if (state.errorMessage != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(state.errorMessage!, style: const TextStyle(color: Colors.red)),
              ),
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('Echo cancellation: ${state.echoCancellationAvailability.name}'),
            ),
            if (state.echoCancellationAvailability == EchoCancellationAvailability.unavailable)
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text(
                  'No hardware echo cancellation on this device — mic mutes '
                  'during model playback instead of true barge-in.',
                  style: TextStyle(fontStyle: FontStyle.italic),
                ),
              ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: isLive ? controller.endCall : controller.startCall,
              child: Text(isLive ? 'End call' : 'Start talking'),
            ),
            if (state.incidentStage != null)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Row(
                  children: [
                    Expanded(child: Text('Incident flagged: ${state.incidentStage!.name}')),
                    TextButton(
                      onPressed: controller.dismissIncident,
                      child: const Text('Dismiss'),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 16),
            const Text('Transcript', style: TextStyle(fontWeight: FontWeight.bold)),
            Expanded(
              child: ListView.builder(
                itemCount: state.lines.length,
                itemBuilder: (context, index) {
                  final line = state.lines[index];
                  return Text('${line.fromUser ? 'You' : 'Companion'}: ${line.text}');
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
