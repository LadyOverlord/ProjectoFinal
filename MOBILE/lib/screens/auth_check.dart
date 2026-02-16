import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart'; // Firebase Auth
import 'login_page.dart'; // tela de login
import 'home_page.dart';  // tela principal
import '../models/user_mode.dart'; // enum de modos de usuário

class AuthCheck extends StatelessWidget {
  const AuthCheck({super.key});

  @override
  Widget build(BuildContext context) {
    // StreamBuilder observa mudanças no login em tempo real
    // Sempre que o usuário loga ou desloga, o Firebase envia um evento
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(), // fluxo de eventos do login

      builder: (context, snapshot) {
        // 1️⃣ Enquanto verifica o login, mostra um loading
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        // 2️⃣ Se o Firebase indica que tem um usuário logado
        if (snapshot.hasData) {
          return const HomePage(
            mode: UserMode.authenticated, // usuário logado
          );
        }

        // 3️⃣ Se não tem usuário logado
        return const LoginPage();
      },
    );
  }
}
