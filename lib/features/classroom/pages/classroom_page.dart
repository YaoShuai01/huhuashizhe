import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import '../widgets/course_detail_page.dart';

class ClassroomPage extends StatefulWidget {
  const ClassroomPage({super.key});

  @override
  State<ClassroomPage> createState() => _ClassroomPageState();
}

class _ClassroomPageState extends State<ClassroomPage> {
  String _selectedCategory = '推荐';

  final List<Map<String, dynamic>> _courses = [
    {
      'title': '水稻稻飞虱防治技术要点',
      'category': '杀虫',
      'cropType': '水稻',
      'content': '稻飞虱是水稻生产中的重要害虫之一...\n\n防治要点：\n1. 选用抗虫品种\n2. 合理施肥，避免偏施氮肥\n3. 保护天敌，如蜘蛛、寄生蜂\n4. 在若虫高峰期施药\n5. 推荐药剂：吡虫啉、噻虫嗪等\n6. 施药时注意均匀喷洒，药液量要充足',
      'season': '夏季',
    },
    {
      'title': '小麦赤霉病综合防治方案',
      'category': '杀虫',
      'cropType': '小麦',
      'content': '小麦赤霉病是一种严重影响小麦产量和品质的病害...\n\n防治要点：\n1. 选用抗病品种\n2. 适时播种，避开扬花期遇雨\n3. 抽穗扬花期及时喷药\n4. 推荐药剂：戊唑醇、咪鲜胺等\n5. 注意轮换用药，避免产生抗性',
      'season': '春季',
    },
    {
      'title': '玉米草地贪夜蛾识别与防治',
      'category': '杀虫',
      'cropType': '玉米',
      'content': '草地贪夜蛾是联合国粮农组织全球预警的重大害虫...\n\n防治要点：\n1. 成虫诱杀：利用性诱剂、杀虫灯\n2. 幼虫防治：低龄幼虫期施药\n3. 推荐药剂：甲维盐、氯虫苯甲酰胺等\n4. 注意施药时间：清晨或傍晚效果最佳',
      'season': '夏季',
    },
    {
      'title': '农药混用禁忌与安全间隔期',
      'category': '农药知识',
      'cropType': '通用',
      'content': '农药混用是农业生产中常见的操作，但不当混用可能导致药效降低甚至产生药害...\n\n混用原则：\n1. 酸碱性不同的农药不能混用\n2. 铜制剂与多数农药不能混用\n3. 有机磷类与碱性农药不能混用\n4. 生物农药与化学农药间隔使用\n\n安全间隔期：\n- 水稻：最后一次施药距收获期不少于15天\n- 小麦：不少于20天\n- 蔬菜：不少于7-14天',
      'season': '通用',
    },
    {
      'title': '果树科学施肥技术指南',
      'category': '施肥',
      'cropType': '果树',
      'content': '科学施肥是果树高产优质的基础...\n\n施肥原则：\n1. 基肥为主，追肥为辅\n2. 有机肥与无机肥配合\n3. 大量元素与微量元素平衡\n4. 根据树龄、树势调整施肥量\n5. 结合灌溉提高肥料利用率',
      'season': '秋季',
    },
    {
      'title': '茶园绿色防控技术',
      'category': '杀虫',
      'cropType': '茶叶',
      'content': '茶叶作为直接饮用的农产品，农药残留问题尤为重要...\n\n绿色防控技术：\n1. 生态调控：茶园间作、保护天敌\n2. 物理防治：杀虫灯、色板诱杀\n3. 生物防治：使用Bt制剂、植物源农药\n4. 化学防治：严格使用低毒低残留农药\n5. 严格执行安全间隔期',
      'season': '春季',
    },
  ];

  @override
  Widget build(BuildContext context) {
    final filtered = _selectedCategory == '推荐'
        ? _courses
        : _courses.where((c) => c['cropType'] == _selectedCategory || c['category'] == _selectedCategory).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('小课堂')),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            color: AppColors.surface,
            child: TextField(
              decoration: InputDecoration(
                hintText: '搜索科普内容...',
                prefixIcon: const Icon(Icons.search, color: AppColors.textHint),
                contentPadding: const EdgeInsets.symmetric(vertical: 0),
              ),
            ),
          ),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [AppColors.primary, AppColors.primaryLight],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Text('当前季节推荐', style: TextStyle(color: Colors.white70, fontSize: 12)),
                      SizedBox(height: 6),
                      Text('水稻病虫害防治指南', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                      SizedBox(height: 4),
                      Text('学习科学防治方法，提升产量', style: TextStyle(color: Colors.white70, fontSize: 13)),
                    ],
                  ),
                ),
                const Icon(Icons.agriculture, color: Colors.white, size: 48),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: _buildCategoryChips(),
            ),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: filtered.length,
              itemBuilder: (context, index) {
                final course = filtered[index];
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: InkWell(
                    onTap: () {
                      context.push('/classroom/course', extra: {
                        'title': course['title'],
                        'content': course['content'],
                        'cropType': course['cropType'],
                        'category': course['category'],
                      });
                    },
                    borderRadius: BorderRadius.circular(12),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Chip(
                                label: Text(course['cropType'], style: const TextStyle(fontSize: 11)),
                                backgroundColor: AppColors.primaryLight.withValues(alpha: 0.1),
                                labelStyle: const TextStyle(color: AppColors.primary),
                                padding: EdgeInsets.zero,
                                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                visualDensity: VisualDensity.compact,
                              ),
                              const SizedBox(width: 8),
                              Chip(
                                label: Text(course['category'], style: const TextStyle(fontSize: 11)),
                                backgroundColor: AppColors.surfaceVariant,
                                padding: EdgeInsets.zero,
                                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                visualDensity: VisualDensity.compact,
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Text(
                            course['title'],
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, height: 1.4),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            course['content'],
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.5),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              const Icon(Icons.visibility_outlined, size: 14, color: AppColors.textHint),
                              const SizedBox(width: 4),
                              const Text('128 次阅读', style: TextStyle(fontSize: 12, color: AppColors.textHint)),
                              const Spacer(),
                              IconButton(
                                icon: const Icon(Icons.bookmark_outline, size: 18),
                                onPressed: () {},
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                              ),
                            ],
                          ),
                        ],
                      ),
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

  List<Widget> _buildCategoryChips() {
    final categories = ['推荐', '水稻', '小麦', '玉米', '棉花', '果树', '蔬菜', '茶叶', '农药知识'];
    return categories.map((category) {
      final isSelected = category == _selectedCategory;
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: GestureDetector(
          onTap: () => setState(() => _selectedCategory = category),
          child: Chip(
            label: Text(category),
            backgroundColor: isSelected ? AppColors.primary : AppColors.surfaceVariant,
            labelStyle: TextStyle(
              color: isSelected ? AppColors.textOnPrimary : AppColors.textSecondary,
              fontSize: 13,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
            ),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            padding: const EdgeInsets.symmetric(horizontal: 4),
          ),
        ),
      );
    }).toList();
  }
}