import 'package:lifeease/core/utils/app_export.dart';
import 'package:lifeease/shared/providers/language_controller.dart';

class AppNavigation extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onDestinationSelected;

  const AppNavigation({
    super.key,
    required this.currentIndex,
    required this.onDestinationSelected,
  });

  String tr(bool isTagalog, String en, String tl) {
    return isTagalog ? tl : en;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ValueListenableBuilder<bool>(
      valueListenable: LanguageController.isTagalog,
      builder: (context, isTagalog, child) {
        return NavigationBar(
          selectedIndex: currentIndex,
          onDestinationSelected: onDestinationSelected,
          backgroundColor: theme.colorScheme.surface,
          indicatorColor: theme.colorScheme.primaryContainer,
          elevation: 4,
          shadowColor: theme.colorScheme.outline.withAlpha(77),
          animationDuration: const Duration(milliseconds: 250),
          destinations: [
            NavigationDestination(
              icon: _animatedIcon(theme, 'home_outlined', 0),
              selectedIcon: _animatedIcon(theme, 'home', 0, selected: true),
              label: tr(isTagalog, 'Home', 'Tahanan'),
            ),
            NavigationDestination(
              icon: _animatedIcon(theme, 'description_outlined', 1),
              selectedIcon: _animatedIcon(
                theme,
                'edit_note',
                1,
                selected: true,
              ),
              label: tr(isTagalog, 'Reminders', 'Mga Paalala'),
            ),
            NavigationDestination(
              icon: _animatedIcon(theme, 'mic_none', 2),
              selectedIcon: _animatedIcon(theme, 'mic', 2, selected: true),
              label: tr(isTagalog, 'Voice', 'Boses'),
            ),
            NavigationDestination(
              icon: _animatedIcon(theme, 'translate', 3),
              selectedIcon: _animatedIcon(
                theme,
                'translate',
                3,
                selected: true,
              ),
              label: tr(isTagalog, 'Translate', 'Isalin'),
            ),
            NavigationDestination(
              icon: _animatedIcon(theme, 'settings_outlined', 4),
              selectedIcon: _animatedIcon(theme, 'settings', 4, selected: true),
              label: tr(isTagalog, 'Settings', 'Mga Setting'),
            ),
          ],
        );
      },
    );
  }

  Widget _animatedIcon(
    ThemeData theme,
    String iconName,
    int index, {
    bool selected = false,
  }) {
    final isCurrent = currentIndex == index || selected;
    return AnimatedScale(
      scale: isCurrent ? 1.16 : 1.0,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      child: AnimatedOpacity(
        opacity: isCurrent ? 1 : 0.72,
        duration: const Duration(milliseconds: 180),
        child: CustomIconWidget(
          iconName: iconName,
          color: isCurrent
              ? theme.colorScheme.primary
              : theme.colorScheme.onSurface.withAlpha(153),
          size: isCurrent ? 27 : 24,
        ),
      ),
    );
  }
}
