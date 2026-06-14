import 'package:flutter/material.dart';

import 'package:lifeease/features/reminders/presentation/add_reminder_screen/add_reminder_screen.dart';
import 'package:lifeease/features/reminders/presentation/all_reminders_screen/all_reminders_screen.dart';
import 'package:lifeease/features/reminders/presentation/home_screen/home_screen.dart';
import 'package:lifeease/features/accessibility/presentation/login_screen/login_screen.dart';
import 'package:lifeease/features/accessibility/presentation/register_screen/register_screen.dart';
import 'package:lifeease/features/accessibility/presentation/forgot_password_screen/forgot_password_screen.dart';
import 'package:lifeease/features/accessibility/presentation/reset_password_screen/reset_password_screen.dart';
import 'package:lifeease/features/accessibility/presentation/settings_screen/settings_screen.dart';
import 'package:lifeease/features/accessibility/presentation/profile_screen/profile_screen.dart';

class AppRoutes {
  static const String initial = '/';
  static const String homeScreen = '/home-screen';
  static const String loginScreen = '/login-screen';
  static const String registerScreen = '/register';
  static const String forgotPasswordScreen = '/forgot-password';
  static const String resetPasswordScreen = '/reset-password';
  static const String addReminderScreen = '/add-reminder-screen';
  static const String allRemindersScreen = '/all-reminders-screen';
  static const String settingsScreen = '/settings-screen';
  static const String profileScreen = '/profile-screen';

  static Map<String, WidgetBuilder> routes = {
    initial: (context) => const LoginScreen(),
    homeScreen: (context) => const HomeScreen(),
    loginScreen: (context) => const LoginScreen(),
    registerScreen: (context) => const RegisterScreen(),
    forgotPasswordScreen: (context) => const ForgotPasswordScreen(),
    resetPasswordScreen: (context) => const ResetPasswordScreen(),
    allRemindersScreen: (context) => const AllRemindersScreen(),
    settingsScreen: (context) => const SettingsScreen(),
    profileScreen: (context) => const ProfileScreen(),
    addReminderScreen: (context) {
      final args =
          ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
      return AddReminderScreen(
        prefillHour: args?['prefillHour'] as int?,
        prefillTitle: args?['prefillTitle'] as String?,
        prefillDescription: args?['prefillDescription'] as String?,
        prefillDate: args?['prefillDate'] as DateTime?,
        prefillTime: args?['prefillTime'] as TimeOfDay?,
        prefillRepeatType: args?['prefillRepeatType'] as String?,
        prefillRepeatIntervalMinutes:
            args?['prefillRepeatIntervalMinutes'] as int?,
        editReminder: args?['editReminder'] as Map<String, dynamic>?,
      );
    },
  };
}
