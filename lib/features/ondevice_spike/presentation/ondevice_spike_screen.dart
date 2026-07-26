import 'package:flutter/material.dart';

import '../application/ondevice_spike_controller.dart';

/// Minimal, standalone UI for the on-device Gemma 4 feasibility spike.
///
/// Not reachable from the real app: there is no route to this screen in
/// `lib/core/router/app_router.dart`. It is only shown by
/// `lib/main_ondevice_spike.dart`, a separate entry point launched via
/// `flutter run -t lib/main_ondevice_spike.dart`.
class OnDeviceSpikeScreen extends StatefulWidget {
  const OnDeviceSpikeScreen({super.key});

  @override
  State<OnDeviceSpikeScreen> createState() => _OnDeviceSpikeScreenState();
}

class _OnDeviceSpikeScreenState extends State<OnDeviceSpikeScreen> {
  late final OnDeviceSpikeController _controller;

  @override
  void initState() {
    super.initState();
    _controller = OnDeviceSpikeController()..addListener(_onControllerChanged);
    _controller.initializeModel();
  }

  void _onControllerChanged() => setState(() {});

  @override
  void dispose() {
    _controller.removeListener(_onControllerChanged);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('On-Device Spike (Gemma 4 E2B)')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _StatusBanner(controller: _controller),
            const SizedBox(height: 16),
            if (_controller.lastLatency != null) ...[
              Text(
                'Last round trip: ${_controller.lastLatency}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
            ],
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_controller.lastUserTranscriptNote.isNotEmpty) ...[
                      Text(
                        _controller.lastUserTranscriptNote,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 8),
                    ],
                    Text(
                      _controller.lastModelResponse.isEmpty
                          ? '(no response yet)'
                          : _controller.lastModelResponse,
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            _RecordButton(controller: _controller),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _controller.state == SpikeState.idle
                  ? _controller.captureFrameAndDescribe
                  : null,
              icon: const Icon(Icons.camera_alt),
              label: const Text('Capture frame & describe'),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({required this.controller});

  final OnDeviceSpikeController controller;

  @override
  Widget build(BuildContext context) {
    switch (controller.state) {
      case SpikeState.downloadingModel:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Downloading Gemma 4 E2B (~2.4GB)... '
                '${controller.downloadProgress}%'),
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: controller.downloadProgress / 100,
            ),
          ],
        );
      case SpikeState.loadingModel:
        return const Text('Loading model into memory...');
      case SpikeState.error:
        return Text(
          controller.lastError ?? 'Unknown error',
          style: const TextStyle(color: Colors.red),
        );
      case SpikeState.idle:
        return const Text('Ready. Hold the button and speak.');
      case SpikeState.recording:
        return const Text('Recording... release to send.');
      case SpikeState.thinking:
        return const Text('Gemma 4 is thinking...');
      case SpikeState.speaking:
        return const Text('Speaking (speak now to interrupt)...');
      case SpikeState.capturingFrame:
        return const Text('Opening camera...');
      case SpikeState.describingFrame:
        return const Text('Describing frame...');
    }
  }
}

class _RecordButton extends StatelessWidget {
  const _RecordButton({required this.controller});

  final OnDeviceSpikeController controller;

  @override
  Widget build(BuildContext context) {
    final ready = controller.state == SpikeState.idle;
    final recording = controller.state == SpikeState.recording;
    return GestureDetector(
      onLongPressStart: ready ? (_) => controller.startRecording() : null,
      onLongPressEnd:
          recording ? (_) => controller.stopRecordingAndRespond() : null,
      child: Container(
        height: 72,
        decoration: BoxDecoration(
          color: recording ? Colors.red : Theme.of(context).colorScheme.primary,
          borderRadius: BorderRadius.circular(12),
        ),
        alignment: Alignment.center,
        child: Text(
          recording ? 'Recording... release to send' : 'Hold to talk',
          style: const TextStyle(color: Colors.white, fontSize: 16),
        ),
      ),
    );
  }
}
