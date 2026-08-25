import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'core/services/storage_service.dart';
import 'core/theme/app_theme.dart';
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

  // Setup System UI Overlay styles
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: AppColors.sidebarBg,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  runApp(const TaduCloudAiAgentApp());
}

class TaduCloudAiAgentApp extends StatelessWidget {
  const TaduCloudAiAgentApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => GatewayProvider()),
        ChangeNotifierProvider(create: (_) => ServerProvider()),
        ChangeNotifierProvider(create: (_) => MetricsProvider()),
        ChangeNotifierProvider(create: (_) => ChatProvider()),
        ChangeNotifierProvider(create: (_) => LogsProvider()),
      ],
      child: MaterialApp(
        title: 'Tadu Cloud AI Agent Control Center',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.darkTheme,
        home: const MainNavigationScreen(),
      ),
    );
  }
}
