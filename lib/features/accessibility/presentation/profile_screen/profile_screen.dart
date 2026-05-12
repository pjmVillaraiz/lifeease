import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:sizer/sizer.dart';

import 'package:lifeease/core/services/backend/supabase_auth_service.dart';
import 'package:lifeease/core/services/backend/user_profile_service.dart';
import 'package:lifeease/core/themes/app_theme.dart';
import 'package:lifeease/core/utils/app_routes.dart';
import 'package:lifeease/shared/widgets/custom_icon_widget.dart';
import 'package:lifeease/shared/widgets/custom_image_widget.dart';
import 'package:lifeease/shared/providers/language_controller.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final SupabaseAuthService _authService = SupabaseAuthService();
  final UserProfileService _profileService = UserProfileService();
  bool _isEditing = false;
  final List<Map<String, String>> _emergencyContacts = [
    {
      'name': 'Maria Santos',
      'relationship': 'Daughter',
      'phone': '+63 917 123 4567',
      'avatarUrl':
          'https://images.pexels.com/photos/1181686/pexels-photo-1181686.jpeg',
    },
    {
      'name': 'Dr. Reyes',
      'relationship': 'Doctor',
      'phone': '+63 928 123 4567',
      'avatarUrl':
          'https://images.pexels.com/photos/5452201/pexels-photo-5452201.jpeg',
    },
  ];

  String tr(bool isTagalog, String en, String tl) => isTagalog ? tl : en;

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _birthdateController = TextEditingController();
  final TextEditingController _conditionsController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _birthdateController.dispose();
    _conditionsController.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    final profile = await _profileService.loadProfile();

    if (!mounted) return;
    setState(() {
      _nameController.text = profile.resolvedDisplayName ?? '';
      _emailController.text = profile.email ?? '';
      _phoneController.text = profile.phone ?? '';
      _birthdateController.text = profile.birthdate ?? '';
      _conditionsController.text = profile.medicalConditions ?? '';
    });
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
                onPressed: () async {
                  if (_isEditing) {
                    await _saveProfile(context);
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
                for (var i = 0; i < _emergencyContacts.length; i++) ...[
                  if (i > 0) _buildDivider(theme),
                  _buildContactTile(
                    theme,
                    name: _emergencyContacts[i]['name']!,
                    relationship: _emergencyContacts[i]['relationship']!,
                    phone: _emergencyContacts[i]['phone']!,
                    avatarUrl: _emergencyContacts[i]['avatarUrl']!,
                  ),
                ],
                if (_isEditing) ...[
                  _buildDivider(theme),
                  InkWell(
                    onTap: _openAddContactPage,
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
            _nameController.text.trim().isEmpty
                ? 'LifeEase Member'
                : _nameController.text,
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

  Future<void> _saveProfile(BuildContext context) async {
    var savedRemotely = true;
    final nameParts = _nameController.text.trim().split(RegExp(r'\s+'));

    try {
      await _profileService.saveProfile(
        UserProfile(
          firstName: nameParts.isNotEmpty ? nameParts.first : null,
          lastName: nameParts.length > 1 ? nameParts.skip(1).join(' ') : null,
          displayName: _nameController.text.trim(),
          email: _emailController.text.trim(),
          phone: _phoneController.text.trim(),
          birthdate: _birthdateController.text.trim(),
          medicalConditions: _conditionsController.text.trim(),
        ),
      );
    } catch (_) {
      savedRemotely = false;
    }

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          tr(
            LanguageController.isTagalog.value,
            savedRemotely
                ? 'Profile saved successfully'
                : 'Profile saved on this device',
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
            onPressed: () async {
              Navigator.pop(ctx);
              await _authService.signOut();
              if (!mounted) return;
              Navigator.pushNamedAndRemoveUntil(
                context,
                AppRoutes.loginScreen,
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

  Future<void> _openAddContactPage() async {
    final contact = await Navigator.push<Map<String, String>>(
      context,
      MaterialPageRoute(builder: (_) => const AddEmergencyContactScreen()),
    );

    if (contact == null) {
      return;
    }

    setState(() => _emergencyContacts.add(contact));
    _showSnackBar('Emergency contact added.');
  }
}

class AddEmergencyContactScreen extends StatefulWidget {
  const AddEmergencyContactScreen({super.key});

  @override
  State<AddEmergencyContactScreen> createState() =>
      _AddEmergencyContactScreenState();
}

class _AddEmergencyContactScreenState extends State<AddEmergencyContactScreen> {
  static const List<String> _relationships = [
    'Husband',
    'Wife',
    'Brother',
    'Sister',
    'Doctor',
    'Nurse',
    'Father',
    'Mother',
    'Son',
    'Daughter',
    'Friend',
    'Caregiver',
    'Other',
  ];

  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  String _relationship = _relationships.first;

  String tr(bool isTagalog, String en, String tl) => isTagalog ? tl : en;

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
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
              tr(
                isTagalog,
                'Add Emergency Contact',
                'Magdagdag ng Emergency Contact',
              ),
              style: GoogleFonts.nunitoSans(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.onSurface,
              ),
            ),
            backgroundColor: theme.colorScheme.surface,
            elevation: 0,
            scrolledUnderElevation: 2,
          ),
          body: SafeArea(
            child: Form(
              key: _formKey,
              child: ListView(
                padding: EdgeInsets.symmetric(horizontal: 4.w, vertical: 2.h),
                children: [
                  _buildHeaderCard(theme, isTagalog),
                  SizedBox(height: 2.h),
                  _buildFormCard(theme, isTagalog),
                  SizedBox(height: 3.h),
                  ElevatedButton.icon(
                    onPressed: _saveContact,
                    icon: const Icon(Icons.check, color: Colors.white),
                    label: Text(
                      tr(isTagalog, 'Save Contact', 'I-save ang Contact'),
                      style: GoogleFonts.nunitoSans(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryBlue,
                      minimumSize: const Size.fromHeight(52),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildHeaderCard(ThemeData theme, bool isTagalog) {
    return Container(
      padding: EdgeInsets.all(4.w),
      decoration: BoxDecoration(
        color: AppTheme.errorContainer.withAlpha(120),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.errorRed.withAlpha(55)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppTheme.errorRed.withAlpha(30),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.emergency,
              color: AppTheme.errorRed,
              size: 26,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tr(
                    isTagalog,
                    'Who should LifeEase call first?',
                    'Sino ang unang tatawagan ng LifeEase?',
                  ),
                  style: GoogleFonts.nunitoSans(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  tr(
                    isTagalog,
                    'Add a trusted person or healthcare provider for emergencies.',
                    'Magdagdag ng pinagkakatiwalaang tao o healthcare provider para sa emergency.',
                  ),
                  style: GoogleFonts.nunitoSans(
                    fontSize: 14,
                    height: 1.35,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFormCard(ThemeData theme, bool isTagalog) {
    return Container(
      padding: EdgeInsets.all(4.w),
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
      child: Column(
        children: [
          _buildTextField(
            theme,
            controller: _nameController,
            icon: Icons.person,
            label: tr(isTagalog, 'Full Name', 'Buong Pangalan'),
            hint: 'Juan dela Cruz',
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return tr(
                  isTagalog,
                  'Name is required',
                  'Kailangan ang pangalan',
                );
              }
              return null;
            },
          ),
          SizedBox(height: 2.h),
          _buildTextField(
            theme,
            controller: _phoneController,
            icon: Icons.phone,
            label: tr(isTagalog, 'Phone Number', 'Numero ng Telepono'),
            hint: '+63 917 000 0000',
            keyboardType: TextInputType.phone,
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return tr(
                  isTagalog,
                  'Phone number is required',
                  'Kailangan ang numero ng telepono',
                );
              }
              return null;
            },
          ),
          SizedBox(height: 2.h),
          DropdownButtonFormField<String>(
            initialValue: _relationship,
            icon: const Icon(Icons.expand_more),
            decoration: _fieldDecoration(
              theme,
              icon: Icons.favorite,
              label: tr(isTagalog, 'Relationship', 'Relasyon sa Contact'),
            ),
            borderRadius: BorderRadius.circular(14),
            style: GoogleFonts.nunitoSans(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurface,
            ),
            items: _relationships
                .map(
                  (relationship) => DropdownMenuItem(
                    value: relationship,
                    child: Text(relationship),
                  ),
                )
                .toList(),
            onChanged: (value) {
              if (value != null) {
                setState(() => _relationship = value);
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildTextField(
    ThemeData theme, {
    required TextEditingController controller,
    required IconData icon,
    required String label,
    required String hint,
    required String? Function(String?) validator,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      validator: validator,
      textInputAction: keyboardType == TextInputType.phone
          ? TextInputAction.done
          : TextInputAction.next,
      style: GoogleFonts.nunitoSans(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: theme.colorScheme.onSurface,
      ),
      decoration: _fieldDecoration(theme, icon: icon, label: label, hint: hint),
    );
  }

  InputDecoration _fieldDecoration(
    ThemeData theme, {
    required IconData icon,
    required String label,
    String? hint,
  }) {
    return InputDecoration(
      prefixIcon: Icon(icon, color: AppTheme.primaryBlue),
      labelText: label,
      hintText: hint,
      labelStyle: GoogleFonts.nunitoSans(
        fontWeight: FontWeight.w700,
        color: theme.colorScheme.onSurfaceVariant,
      ),
      hintStyle: GoogleFonts.nunitoSans(
        color: theme.colorScheme.onSurfaceVariant.withAlpha(170),
      ),
      filled: true,
      fillColor: theme.colorScheme.surfaceContainerHighest.withAlpha(120),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppTheme.primaryBlue, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppTheme.errorRed),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppTheme.errorRed, width: 2),
      ),
    );
  }

  void _saveContact() {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    Navigator.pop(context, {
      'name': _nameController.text.trim(),
      'relationship': _relationship,
      'phone': _phoneController.text.trim(),
      'avatarUrl':
          'https://images.pexels.com/photos/1181519/pexels-photo-1181519.jpeg',
    });
  }
}
