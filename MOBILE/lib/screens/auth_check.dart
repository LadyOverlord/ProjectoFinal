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

                // ── NOVO/CORRIGIDO: verificação de email obrigatória ───────
                // Antes isto só era tentado no botão de login
                // (login_page.dart), mas este StreamBuilder reage a
                // authStateChanges() em tempo real — ou seja, assim que o
                // Firebase Auth confirma o login (mesmo com email por
                // verificar), ESTE código já decidia sozinho ir para a
                // Home, numa corrida que ganhava sempre ao signOut() do
                // botão. Por ser o único sítio que realmente controla para
                // onde se navega, a verificação tem de estar aqui.
                final emailVerificado = snapshot.data!.emailVerified;
                if (!emailVerificado && role != 'admin') {
                  return _TelaEmailNaoVerificado(email: snapshot.data!.email ?? '');
                }

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
                // CORRIGIDO: admins não têm Trust Score (não faz sentido
                // uma conta admin ser suspensa por pontuação — é ela
                // própria, geralmente, quem aplica essas penalizações a
                // utilizadores comuns). Antes esta verificação corria para
                // todos os roles; agora ignora-a por completo para admins.
                if (role != 'admin' && (isSuspended || trustScore <= 0)) {
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

// ─────────────────────────────────────────────────────────────────────────────
// NOVO — ecrã bloqueante enquanto o email não é verificado (exceto admins).
// Fica aqui (e não em login_page.dart) precisamente porque é o AuthCheck,
// e só o AuthCheck, que decide o que aparece depois de um login com sucesso.
// ─────────────────────────────────────────────────────────────────────────────
class _TelaEmailNaoVerificado extends StatefulWidget {
  final String email;
  const _TelaEmailNaoVerificado({required this.email});

  @override
  State<_TelaEmailNaoVerificado> createState() => _TelaEmailNaoVerificadoState();
}

class _TelaEmailNaoVerificadoState extends State<_TelaEmailNaoVerificado> {
  bool _enviando = false;
  bool _enviado = false;
  bool _verificando = false;

  Future<void> _reenviarEmail() async {
    setState(() => _enviando = true);
    try {
      await FirebaseAuth.instance.currentUser?.sendEmailVerification();
      if (mounted) setState(() { _enviando = false; _enviado = true; });
    } catch (e) {
      if (mounted) {
        setState(() => _enviando = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao reenviar: $e')),
        );
      }
    }
  }

  // NOVO: User.reload() actualiza os dados locais (incluindo
  // emailVerified) a partir do servidor, mas NÃO dispara sozinho o
  // authStateChanges() que o AuthCheck escuta — por isso, mesmo depois
  // de confirmado no email, o ecrã não mudava sozinho. Reconstruir o
  // AuthCheck manualmente (com um novo StreamBuilder) força uma nova
  // leitura do currentUser já actualizado.
  Future<void> _jaVerifiquei() async {
    setState(() => _verificando = true);
    try {
      await FirebaseAuth.instance.currentUser?.reload();
      if (!mounted) return;
      if (FirebaseAuth.instance.currentUser?.emailVerified == true) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const AuthCheck()),
          (_) => false,
        );
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ainda não confirmámos a verificação. Tente reenviar o email e clique no link.')),
      );
    } finally {
      if (mounted) setState(() => _verificando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 80, height: 80,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE3F2FD),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Icon(Icons.mark_email_unread_rounded, color: Color(0xFF0077B6), size: 40),
                ),
                const SizedBox(height: 20),
                const Text(
                  'Verifique o seu email',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'Enviámos um link de confirmação para:\n${widget.email}',
                  style: const TextStyle(color: Colors.grey, fontSize: 14, height: 1.5),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 6),
                const Text(
                  'Clique no link do email, depois volte aqui e toque em "Já verifiquei".',
                  style: TextStyle(color: Colors.grey, fontSize: 12),
                  textAlign: TextAlign.center,
                ),
                if (_enviado) ...[
                  const SizedBox(height: 14),
                  const Text(
                    '✅ Email reenviado! Verifique a caixa de entrada (e o Spam).',
                    style: TextStyle(color: Color(0xFF22C55E), fontSize: 13, fontWeight: FontWeight.w600),
                    textAlign: TextAlign.center,
                  ),
                ],
                const SizedBox(height: 28),
                SizedBox(
                  width: double.infinity, height: 48,
                  child: ElevatedButton(
                    onPressed: _verificando ? null : _jaVerifiquei,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0077B6),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: _verificando
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Text('Já verifiquei — actualizar'),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity, height: 48,
                  child: OutlinedButton(
                    onPressed: _enviando ? null : _reenviarEmail,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF0077B6),
                      side: const BorderSide(color: Color(0xFF0077B6)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: _enviando
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Reenviar email'),
                  ),
                ),
                const SizedBox(height: 10),
                TextButton(
                  onPressed: () async {
                    await NotificationService.instance.removerTokenAntesDeSair();
                    await FirebaseAuth.instance.signOut();
                  },
                  child: const Text('Sair', style: TextStyle(color: Colors.grey)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}