// Basic smoke tests that don't require Firebase bootstrap (M0 scope).
// Full widget/integration tests against faked repositories are future work
// per DESIGN.md §2.5.

import 'package:flutter_test/flutter_test.dart';
import 'package:soter_recovery/core/theme/app_theme.dart';

void main() {
  test('dark theme uses the ember accent as primary', () {
    expect(AppTheme.dark.colorScheme.primary, AppColors.ember);
    expect(AppTheme.dark.colorScheme.surface, AppColors.voidBg);
  });

  test('light theme uses the ember accent as primary', () {
    expect(AppTheme.light.colorScheme.primary, AppColors.ember);
    expect(AppTheme.light.colorScheme.surface, AppColors.lightBg);
  });
}
