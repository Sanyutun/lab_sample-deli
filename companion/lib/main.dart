import 'package:flutter/material.dart';

import 'core/app_services.dart';
import 'core/strings.dart';
import 'ui/screens/home_shell.dart';
import 'ui/screens/login_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final services = await AppServices.bootstrap();
  runApp(CompanionApp(services: services));
}

class CompanionApp extends StatelessWidget {
  const CompanionApp({super.key, required this.services});

  final AppServices services;

  @override
  Widget build(BuildContext context) {
    return AppScope(
      services: services,
      child: MaterialApp(
        title: S.appName,
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
          useMaterial3: true,
        ),
        home: AnimatedBuilder(
          animation: services.auth,
          builder: (context, _) {
            if (services.auth.isRestoring) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }
            return services.auth.isLoggedIn
                ? const HomeShell()
                : const LoginScreen();
          },
        ),
      ),
    );
  }
}
