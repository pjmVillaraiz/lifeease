import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../theme/app_theme.dart';

class _CategoryItem {
  final String id;
  final String label;
  final String emoji;
  final Color color;

  const _CategoryItem({
    required this.id,
    required this.label,
    required this.emoji,
    required this.color,
  });
}

class CategoryChipRowWidget extends StatelessWidget {
  final String selectedCategory;
  final ValueChanged<String> onCategorySelected;

  const CategoryChipRowWidget({
    super.key,
    required this.selectedCategory,
    required this.onCategorySelected,
  });

  static const _categories = [
    _CategoryItem(
      id: 'pill',
      label: 'Pill',
      emoji: '💊',
      color: AppTheme.categoryPill,
    ),
    _CategoryItem(
      id: 'food',
      label: 'Food',
      emoji: '🍽️',
      color: AppTheme.categoryFood,
    ),
    _CategoryItem(
      id: 'appointment',
      label: 'Appointment',
      emoji: '🏥',
      color: AppTheme.categoryAppointment,
    ),
    _CategoryItem(
      id: 'calendar',
      label: 'Calendar',
      emoji: '📅',
      color: AppTheme.categoryCalendar,
    ),
    _CategoryItem(
      id: 'shopping',
      label: 'Shopping',
      emoji: '🛒',
      color: AppTheme.categoryShopping,
    ),
    _CategoryItem(
      id: 'general',
      label: 'General',
      emoji: '📋',
      color: AppTheme.categoryGeneral,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 88,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(vertical: 4),
        itemCount: _categories.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (ctx, i) {
          final cat = _categories[i];
          final isSelected = selectedCategory == cat.id;
          return _CategoryChip(
            item: cat,
            isSelected: isSelected,
            onTap: () {
              HapticFeedback.lightImpact();
              onCategorySelected(cat.id);
            },
          );
        },
      ),
    );
  }
}

class _CategoryChip extends StatefulWidget {
  final _CategoryItem item;
  final bool isSelected;
  final VoidCallback onTap;

  const _CategoryChip({
    required this.item,
    required this.isSelected,
    required this.onTap,
  });

  @override
  State<_CategoryChip> createState() => _CategoryChipState();
}

class _CategoryChipState extends State<_CategoryChip>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
    );
    _scale = Tween<double>(
      begin: 1.0,
      end: 0.93,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return GestureDetector(
      onTapDown: (_) => _controller.forward(),
      onTapUp: (_) {
        _controller.reverse();
        widget.onTap();
      },
      onTapCancel: () => _controller.reverse(),
      child: AnimatedBuilder(
        animation: _scale,
        builder: (ctx, child) =>
            Transform.scale(scale: _scale.value, child: child),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: widget.isSelected
                ? widget.item.color
                : theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: widget.isSelected
                  ? widget.item.color
                  : theme.colorScheme.outlineVariant,
              width: widget.isSelected ? 0 : 1.5,
            ),
            boxShadow: widget.isSelected
                ? [
                    BoxShadow(
                      color: widget.item.color.withAlpha(77),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ]
                : null,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(widget.item.emoji, style: const TextStyle(fontSize: 20)),
              const SizedBox(height: 3),
              Text(
                widget.item.label,
                style: GoogleFonts.nunitoSans(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: widget.isSelected
                      ? Colors.white
                      : theme.colorScheme.onSurface.withAlpha(179),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
