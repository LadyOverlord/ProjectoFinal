// screens/chatbot_page.dart
// A chave da API está em lib/config.dart (não versionado no git)

import 'package:flutter/material.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'home_page.dart';
import 'login_page.dart';
import 'profile.dart';
import 'map_page.dart';
import '../models/user_mode.dart';
import '../config.dart'; // ← chave protegida
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class ChatbotPage extends StatefulWidget {
  const ChatbotPage({super.key});

  @override
  State<ChatbotPage> createState() => _ChatbotPageState();
}

class _ChatbotPageState extends State<ChatbotPage> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<Map<String, String>> _messages = [];
  bool _isLoading = false;
  int _selectedIndex = 2;
  String _userName = 'Utilizador';

  final List<Map<String, String>> _quickOptions = [
    {'label': 'Como postar anúncio?',  'message': 'Como faço para postar um anúncio de desaparecido?'},
    {'label': 'Ajuda emocional',        'message': 'Preciso de apoio emocional para lidar com o desaparecimento.'},
    {'label': 'Usar o mapa',            'message': 'Como usar o mapa para ver locais?'},
    {'label': 'Fazer login',            'message': 'Como faço login no app?'},
    {'label': 'Notificações',           'message': 'Como recebo notificações regionais?'},
  ];

  @override
  void initState() {
    super.initState();
    _loadUserName();
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadUserName() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      try {
        final userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();
        if (userDoc.exists && mounted) {
          setState(() {
            _userName = userDoc.data()!['nome'] as String? ?? 'Utilizador';
          });
        }
      } catch (_) {}
    }
    if (mounted) {
      setState(() {
        _messages.add({
          'sender': 'bot',
          'text': 'Olá $_userName! Sou o Missing AI 🤖\nComo posso ajudar com desaparecimentos ou o uso do app?'
        });
      });
    }
  }

  Future<void> _sendMessage(String message) async {
    if (message.trim().isEmpty || _isLoading) return;

    setState(() {
      _messages.add({'sender': 'user', 'text': message});
      _isLoading = true;
    });
    _messageController.clear();
    _scrollToBottom();

    try {
      final model = GenerativeModel(
        model: 'gemini-2.5-flash',
        apiKey: geminiApiKey, // ← vem do config.dart
      );

      final prompt = '''
Você é o Missing AI, assistente virtual do aplicativo Missing AO especializado em casos de desaparecimento em Angola.
Responda com empatia, de forma clara e em português de Angola.
Ajude com: registar casos, usar o app, apoio emocional, e informações sobre desaparecidos.
Seja conciso (máximo 3 parágrafos).

Mensagem do utilizador: $message
''';

      final response = await model.generateContent([Content.text(prompt)]);

      if (mounted) {
        setState(() {
          _messages.add({
            'sender': 'bot',
            'text': response.text ?? 'Não consegui gerar uma resposta. Tenta novamente.'
          });
        });
        _scrollToBottom();
      }
    } on GenerativeAIException catch (e) {
      debugPrint('Erro Gemini: $e');
      if (mounted) {
        setState(() {
          _messages.add({
            'sender': 'bot',
            'text': 'Erro na API. Tenta novamente mais tarde.'
          });
        });
      }
    } catch (e) {
      debugPrint('Erro geral: $e');
      if (mounted) {
        setState(() {
          _messages.add({
            'sender': 'bot',
            'text': 'Erro de ligação. Verifica a tua internet e tenta novamente.'
          });
        });
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _onItemTapped(int index) {
    if (index == _selectedIndex) return;
    setState(() => _selectedIndex = index);

    switch (index) {
      case 0:
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const HomePage(mode: UserMode.authenticated)),
        );
        break;
      case 1:
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const MapPage()),
        );
        break;
      case 2:
        break; // já está no chatbot
      case 3:
        if (FirebaseAuth.instance.currentUser == null) {
          showDialog(
            context: context,
            builder: (_) => AlertDialog(
              backgroundColor: const Color(0xFF1C1C22),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: const Text('Acesso Restrito', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
              content: const Text('Para interagir, faça login ou cadastre-se.', style: TextStyle(color: Colors.grey, fontSize: 14)),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancelar', style: TextStyle(color: Colors.grey)),
                ),
                ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context);
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const LoginPage()));
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                  child: const Text('Login', style: TextStyle(color: Colors.white)),
                ),
              ],
            ),
          );
        } else {
          Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfileScreen()));
        }
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[900],
      appBar: AppBar(
        backgroundColor: Colors.grey[900],
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded, color: Colors.white, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8, height: 8,
              decoration: const BoxDecoration(color: Colors.greenAccent, shape: BoxShape.circle),
            ),
            const SizedBox(width: 8),
            const Text('Missing AI', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ],
        ),
        centerTitle: true,
      ),
      body: Column(
        children: [
          // ── Lista de mensagens ──
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(16),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final message = _messages[index];
                final isUser = message['sender'] == 'user';
                return Align(
                  alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 6),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
                    decoration: BoxDecoration(
                      color: isUser ? Colors.blueAccent : Colors.grey[800],
                      borderRadius: BorderRadius.only(
                        topLeft: const Radius.circular(18),
                        topRight: const Radius.circular(18),
                        bottomLeft: Radius.circular(isUser ? 18 : 4),
                        bottomRight: Radius.circular(isUser ? 4 : 18),
                      ),
                    ),
                    child: Text(
                      message['text']!,
                      style: const TextStyle(color: Colors.white, fontSize: 15, height: 1.4),
                    ),
                  ),
                );
              },
            ),
          ),

          // ── Indicador a escrever ──
          if (_isLoading)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(color: Colors.grey[800], borderRadius: BorderRadius.circular(18)),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(
                        width: 16, height: 16,
                        child: CircularProgressIndicator(color: Colors.blueAccent, strokeWidth: 2),
                      ),
                      const SizedBox(width: 8),
                      Text('Missing AI está a escrever...', style: TextStyle(color: Colors.grey[400], fontSize: 13)),
                    ],
                  ),
                ),
              ),
            ),

          // ── Sugestões rápidas ──
          SizedBox(
            height: 50,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _quickOptions.length,
              itemBuilder: (context, index) {
                final option = _quickOptions[index];
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ActionChip(
                    label: Text(option['label']!),
                    onPressed: () => _sendMessage(option['message']!),
                    backgroundColor: Colors.grey[800],
                    labelStyle: const TextStyle(color: Colors.white, fontSize: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  ),
                );
              },
            ),
          ),

          // ── Input ──
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Escreve a tua mensagem...',
                      hintStyle: const TextStyle(color: Colors.grey),
                      filled: true,
                      fillColor: Colors.grey[800],
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(25),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    ),
                    onSubmitted: _sendMessage,
                    textInputAction: TextInputAction.send,
                  ),
                ),
                const SizedBox(width: 8),
                CircleAvatar(
                  backgroundColor: Colors.blueAccent,
                  child: IconButton(
                    icon: const Icon(Icons.send_rounded, color: Colors.white),
                    onPressed: () => _sendMessage(_messageController.text),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        backgroundColor: Colors.grey[900],
        selectedItemColor: Colors.blueAccent,
        unselectedItemColor: Colors.grey,
        type: BottomNavigationBarType.fixed,
        currentIndex: _selectedIndex,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home_filled),          label: 'Home'),
          BottomNavigationBarItem(icon: Icon(Icons.map_rounded),           label: 'Mapa'),
          BottomNavigationBarItem(icon: Icon(Icons.auto_awesome_rounded),  label: 'Chatbot'),
          BottomNavigationBarItem(icon: Icon(Icons.person_outline),        label: 'Perfil'),
        ],
        onTap: _onItemTapped,
      ),
    );
  }
}