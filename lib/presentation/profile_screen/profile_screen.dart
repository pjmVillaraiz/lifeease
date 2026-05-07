import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:sizer/sizer.dart';

import '../../theme/app_theme.dart';
import '../../widgets/custom_icon_widget.dart';
import '../../widgets/custom_image_widget.dart';
import '../../core/language_controller.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _isEditing = false;

  String tr(bool isTagalog, String en, String tl) => isTagalog ? tl : en;

  final TextEditingController _nameController = TextEditingController(
    text: 'Lola Nena',
  );
  final TextEditingController _emailController = TextEditingController(
    text: 'user@lifeease.ph',
  );
  final TextEditingController _phoneController = TextEditingController(
    text: '+63 917 123 4567',
  );
  final TextEditingController _birthdateController = TextEditingController(
    text: 'January 15, 1950',
  );
  final TextEditingController _conditionsController = TextEditingController(
    text: 'Hypertension, Type 2 Diabetes',
  );

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _birthdateController.dispose();
    _conditionsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ValueListenableBuilder<bool>(
      valueListenable: LanguageController.isTagalog,
      builder: (context, isTagalog, child) {
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
              tooltip: tr(isTagalog, 'Back', 'Bumalik'),
            ),
            title: Text(
              tr(isTagalog, 'Profile', 'Profile'),
              style: GoogleFonts.nunitoSans(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.onSurface,
              ),
            ),
            backgroundColor: theme.colorScheme.surface,
            elevation: 0,
            scrolledUnderElevation: 2,
            actions: [
              TextButton.icon(
                onPressed: () {
                  if (_isEditing) {
                    _saveProfile(context);
                  }
                  setState(() => _isEditing = !_isEditing);
                },
                icon: CustomIconWidget(
                  iconName: _isEditing ? 'check' : 'edit',
                  color: AppTheme.primaryBlue,
                  size: 18,
                ),
                label: Text(
                  _isEditing
                      ? tr(isTagalog, 'Save', 'I-save')
                      : tr(isTagalog, 'Edit', 'I-edit'),
                  style: GoogleFonts.nunitoSans(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.primaryBlue,
                  ),
                ),
              ),
              const SizedBox(width: 8),
            ],
          ),
          body: ListView(
            padding: EdgeInsets.symmetric(horizontal: 4.w, vertical: 1.5.h),
            children: [
              _buildAvatarSection(theme),
              SizedBox(height: 2.h),
              _buildSectionHeader(
                theme,
                tr(
                  isTagalog,
                  'Personal Information',
                  'Personal na Impormasyon',
                ),
                'person',
              ),
              _buildCard(theme, [
                _buildFieldTile(
                  theme,
                  icon: 'badge',
                  iconColor: AppTheme.primaryBlue,
                  label: tr(isTagalog, 'Full Name', 'Buong Pangalan'),
                  controller: _nameController,
                  enabled: _isEditing,
                ),
                _buildDivider(theme),
                _buildFieldTile(
                  theme,
                  icon: 'email',
                  iconColor: AppTheme.secondaryTeal,
                  label: tr(isTagalog, 'Email Address', 'Email Address'),
                  controller: _emailController,
                  enabled: _isEditing,
                  keyboardType: TextInputType.emailAddress,
                ),
                _buildDivider(theme),
                _buildFieldTile(
                  theme,
                  icon: 'phone',
                  iconColor: AppTheme.categoryCalendar,
                  label: tr(isTagalog, 'Phone Number', 'Numero ng Telepono'),
                  controller: _phoneController,
                  enabled: _isEditing,
                  keyboardType: TextInputType.phone,
                ),
                _buildDivider(theme),
                _buildFieldTile(
                  theme,
                  icon: 'cake',
                  iconColor: AppTheme.categoryPill,
                  label: tr(
                    isTagalog,
                    'Date of Birth',
                    'Petsa ng Kapanganakan',
                  ),
                  controller: _birthdateController,
                  enabled: _isEditing,
                ),
              ]),
              SizedBox(height: 2.h),
              _buildSectionHeader(
                theme,
                tr(isTagalog, 'Health Information', 'Impormasyon sa Kalusugan'),
                'favorite',
              ),
              _buildCard(theme, [
                _buildFieldTile(
                  theme,
                  icon: 'medical_information',
                  iconColor: AppTheme.errorRed,
                  label: tr(
                    isTagalog,
                    'Medical Conditions',
                    'Mga Kundisyon sa Medikal',
                  ),
                  controller: _conditionsController,
                  enabled: _isEditing,
                  maxLines: 2,
                ),
              ]),
              SizedBox(height: 2.h),
              _buildSectionHeader(
                theme,
                tr(
                  isTagalog,
                  'Emergency Contacts',
                  'Mga Pang-emergency na Contact',
                ),
                'emergency',
              ),
              _buildCard(theme, [
                _buildContactTile(
                  theme,
                  name: 'Maria Santos',
                  relationship: 'Daughter',
                  phone: '+63 917 123 4567',
                  avatarUrl:
                      'https://images.pexels.com/photos/1181686/pexels-photo-1181686.jpeg',
                ),
                _buildDivider(theme),
                _buildContactTile(
                  theme,
                  name: 'Dr. Reyes',
                  relationship: 'Doctor',
                  phone: '+63 928 123 4567',
                  avatarUrl:
                      'https://images.pexels.com/photos/5452201/pexels-photo-5452201.jpeg',
                ),
                if (_isEditing) ...[
                  _buildDivider(theme),
                  InkWell(
                    onTap: () =>
                        _showSnackBar('Add contact feature coming soon'),
                    borderRadius: const BorderRadius.only(
                      bottomLeft: Radius.circular(16),
                      bottomRight: Radius.circular(16),
                    ),
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: 4.w,
                        vertical: 1.5.h,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          CustomIconWidget(
                            iconName: 'add_circle_outline',
                            color: AppTheme.primaryBlue,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            tr(
                              isTagalog,
                              'Add Emergency Contact',
                              'Magdagdag ng Emergency Contact',
                            ),
                            style: GoogleFonts.nunitoSans(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.primaryBlue,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ]),
              SizedBox(height: 2.h),
              _buildLogoutButton(theme),
              SizedBox(height: 3.h),
            ],
          ),
        );
      },
    );
  }

  Widget _buildAvatarSection(ThemeData theme) {
    return Center(
      child: Column(
        children: [
          Stack(
            children: [
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: AppTheme.primaryBlue, width: 3),
                ),
                child: ClipOval(
                  child: CustomImageWidget(
                    imageUrl:
                        'https://images.pexels.com/photos/1181519/pexels-photo-1181519.jpeg',
                    width: 100,
                    height: 100,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
              if (_isEditing)
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: AppTheme.primaryBlue,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: theme.colorScheme.surface,
                        width: 2,
                      ),
                    ),
                    child: const Icon(
                      Icons.camera_alt,
                      color: Colors.white,
                      size: 16,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            _nameController.text,
            style: GoogleFonts.nunitoSans(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: theme.colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: AppTheme.primaryContainer,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              'LifeEase Member',
              style: GoogleFonts.nunitoSans(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppTheme.primaryBlue,
              ),
            ),
          ),
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

  Widget _buildFieldTile(
    ThemeData theme, {
    required String icon,
    required Color iconColor,
    required String label,
    required TextEditingController controller,
    required bool enabled,
    TextInputType keyboardType = TextInputType.text,
    int maxLines = 1,
  }) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 4.w, vertical: 1.2.h),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
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
                  label,
                  style: GoogleFonts.nunitoSans(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurfaceVariant,
                    letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(height: 2),
                enabled
                    ? TextField(
                        controller: controller,
                        keyboardType: keyboardType,
                        maxLines: maxLines,
                        style: GoogleFonts.nunitoSans(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: theme.colorScheme.onSurface,
                        ),
                        decoration: InputDecoration(
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: 4,
                          ),
                          border: UnderlineInputBorder(
                            borderSide: BorderSide(color: AppTheme.primaryBlue),
                          ),
                          focusedBorder: UnderlineInputBorder(
                            borderSide: BorderSide(
                              color: AppTheme.primaryBlue,
                              width: 2,
                            ),
                          ),
                          enabledBorder: UnderlineInputBorder(
                            borderSide: BorderSide(
                              color: theme.colorScheme.outlineVariant,
                            ),
                          ),
                        ),
                      )
                    : Text(
                        controller.text,
                        style: GoogleFonts.nunitoSans(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: theme.colorScheme.onSurface,
                        ),
                        maxLines: maxLines,
                        overflow: TextOverflow.ellipsis,
                      ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContactTile(
    ThemeData theme, {
    required String name,
    required String relationship,
    required String phone,
    required String avatarUrl,
  }) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 4.w, vertical: 1.2.h),
      child: Row(
        children: [
          ClipOval(
            child: CustomImageWidget(
              imageUrl: avatarUrl,
              width: 44,
              height: 44,
              fit: BoxFit.cover,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: GoogleFonts.nunitoSans(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                Text(
                  '$relationship · $phone',
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
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppTheme.successContainer,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              relationship,
              style: GoogleFonts.nunitoSans(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppTheme.success,
              ),
            ),
          ),
        ],
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

  Widget _buildLogoutButton(ThemeData theme) {
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
      child: InkWell(
        onTap: () => _confirmLogout(theme),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 4.w, vertical: 1.8.h),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CustomIconWidget(
                iconName: 'logout',
                color: AppTheme.errorRed,
                size: 20,
              ),
              const SizedBox(width: 10),
              Text(
                'Log Out',
                style: GoogleFonts.nunitoSans(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.errorRed,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _saveProfile(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          tr(
            LanguageController.isTagalog.value,
            'Profile saved successfully',
            'Matagumpay na na-save ang profile',
          ),
          style: GoogleFonts.nunitoSans(fontSize: 14),
        ),
        backgroundColor: AppTheme.success,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _confirmLogout(ThemeData theme) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          tr(LanguageController.isTagalog.value, 'Log Out', 'Mag-logout'),
          style: GoogleFonts.nunitoSans(
            fontSize: 20,
            fontWeight: FontWeight.w700,
          ),
        ),
        content: Text(
          tr(
            LanguageController.isTagalog.value,
            'Are you sure you want to log out of LifeEase?',
            'Sigurado ka bang gusto mong mag-logout mula sa LifeEase?',
          ),
          style: GoogleFonts.nunitoSans(fontSize: 15),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              tr(LanguageController.isTagalog.value, 'Cancel', 'Kanselahin'),
              style: GoogleFonts.nunitoSans(
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.pushNamedAndRemoveUntil(
                context,
                '/login-screen',
                (route) => false,
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.errorRed,
              minimumSize: const Size(80, 40),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Text(
              tr(LanguageController.isTagalog.value, 'Log Out', 'Mag-logout'),
              style: GoogleFonts.nunitoSans(
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
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
