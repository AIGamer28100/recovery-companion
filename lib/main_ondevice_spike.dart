import 'package:flutter/material.dart';
import 'package:flutter_gemma/flutter_gemma.dart';

import 'features/ondevice_spike/presentation/ondevice_spike_screen.dart';

/// Separate, isolated entry point for the on-device Gemma 4 feasibility
/// spike. Run with:
///
///   flutter run -t lib/main_ondevice_spike.dart
///
/// This is intentionally NOT wired into `lib/main.dart` or
/// `lib/core/router/app_router.dart` -- the real app's normal navigation
/// cannot reach this screen.
///
/// Gemma 4 E2B is not a gated model on Hugging Face (see
/// `lib/features/ondevice_spike/data/spike_gemma_service.dart` for the
/// verification notes), so no `huggingFaceToken` is configured here.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await FlutterGemma.initialize();
  runApp(const OnDeviceSpikeApp());
}

class OnDeviceSpikeApp extends StatelessWidget {
  const OnDeviceSpikeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Soter On-Device Spike',
      theme: ThemeData(colorSchemeSeed: Colors.teal, useMaterial3: true),
      home: const OnDeviceSpikeScreen(),
    );
  }
}
