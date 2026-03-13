import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'home_page.dart';
import 'register_page.dart';
import 'admin_page.dart';
import '../models/user_mode.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  Future<void> _loginWithEmail(BuildContext context) async {
    try {
      UserCredential userCredential =
          await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );

      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(userCredential.user!.uid)
          .get();

      final role = userDoc.exists
          ? (userDoc.data() as Map<String, dynamic>)['role'] ?? 'user'
          : 'user';

      if (!mounted) return;

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => role == 'admin'
              ? const AdminPage()
              : const HomePage(mode: UserMode.authenticated),
        ),
      );
    } on FirebaseAuthException catch (e) {
      String errorMessage;

      switch (e.code) {
        case 'user-not-found':
          errorMessage = 'Conta não encontrada.';
          break;
        case 'wrong-password':
          errorMessage = 'Senha incorreta.';
          break;
        case 'invalid-email':
          errorMessage = 'Email inválido.';
          break;
        case 'user-disabled':
          errorMessage = 'Conta desativada.';
          break;
        default:
          errorMessage = 'Erro ao fazer login.';
      }

      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(errorMessage)));
    } catch (_) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Erro inesperado.')),
      );
    }
  }

  Future<void> _loginWithGoogle(BuildContext context) async {
    try {
      final googleUser = await GoogleSignIn().signIn();
      if (googleUser == null) return;

      final googleAuth = await googleUser.authentication;

      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      await FirebaseAuth.instance.signInWithCredential(credential);

      final user = FirebaseAuth.instance.currentUser;

      if (user != null) {
        final userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();

        final role = userDoc.exists
            ? (userDoc.data() as Map<String, dynamic>)['role'] ?? 'user'
            : 'user';

        if (!mounted) return;

        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => role == 'admin'
                ? const AdminPage()
                : const HomePage(mode: UserMode.authenticated),
          ),
        );
      }
    } catch (_) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Erro no login com Google.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;

    return Scaffold(
      resizeToAvoidBottomInset: false, // 🔥 impede layout subir
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          // 🔵 Rodapé azul FIXO
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              height: 120,
              color: const Color(0xFF0077B6),
            ),
          ),

          // Conteúdo principal
          SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: 30),
            child: Column(
              children: [
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 28, vertical: 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          "Entrar",
                          style: TextStyle(
                            fontSize: 34,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const Text(
                          "Bem-vindo de volta!",
                          style: TextStyle(color: Colors.grey),
                        ),
                        const SizedBox(height: 30),
                        _buildTextField("Email:", "seu e-mail",
                            controller: _emailController),
                        const SizedBox(height: 12),
                        _buildTextField("Senha:", "sua senha",
                            controller: _passwordController,
                            obscureText: true),
                        const SizedBox(height: 20),
                        SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: ElevatedButton(
                            onPressed: () => _loginWithEmail(context),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF90E0EF),
                              foregroundColor: Colors.black87,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8)),
                            ),
                            child: const Text("Entrar"),
                          ),
                        ),
                        TextButton(
                          onPressed: () {
                            Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (_) => const RegisterPage()));
                          },
                          child: const Text(
                              "Não tem conta? Cadastre-se aqui"),
                        ),
                        const SizedBox(height: 15),
                        Row(
                          children: [
                            Expanded(
                              child: _socialButton(
                                  "Google",
                                  Icons.g_mobiledata,
                                  Colors.red,
                                  () => _loginWithGoogle(context)),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _socialButton(
                                  "Convidado",
                                  Icons.person_outline,
                                  Colors.blueGrey,
                                  () => Navigator.pushReplacement(
                                        context,
                                        MaterialPageRoute(
                                            builder: (_) =>
                                                const HomePage(
                                                    mode:
                                                        UserMode.guest)),
                                      )),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),

                // 🗺️ IMAGEM CENTRALIZADA
                Container(
                  height: screenHeight * 0.35,
                  width: double.infinity,
                  alignment: Alignment.center, // 🔥 centraliza
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Image.asset(
                        'assets/images/desaparecidosimg3.jpeg',
                        fit: BoxFit.cover,
                        width: double.infinity,
                        height: double.infinity,
                        alignment: Alignment.center,
                      ),
                      Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.transparent,
                              const Color(0xFF0077B6)
                                  .withOpacity(0.7),
                            ],
                          ),
                        ),
                      ),
                      const Padding(
                        padding:
                            EdgeInsets.symmetric(horizontal: 60),
                        child: Text(
                          "",
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextField(String label, String hint,
      {TextEditingController? controller,
      bool obscureText = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          obscureText: obscureText,
          decoration: InputDecoration(
            hintText: hint,
            filled: true,
            fillColor: const Color(0xFFF8F9FA),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8)),
          ),
        ),
      ],
    );
  }

  Widget _socialButton(String label, IconData icon,
      Color color, VoidCallback onPressed) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, color: color),
      label: Text(label),
    );
  }
}
