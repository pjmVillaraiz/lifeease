import 'package:flutter/services.dart';

import '../core/app_export.dart';
import '../core/language_controller.dart';
import '../core/settings_controller.dart';
import '../widgets/custom_error_widget.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  bool hasShownError = false;

  // 🚨 CRITICAL: Custom error handling - DO NOT REMOVE
  ErrorWidget.builder = (FlutterErrorDetails details) {
    if (!hasShownError) {
      hasShownError = true;

      // Reset flag after 3 seconds to allow error widget on new screens
      Future.delayed(Duration(seconds: 5), () {
        hasShownError = false;
      });

      return CustomErrorWidget(errorDetails: details);
    }
    return SizedBox.shrink();
  };

  // 🚨 CRITICAL: Device orientation lock - DO NOT REMOVE
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  final settingsController = await SettingsController.load();

  runApp(MyApp(settingsController: settingsController));
}

class MyApp extends StatelessWidget {
  final SettingsController settingsController;

  const MyApp({super.key, required this.settingsController});

  @override
  Widget build(BuildContext context) {
    return Sizer(
      builder: (context, orientation, screenType) {
        return AnimatedBuilder(
          animation: settingsController,
          builder: (context, child) {
            final isHighContrast = settingsController.highContrast;
            return ValueListenableBuilder<bool>(
              valueListenable: LanguageController.isTagalog,
              builder: (context, isTagalog, child) {
                return MaterialApp(
                  title: 'lifeease',
                  theme: isHighContrast
                      ? AppTheme.highContrastLightTheme
                      : AppTheme.lightTheme,
                  darkTheme: isHighContrast
                      ? AppTheme.highContrastDarkTheme
                      : AppTheme.darkTheme,
                  themeMode: settingsController.themeMode,
                  // 🚨 CRITICAL: NEVER REMOVE OR MODIFY
                  builder: (context, child) {
                    return MediaQuery(
                      data: MediaQuery.of(context).copyWith(
                        textScaler: TextScaler.linear(
                          settingsController.textScaleFactor,
                        ),
                      ),
                      child: child!,
                    );
                  },
                  // 🚨 END CRITICAL SECTION
                  debugShowCheckedModeBanner: false,
                  routes: AppRoutes.routes,
                  initialRoute: AppRoutes.initial,
                );
              },
            );
          },
        );
      },
    );
  }
}
