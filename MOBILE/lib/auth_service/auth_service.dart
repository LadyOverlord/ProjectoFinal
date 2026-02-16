import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'login_page.dart';
import 'home_page.dart';
import '../models/user_mode.dart';

class AuthCheck extends StatelessWidget {
  const AuthCheck({super.key});

  @override
  Widget build(BuildContext context) {
    // StreamBuilder observa mudanças no login em tempo real
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(), // envia eventos de login/logout

      builder: (context, snapshot) {
        // Enquanto verifica login, mostra um loading
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        // Se tem usuário logado
        if (snapshot.hasData) {
          return const HomePage(mode: UserMode.authenticated);
        }

        // Se NÃO tem usuário logado
        return const LoginPage();
      },
    );
  }
}
