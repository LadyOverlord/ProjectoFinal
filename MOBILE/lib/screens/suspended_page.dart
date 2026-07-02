// lib/screens/suspended_page.dart
// ─────────────────────────────────────────────────────────────────────────────
// Ecrã exibido quando o utilizador tem trustScore = 0 (suspenso).
// Funcionalidades:
//   • Mostra score actual, motivo da suspensão e data
//   • Chatbot contextual que sabe que o utilizador está suspenso
//   • Opção "Reler diretrizes"
//   • Opção "Falar com o suporte" → cria documento em suporte_suspensao/
//     com o histórico completo da conversa (o admin recebe no painel)
//   • Botão de logout
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import 'login_page.dart';
import '../config.dart'; // ← NOVO: groqApiKey, já usado no chatbot principal

// ─── PALETA ──────────────────────────────────────────────────────────────────
class _C {
  static const bg         = Color(0xFF0D0D0F);
  static const surface    = Color(0xFF141418);
  static const card       = Color(0xFF1C1C22);
  static const border     = Color(0xFF2A2A33);
  static const accent     = Color(0xFF4F7EFF);
  static const accentSoft = Color(0x264F7EFF);
  static const green      = Color(0xFF22C55E);
  static const greenSoft  = Color(0x2222C55E);
  static const orange     = Color(0xFFF59E0B);
  static const orangeSoft = Color(0x26F59E0B);
  static const red        = Color(0xFFEF4444);
  static const redSoft    = Color(0x26EF4444);
  static const white      = Color(0xFFFFFFFF);
  static const grey1      = Color(0xFFE4E4E7);
  static const grey2      = Color(0xFFA1A1AA);
  static const grey3      = Color(0xFF52525B);
  static const grey4      = Color(0xFF3F3F46);
}

// ─── DIRETRIZES ──────────────────────────────────────────────────────────────
const _diretrizes = '''
📋 DIRETRIZES DA COMUNIDADE — Missing AO

1. INFORMAÇÃO VERDADEIRA
   Apenas relate casos reais. Informações falsas prejudicam famílias e consomem recursos de busca.

2. RESPEITO
   Trate todos os utilizadores e familiares com respeito. Comentários ofensivos ou discriminatórios não são tolerados.

3. COMENTÁRIOS CONSTRUTIVOS
   Comente apenas se tiver informações úteis. Evite especulações infundadas.

4. PRIVACIDADE
   Não partilhe dados pessoais de terceiros sem autorização.

5. NÃO ABUSE DO SISTEMA
   Não crie casos duplicados, não apoie casos sabendo que são falsos e não use a plataforma para outros fins.

Como funciona o Trust Score:
• Começa em 100 pontos
• Comentário removido: −10 pontos
• Caso desmentido: −20 pontos
• Caso rejeitado por informação falsa: −15 pontos
• Score = 0: acesso suspenso

Para reactivar a sua conta, contacte o suporte através do chat abaixo.
''';

// ─── MODELO DE MENSAGEM ───────────────────────────────────────────────────────
class _Msg {
  final String texto;
  final bool isUser;
  final DateTime hora;
  _Msg({required this.texto, required this.isUser}) : hora = DateTime.now();
}

// ─── ECRÃ PRINCIPAL ──────────────────────────────────────────────────────────
class SuspendedPage extends StatefulWidget {
  const SuspendedPage({super.key});

  @override
  State<SuspendedPage> createState() => _SuspendedPageState();
}

class _SuspendedPageState extends State<SuspendedPage> {
  final _db   = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  Map<String, dynamic>? _userData;
  bool _loading       = true;
  bool _showDiretrizes = false;
  bool _chatIniciado  = false;
  bool _pedidoEnviado = false;

  final List<_Msg> _mensagens = [];
  final _textCtrl  = TextEditingController();
  final _scrollCtrl = ScrollController();
  bool _enviando   = false;

  // Mensagens iniciais do chatbot
  static const _boasVindas = [
    '👋 Olá! A sua conta está actualmente suspensa.',
    'Posso ajudá-lo(a) de duas formas:\n\n1️⃣ Reler as diretrizes da comunidade\n2️⃣ Enviar um pedido de reactivação ao suporte',
  ];

  @override
  void initState() {
    super.initState();
    _carregarDados();
  }

  @override
  void dispose() {
    _textCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _carregarDados() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    try {
      final snap = await _db.collection('users').doc(uid).get();
      if (snap.exists && mounted) {
        setState(() {
          _userData = snap.data();
          _loading  = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _iniciarChat() {
    setState(() {
      _chatIniciado = true;
      for (final txt in _boasVindas) {
        _mensagens.add(_Msg(texto: txt, isUser: false));
      }
    });
    _rolarParaBaixo();
  }

  void _rolarParaBaixo() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // ── Chama a API Groq com contexto de suspensão ───────────────────────────
  // CORRIGIDO: antes chamava diretamente https://api.anthropic.com/v1/messages
  // sem cabeçalho 'x-api-key' nem 'anthropic-version' — a Anthropic exige os
  // dois, por isso o pedido devolvia sempre 401 e caía sempre no fallback
  // "não consegui responder agora". Trocado para a API Groq, que já está
  // configurada e a funcionar no chatbot_page.dart (mesma chave, mesmo padrão).
  Future<String> _chamarIA(String pergunta) async {
    final motivo = _userData?['suspensionReason'] as String? ?? 'violação das diretrizes';
    final score  = _userData?['trustScore']       as int?    ?? 0;

    final systemPrompt = '''
Você é o assistente de suporte do Missing AO, uma plataforma angolana de rastreio de pessoas desaparecidas.

CONTEXTO IMPORTANTE:
- Este utilizador está SUSPENSO. O seu Trust Score chegou a $score/100.
- Motivo da suspensão: "$motivo"
- O utilizador pode apenas: ler as diretrizes e pedir reactivação ao suporte humano.
- O utilizador NÃO pode aceder a nenhuma outra função da plataforma enquanto suspenso.

COMPORTAMENTO ESPERADO:
- Seja empático mas claro sobre a situação.
- Explique sempre que a reactivação depende da revisão humana do admin.
- Se o utilizador pedir para "falar com o suporte", diga que pode enviar o pedido tocando no botão "Falar com admin" no topo do ecrã.
- Se o utilizador perguntar sobre as diretrizes, resuma-as brevemente.
- Responda SEMPRE em português de Angola (informal mas respeitoso).
- Respostas curtas, máximo 3 parágrafos.
''';

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
            {'role': 'system', 'content': systemPrompt},
            ..._mensagens.map((m) => {
              'role':    m.isUser ? 'user' : 'assistant',
              'content': m.texto,
            }),
            {'role': 'user', 'content': pergunta},
          ],
          'max_tokens': 400,
          'temperature': 0.7,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final texto = data['choices'][0]['message']['content'] as String?;
        return (texto ?? '').trim().isNotEmpty
            ? texto!.trim()
            : 'Desculpe, não consegui responder agora. Tente novamente.';
      }

      debugPrint('Erro Groq (suporte) — status ${response.statusCode}: ${response.body}');
      return 'Desculpe, não consegui responder agora. Tente novamente.';
    } catch (e) {
      debugPrint('Erro de ligação (suporte): $e');
      return 'Sem ligação ao servidor. Verifique a sua internet e tente novamente.';
    }
  }

  Future<void> _enviarMensagem() async {
    final texto = _textCtrl.text.trim();
    if (texto.isEmpty || _enviando) return;

    _textCtrl.clear();
    setState(() {
      _mensagens.add(_Msg(texto: texto, isUser: true));
      _enviando = true;
    });
    _rolarParaBaixo();

    final resposta = await _chamarIA(texto);

    if (mounted) {
      setState(() {
        _mensagens.add(_Msg(texto: resposta, isUser: false));
        _enviando = false;
      });
      _rolarParaBaixo();
    }
  }

  // ── Envia pedido de suporte com histórico da conversa ────────────────────
  Future<void> _enviarPedidoSuporte() async {
    final uid   = _auth.currentUser?.uid;
    final email = _auth.currentUser?.email ?? '';
    if (uid == null) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: _C.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Enviar ao suporte?',
          style: TextStyle(color: _C.white, fontSize: 16, fontWeight: FontWeight.w700)),
        content: const Text(
          'O histório desta conversa e os dados da sua conta serão enviados ao administrador para análise.\n\nDeseja continuar?',
          style: TextStyle(color: _C.grey2, fontSize: 13, height: 1.5)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar', style: TextStyle(color: _C.grey2)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: _C.accent,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Enviar', style: TextStyle(color: _C.white)),
          ),
        ],
      ),
    );

    if (ok != true || !mounted) return;

    try {
      await _db.collection('suporte_suspensao').add({
        'uid':             uid,
        'email':           email,
        'nome':            _userData?['nome'] ?? email,
        'trustScore':      _userData?['trustScore'] ?? 0,
        'suspensionReason': _userData?['suspensionReason'] ?? '',
        'suspendedAt':     _userData?['suspendedAt'],
        'historico':       _mensagens.map((m) => {
          'texto':  m.texto,
          'isUser': m.isUser,
          'hora':   m.hora.toIso8601String(),
        }).toList(),
        'status':    'pendente',     // pendente | resolvido
        'criadoEm': Timestamp.now(),
      });

      if (mounted) {
        setState(() => _pedidoEnviado = true);
        // Adiciona mensagem de confirmação no chat
        setState(() {
          _mensagens.add(_Msg(
            texto: '✅ O seu pedido foi enviado! O administrador irá analisar e responder em breve. Obrigado pela paciência.',
            isUser: false,
          ));
        });
        _rolarParaBaixo();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao enviar: $e'), backgroundColor: _C.red),
        );
      }
    }
  }

  Future<void> _logout() async {
    await _auth.signOut();
    if (mounted) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const LoginPage()),
        (_) => false,
      );
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: _C.bg,
        body: Center(child: CircularProgressIndicator(color: _C.accent)),
      );
    }

    final score  = _userData?['trustScore']       as int?    ?? 0;
    final motivo = _userData?['suspensionReason'] as String? ?? 'Violação das diretrizes';
    final nome   = _userData?['nome']             as String? ?? 'Utilizador';

    return Scaffold(
      backgroundColor: _C.bg,
      // Explícito por clareza: true é o valor por omissão, mas fica registado
      // que é esta a forma de lidar com o teclado — o Scaffold redimensiona
      // o corpo sozinho, por isso _buildBarraChat() NÃO deve voltar a somar
      // manualmente MediaQuery.of(context).viewInsets.bottom (ver correcção
      // abaixo — era isso que causava o "bottom overflowed by 128 pixels").
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: Column(
          children: [
            // ── Header ──────────────────────────────────────────────────────
            _buildHeader(nome, score, motivo),

            // ── Corpo principal ──────────────────────────────────────────────
            Expanded(
              child: _showDiretrizes
                  ? _buildDiretrizes()
                  : _chatIniciado
                      ? _buildChat()
                      : _buildMenuInicial(),
            ),

            // ── Barra de acções ──────────────────────────────────────────────
            if (_chatIniciado) _buildBarraChat(),
          ],
        ),
      ),
    );
  }

  // ── Header com score e motivo ─────────────────────────────────────────────
  Widget _buildHeader(String nome, int score, String motivo) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: _C.surface,
        border: Border(bottom: BorderSide(color: _C.border)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: _C.redSoft,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: _C.red.withOpacity(0.4)),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.block_rounded, color: _C.red, size: 12),
                    SizedBox(width: 5),
                    Text('CONTA SUSPENSA',
                      style: TextStyle(color: _C.red, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.5)),
                  ],
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: _logout,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: _C.card,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: _C.border),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.logout_rounded, color: _C.grey2, size: 14),
                      SizedBox(width: 5),
                      Text('Sair', style: TextStyle(color: _C.grey2, fontSize: 12)),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text('Olá, $nome', style: const TextStyle(color: _C.white, fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text('A sua conta está suspensa por: $motivo',
            style: const TextStyle(color: _C.grey2, fontSize: 13, height: 1.4)),
          const SizedBox(height: 12),
          // Barra de trust score
          Row(
            children: [
              const Text('Trust Score:', style: TextStyle(color: _C.grey3, fontSize: 12)),
              const SizedBox(width: 8),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: score / 100,
                    backgroundColor: _C.card,
                    color: _C.red,
                    minHeight: 6,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text('$score/100', style: const TextStyle(color: _C.red, fontSize: 12, fontWeight: FontWeight.w700)),
            ],
          ),
        ],
      ),
    );
  }

  // ── Menu inicial (antes de iniciar o chat) ────────────────────────────────
  Widget _buildMenuInicial() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80, height: 80,
              decoration: const BoxDecoration(color: _C.redSoft, shape: BoxShape.circle),
              child: const Icon(Icons.support_agent_rounded, color: _C.red, size: 40),
            ),
            const SizedBox(height: 20),
            const Text('Como posso ajudar?',
              style: TextStyle(color: _C.white, fontSize: 20, fontWeight: FontWeight.w700),
              textAlign: TextAlign.center),
            const SizedBox(height: 8),
            const Text('Escolha uma opção abaixo para continuar.',
              style: TextStyle(color: _C.grey2, fontSize: 14),
              textAlign: TextAlign.center),
            const SizedBox(height: 32),

            // Botão: Reler diretrizes
            _MenuBtn(
              icon: Icons.menu_book_rounded,
              label: 'Reler as diretrizes',
              sublabel: 'Entenda o que levou à suspensão',
              color: _C.orange,
              colorSoft: _C.orangeSoft,
              onTap: () => setState(() => _showDiretrizes = true),
            ),
            const SizedBox(height: 12),

            // Botão: Falar com o suporte
            _MenuBtn(
              icon: Icons.chat_rounded,
              label: 'Falar com o suporte',
              sublabel: 'Solicitar reactivação da conta',
              color: _C.accent,
              colorSoft: _C.accentSoft,
              onTap: _iniciarChat,
            ),
          ],
        ),
      ),
    );
  }

  // ── Ecrã de diretrizes ───────────────────────────────────────────────────
  Widget _buildDiretrizes() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
          child: Row(
            children: [
              const Icon(Icons.menu_book_rounded, color: _C.orange, size: 18),
              const SizedBox(width: 8),
              const Expanded(
                child: Text('Diretrizes da Comunidade',
                  style: TextStyle(color: _C.white, fontSize: 16, fontWeight: FontWeight.w700)),
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded, color: _C.grey2),
                onPressed: () => setState(() => _showDiretrizes = false),
              ),
            ],
          ),
        ),
        const Divider(color: _C.border, height: 1),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _C.card,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: _C.border),
              ),
              child: Text(_diretrizes,
                style: const TextStyle(color: _C.grey1, fontSize: 14, height: 1.6)),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () {
                setState(() => _showDiretrizes = false);
                _iniciarChat();
              },
              icon: const Icon(Icons.chat_rounded, size: 18),
              label: const Text('Falar com o suporte', style: TextStyle(fontWeight: FontWeight.w700)),
              style: ElevatedButton.styleFrom(
                backgroundColor: _C.accent,
                foregroundColor: _C.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 0,
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ── Chat ──────────────────────────────────────────────────────────────────
  Widget _buildChat() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
          child: Row(
            children: [
              const Icon(Icons.support_agent_rounded, color: _C.accent, size: 18),
              const SizedBox(width: 8),
              const Expanded(
                child: Text('Suporte Missing AO',
                  style: TextStyle(color: _C.white, fontSize: 16, fontWeight: FontWeight.w700)),
              ),
              if (!_pedidoEnviado)
                TextButton.icon(
                  onPressed: _enviarPedidoSuporte,
                  icon: const Icon(Icons.send_rounded, size: 14, color: _C.green),
                  label: const Text('Falar com admin',
                    style: TextStyle(color: _C.green, fontSize: 12, fontWeight: FontWeight.w600)),
                ),
            ],
          ),
        ),
        const Divider(color: _C.border, height: 1),
        Expanded(
          child: ListView.builder(
            controller: _scrollCtrl,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            itemCount: _mensagens.length + (_enviando ? 1 : 0),
            itemBuilder: (_, i) {
              if (i == _mensagens.length) return _buildTyping();
              final msg = _mensagens[i];
              return _buildBubble(msg);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildBubble(_Msg msg) {
    final isUser = msg.isUser;
    final ts = '${msg.hora.hour.toString().padLeft(2, '0')}:${msg.hora.minute.toString().padLeft(2, '0')}';

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isUser) ...[
            Container(
              width: 30, height: 30,
              decoration: const BoxDecoration(color: _C.accentSoft, shape: BoxShape.circle),
              child: const Icon(Icons.support_agent_rounded, color: _C.accent, size: 16),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: isUser ? _C.accent : _C.card,
                    borderRadius: BorderRadius.only(
                      topLeft:     const Radius.circular(14),
                      topRight:    const Radius.circular(14),
                      bottomLeft:  Radius.circular(isUser ? 14 : 4),
                      bottomRight: Radius.circular(isUser ? 4 : 14),
                    ),
                    border: isUser ? null : Border.all(color: _C.border),
                  ),
                  child: Text(msg.texto,
                    style: TextStyle(
                      color: isUser ? _C.white : _C.grey1,
                      fontSize: 14,
                      height: 1.45,
                    )),
                ),
                const SizedBox(height: 3),
                Text(ts, style: const TextStyle(color: _C.grey3, fontSize: 10)),
              ],
            ),
          ),
          if (isUser) const SizedBox(width: 8),
        ],
      ),
    );
  }

  Widget _buildTyping() {
    return Row(
      children: [
        Container(
          width: 30, height: 30,
          decoration: const BoxDecoration(color: _C.accentSoft, shape: BoxShape.circle),
          child: const Icon(Icons.support_agent_rounded, color: _C.accent, size: 16),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: _C.card,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _C.border),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _Dot(delay: 0),
              SizedBox(width: 4),
              _Dot(delay: 150),
              SizedBox(width: 4),
              _Dot(delay: 300),
            ],
          ),
        ),
      ],
    );
  }

  // ── Barra de texto do chat ────────────────────────────────────────────────
  // CORRIGIDO: "bottom overflowed by 128 pixels" ao abrir o teclado.
  // O Scaffold já tem resizeToAvoidBottomInset: true (é o valor por omissão),
  // o que significa que ele PRÓPRIO reduz a altura do body quando o teclado
  // aparece. O código antigo somava MediaQuery.of(context).viewInsets.bottom
  // ao padding desta barra POR CIMA disso — ou seja, o teclado era contado
  // duas vezes: uma pelo Scaffold (que já encolheu o espaço disponível) e
  // outra por este padding manual (que pedia ainda mais espaço lá dentro).
  // O Column ficava a pedir mais altura do que a que realmente existia,
  // daí o overflow. A correcção é simplesmente não voltar a somar
  // viewInsets.bottom aqui — o Scaffold já trata disso sozinho.
  Widget _buildBarraChat() {
    return Container(
      padding: const EdgeInsets.only(left: 12, right: 12, top: 10, bottom: 12),
      decoration: BoxDecoration(
        color: _C.surface,
        border: Border(top: BorderSide(color: _C.border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _textCtrl,
              style: const TextStyle(color: _C.white, fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Escreva uma mensagem...',
                hintStyle: const TextStyle(color: _C.grey3, fontSize: 14),
                filled: true,
                fillColor: _C.card,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                isDense: true,
              ),
              onSubmitted: (_) => _enviarMensagem(),
              textInputAction: TextInputAction.send,
              enabled: !_enviando,
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: _enviando ? null : _enviarMensagem,
            child: Container(
              width: 40, height: 40,
              decoration: BoxDecoration(
                color: _enviando ? _C.grey4 : _C.accent,
                shape: BoxShape.circle,
              ),
              child: _enviando
                  ? const Padding(
                      padding: EdgeInsets.all(10),
                      child: CircularProgressIndicator(color: _C.white, strokeWidth: 2),
                    )
                  : const Icon(Icons.send_rounded, color: _C.white, size: 18),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── BOTÃO DO MENU INICIAL ────────────────────────────────────────────────────
class _MenuBtn extends StatelessWidget {
  final IconData icon;
  final String label, sublabel;
  final Color color, colorSoft;
  final VoidCallback onTap;
  const _MenuBtn({
    required this.icon, required this.label, required this.sublabel,
    required this.color, required this.colorSoft, required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _C.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Row(
          children: [
            Container(
              width: 44, height: 44,
              decoration: BoxDecoration(color: colorSoft, borderRadius: BorderRadius.circular(12)),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: TextStyle(color: color, fontSize: 15, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(sublabel, style: const TextStyle(color: _C.grey2, fontSize: 12)),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios_rounded, color: color, size: 14),
          ],
        ),
      ),
    );
  }
}

// ─── ANIMAÇÃO DE "TYPING" ────────────────────────────────────────────────────
class _Dot extends StatefulWidget {
  final int delay;
  const _Dot({required this.delay});
  @override
  State<_Dot> createState() => _DotState();
}

class _DotState extends State<_Dot> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 600))
      ..repeat(reverse: true);
    _anim = Tween<double>(begin: 0.3, end: 1.0).animate(_ctrl);
    Future.delayed(Duration(milliseconds: widget.delay), () {
      if (mounted) _ctrl.forward();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _anim,
      child: Container(
        width: 6, height: 6,
        decoration: const BoxDecoration(color: _C.grey2, shape: BoxShape.circle),
      ),
    );
  }
}
