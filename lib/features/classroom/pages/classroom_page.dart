import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import '../data/classroom_courses.dart';
import '../data/classroom_store.dart';
import '../widgets/course_card.dart';

class ClassroomPage extends StatefulWidget {
  const ClassroomPage({super.key});

  @override
  State<ClassroomPage> createState() => _ClassroomPageState();
}

class _ClassroomPageState extends State<ClassroomPage> {
  String _selectedCategory = '推荐';
  final ClassroomStore _store = ClassroomStore.instance;

  Future<void> _openCourse(Course course) async {
    // 进详情即计入一次阅读，列表通过 AnimatedBuilder 自动刷新
    final reads = _store.incrementRead(course.id);
    await GoRouter.of(context).push(
      '/classroom/course',
      extra: <String, dynamic>{
        'id': course.id,
        'title': course.title,
        'content': course.content,
        'cropType': course.cropType,
        'category': course.category,
        'readCount': reads,
      },
    );
  }

  void _toggleFavorite(Course course) {
    final nowFavorite = _store.toggleFavorite(course.id);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(nowFavorite ? '已收藏，可在「我的 - 我的收藏」查看' : '已取消收藏'),
          duration: const Duration(seconds: 2),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _store,
      builder: (context, _) {
        final filtered = _selectedCategory == '推荐'
            ? classroomCourses
            : classroomCourses
                .where((c) => c.cropType == _selectedCategory || c.category == _selectedCategory)
                .toList();

        return Scaffold(
          appBar: AppBar(title: const Text('小课堂')),
          body: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                color: context.palette.surface,
                child: TextField(
                  decoration: InputDecoration(
                    hintText: '搜索科普内容...',
                    prefixIcon: Icon(Icons.search, color: context.palette.textHint),
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
                    return CourseCard(
                      course: course,
                      readCount: _store.readCount(course.id),
                      favorited: _store.isFavorite(course.id),
                      onTap: () => _openCourse(course),
                      onToggleFavorite: () => _toggleFavorite(course),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
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
            backgroundColor: isSelected ? AppColors.primary : context.palette.surfaceVariant,
            labelStyle: TextStyle(
              color: isSelected ? AppColors.textOnPrimary : context.palette.textSecondary,
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
