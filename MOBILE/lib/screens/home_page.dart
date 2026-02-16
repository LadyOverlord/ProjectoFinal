import 'package:flutter/material.dart';
import '../models/user_mode.dart';
import 'login_page.dart';
import 'package:firebase_auth/firebase_auth.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key, required this.mode});

  final UserMode mode;

  // Dados mockados para os cards (simulando dados do banco)
  final List<Map<String, dynamic>> _posts = const [
    {
      'family': 'Família António',
      'location': 'Luanda, Angola',
      'imageUrl': 'https://images.unsplash.com/photo-1531123897727-8f129e16fd3c?w=500',
      'name': 'Miguel António, 12 anos',
      'lastSeen': 'Nova-vida, Luanda',
      'description': 'Visto pela última vez trajando t-shirt branca e calças azuis. Por favor, ajudem.',
    },
    {
      'family': 'Família Silva',
      'location': 'Benguela, Angola',
      'imageUrl': 'https://images.unsplash.com/photo-1529139574466-a3090c302d1a?w=500',
      'name': 'Ana Silva, 8 anos',
      'lastSeen': 'Zona Comercial, Benguela',
      'description': 'Desaparecida desde ontem. Estava com um vestido cor-de-rosa. Ajudem a partilhar.',
    },
    {
      'family': 'Família Santos',
      'location': 'Huambo, Angola',
      'imageUrl': 'https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?w=500',
      'name': 'Pedro Santos, 25 anos',
      'lastSeen': 'Bairro Operário, Huambo',
      'description': 'Saiu de casa para o trabalho e não regressou. Qualquer info é importante.',
    },
  ];

  // Função para redirecionar guests ao login
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
              Navigator.push(context, MaterialPageRoute(builder: (_) => const LoginPage()));
            },
            child: const Text('Login'),
          ),
        ],
      ),
    );
  }

  // Função para simular criação de publicação (expandir para tela real)
  void _createPost(BuildContext context) {
    if (mode == UserMode.guest) {
      _redirectToLogin(context);
    } else {
      // Para authenticated: Abrir dialog simples (substitua por navegação para tela de criação)
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Criar Publicação'),
          content: const Text('Funcionalidade em desenvolvimento. Aqui você criaria uma nova publicação.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
  }

  // Função para simular apoiar/comentar (expandir para lógica real)
  void _interact(BuildContext context, String action) {
    if (mode == UserMode.guest) {
      _redirectToLogin(context);
    } else {
      // Para authenticated: Simular ação (substitua por lógica real, ex.: salvar no Firestore)
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$action realizado!')),
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
          "Desaparecidos",
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 22,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_none_rounded, color: Colors.white),
            onPressed: () {},
          ),
        ],
      ),
      body: Column(
        children: [
          // BARRA DE PESQUISA
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

          // LISTA DE CARDS DINÂMICOS
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _posts.length,
              itemBuilder: (context, index) {
                final post = _posts[index];
                return Card(
                  clipBehavior: Clip.antiAlias,
                  color: Colors.grey[850],
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ListTile(
                        leading: const CircleAvatar(backgroundColor: Colors.blueAccent, child: Icon(Icons.person, color: Colors.white)),
                        title: Text(post['family'], style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                        subtitle: Text(post['location'], style: const TextStyle(color: Colors.grey, fontSize: 12)),
                        trailing: const Icon(Icons.more_horiz, color: Colors.grey),
                      ),
                      Image.network(
                        post['imageUrl'],
                        height: 250,
                        width: double.infinity,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) => Container(
                          height: 250,
                          color: Colors.grey[800],
                          child: const Icon(Icons.broken_image, color: Colors.grey),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(15),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(post['name'], style: const TextStyle(color: Colors.white, fontSize: 18)),
                            const SizedBox(height: 5),
                            Text(post['lastSeen'], style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 12),
                            Text(post['description'], style: const TextStyle(color: Colors.grey, fontSize: 13)),
                            const SizedBox(height: 15),
                            Row(
                              children: [
                                Expanded(
                                  child: TextButton.icon(
                                    onPressed: () => _interact(context, 'Apoiar'),
                                    icon: const Icon(Icons.favorite_border, color: Colors.grey, size: 16),
                                    label: const Text("Apoiar", style: TextStyle(color: Colors.grey, fontSize: 10)),
                                    style: TextButton.styleFrom(backgroundColor: Colors.white.withOpacity(0.05), padding: EdgeInsets.zero),
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: TextButton.icon(
                                    onPressed: () => _interact(context, 'Comentar'),
                                    icon: const Icon(Icons.mode_comment_outlined, color: Colors.grey, size: 16),
                                    label: const Text("Comentar", style: TextStyle(color: Colors.grey, fontSize: 10)),
                                    style: TextButton.styleFrom(backgroundColor: Colors.white.withOpacity(0.05), padding: EdgeInsets.zero),
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: TextButton.icon(
                                    onPressed: () => _interact(context, 'Partilhar'),
                                    icon: const Icon(Icons.send_outlined, color: Colors.grey, size: 16),
                                    label: const Text("Partilhar", style: TextStyle(color: Colors.grey, fontSize: 10)),
                                    style: TextButton.styleFrom(backgroundColor: Colors.white.withOpacity(0.05), padding: EdgeInsets.zero),
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
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _createPost(context),
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
          // Lógica para navegação (ex.: para chatbot, verificar mode)
          if (index == 2 && mode == UserMode.guest) {
            // Guests podem acessar chatbot
            // Adicione navegação aqui quando criar a tela
          } else if (index == 3 && mode == UserMode.guest) {
            _redirectToLogin(context); // Perfil só para logados
          }
          // Adicione mais lógica para outras abas
        },
      ),
    );
  }
}