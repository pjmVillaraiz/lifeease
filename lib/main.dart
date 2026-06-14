import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'package:app_links/app_links.dart';

import 'package:lifeease/core/navigation/app_navigator.dart';
import 'package:lifeease/core/utils/app_export.dart';
import 'package:lifeease/features/reminders/application/due_reminder_prompt_coordinator.dart';
import 'package:lifeease/core/constants/env_config.dart';
import 'package:lifeease/shared/providers/language_controller.dart';
import 'package:lifeease/shared/providers/settings_controller.dart';
import 'package:lifeease/core/services/backend/reminder_repository.dart';
import 'package:lifeease/core/services/backend/supabase_auth_service.dart';
import 'package:lifeease/core/services/notifications/reminder_notification_service.dart';
import 'package:lifeease/core/services/supabase_config.dart';
import 'package:lifeease/shared/widgets/custom_error_widget.dart';

class _DeepLinkHandler {
  static void setup() {
    final links = AppLinks();
    links.uriLinkStream.listen((uri) {
      if (uri.scheme == 'io.supabase.lifeease' &&
          uri.host == 'reset-callback') {
        AppNavigator.key.currentState?.pushNamedAndRemoveUntil(
          AppRoutes.resetPasswordScreen,
          (route) => false,
        );
      }
    });
  }
}

void main() async {
  // 1. Initialize Flutter bindings immediately
  WidgetsFlutterBinding.ensureInitialized();

  // 2. Set up global error handling for build-time errors
  _setupErrorHandling();

  // 3. Render immediately, then bootstrap the app asynchronously.
  runApp(const StartupApp());
}

void _setupErrorHandling() {
  bool hasShownError = false;

  ErrorWidget.builder = (FlutterErrorDetails details) {
    if (!hasShownError) {
      hasShownError = true;

      // Reset flag after 5 seconds
      Future.delayed(const Duration(seconds: 5), () {
        hasShownError = false;
      });

      try {
        return CustomErrorWidget(errorDetails: details);
      } catch (e) {
        // Ultimate fallback if CustomErrorWidget itself fails
        return MaterialApp(
          home: Scaffold(
            body: Center(
              child: Text(
                'A build error occurred:\n${details.exception}',
                textAlign: TextAlign.center,
              ),
            ),
          ),
        );
      }
    }
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Text(
              'A build error occurred:\n${details.exception}',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  };
}

Future<void> _bootstrapNotifications() async {
  try {
    await ReminderNotificationService.instance.initialize();
    final reminders = await ReminderRepository().loadReminders();
    await ReminderNotificationService.instance.schedulePendingReminders(
      reminders,
    );
  } catch (error) {
    // Notifications should never prevent the app UI from loading.
    debugPrint('Notification startup skipped: $error');
  }
}

class StartupApp extends StatefulWidget {
  const StartupApp({super.key});

  @override
  State<StartupApp> createState() => _StartupAppState();
}

class _StartupAppState extends State<StartupApp> {
  SettingsController? _settingsController;
  String _initialRoute = AppRoutes.loginScreen;
  Object? _startupError;
  bool _initializing = true;

  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    try {
      await EnvConfig.load().timeout(const Duration(seconds: 10));

      await Future.wait([
        SupabaseConfig.initialize(),
        SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]),
        if (defaultTargetPlatform == TargetPlatform.android)
          AndroidAlarmManager.initialize(),
      ]).timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          debugPrint('⚠️ Some initializations timed out, continuing...');
          return [];
        },
      );

      final settingsController = await SettingsController.load();
      final authService = SupabaseAuthService();
      final shouldStartAtHome = await authService.shouldStartAtHome();

      if (!mounted) {
        return;
      }

      setState(() {
        _settingsController = settingsController;
        _initialRoute = shouldStartAtHome
            ? AppRoutes.homeScreen
            : AppRoutes.loginScreen;
        _initializing = false;
      });

      WidgetsBinding.instance.addPostFrameCallback((_) {
        _bootstrapNotifications();
      });
    } catch (error, stack) {
      debugPrint('🚨 CRITICAL STARTUP ERROR: $error');
      debugPrint(stack.toString());

      if (!mounted) {
        return;
      }

      setState(() {
        _startupError = error;
        _initializing = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_startupError != null) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Text(
                'Failed to start LifeEase.\n\nDetails: $_startupError',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.red, fontSize: 16),
              ),
            ),
          ),
        ),
      );
    }

    if (_initializing || _settingsController == null) {
      return const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Starting LifeEase...'),
              ],
            ),
          ),
        ),
      );
    }

    return MyApp(
      settingsController: _settingsController!,
      initialRoute: _initialRoute,
    );
  }
}

class MyApp extends StatelessWidget {
  final SettingsController settingsController;
  final String initialRoute;

  const MyApp({
    super.key,
    required this.settingsController,
    required this.initialRoute,
  });

  @override
  Widget build(BuildContext context) {
    _DeepLinkHandler.setup();
    return Sizer(
      builder: (context, orientation, screenType) {
        return AnimatedBuilder(
          animation: settingsController,
          builder: (context, child) {
            final isHighContrast = settingsController.highContrast;
            return ValueListenableBuilder<bool>(
              valueListenable: LanguageController.isTagalog,
              builder: (context, isTagalog, child) {
                return DueReminderPromptListener(
                  child: MaterialApp(
                  navigatorKey: AppNavigator.key,
                  title: 'LifeEase',
                  theme: isHighContrast
                      ? AppTheme.highContrastLightTheme
                      : AppTheme.lightTheme,
                  darkTheme: isHighContrast
                      ? AppTheme.highContrastDarkTheme
                      : AppTheme.darkTheme,
                  themeMode: settingsController.themeMode,
                  // 🚨 CRITICAL: MediaQuery override for text scaling
                  builder: (context, widget) {
                    return MediaQuery(
                      data: MediaQuery.of(context).copyWith(
                        textScaler: TextScaler.linear(
                          settingsController.textScaleFactor,
                        ),
                      ),
                      // Provide a visible fallback if child is null
                      child:
                          widget ??
                          const Center(child: CircularProgressIndicator()),
                    );
                  },
                  debugShowCheckedModeBanner: false,
                  routes: AppRoutes.routes,
                  initialRoute: initialRoute,
                ),
                );
              },
            );
          },
        );
      },
    );
  }
}
