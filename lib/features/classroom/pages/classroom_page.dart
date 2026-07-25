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
    // ===== 油菜专题（核心内容） =====
    {
      'title': '油菜菌核病综合防治技术',
      'category': '病害防治',
      'cropType': '油菜',
      'content': '菌核病是油菜生产中最严重的病害之一，可导致减产20%-50%...\n\n防治要点：\n1. 选用抗病品种，合理轮作\n2. 开花初期喷药防治，7-10天后再喷一次\n3. 推荐药剂：多菌灵、菌核净、咪鲜胺\n4. 施药时重点喷施植株中下部\n5. 无人机喷洒时飞行高度2-3米，飞行速度3-4m/s\n6. 种植密度不宜过大，保持良好的通风透光条件',
      'season': '春季',
    },
    {
      'title': '油菜蚜虫绿色防控方案',
      'category': '虫害防治',
      'cropType': '油菜',
      'content': '蚜虫是油菜生长前期的主要害虫，严重时导致植株萎蔫死亡...\n\n防治要点：\n1. 苗期加强监测，发现蚜虫及时防治\n2. 保护瓢虫、草蛉等天敌昆虫\n3. 推荐药剂：吡虫啉、啶虫脒、噻虫嗪\n4. 无人机喷洒亩用药液量1-2升\n5. 施药时间选择清晨或傍晚，避免高温时段\n6. 注意轮换用药，防止产生抗药性',
      'season': '秋季',
    },
    {
      'title': '油菜各生长阶段管理要点',
      'category': '种植管理',
      'cropType': '油菜',
      'content': '油菜生长分为苗期、蕾薹期、开花期、结荚期和成熟期五个阶段...\n\n各阶段管理：\n苗期：适时间苗定苗，亩留苗2-3万株\n蕾薹期：追施薹肥，每亩追施尿素5-8kg\n开花期：叶面喷施硼肥，防止"花而不实"\n结荚期：保持土壤湿润，防治病虫害\n成熟期：适时收获，角果70%-80%变黄时收割\n\n无人机植保建议：结合生长阶段精准施药，苗期和开花期是关键防控窗口',
      'season': '全年',
    },
    {
      'title': '油菜硼肥施用技术指南',
      'category': '施肥技术',
      'cropType': '油菜',
      'content': '油菜是对硼元素最敏感的作物之一，缺硼会导致"花而不实"现象...\n\n施肥要点：\n1. 基施硼肥：每亩用硼砂0.5-1kg作基肥\n2. 叶面喷施：蕾薹期和初花期各喷一次0.2%硼砂溶液\n3. 无人机喷洒：飞行高度2-3米，飞行速度4-5m/s\n4. 喷施时间选在晴天上午10点前或下午4点后\n5. 注意硼肥不能与碱性农药混用\n6. 严重缺硼田块可增加喷施次数',
      'season': '春季',
    },
    {
      'title': '油菜无人机植保作业规范',
      'category': '植保作业',
      'cropType': '油菜',
      'content': '使用植保无人机对油菜进行喷洒作业，需要掌握科学的作业规范...\n\n作业规范：\n1. 飞行高度：2-3米（根据作物高度调整）\n2. 飞行速度：3-5m/s（病虫害防治）\n3. 喷幅宽度：4-6米\n4. 亩用药液量：1-2升\n5. 作业时间：避免高温和强风天气\n6. 地块规划：提前规划飞行路径，确保全覆盖\n\n注意事项：\n- 作业前检查无人机状态和药液配置\n- 作业时避开敏感区域（水源、居民区）\n- 作业后及时清洗无人机和药箱',
      'season': '全年',
    },
    {
      'title': '油菜田杂草化学防除技术',
      'category': '除草技术',
      'cropType': '油菜',
      'content': '油菜田杂草种类繁多，与油菜争光、争水、争肥，严重影响产量...\n\n防除要点：\n1. 播前土壤处理：使用乙草胺等封闭除草剂\n2. 苗后茎叶处理：根据杂草类型选用精喹禾灵、草除灵等\n3. 无人机喷洒：飞行高度2-3米，飞行速度3-4m/s\n4. 施药时注意风向，避免漂移到其他作物\n5. 阔叶杂草和禾本科杂草需分别选用针对性药剂\n6. 施药后保持土壤湿润以提高除草效果',
      'season': '秋季',
    },
    // ===== 其他作物参考 =====
    {
      'title': '水稻稻飞虱防治技术要点',
      'category': '虫害防治',
      'cropType': '水稻',
      'content': '稻飞虱是水稻生产中的重要害虫之一...\n\n防治要点：\n1. 选用抗虫品种\n2. 合理施肥，避免偏施氮肥\n3. 保护天敌，如蜘蛛、寄生蜂\n4. 在若虫高峰期施药\n5. 推荐药剂：吡虫啉、噻虫嗪等\n6. 施药时注意均匀喷洒，药液量要充足',
      'season': '夏季',
    },
    {
      'title': '小麦赤霉病综合防治方案',
      'category': '病害防治',
      'cropType': '小麦',
      'content': '小麦赤霉病是一种严重影响小麦产量和品质的病害...\n\n防治要点：\n1. 选用抗病品种\n2. 适时播种，避开扬花期遇雨\n3. 抽穗扬花期及时喷药\n4. 推荐药剂：戊唑醇、咪鲜胺等\n5. 注意轮换用药，避免产生抗性',
      'season': '春季',
    },
    {
      'title': '农药混用禁忌与安全间隔期',
      'category': '农药知识',
      'cropType': '通用',
      'content': '农药混用是农业生产中常见的操作，但不当混用可能导致药效降低甚至产生药害...\n\n混用原则：\n1. 酸碱性不同的农药不能混用\n2. 铜制剂与多数农药不能混用\n3. 有机磷类与碱性农药不能混用\n4. 生物农药与化学农药间隔使用\n\n安全间隔期：\n- 油菜：最后一次施药距收获期不少于20天\n- 水稻：不少于15天\n- 小麦：不少于20天\n- 蔬菜：不少于7-14天',
      'season': '通用',
    },
    {
      'title': '果树科学施肥技术指南',
      'category': '施肥技术',
      'cropType': '果树',
      'content': '科学施肥是果树高产优质的基础...\n\n施肥原则：\n1. 基肥为主，追肥为辅\n2. 有机肥与无机肥配合\n3. 大量元素与微量元素平衡\n4. 根据树龄、树势调整施肥量\n5. 结合灌溉提高肥料利用率',
      'season': '秋季',
    },
    {
      'title': '茶园绿色防控技术',
      'category': '虫害防治',
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
                      Text('油菜专题推荐', style: TextStyle(color: Colors.white70, fontSize: 12)),
                      SizedBox(height: 6),
                      Text('油菜病虫害防治指南', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                      SizedBox(height: 4),
                      Text('掌握科学植保技术，护航油菜丰收', style: TextStyle(color: Colors.white70, fontSize: 13)),
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
                      final args = <String, String>{
                        'title': course['title'].toString(),
                        'content': course['content'].toString(),
                        'cropType': course['cropType'].toString(),
                        'category': course['category'].toString(),
                      };
                      // 使用 rootNavigator 推送到外部路由
                      GoRouter.of(context).push('/classroom/course', extra: args);
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
    final categories = ['推荐', '油菜', '水稻', '小麦', '病害防治', '虫害防治', '施肥技术', '农药知识'];
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