import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/constants/app_version.dart';
import '../core/theme/app_theme.dart';
import '../providers/update_provider.dart';

class UpdateDialog extends ConsumerWidget {
  const UpdateDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const UpdateDialog(),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(updateProvider);
    final notifier = ref.read(updateProvider.notifier);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: SizedBox(
          width: 320,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildHeader(),
              Flexible(child: _buildBody(context, state, notifier)),
              if (state.status == UpdateStatus.updateAvailable)
                _buildActionButtons(context, notifier),
              if (state.status == UpdateStatus.downloaded)
                _buildInstallButton(context, ref),
              if (state.status == UpdateStatus.error)
                _buildErrorRetry(state, notifier),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 24),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.primaryDark, AppColors.primary, AppColors.primaryLight],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.system_update, size: 28, color: Colors.white),
          ),
          const SizedBox(height: 10),
          const Text(
            '发现新版本',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context, UpdateState state, UpdateNotifier notifier) {
    if (state.status == UpdateStatus.checking) {
      return Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(color: AppColors.primary),
            const SizedBox(height: 16),
            Text('正在检查更新...', style: TextStyle(color: AppColors.textSecondary, fontSize: 14)),
          ],
        ),
      );
    }

    if (state.status == UpdateStatus.downloading) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(28, 28, 28, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 80,
                  height: 80,
                  child: CircularProgressIndicator(
                    value: state.progress,
                    strokeWidth: 6,
                    backgroundColor: AppColors.surfaceVariant,
                    valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primary),
                  ),
                ),
                Text(
                  '${(state.progress * 100).toInt()}%',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              '正在下载更新...',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
            ),
          ],
        ),
      );
    }

    final info = state.updateInfo;
    if (info == null) return const SizedBox.shrink();

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                decoration: BoxDecoration(
                  color: AppColors.primaryLight.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  'v${info.versionName}',
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '当前 v$appVersion',
                style: TextStyle(color: AppColors.textHint, fontSize: 13),
              ),
            ],
          ),
          const SizedBox(height: 18),
          if (info.releaseNotes.isNotEmpty) ...[
            const Text(
              '更新内容',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                _formatReleaseNotes(info.releaseNotes),
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                  height: 1.7,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildActionButtons(BuildContext context, UpdateNotifier notifier) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
      child: Row(
        children: [
          Expanded(
            child: TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text(
                '下次再说',
                style: TextStyle(color: AppColors.textHint),
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: ElevatedButton(
              onPressed: () => notifier.startDownload(),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 46),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text('立即更新', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInstallButton(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: () async {
            final service = ref.read(updateServiceProvider);
            final filePath = service.downloadPath;
            final success = await service.installUpdate(filePath);
            if (!success && context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('安装失败，请到文件管理器中手动安装')),
              );
            }
          },
          icon: const Icon(Icons.install_mobile, size: 20),
          label: const Text('安装更新', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.success,
            foregroundColor: Colors.white,
            minimumSize: const Size(double.infinity, 46),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildErrorRetry(UpdateState state, UpdateNotifier notifier) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
      child: Column(
        children: [
          Text(
            state.errorMessage,
            style: const TextStyle(color: AppColors.error, fontSize: 13),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => notifier.startDownload(),
            child: const Text('重新下载'),
          ),
        ],
      ),
    );
  }

  String _formatReleaseNotes(String notes) {
    return notes
        .replaceAll(RegExp(r'#{1,3}\s*'), '')
        .replaceAll(RegExp(r'\*\*(.*?)\*\*'), r'\1')
        .replaceAll(RegExp(r'-\s*'), '• ')
        .trim();
  }
}
