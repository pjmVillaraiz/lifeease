import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lifeease/core/constants/app_assets.dart';
import 'package:lifeease/core/themes/app_theme.dart';
import 'package:lifeease/shared/widgets/custom_icon_widget.dart';

class HomeHeaderWidget extends StatelessWidget {
  final String userName;
  final int pendingCount;
  final VoidCallback onNotificationTap;
  final VoidCallback? onAvatarTap;

  const HomeHeaderWidget({
    super.key,
    required this.userName,
    required this.pendingCount,
    required this.onNotificationTap,
    this.onAvatarTap,
  });

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning,';
    if (hour < 17) return 'Good afternoon,';
    return 'Good evening,';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(13),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          GestureDetector(
            onTap: onAvatarTap,
            child: Container(
              width: 64,
              height: 54,
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: AppTheme.primaryBlue.withAlpha(77),
                  width: 2,
                ),
              ),
              child: Semantics(
                image: true,
                label: 'LifeEase logo',
                child: Image.asset(
                  AppAssets.logo,
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.medium,
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),
          // Greeting + name
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _getGreeting(),
                  style: GoogleFonts.nunitoSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: theme.colorScheme.outline,
                  ),
                ),
                Text(
                  userName,
                  style: GoogleFonts.nunitoSans(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: theme.colorScheme.onSurface,
                    height: 1.2,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          // Notification bell with badge
          Stack(
            clipBehavior: Clip.none,
            children: [
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: onNotificationTap,
                  borderRadius: BorderRadius.circular(12),
                  splashColor: AppTheme.primaryBlue.withAlpha(31),
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Center(
                      child: CustomIconWidget(
                        iconName: 'notifications_outlined',
                        color: theme.colorScheme.onSurface,
                        size: 22,
                      ),
                    ),
                  ),
                ),
              ),
              if (pendingCount > 0)
                Positioned(
                  top: -4,
                  right: -4,
                  child: Container(
                    width: 20,
                    height: 20,
                    decoration: const BoxDecoration(
                      color: AppTheme.errorRed,
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        pendingCount > 9 ? '9+' : '$pendingCount',
                        style: GoogleFonts.nunitoSans(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
