import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'core/app_colors.dart';
import 'services/backend_service.dart';
import 'ui/main_navigation.dart';
import 'ui/splash_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // حماية التطبيق من الانهيار إذا فشلت تهيئة الخدمات في الخلفية
  try {
    await BackendService().initBackend();
  } catch (e) {
    debugPrint('Backend Init Error: $e');
  }



  // انطلاق التطبيق بغض النظر عن أي أخطاء في الخلفية
  runApp(const BoyktaApp());
}

class BoyktaApp extends StatelessWidget {
  const BoyktaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: BackendService().themeNotifier,
      builder: (context, currentMode, child) {
        return MaterialApp(
          title: 'Boykta',
          debugShowCheckedModeBanner: false,
          themeMode: currentMode,
          theme: ThemeData.light().copyWith(
            scaffoldBackgroundColor: const Color(0xFFF5F5FA),
            primaryColor: AppColors.cyan,
          ),
          darkTheme: ThemeData.dark().copyWith(
            scaffoldBackgroundColor: AppColors.background,
            primaryColor: AppColors.cyan,
          ),
          home: const SplashScreen(),
        );
      },
    );
  }
}
