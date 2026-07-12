// screens/chatbot_page.dart
// API Groq — chave em lib/config.dart (não versionado no git)


import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'home_page.dart';
import 'profile.dart';
import 'map_page.dart';
import '../models/user_mode.dart';
import '../config.dart';
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

  final List<Map<String, String>> _conversationHistory = [];

  final List<Map<String, String>> _quickOptions = [
    {
      'label': 'Como postar anúncio?',
      'message': 'Como faço para postar um anúncio de desaparecido?'
    },
    {
      'label': 'Ajuda emocional',
      'message': 'Preciso de apoio emocional para lidar com o desaparecimento.'
    },
    {'label': 'Usar o mapa', 'message': 'Como usar o mapa para ver locais?'},
    {'label': 'Fazer login', 'message': 'Como faço login no app?'},
    {'label': 'Notificações', 'message': 'Como recebo notificações regionais?'},
  ];

  static const String _systemPrompt = '''
Você é o Missing AI, assistente virtual oficial do aplicativo Missing AO — uma plataforma angolana dedicada a ajudar famílias a encontrar pessoas desaparecidas em Angola.

Responda SEMPRE em português de Angola, com empatia, clareza e concisão (máximo 3 parágrafos).
Nunca invente informações sobre casos reais. Seja honesto quando não souber algo.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
ESTRUTURA DO APLICATIVO
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

O Missing AO tem 4 ecrãs principais acessíveis pela barra de navegação inferior:

1. HOME (Feed)
   - Lista todos os casos aprovados em tempo real via Firestore
   - Cada caso mostra: foto, nome, idade, província, último local, dias desaparecido, status
   - Ações por caso: Apoiar, Comentar, Partilhar
   - Barra de pesquisa para filtrar por nome, local ou província
   - Botão flutuante "Relatar" para submeter novos casos
   - Convidados podem ver casos mas não interagir (redireciona para login)

2. MAPA
   - Mapa interativo (Google Maps) com marcadores coloridos por status:
     - Azul = Ativo (aprovado, ainda à procura)
     - Verde = Encontrado
     - Cinzento = Desmentido
   - Filtros por status e por província (todas as 18 províncias de Angola)
   - Ao tocar num marcador aparece um card com foto, nome, idade, local e apoios
   - Casos sem coordenadas GPS ficam na capital da província

3. CHATBOT (este ecrã)
   - Assistente IA alimentado pelo Groq (modelo llama-3.1-8b-instant)
   - Responde a dúvidas sobre o app, apoio emocional e orientações sobre desaparecimentos
   - Mantém contexto da conversa (histórico)

4. PERFIL
   - Foto de perfil (base64, editável)
   - Nome editável inline
   - Stats: casos apoiados, casos aprovados, casos pendentes
   - Sistema de Emblemas:
     - Admin: utilizador com role admin
     - Apoiador: deu 5 ou mais apoios
     - Comentador: fez 5 ou mais comentários
     - Partilhador: partilhou 3 ou mais vezes
     - Publicador: submeteu 3 ou mais casos
     - Impacto: recebeu 10 ou mais apoios nos seus casos
   - Tabs: "Meus Casos" e "Apoios" em grelha 3x3 estilo Instagram
   - Atualização automática de localização via GPS
   - Opções: editar nome, alterar foto, atualizar localização, sair

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
COMO RELATAR UM DESAPARECIMENTO
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

O formulário tem 3 páginas:

Página 1 - Pessoa:
- Foto (opcional, da galeria)
- Nome completo (obrigatório, mínimo 3 letras)
- Idade (obrigatório) e Sexo (obrigatório)
- Altura (opcional, ex: 1.75m) e Número do BI (opcional)
- Província (obrigatório) — 18 províncias disponíveis
- Município (obrigatório) — aparece após escolher a província

Página 2 - Local:
- Data do desaparecimento (obrigatório)
- Hora (opcional)
- Último local visto com pesquisa por endereço via geocodificação
- Mapa interativo para marcar o local exato

Página 3 - Detalhes:
- Roupas que usava
- Deficiência (sim/não, com descrição)
- Informações adicionais (cicatrizes, tatuagens, comportamento)
- Resumo do relato antes de enviar

IMPORTANTE: Após submeter, o caso vai para "casos_pendentes" com status "pendente".
Um administrador precisa APROVAR o caso antes de aparecer no mapa e no feed.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
AUTENTICAÇÃO E UTILIZADORES
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

- Login com email e senha (Firebase Auth)
- Registo requer: nome, email, telefone, data de nascimento (mínimo 16 anos), província, município, senha (mínimo 6 caracteres)
- Verificação de email obrigatória após registo
- Recuperação de senha por email disponível no ecrã de login
- Modo convidado: pode ver o feed e o mapa, mas não pode relatar, apoiar, comentar ou partilhar
- Roles: "user" (utilizador normal) ou "admin" (administrador)
- O sistema verifica automaticamente o role ao iniciar e redireciona para o painel correto

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
PAINEL DE ADMINISTRADOR
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Acessível apenas para utilizadores com role "admin". Tem 4 secções:

Dashboard:
- Stats em tempo real: total de utilizadores, casos pendentes, casos ativos, casos encontrados
- Tabela de casos ativos com dropdown para alterar status

Utilizadores:
- Lista todos os utilizadores registados com filtros avançados
- Promover/rebaixar utilizadores para admin
- Remover utilizadores

Aprovações:
- Lista casos pendentes aguardando revisão
- Mostra mini-perfil do relator (nome, email, verificado ou não)
- Botões: Aprovar + Alertar (envia notificação FCM) ou Rejeitar

Mapa de Casos:
- Mapa com todos os casos aprovados
- Botão "Corrigir" para editar localização de casos sem GPS

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
NOTIFICAÇÕES
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

- Sistema de notificações push via Firebase Cloud Messaging (FCM)
- Token FCM guardado no Firestore do utilizador ao fazer login
- Quando um caso é aprovado, o admin envia alertas para utilizadores da mesma região
- O alerta inclui: nome, província, município, último local, idade, sexo, roupas e foto

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
BASE DE DADOS (Firestore)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Coleções principais:
- "users": dados dos utilizadores (nome, email, role, stats, foto, localização)
- "casos": casos aprovados visíveis no feed e mapa
- "casos_pendentes": casos aguardando aprovação do admin
- "casos/{id}/comentarios": subcoleção com comentários de cada caso

Status possíveis de um caso: pendente, aprovado, encontrado, desmentido, rejeitado

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
PROVÍNCIAS SUPORTADAS
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Luanda, Benguela, Huambo, Bié, Cabinda, Cuando Cubango, Cuanza Norte, Cuanza Sul, Cunene, Huíla, Lunda Norte, Lunda Sul, Malanje, Moxico, Namibe, Uíge, Zaire, Bengo (com municípios detalhados para cada uma)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
TECNOLOGIAS DO PROJETO
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Flutter (Dart), Firebase Auth, Cloud Firestore, Firebase Cloud Messaging, Google Maps Flutter, Geocoding, Groq API (llama-3.1-8b-instant), share_plus, image_picker, geolocator

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
GUIA DE RESPOSTAS COMUNS
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

- "Como relatar?" → Explicar o formulário de 3 páginas acima
- "Onde está o meu caso?" → Pode estar pendente aguardando aprovação do admin
- "Não consigo fazer login" → Verificar se confirmou o email após o registo
- "Como funciona o mapa?" → Marcadores coloridos por status, com filtros disponíveis
- "Como recebo notificações?" → Automático após login, baseado na região do utilizador
- "O que é o modo convidado?" → Pode ver o feed e mapa mas não pode interagir
- "Como me torno admin?" → Um admin existente promove via painel de utilizadores
- Apoio emocional → Responder com empatia, validar sentimentos, orientar a usar o app e contactar as autoridades angolanas (Polícia Nacional de Angola) se necessário
''';

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
          'text':
              'Olá $_userName! Sou o Missing AI, assistente do Missing AO. Como posso ajudar?'
        });
      });
    }
  }

  Future<void> _sendMessage(String message) async { //verifica se a mensagem está vazia;adiciona a mensagem do utilizador na interface;limpa o TextField;faz o scroll para baixo;guarda a pergunta no histórico;envia um POST para a Groq;recebe a resposta;adiciona a resposta ao histórico;mostra a resposta na tela.
    if (message.trim().isEmpty || _isLoading) return; //clausula de guarda pra parar

    setState(() {
      _messages.add({'sender': 'user', 'text': message});
      _isLoading = true;
    });
    _messageController.clear();
    _scrollToBottom();

    _conversationHistory.add({'role': 'user', 'content': message});

    try {
      final response = await http.post(
        Uri.parse('https://api.groq.com/openai/v1/chat/completions'),
        headers: {
          'Authorization': 'Bearer $groqApiKey',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'model': 'llama-3.1-8b-instant',
          'messages': [
            {'role': 'system', 'content': _systemPrompt},
            ..._conversationHistory,
          ],
          'max_tokens': 600,
          'temperature': 0.7,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final botReply =
            data['choices'][0]['message']['content'] as String? ??
                'Não consegui gerar uma resposta. Tenta novamente.';

        _conversationHistory.add({'role': 'assistant', 'content': botReply});

        if (mounted) {
          setState(() {
            _messages.add({'sender': 'bot', 'text': botReply});
          });
          _scrollToBottom();
        }
      } else {
        final errorData = jsonDecode(response.body);
        final errorMsg = errorData['error']?['message'] ?? 'Erro desconhecido';
        debugPrint('Erro Groq (${response.statusCode}): $errorMsg');
        if (mounted) {
          setState(() {
            _messages.add({
              'sender': 'bot',
              'text': _friendlyError(response.statusCode, errorMsg),
            });
          });
        }
      }
    } catch (e) {
      debugPrint('Erro de ligação: $e');
      if (mounted) {
        setState(() {
          _messages.add({
            'sender': 'bot',
            'text': 'Erro de ligação. Verifica a tua internet e tenta novamente.',
          });
        });
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _friendlyError(int statusCode, String rawMessage) {
    switch (statusCode) {
      case 401:
        return 'Chave de API inválida. Verifica o valor de groqApiKey no config.dart.';
      case 429:
        return 'Muitas mensagens enviadas. Aguarda alguns segundos e tenta novamente.';
      case 503:
        return 'O serviço está temporariamente indisponível. Tenta mais tarde.';
      default:
        return 'Erro ($statusCode): $rawMessage';
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
          MaterialPageRoute(
              builder: (_) => HomePage(mode: UserMode.authenticated)),
        );
        break;
      case 1:
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const MapPage()),
        );
        break;
      case 3:
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const ProfileScreen()),
        );
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
          icon: const Icon(Icons.arrow_back_ios_rounded,
              color: Colors.white, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                color: Colors.greenAccent,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            const Text('Missing AI',
                style: TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold)),
          ],
        ),
        centerTitle: true,
      ),
      body: Column(
        children: [
          Expanded(
            child: _messages.isEmpty
                ? Center(
                    child: Text(
                      'Inicia uma conversa!',
                      style: TextStyle(color: Colors.grey[500], fontSize: 16),
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(16),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      final message = _messages[index];
                      final isUser = message['sender'] == 'user';
                      return Align(
                        alignment: isUser
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.symmetric(vertical: 6),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                          constraints: BoxConstraints(
                              maxWidth:
                                  MediaQuery.of(context).size.width * 0.75),
                          decoration: BoxDecoration(
                            color: isUser
                                ? Colors.blueAccent
                                : Colors.grey[800],
                            borderRadius: BorderRadius.only(
                              topLeft: const Radius.circular(18),
                              topRight: const Radius.circular(18),
                              bottomLeft: Radius.circular(isUser ? 18 : 4),
                              bottomRight: Radius.circular(isUser ? 4 : 18),
                            ),
                          ),
                          child: Text(
                            message['text']!,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                height: 1.4),
                          ),
                        ),
                      );
                    },
                  ),
          ),
          if (_isLoading)
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.grey[800],
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _AnimatedDot(delay: 0),
                      const SizedBox(width: 4),
                      _AnimatedDot(delay: 100),
                      const SizedBox(width: 4),
                      _AnimatedDot(delay: 200),
                    ],
                  ),
                ),
              ),
            ),
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
                    labelStyle: const TextStyle(
                        color: Colors.white, fontSize: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20)),
                  ),
                );
              },
            ),
          ),
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
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 10),
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
          BottomNavigationBarItem(
              icon: Icon(Icons.home_filled), label: 'Home'),
          BottomNavigationBarItem(
              icon: Icon(Icons.location_on_outlined), label: 'Mapa'),
          BottomNavigationBarItem(
              icon: Icon(Icons.auto_awesome), label: 'Chatbot'),
          BottomNavigationBarItem(
              icon: Icon(Icons.person_outline), label: 'Perfil'),
        ],
        onTap: _onItemTapped,
      ),
    );
  }
}

class _AnimatedDot extends StatefulWidget {
  final int delay;
  const _AnimatedDot({required this.delay});

  @override
  State<_AnimatedDot> createState() => _AnimatedDotState();
}

class _AnimatedDotState extends State<_AnimatedDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    )..repeat();

    Future.delayed(Duration(milliseconds: widget.delay), () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: Tween<double>(begin: 0.5, end: 1).animate(_controller),
      child: Container(
        width: 6,
        height: 6,
        decoration: const BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}