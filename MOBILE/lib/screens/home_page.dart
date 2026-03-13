import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../models/user_mode.dart';
import 'login_page.dart';
import 'chatbot_page.dart';
import 'profile.dart';
import 'create_caso_dialog.dart'; // Formulário de criação
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key, required this.mode});

  final UserMode mode;

  bool get isGuest => FirebaseAuth.instance.currentUser == null;

  void _redirectToLogin(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Acesso Restrito'),
        content: const Text('Para interagir, faça login ou cadastre-se.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const LoginPage()),
              );
            },
            child: const Text('Login'),
          ),
        ],
      ),
    );
  }

  void _handleInteraction(BuildContext context, String action) {
    if (isGuest) {
      _redirectToLogin(context);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$action realizado')),
      );
    }
  }

  void _handleCreate(BuildContext context) {
    if (isGuest) {
      _redirectToLogin(context);
    } else {
      showDialog(
        context: context,
        builder: (_) => const CreateCasoDialog(),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[900],
      appBar: AppBar(
        backgroundColor: Colors.grey[900],
        elevation: 0,
        title: const Text(
          "Missing AO",
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 22,
          ),
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Container(
              height: 45,
              decoration: BoxDecoration(
                color: Colors.grey[800],
                borderRadius: BorderRadius.circular(15),
              ),
              child: const TextField(
                style: TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: "Procurar...",
                  hintStyle: TextStyle(color: Colors.grey),
                  prefixIcon: Icon(Icons.search, color: Colors.grey),
                  border: InputBorder.none,
                ),
              ),
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('casos')
                  .orderBy('createdAt', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return const Center(
                    child: Text(
                      'Nenhum caso ainda.',
                      style: TextStyle(color: Colors.white),
                    ),
                  );
                }

                final casos = snapshot.data!.docs;

                return ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: casos.length,
                  itemBuilder: (context, index) {
                    final caso = casos[index].data() as Map<String, dynamic>;

                    final nome = caso['nome'] ?? 'Nome não informado';
                    final municipio = caso['municipio'] ?? 'Não informado';
                    final provincia = caso['provincia'] ?? 'Província';
                    final ultimoLocal = caso['ultimo_local'] ?? 'Local não informado';
                    final info = caso['informacoes_adicionais'] ?? 'Sem informações adicionais';
                    final roupas = caso['roupas'] ?? 'Não informado';
                    final imageField = caso['imagem'] ?? '';

                    Uint8List? imageBytes;
                    if (imageField.toString().startsWith('data:image')) {
                      final base64String = imageField.toString().split(',').last;
                      imageBytes = base64Decode(base64String);
                    }

                    return Card(
                      color: Colors.grey[850],
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ListTile(
                            title: Text(
                              nome,
                              style: const TextStyle(
                                  color: Colors.white, fontWeight: FontWeight.bold),
                            ),
                            subtitle: Text(
                              '$municipio, $provincia',
                              style: const TextStyle(color: Colors.grey),
                            ),
                          ),
                          imageBytes != null
                              ? Image.memory(
                                  imageBytes,
                                  height: 250,
                                  width: double.infinity,
                                  fit: BoxFit.cover,
                                )
                              : Container(
                                  height: 250,
                                  color: Colors.grey[800],
                                  child: const Center(
                                    child: Icon(Icons.image_not_supported, color: Colors.white),
                                  ),
                                ),
                          Padding(
                            padding: const EdgeInsets.all(15),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  ultimoLocal,
                                  style: const TextStyle(
                                      color: Colors.redAccent, fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  '$info. Roupas: $roupas.',
                                  style: const TextStyle(color: Colors.white),
                                ),
                                const SizedBox(height: 15),
                                Row(
                                  children: [
                                    Expanded(
                                      child: TextButton.icon(
                                        onPressed: () => _handleInteraction(context, 'Apoiar'),
                                        icon: const Icon(Icons.favorite_border,
                                            size: 16, color: Colors.white),
                                        label: const Text(
                                          "Apoiar",
                                          style: TextStyle(color: Colors.white),
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      child: TextButton.icon(
                                        onPressed: () => _handleInteraction(context, 'Comentar'),
                                        icon: const Icon(Icons.mode_comment_outlined,
                                            size: 16, color: Colors.white),
                                        label: const Text(
                                          "Comentar",
                                          style: TextStyle(color: Colors.white),
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      child: TextButton.icon(
                                        onPressed: () => _handleInteraction(context, 'Partilhar'),
                                        icon: const Icon(Icons.send_outlined,
                                            size: 16, color: Colors.white),
                                        label: const Text(
                                          "Partilhar",
                                          style: TextStyle(color: Colors.white),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _handleCreate(context),
        backgroundColor: Colors.blueAccent,
        child: const Icon(Icons.add),
      ),
      bottomNavigationBar: BottomNavigationBar(
        backgroundColor: Colors.grey[900],
        selectedItemColor: Colors.blueAccent,
        unselectedItemColor: Colors.grey,
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home_filled), label: 'Home'),
          BottomNavigationBarItem(icon: Icon(Icons.location_on_outlined), label: 'Mapa'),
          BottomNavigationBarItem(icon: Icon(Icons.auto_awesome), label: 'Chatbot'),
          BottomNavigationBarItem(icon: Icon(Icons.person_outline), label: 'Perfil'),
        ],
        onTap: (index) {
          if (index == 2) {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ChatbotPage()),
            );
          } else if (index == 3) {
            if (isGuest) {
              _redirectToLogin(context);
            } else {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const  ProfileScreen()),
              );
            }
          }
        },
      ),
    );
  }
}