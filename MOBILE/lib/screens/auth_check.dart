import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart'; // Adicione este import
import 'login_page.dart';
import 'home_page.dart';
import 'admin_page.dart'; // Nova tela para admins (crie abaixo)
import '../models/user_mode.dart';

class AuthCheck extends StatelessWidget {
  const AuthCheck({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasData) {
          // Busca o role do usuário no Firestore
          return FutureBuilder<DocumentSnapshot>(
            future: FirebaseFirestore.instance.collection('users').doc(snapshot.data!.uid).get(),
            builder: (context, userSnapshot) {
              if (userSnapshot.connectionState == ConnectionState.waiting) {
                return const Scaffold(body: Center(child: CircularProgressIndicator()));
              }
              if (userSnapshot.hasData && userSnapshot.data!.exists) {
                final userData = userSnapshot.data!.data() as Map<String, dynamic>;
                final role = userData['role'] ?? 'user'; // Padrão 'user' se não existir
                if (role == 'admin') {
                  return const AdminPage(); // Tela de admin
                } else {
                  return const HomePage(mode: UserMode.authenticated); // Tela normal
                }
              } else {
                // Se não encontrar dados, assume user
                return const HomePage(mode: UserMode.authenticated);
              }
            },
          );
        }
        return const LoginPage();
      },
    );
  }
}