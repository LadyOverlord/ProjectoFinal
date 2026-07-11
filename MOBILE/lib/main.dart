// main.dart
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'screens/auth_check.dart';
import 'screens/home_page.dart';
import 'screens/map_page.dart';
import 'services/notification_service.dart';
import 'models/user_mode.dart';

void main() async { //funcao principal
  WidgetsFlutterBinding.ensureInitialized(); //cominucacao com o hardware do telefone
  await Firebase.initializeApp(); //
  await NotificationService.instance.init();
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});
  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  @override
  void initState() {
    super.initState();
    // Verifica se a app foi aberta a partir de uma notificação
    // enquanto estava em segundo plano (background → foreground)
    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      NotificationService.instance.handleNotificationNavigation(message.data);
    });

    // Verifica se a app foi aberta a partir de uma notificação
    // enquanto estava completamente fechada (terminated state)
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final message = await FirebaseMessaging.instance.getInitialMessage();
      if (message != null) {
        NotificationService.instance.handleNotificationNavigation(message.data);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      // ── Chave global do navigator — necessária para navegar a partir
      // do NotificationService sem precisar de um BuildContext ──────────
      navigatorKey: NotificationService.navigatorKey,
      // ── Rotas nomeadas (evitam imports circulares no serviço) ─────────
      routes: {
        '/home': (_) => const HomePage(mode: UserMode.authenticated),
        '/map':  (_) => const MapPage(),
      },
      home: const AuthCheck(),
    );
  }
}