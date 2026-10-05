/// Update check state provider.
///
/// Manages the state of update checks and provides the update check result.
library update_state;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'update_service.dart';
import 'version_compare.dart';
import '../telemetry/telemetry_service.dart';
import '../providers/app_providers.dart';

/// State of the update check.
class UpdateState {
  const UpdateState({
    this.result,
    this.isLoading = false,
    this.error,
  });

  final UpdateCheckResult? result;
  final bool isLoading;
  final String? error;

  UpdateState copyWith({
    UpdateCheckResult? result,
    bool? isLoading,
    String? error,
  }) {
    return UpdateState(
      result: result ?? this.result,
      isLoading: isLoading ?? this.isLoading,
      error: error ?? this.error,
    );
  }

  @override
  String toString() => 'UpdateState(result: $result, isLoading: $isLoading, error: $error)';
}

/// Notifier for update check state.
class UpdateNotifier extends Notifier<UpdateState> {
  @override
  UpdateState build() => const UpdateState();

  /// Performs an update check.
  Future<void> checkForUpdates() async {
    if (state.isLoading) return;

    state = state.copyWith(isLoading: true, error: null);

    try {
      final service = ref.read(updateServiceProvider);
      final result = await service.checkForUpdates(ref);
      state = state.copyWith(isLoading: false, result: result);

      // Emit telemetry for update check
      _emitTelemetry(result);
    } catch (e, st) {
      state = state.copyWith(
        isLoading: false,
        error: e.toString(),
      );
      // TEŞHİS: Bu catch rethrow etmedigi icin UpdateChecker'in catch'i devreye
      // girmiyor ve hata hicbir yerde gorunmuyordu. Simdi loglanir.
      debugPrint(
        '[UpdateNotifier] checkForUpdates BASARISIZ; state.error ayarlandi. '
        'Detay: $e\n$st',
      );
      // Emit telemetry for failed check
      unawaited(ref.read(telemetryProvider).trackUpdateCheck(status: 'error'));
    }
  }

  void _emitTelemetry(UpdateCheckResult result) {
    final telemetry = ref.read(telemetryProvider);
    unawaited(telemetry.trackUpdateCheck(status: result.status.name));

    if (result.isUpdateAvailable) {
      unawaited(telemetry.trackUpdateAvailable(forced: result.isForcedUpdate));
    }
  }

  /// Resets the update state.
  void reset() {
    state = const UpdateState();
  }
}

/// Provider for the update notifier.
final updateNotifierProvider =
    NotifierProvider<UpdateNotifier, UpdateState>(UpdateNotifier.new);