import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'core/services/database_service.dart';
import 'core/services/local_config_service.dart';
import 'core/services/storage_service.dart';
import 'core/theme/app_theme.dart';
import 'providers/auth_provider.dart';
import 'providers/chat_provider.dart';
import 'providers/gateway_provider.dart';
import 'providers/logs_provider.dart';
import 'providers/metrics_provider.dart';
import 'providers/server_provider.dart';
import 'screens/main_navigation_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Storage Service
  await StorageService().init();

  // Initialize Database and Local Config (Desktop & Mobile)
  try {
    await DatabaseService().init();
    await LocalConfigService().loadConfig();
  } catch (_) {}

  // Setup System UI Overlay styles
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: AppColors.sidebarBg,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  runApp(const AiTypeAgentApp());
}

class AiTypeAgentApp extends StatelessWidget {
  const AiTypeAgentApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => GatewayProvider()),
        ChangeNotifierProvider(create: (_) => ServerProvider()),
        ChangeNotifierProvider(create: (_) => MetricsProvider()),
        ChangeNotifierProvider(create: (_) => ChatProvider()),
        ChangeNotifierProvider(create: (_) => LogsProvider()),
      ],
      child: MaterialApp(
        title: 'AI Type Agent Control Server',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.darkTheme,
        home: const MainNavigationScreen(),
      ),
    );
  }
}
