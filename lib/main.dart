import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // In debug builds, crash straight to the console instead of silently
  // uploading to Crashlytics — developer errors shouldn't be invisible.
  FlutterError.onError = kReleaseMode
      ? FirebaseCrashlytics.instance.recordFlutterFatalError
      : FlutterError.presentError;
  PlatformDispatcher.instance.onError = (error, stack) {
    if (kReleaseMode) {
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
    }
    return kReleaseMode;
  };

  runApp(const ProviderScope(child: RecoveryCompanionApp()));
}
