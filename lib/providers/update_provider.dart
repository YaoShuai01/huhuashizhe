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

  /// 是否处于后台下载模式（进度条显示在版本信息页，不弹对话框）
  final bool background;

  const UpdateState({
    this.status = UpdateStatus.idle,
    this.progress = 0,
    this.updateInfo,
    this.errorMessage = '',
    this.background = false,
  });

  UpdateState copyWith({
    UpdateStatus? status,
    double? progress,
    UpdateInfo? updateInfo,
    String? errorMessage,
    bool? background,
  }) {
    return UpdateState(
      status: status ?? this.status,
      progress: progress ?? this.progress,
      updateInfo: updateInfo ?? this.updateInfo,
      errorMessage: errorMessage ?? this.errorMessage,
      background: background ?? this.background,
    );
  }
}

class UpdateNotifier extends StateNotifier<UpdateState> {
  final Ref ref;

  UpdateNotifier(this.ref) : super(const UpdateState());

  Future<void> checkForUpdate() async {
    // 正在下载/已下载待安装时不要重新检测，避免覆盖后台下载进度
    if (state.status == UpdateStatus.downloading ||
        state.status == UpdateStatus.downloaded) {
      return;
    }
    // 已经提示过有新版本时不要重复检测：
    // 回前台/切后台再回来会触发重查，否则每次都会再叠一个更新弹窗
    if (state.status == UpdateStatus.updateAvailable) {
      return;
    }
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

  /// 开始下载。[background]=true 时进入后台模式：
  /// 下载继续进行，进度显示在版本信息页，完成后仍自动拉起系统安装器
  Future<void> startDownload({bool background = false}) async {
    final info = state.updateInfo;
    if (info == null || info.downloadUrl.isEmpty) {
      state = state.copyWith(
        status: UpdateStatus.error,
        errorMessage: '未找到下载资源，请稍后重试',
      );
      return;
    }

    state = state.copyWith(
      status: UpdateStatus.downloading,
      progress: 0,
      background: background,
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
      // 下载完成后自动拉起系统安装器，无需用户点击
      await service.installUpdate(service.downloadPath);
    } else {
      state = state.copyWith(
        status: UpdateStatus.error,
        errorMessage: '下载失败：所有下载通道均不可用，请稍后重试或切换网络',
      );
    }
  }

  /// 下载中切换为后台模式：下载继续，进度条显示在版本信息页
  void switchToBackground() {
    if (state.status == UpdateStatus.downloading) {
      state = state.copyWith(background: true);
    }
  }

  void dismiss() {
    state = const UpdateState();
  }

  void reset() {
    state = const UpdateState();
  }
}
