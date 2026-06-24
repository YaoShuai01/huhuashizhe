import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/update_service.dart';

final updateServiceProvider = Provider<UpdateService>((ref) => UpdateService());
final updateProvider =
    StateNotifierProvider<UpdateNotifier, UpdateState>(UpdateNotifier.new);

enum UpdateStatus { idle, checking, updateAvailable, downloading, downloaded, error, upToDate, noRelease }

class UpdateState {
  final UpdateStatus status;
  final double progress;
  final UpdateInfo? updateInfo;
  final String errorMessage;

  const UpdateState({
    this.status = UpdateStatus.idle,
    this.progress = 0,
    this.updateInfo,
    this.errorMessage = '',
  });

  UpdateState copyWith({
    UpdateStatus? status,
    double? progress,
    UpdateInfo? updateInfo,
    String? errorMessage,
  }) {
    return UpdateState(
      status: status ?? this.status,
      progress: progress ?? this.progress,
      updateInfo: updateInfo ?? this.updateInfo,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}

class UpdateNotifier extends StateNotifier<UpdateState> {
  final Ref ref;

  UpdateNotifier(this.ref) : super(const UpdateState());

  Future<void> checkForUpdate() async {
    state = state.copyWith(status: UpdateStatus.checking);
    final service = ref.read(updateServiceProvider);
    final (result, info) = await service.checkForUpdate();
    switch (result) {
      case CheckResult.hasUpdate:
        state = state.copyWith(
          status: UpdateStatus.updateAvailable,
          updateInfo: info,
        );
      case CheckResult.upToDate:
        state = state.copyWith(status: UpdateStatus.upToDate, updateInfo: info);
      case CheckResult.noRelease:
        state = state.copyWith(status: UpdateStatus.noRelease);
      case CheckResult.networkError:
        state = state.copyWith(
          status: UpdateStatus.error,
          errorMessage: '网络连接失败，请检查网络后重试',
        );
    }
  }

  Future<void> startDownload() async {
    final info = state.updateInfo;
    if (info == null || info.downloadUrl.isEmpty) return;

    state = state.copyWith(
      status: UpdateStatus.downloading,
      progress: 0,
    );

    final service = ref.read(updateServiceProvider);
    final success = await service.downloadUpdate(
      info.downloadUrl,
      (received, total) {
        if (total > 0) {
          state = state.copyWith(progress: received / total);
        }
      },
    );

    if (success) {
      state = state.copyWith(status: UpdateStatus.downloaded, progress: 1.0);
    } else {
      state = state.copyWith(
        status: UpdateStatus.error,
        errorMessage: '下载失败，请检查网络后重试',
      );
    }
  }

  void dismiss() {
    state = const UpdateState();
  }

  void reset() {
    state = const UpdateState();
  }
}
