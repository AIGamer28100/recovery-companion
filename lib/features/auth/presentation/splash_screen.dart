import 'package:flutter/material.dart';

/// Shown only for the brief moment the router is still figuring out whether
/// there's a signed-in user and, if so, whether they have a profile yet.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}
