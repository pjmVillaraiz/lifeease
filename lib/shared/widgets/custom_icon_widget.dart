import 'package:flutter/material.dart';

class CustomIconWidget extends StatelessWidget {
  static const Map<String, IconData> _icons = {
    'add_circle': Icons.add_circle,
    'add_circle_outline': Icons.add_circle_outline,
    'alarm': Icons.alarm,
    'alarm_outlined': Icons.alarm_outlined,
    'arrow_back': Icons.arrow_back,
    'badge': Icons.badge,
    'cake': Icons.cake,
    'calendar_today': Icons.calendar_today,
    'check': Icons.check,
    'check_circle': Icons.check_circle,
    'chevron_right': Icons.chevron_right,
    'contrast': Icons.contrast,
    'dark_mode': Icons.dark_mode,
    'delete': Icons.delete,
    'delete_outlined': Icons.delete_outlined,
    'description_outlined': Icons.description_outlined,
    'edit': Icons.edit,
    'edit_note': Icons.edit_note,
    'email': Icons.email,
    'emergency': Icons.emergency,
    'error': Icons.error,
    'event': Icons.event,
    'expand_more': Icons.expand_more,
    'fact_check': Icons.fact_check,
    'help_outline': Icons.help_outline,
    'home': Icons.home,
    'home_outlined': Icons.home_outlined,
    'info': Icons.info,
    'info_outline': Icons.info_outline,
    'lightbulb': Icons.lightbulb,
    'list_alt': Icons.list_alt,
    'local_hospital': Icons.local_hospital,
    'lock': Icons.lock,
    'logout': Icons.logout,
    'medical_information': Icons.medical_information,
    'medication': Icons.medication,
    'mic': Icons.mic,
    'mic_none': Icons.mic_none,
    'more_vert': Icons.more_vert,
    'notifications': Icons.notifications,
    'notifications_outlined': Icons.notifications_outlined,
    'person': Icons.person,
    'person_outlined': Icons.person_outlined,
    'phone': Icons.phone,
    'play_arrow': Icons.play_arrow,
    'privacy_tip': Icons.privacy_tip,
    'repeat': Icons.repeat,
    'restaurant': Icons.restaurant,
    'schedule': Icons.schedule,
    'settings': Icons.settings,
    'settings_outlined': Icons.settings_outlined,
    'shopping_cart': Icons.shopping_cart,
    'text_fields': Icons.text_fields,
    'translate': Icons.translate,
    'vibration': Icons.vibration,
    'visibility': Icons.visibility,
    'visibility_off': Icons.visibility_off,
    'volume_up': Icons.volume_up,
  };

  final String iconName;
  final double size;
  final Color? color;

  const CustomIconWidget({
    super.key,
    required this.iconName,
    this.size = 24,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Icon(
      _icons[iconName] ?? Icons.help_outline,
      size: size,
      color: color,
      semanticLabel: iconName,
    );
  }
}
