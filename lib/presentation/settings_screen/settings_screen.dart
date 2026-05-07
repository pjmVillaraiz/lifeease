import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:sizer/sizer.dart';

import '../../core/language_controller.dart';
import '../../core/settings_controller.dart';
import '../../theme/app_theme.dart';
import '../../widgets/custom_icon_widget.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final SettingsController _controller = SettingsController.instance;

  final List<String> _leadTimeOptions = [
    '5 minutes',
    '10 minutes',
    '15 minutes',
    '30 minutes',
    '1 hour',
  ];

  String tr(String en, String tl) {
    return LanguageController.isTagalog.value ? tl : en;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        leading: IconButton(
          icon: CustomIconWidget(
            iconName: 'arrow_back',
            color: theme.colorScheme.onSurface,
            size: 24,
          ),
          onPressed: () => Navigator.pop(context),
          tooltip: 'Back',
        ),
        title: Text(
          tr('Settings', 'Mga Setting'),
          style: GoogleFonts.nunitoSans(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: theme.colorScheme.onSurface,
          ),
        ),
        backgroundColor: theme.colorScheme.surface,
        elevation: 0,
        scrolledUnderElevation: 2,
      ),
      body: ListView(
        padding: EdgeInsets.symmetric(horizontal: 4.w, vertical: 1.5.h),
        children: [
          _buildSectionHeader(
            theme,
            tr('Notifications', 'Mga Abiso'),
            'notifications',
          ),
          _buildCard(theme, [
            _buildSwitchTile(
              theme,
              icon: 'notifications',
              iconColor: AppTheme.primaryBlue,
              title: tr('Enable Notifications', 'Paganahin ang Mga Abiso'),
              subtitle: tr(
                'Receive reminder alerts',
                'Tumatanggap ng mga paalala',
              ),
              value: _controller.notificationsEnabled,
              onChanged: (v) {
                _controller.updateNotificationsEnabled(v);
                setState(() {});
              },
            ),
            _buildDivider(theme),
            _buildSwitchTile(
              theme,
              icon: 'volume_up',
              iconColor: AppTheme.secondaryTeal,
              title: tr('Sound', 'Tunog'),
              subtitle: tr(
                'Play sound for reminders',
                'Patugtugin ang tunog para sa mga paalala',
              ),
              value: _controller.soundEnabled,
              onChanged: _controller.notificationsEnabled
                  ? (v) {
                      _controller.updateSoundEnabled(v);
                      setState(() {});
                    }
                  : null,
            ),
            _buildDivider(theme),
            _buildSwitchTile(
              theme,
              icon: 'vibration',
              iconColor: AppTheme.categoryAppointment,
              title: tr('Vibration', 'Pag-vibrate'),
              subtitle: tr(
                'Vibrate for reminders',
                'Mag-vibrate para sa mga paalala',
              ),
              value: _controller.vibrationEnabled,
              onChanged: _controller.notificationsEnabled
                  ? (v) {
                      _controller.updateVibrationEnabled(v);
                      setState(() {});
                    }
                  : null,
            ),
            _buildDivider(theme),
            _buildDropdownTile(
              theme,
              icon: 'alarm',
              iconColor: AppTheme.warning,
              title: tr('Reminder Lead Time', 'Oras ng Paalala'),
              subtitle: tr(
                'Notify before scheduled time',
                'Abisuhan bago ang nakatakdang oras',
              ),
              value: _controller.reminderLeadTime,
              items: _leadTimeOptions,
              onChanged: (v) {
                if (v != null) {
                  _controller.updateReminderLeadTime(v);
                  setState(() {});
                }
              },
            ),
          ]),
          SizedBox(height: 2.h),
          _buildSectionHeader(
            theme,
            tr('Accessibility', 'Pagiging Magagamit'),
            'accessibility',
          ),
          _buildCard(theme, [
            _buildSwitchTile(
              theme,
              icon: 'text_fields',
              iconColor: AppTheme.categoryPill,
              title: tr('Large Text', 'Malaking Teksto'),
              subtitle: tr(
                'Increase text size for easier reading',
                'Palakihin ang laki ng teksto para mas madaling mabasa',
              ),
              value: _controller.largeText,
              onChanged: (v) {
                _controller.updateLargeText(v);
                setState(() {});
              },
            ),
            _buildDivider(theme),
            _buildSwitchTile(
              theme,
              icon: 'contrast',
              iconColor: AppTheme.categoryShopping,
              title: tr('High Contrast', 'Mataas na Kontraste'),
              subtitle: tr(
                'Improve visibility with higher contrast',
                'Pahusayin ang nakikita gamit ang mas mataas na kontraste',
              ),
              value: _controller.highContrast,
              onChanged: (v) {
                _controller.updateHighContrast(v);
                setState(() {});
              },
            ),
          ]),
          SizedBox(height: 2.h),
          _buildSectionHeader(theme, tr('Appearance', 'Hitsura'), 'palette'),
          _buildCard(theme, [
            _buildSwitchTile(
              theme,
              icon: 'dark_mode',
              iconColor: const Color(0xFF5C6BC0),
              title: tr('Dark Mode', 'Madilim na Tema'),
              subtitle: tr(
                'Switch to dark theme',
                'Lumipat sa madilim na tema',
              ),
              value: _controller.darkMode,
              onChanged: (v) {
                _controller.updateDarkMode(v);
                setState(() {});
              },
            ),
          ]),
          SizedBox(height: 2.h),
          _buildSectionHeader(theme, tr('Language', 'Wika'), 'language'),
          _buildCard(theme, [
            _buildSwitchTile(
              theme,
              icon: 'translate',
              iconColor: AppTheme.secondaryTeal,
              title: tr('Filipino (Tagalog)', 'Filipino (Tagalog)'),
              subtitle: tr(
                'Show app in Filipino language',
                'Ipakita ang app sa wikang Filipino',
              ),
              value: _controller.tagalog,
              onChanged: (v) {
                _controller.updateTagalog(v);
                LanguageController.isTagalog.value = v;
                setState(() {});
              },
            ),
          ]),
          SizedBox(height: 2.h),
          _buildSectionHeader(theme, tr('About', 'Tungkol'), 'info'),
          _buildCard(theme, [
            _buildInfoTile(
              theme,
              icon: 'info_outline',
              iconColor: AppTheme.primaryBlue,
              title: 'App Version',
              trailing: Text(
                '1.0.0',
                style: GoogleFonts.nunitoSans(
                  fontSize: 14,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            _buildDivider(theme),
            _buildInfoTile(
              theme,
              icon: 'privacy_tip',
              iconColor: AppTheme.categoryCalendar,
              title: 'Privacy Policy',
              trailing: CustomIconWidget(
                iconName: 'chevron_right',
                color: theme.colorScheme.onSurfaceVariant,
                size: 20,
              ),
              onTap: () => _showSnackBar('Privacy Policy coming soon'),
            ),
            _buildDivider(theme),
            _buildInfoTile(
              theme,
              icon: 'help_outline',
              iconColor: AppTheme.categoryFood,
              title: 'Help & Support',
              trailing: CustomIconWidget(
                iconName: 'chevron_right',
                color: theme.colorScheme.onSurfaceVariant,
                size: 20,
              ),
              onTap: () => _showSnackBar('Help & Support coming soon'),
            ),
          ]),
          SizedBox(height: 3.h),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(ThemeData theme, String title, String iconName) {
    return Padding(
      padding: EdgeInsets.only(left: 1.w, bottom: 1.h),
      child: Row(
        children: [
          CustomIconWidget(
            iconName: iconName,
            color: AppTheme.primaryBlue,
            size: 18,
          ),
          const SizedBox(width: 8),
          Text(
            title,
            style: GoogleFonts.nunitoSans(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppTheme.primaryBlue,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCard(ThemeData theme, List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: theme.colorScheme.outline.withAlpha(30),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(children: children),
    );
  }

  Widget _buildSwitchTile(
    ThemeData theme, {
    required String icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool>? onChanged,
  }) {
    final isDisabled = onChanged == null;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: isDisabled ? null : () => onChanged(!value),
        splashColor: AppTheme.primaryBlue.withAlpha(25),
        highlightColor: AppTheme.primaryBlue.withAlpha(12),
        child: Opacity(
          opacity: isDisabled ? 0.5 : 1.0,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 4.w, vertical: 1.2.h),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: iconColor.withAlpha(25),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Center(
                    child: CustomIconWidget(
                      iconName: icon,
                      color: iconColor,
                      size: 20,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: GoogleFonts.nunitoSans(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                      Text(
                        subtitle,
                        style: GoogleFonts.nunitoSans(
                          fontSize: 13,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: value,
                  onChanged: onChanged,
                  activeColor: AppTheme.primaryBlue,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDropdownTile(
    ThemeData theme, {
    required String icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required String value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
  }) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 4.w, vertical: 0.6.h),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: iconColor.withAlpha(25),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Center(
              child: CustomIconWidget(
                iconName: icon,
                color: iconColor,
                size: 20,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.nunitoSans(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                Text(
                  subtitle,
                  style: GoogleFonts.nunitoSans(
                    fontSize: 13,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: DropdownButton<String>(
              value: value,
              underline: const SizedBox.shrink(),
              isDense: true,
              style: GoogleFonts.nunitoSans(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppTheme.primaryBlue,
              ),
              items: items
                  .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                  .toList(),
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoTile(
    ThemeData theme, {
    required String icon,
    required Color iconColor,
    required String title,
    required Widget trailing,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 4.w, vertical: 1.5.h),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: iconColor.withAlpha(25),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Center(
                child: CustomIconWidget(
                  iconName: icon,
                  color: iconColor,
                  size: 20,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: GoogleFonts.nunitoSans(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ),
            trailing,
          ],
        ),
      ),
    );
  }

  Widget _buildDivider(ThemeData theme) {
    return Divider(
      height: 1,
      indent: 16 + 40 + 12.0,
      endIndent: 16,
      color: theme.colorScheme.outlineVariant,
    );
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: GoogleFonts.nunitoSans(fontSize: 14)),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 2),
      ),
    );
  }
}
