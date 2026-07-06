// screens/auth_check.dart
// MODIFICADO: verifica isSuspended e redireciona para SuspendedPage
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'login_page.dart';
import 'home_page.dart';
import 'admin_page.dart';
import 'suspended_page.dart';          // ← NOVO
import 'terms_acceptance_page.dart';   // ← NOVO
import '../models/user_mode.dart';
import '../services/notification_service.dart';

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
          NotificationService.instance.salvarTokenAposLogin();

          // CORRIGIDO: era FutureBuilder com .get() — uma leitura única, feita
          // só no momento do login. Se o utilizador já estava dentro da app
          // quando o admin o suspendia, esta verificação nunca voltava a
          // correr (não há novo login, não há novo .get()), e ele continuava
          // a usar a app normalmente até fazer logout/login de novo.
          // Com .snapshots() (StreamBuilder), qualquer alteração a
          // isSuspended/trustScore no Firestore chega em tempo real e o
          // ecrã muda para SuspendedPage de imediato, sem precisar de sair.
          return StreamBuilder<DocumentSnapshot>(
            stream: FirebaseFirestore.instance
                .collection('users')
                .doc(snapshot.data!.uid)
                .snapshots(),
            builder: (context, userSnapshot) {
              if (userSnapshot.connectionState == ConnectionState.waiting) {
                return const Scaffold(
                  body: Center(child: CircularProgressIndicator()),
                );
              }

              if (userSnapshot.hasData && userSnapshot.data!.exists) {
                final userData =
                    userSnapshot.data!.data() as Map<String, dynamic>;
                final role        = userData['role']        ?? 'user';
                final isSuspended = userData['isSuspended'] as bool? ?? false;
                final trustScore  = userData['trustScore']  as int?  ?? 100;
                final termosVersao = userData['termosVersao'] as String?;

                // ── NOVO: gate de aceitação de termos ──────────────────────
                // Cobre tanto contas novas (nunca tiveram este campo) como
                // já existentes (versão desactualizada). Fica ANTES da
                // verificação de suspensão de propósito — aceitar os termos
                // actuais é mais fundamental do que qualquer outro estado
                // da conta, incluindo estar suspenso.
                if (termosVersao != kTermosVersaoActual) {
                  return const TermsAcceptancePage();
                }

                // ── suspensos vão para SuspendedPage ───────────────────────
                if (isSuspended || trustScore <= 0) {
                  return const SuspendedPage();
                }

                if (role == 'admin') {
                  return const AdminPage();
                } else {
                  return const HomePage(mode: UserMode.authenticated);
                }
              }

              return const HomePage(mode: UserMode.authenticated);
            },
          );
        }

        return const LoginPage();
      },
    );
  }
}