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
              icon: CustomIconWidget(
                iconName: 'home_outlined',
                color: theme.colorScheme.onSurface.withAlpha(153),
                size: 24,
              ),
              selectedIcon: CustomIconWidget(
                iconName: 'home',
                color: theme.colorScheme.primary,
                size: 24,
              ),
              label: tr(isTagalog, 'Home', 'Tahanan'),
            ),
            NavigationDestination(
              icon: CustomIconWidget(
                iconName: 'alarm_outlined',
                color: theme.colorScheme.onSurface.withAlpha(153),
                size: 24,
              ),
              selectedIcon: CustomIconWidget(
                iconName: 'alarm',
                color: theme.colorScheme.primary,
                size: 24,
              ),
              label: tr(isTagalog, 'Reminders', 'Mga Paalala'),
            ),
            NavigationDestination(
              icon: CustomIconWidget(
                iconName: 'mic_none',
                color: theme.colorScheme.onSurface.withAlpha(153),
                size: 24,
              ),
              selectedIcon: CustomIconWidget(
                iconName: 'mic',
                color: theme.colorScheme.primary,
                size: 24,
              ),
              label: tr(isTagalog, 'Voice', 'Boses'),
            ),
            NavigationDestination(
              icon: CustomIconWidget(
                iconName: 'translate',
                color: theme.colorScheme.onSurface.withAlpha(153),
                size: 24,
              ),
              selectedIcon: CustomIconWidget(
                iconName: 'g_translate',
                color: theme.colorScheme.primary,
                size: 24,
              ),
              label: tr(isTagalog, 'Translate', 'Isalin'),
            ),
            NavigationDestination(
              icon: CustomIconWidget(
                iconName: 'settings_outlined',
                color: theme.colorScheme.onSurface.withAlpha(153),
                size: 24,
              ),
              selectedIcon: CustomIconWidget(
                iconName: 'settings',
                color: theme.colorScheme.primary,
                size: 24,
              ),
              label: tr(isTagalog, 'Settings', 'Mga Setting'),
            ),
          ],
        );
      },
    );
  }
}
