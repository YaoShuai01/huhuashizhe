import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../../../providers/preset_provider.dart';
import '../widgets/preset_form_page.dart';

class PresetsPage extends ConsumerWidget {
  const PresetsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final presets = ref.watch(presetsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('预设')),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            color: AppColors.surface,
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: '搜索预设名称...',
                      prefixIcon: const Icon(Icons.search, color: AppColors.textHint),
                      contentPadding: const EdgeInsets.symmetric(vertical: 0),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                InkWell(
                  onTap: () {},
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.primaryLight.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.filter_list, color: AppColors.primary, size: 20),
                  ),
                ),
              ],
            ),
          ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            color: AppColors.surface,
            child: ElevatedButton.icon(
              onPressed: () async {
                final result = await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const PresetFormPage()),
                );
                if (result == true) { ref.invalidate(presetsProvider); }
              },
              icon: const Icon(Icons.add, size: 20),
              label: const Text('新建预设'),
            ),
          ),
          Expanded(
            child: presets.isEmpty
                ? Center(child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.bookmark_outline, size: 80, color: AppColors.textDisabled.withValues(alpha: 0.5)),
                      const SizedBox(height: 16),
                      const Text('暂无预设', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500, color: AppColors.textHint)),
                      const SizedBox(height: 8),
                      const Text('点击上方按钮创建你的第一个预设', style: TextStyle(fontSize: 14, color: AppColors.textDisabled)),
                    ],
                  ))
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: presets.length,
                    itemBuilder: (context, index) {
                      final p = presets[index];
                      return Card(
                        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(children: [
                                Expanded(child: Text(p['name'] ?? '未命名', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600))),
                                if (p['isAiGenerated'] == true)
                                  Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2), decoration: BoxDecoration(color: AppColors.accent.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(6)), child: const Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.auto_awesome, size: 12, color: AppColors.accent), SizedBox(width: 2), Text('AI', style: TextStyle(fontSize: 11, color: AppColors.accent, fontWeight: FontWeight.w600))])),
                              ]),
                              const SizedBox(height: 8),
                              Row(children: [_infoChip(p['cropType'] ?? ''), const SizedBox(width: 8), _infoChip(p['operationType'] ?? '')]),
                              const SizedBox(height: 8),
                              Text('喷洒量 ${(p['sprayVolume'] ?? 0).toStringAsFixed(1)} L/亩 · 高度 ${(p['flightHeight'] ?? 0).toStringAsFixed(1)} m', style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                              const SizedBox(height: 8),
                              Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                                TextButton.icon(onPressed: () {}, icon: const Icon(Icons.flight_takeoff, size: 16), label: const Text('使用')),
                                const SizedBox(width: 8),
                                TextButton.icon(onPressed: () async { await Navigator.push(context, MaterialPageRoute(builder: (_) => PresetFormPage(existingPreset: p))); ref.invalidate(presetsProvider); }, icon: const Icon(Icons.edit, size: 16), label: const Text('编辑')),
                                TextButton.icon(onPressed: () { showDialog(context: context, builder: (ctx) => AlertDialog(title: const Text('删除预设'), content: const Text('确定要删除此预设吗？'), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')), TextButton(onPressed: () { ref.read(presetsProvider.notifier).deletePreset(p['id']); Navigator.pop(ctx); }, child: const Text('删除', style: TextStyle(color: AppColors.error)))])); }, icon: const Icon(Icons.delete_outline, size: 16), label: const Text('删除'), style: TextButton.styleFrom(foregroundColor: AppColors.error)),
                              ]),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _infoChip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: AppColors.primaryLight.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
      child: Text(label, style: const TextStyle(fontSize: 12, color: AppColors.primary)),
    );
  }
}