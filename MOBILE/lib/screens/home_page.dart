// screens/home_page.dart
//   share_plus: ^7.0.0

import 'dart:convert'; //conversor de dados
import 'dart:typed_data';//processar os codigos em milisegundos
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:share_plus/share_plus.dart';
import '../models/user_mode.dart';
import 'login_page.dart';
import 'chatbot_page.dart';
import 'profile.dart';
import 'create_caso_dialog.dart';
import 'map_page.dart';
import 'admin_page.dart'; // ← adiciona esta linha com os outros imports
import 'suspended_page.dart'; // ← NOVO: para navegar directamente para lá

// ─── PALETA ─────────────────────────────────────────────
class _C {
  static const bg      = Color(0xFF0D0D0F);
  static const surface = Color(0xFF141418);
  static const card    = Color(0xFF1C1C22);
  static const border  = Color(0xFF2A2A33);
  static const accent  = Color(0xFF4F7EFF);
  static const green   = Color(0xFF22C55E);
  static const orange  = Color(0xFFF59E0B);
  static const red     = Color(0xFFEF4444);
  static const purple  = Color(0xFF9B5DE5);
  static const grey1   = Color(0xFFE4E4E7);
  static const grey2   = Color(0xFFA1A1AA);
  static const grey3   = Color(0xFF52525B);
  static const grey4   = Color(0xFF3F3F46);
  static const white   = Color(0xFFFFFFFF);
}

// ─── STATUS CONFIG ───────────────────────────────────────
class _StatusCfg {
  final String label;
  final Color color;
  final Color bg;
  final IconData icon;
  const _StatusCfg(this.label, this.color, this.bg, this.icon);
}

_StatusCfg _statusCfg(String? status) {
  switch (status) {
    case 'aprovado':   return const _StatusCfg('Ativo',      _C.accent, Color(0x264F7EFF), Icons.search_rounded);
    case 'encontrado': return const _StatusCfg('Encontrado', _C.green,  Color(0x2222C55E), Icons.check_circle_rounded);
    case 'desmentido': return const _StatusCfg('Desmentido', _C.grey3,  Color(0x2652525B), Icons.cancel_rounded);
    default:           return const _StatusCfg('Ativo',      _C.accent, Color(0x264F7EFF), Icons.search_rounded);
  }
}

// ─── HOME PAGE ───────────────────────────────────────────
class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.mode});
  final UserMode mode;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final TextEditingController _searchCtrl = TextEditingController();
  String _query    = '';
  int    _navIndex = 0;

  bool get isGuest => FirebaseAuth.instance.currentUser == null;
  bool _isAdmin = false;

  // ── Método novo ──
  Future<void> _checkAdmin() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      if (snap.exists && mounted) {
        setState(() =>
            _isAdmin = (snap.data()?['role'] ?? 'user') == 'admin');
      }
    } catch (_) {}
  }

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(() => setState(() => _query = _searchCtrl.text.toLowerCase()));
    _checkAdmin();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _redirectToLogin() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: _C.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: const BorderSide(color: _C.border)),
        title: const Text('Acesso Restrito', style: TextStyle(color: _C.white, fontWeight: FontWeight.w700)),
        content: const Text('Para interagir, faça login ou cadastre-se.', style: TextStyle(color: _C.grey2, fontSize: 14)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar', style: TextStyle(color: _C.grey2))),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.push(context, MaterialPageRoute(builder: (_) => const LoginPage()));
            },
            style: ElevatedButton.styleFrom(backgroundColor: _C.accent, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            child: const Text('Login', style: TextStyle(color: _C.white, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  // CORRIGIDO: antes só verificava isGuest — um utilizador suspenso
  // (autenticado, mas com isSuspended=true ou trustScore<=0) passava
  // directo para o diálogo de criação de caso. Esta verificação lê o
  // estado actual no Firestore (não um valor em cache) mesmo que o
  // AuthCheck ainda não tenha reagido por o utilizador estar numa
  // página empilhada por cima da HomePage.
  Future<bool> _isUserSuspended() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;
    try {
      final snap = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      if (!snap.exists) return false;
      final data = snap.data()!;
      final isSuspended = data['isSuspended'] as bool? ?? false;
      final trustScore  = data['trustScore']  as int?  ?? 100;
      return isSuspended || trustScore <= 0;
    } catch (_) {
      return false; // falha de rede não deve bloquear; a regra do Firestore continua a proteger a escrita
    }
  }

  void _mostrarBloqueadoPorSuspensao() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: _C.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: const BorderSide(color: _C.border)),
        title: const Text('Conta suspensa', style: TextStyle(color: _C.white, fontWeight: FontWeight.w700)),
        content: const Text(
          'A sua conta está suspensa e não pode reportar casos neste momento. Pode falar com o suporte para pedir a reactivação.',
          style: TextStyle(color: _C.grey2, fontSize: 14, height: 1.4),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar', style: TextStyle(color: _C.grey2))),
          // NOVO: antes só dizia "vá ao ecrã de suspensão" sem dar nenhuma
          // forma de lá chegar — o utilizador ficava sem saber onde isso
          // ficava. Este botão navega directamente para o SuspendedPage.
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context); // fecha o diálogo
              Navigator.push(context, MaterialPageRoute(builder: (_) => const SuspendedPage()));
            },
            style: ElevatedButton.styleFrom(backgroundColor: _C.accent, foregroundColor: _C.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            child: const Text('Falar com o suporte', style: TextStyle(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  void _handleCreate() async {
    if (isGuest) { _redirectToLogin(); return; }
    if (await _isUserSuspended()) {
      if (mounted) _mostrarBloqueadoPorSuspensao();
      return;
    }
    if (mounted) showDialog(context: context, builder: (_) => const CreateCasoDialog());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _C.bg,
      body: SafeArea(
        child: Column(
          children: [_buildHeader(), Expanded(child: _buildFeed())],
        ),
      ),
      floatingActionButton: _buildFAB(),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
      decoration: BoxDecoration(color: _C.surface, border: Border(bottom: BorderSide(color: _C.border, width: 1))),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [_C.accent, _C.purple],
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.location_searching_rounded,
                  color: _C.white,
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              const Text(
                'Missing AO',
                style: TextStyle(
                  color: _C.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                ),
              ),
              const Spacer(),

              // ── BOTÃO ADMIN ─────────────────────────────
              if (_isAdmin) ...[
                GestureDetector(
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const AdminPage(),
                    ),
                  ),
                  child: Container(
                    width: 38,
                    height: 38,
                    margin: const EdgeInsets.only(right: 8),
                    decoration: BoxDecoration(
                      color: const Color(0x264F7EFF),
                      borderRadius: BorderRadius.circular(11),
                      border: Border.all(
                        color: _C.accent.withOpacity(0.35),
                      ),
                    ),
                    child: const Icon(
                      Icons.admin_panel_settings_rounded,
                      color: _C.accent,
                      size: 18,
                    ),
                  ),
                ),
              ],
              // ────────────────────────────────────────────

              StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('casos_pendentes')
                    .snapshots(),
                builder: (_, snap) {
                  final count =
                      (snap.hasData && !isGuest)
                          ? snap.data!.docs.length
                          : 0;

                  return Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: _C.card,
                          borderRadius: BorderRadius.circular(11),
                          border: Border.all(color: _C.border),
                        ),
                        child: const Icon(
                          Icons.notifications_rounded,
                          color: _C.grey2,
                          size: 18,
                        ),
                      ),
                      if (count > 0)
                        Positioned(
                          top: -3,
                          right: -3,
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: const BoxDecoration(
                              color: _C.red,
                              shape: BoxShape.circle,
                            ),
                            child: Text(
                              '$count',
                              style: const TextStyle(
                                color: _C.white,
                                fontSize: 8,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            height: 42,
            decoration: BoxDecoration(color: _C.card, borderRadius: BorderRadius.circular(12), border: Border.all(color: _C.border)),
            child: Row(
              children: [
                const Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: Icon(Icons.search_rounded, color: _C.grey3, size: 18)),
                Expanded(
                  child: TextField(
                    controller: _searchCtrl,
                    style: const TextStyle(color: _C.grey1, fontSize: 14),
                    decoration: const InputDecoration(
                      hintText: 'Procurar desaparecidos...',
                      hintStyle: TextStyle(color: _C.grey3, fontSize: 14),
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ),
                if (_query.isNotEmpty)
                  GestureDetector(
                    onTap: () => _searchCtrl.clear(),
                    child: const Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: Icon(Icons.close_rounded, color: _C.grey3, size: 16)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeed() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('casos').orderBy('createdAt', descending: true).snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: _C.accent));
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) return _buildEmpty();

        var docs = snapshot.data!.docs.where((d) {
          final data   = d.data() as Map<String, dynamic>;
          final status = data['status'] as String? ?? '';
          return status != 'pendente' && status != 'rejeitado' && status.isNotEmpty;
        }).toList();

        if (_query.isNotEmpty) {
          docs = docs.where((d) {
            final data  = d.data() as Map<String, dynamic>;
            final nome  = (data['nome']        ?? '').toString().toLowerCase();
            final local = (data['ultimo_local'] ?? '').toString().toLowerCase();
            final prov  = (data['provincia']   ?? '').toString().toLowerCase();
            return nome.contains(_query) || local.contains(_query) || prov.contains(_query);
          }).toList();
        }

        if (docs.isEmpty) return _buildEmpty(msg: 'Nenhum resultado para "$_query"');

        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
          itemCount: docs.length,
          itemBuilder: (_, i) => Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: _CasoCard(
              doc: docs[i],
              onLoginRequired: _redirectToLogin,
            ),
          ),
        );
      },
    );
  }

  Widget _buildEmpty({String msg = 'Nenhum caso publicado ainda.'}) {
    return Center(
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Container(
          width: 72, height: 72,
          decoration: BoxDecoration(color: _C.card, borderRadius: BorderRadius.circular(20), border: Border.all(color: _C.border)),
          child: const Icon(Icons.search_off_rounded, color: _C.grey3, size: 36),
        ),
        const SizedBox(height: 16),
        Text(msg, style: const TextStyle(color: _C.grey3, fontSize: 15)),
      ]),
    );
  }

  Widget _buildFAB() {
    return Container(
      decoration: BoxDecoration(gradient: const LinearGradient(colors: [_C.accent, _C.purple]), borderRadius: BorderRadius.circular(16)),
      child: FloatingActionButton.extended(
        onPressed: _handleCreate,
        backgroundColor: Colors.transparent,
        elevation: 0,
        icon: const Icon(Icons.add_rounded, color: _C.white),
        label: const Text('Relatar', style: TextStyle(color: _C.white, fontWeight: FontWeight.w700)),
      ),
    );
  }

  Widget _buildBottomNav() {
    return Container(
      decoration: BoxDecoration(color: _C.surface, border: Border(top: BorderSide(color: _C.border, width: 1))),
      child: BottomNavigationBar(
        currentIndex: _navIndex,
        backgroundColor: Colors.transparent,
        elevation: 0,
        selectedItemColor: _C.accent,
        unselectedItemColor: _C.grey3,
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home_rounded),         label: 'Home'),
          BottomNavigationBarItem(icon: Icon(Icons.map_rounded),           label: 'Mapa'),
          BottomNavigationBarItem(icon: Icon(Icons.auto_awesome_rounded),  label: 'Chatbot'),
          BottomNavigationBarItem(icon: Icon(Icons.person_rounded),        label: 'Perfil'),
        ],
        onTap: (i) {
          setState(() => _navIndex = i);
          if (i == 1) Navigator.push(context, MaterialPageRoute(builder: (_) => const MapPage()));
          if (i == 2) Navigator.push(context, MaterialPageRoute(builder: (_) => const ChatbotPage()));
          if (i == 3) {
            if (isGuest) _redirectToLogin();
            else Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfileScreen()));
          }
        },
      ),
    );
  }
}

// ─── CARD DO CASO ────────────────────────────────────────
class _CasoCard extends StatefulWidget {
  final QueryDocumentSnapshot doc;
  final VoidCallback onLoginRequired;
  const _CasoCard({super.key, required this.doc, required this.onLoginRequired});

  @override
  State<_CasoCard> createState() => _CasoCardState();
}

class _CasoCardState extends State<_CasoCard> {
  bool _apoiado   = false;
  bool _isLoading = false;
  final _currentUser = FirebaseAuth.instance.currentUser;

  Map<String, dynamic> get d => widget.doc.data() as Map<String, dynamic>;

  Uint8List? get _imageBytes {
    final img = d['imagem'] as String? ?? '';
    if (img.startsWith('data:image')) {
      try { return base64Decode(img.split(',').last); } catch (_) {}
    }
    return null;
  }

  int get apoiosCount      => d['apoios']      as int? ?? 0;
  int get comentariosCount => d['comentarios'] as int? ?? 0;

  // ── CORRIGIDO: trata Timestamp E String ──────────────
  String _daysAgo() {
    final raw = d['data_desaparecimento'];
    if (raw == null) return '';

    DateTime? dt;
    if (raw is Timestamp) {
      dt = raw.toDate();
    } else if (raw is String) {
      dt = DateTime.tryParse(raw);
    }

    if (dt == null) return '';
    final diff = DateTime.now().difference(dt).inDays;
    return diff == 0 ? 'Hoje' : 'Há $diff dias';
  }

  @override
  void initState() {
    super.initState();
    _loadSupportStatus();
  }

  Future<void> _loadSupportStatus() async {
    if (_currentUser == null) return;
    try {
      final snap = await FirebaseFirestore.instance.collection('casos').doc(widget.doc.id).get();
      final apoiadoPor = List<String>.from(snap.data()?['apoiadoPor'] ?? []);
      if (mounted) setState(() => _apoiado = apoiadoPor.contains(_currentUser!.uid));
    } catch (_) {}
  }

  Future<void> _toggleApoio() async {
    if (_currentUser == null) { widget.onLoginRequired(); return; }
    if (_isLoading) return;

    setState(() => _isLoading = true);
    final casoRef = FirebaseFirestore.instance.collection('casos').doc(widget.doc.id);

    try {
      final snap       = await casoRef.get();
      final apoiadoPor = List<String>.from(snap.data()?['apoiadoPor'] ?? []);
      final jaApoiou   = apoiadoPor.contains(_currentUser!.uid);

      if (jaApoiou) {
        await casoRef.update({
          'apoiadoPor': FieldValue.arrayRemove([_currentUser!.uid]),
          'apoios':     FieldValue.increment(-1),
        });
        setState(() => _apoiado = false);
      } else {
        await casoRef.update({
          'apoiadoPor': FieldValue.arrayUnion([_currentUser!.uid]),
          'apoios':     FieldValue.increment(1),
        });
        setState(() => _apoiado = true);

        await FirebaseFirestore.instance.collection('users').doc(_currentUser!.uid).update({
          'stats.apoios': FieldValue.increment(1),
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao apoiar: $e'), backgroundColor: _C.red));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _abrirComentarios() {
    if (_currentUser == null) { widget.onLoginRequired(); return; }
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: _C.bg,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => ComentariosBottomSheet(
        casoId:   widget.doc.id,
        casoNome: d['nome'] as String? ?? 'Caso',
      ),
    );
  }

  // ── NOVO: abre o modal de detalhes completos do caso ──────────────────
  void _abrirDetalhes() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _DetalhesCasoSheet(
        doc: widget.doc,
        imageBytes: _imageBytes,
        diasAgo: _daysAgo(),
      ),
    );
  }

  Future<void> _partilhar() async {
    final nome      = d['nome']     as String? ?? 'Desconhecido';
    final provincia = d['provincia'] as String? ?? 'Angola';
    final casoId    = widget.doc.id;
    // NOVO/CORRIGIDO: volta a incluir o link para o caso no site web
    // (o mesmo formato que o botão "Partilhar" do web já usa:
    // ?caso=<id>), agora com o domínio público real do GitHub Pages —
    // assim quem recebe a mensagem, mesmo sem a app instalada, consegue
    // abrir e ver o caso directamente no browser.
    final url = 'https://missing-ao.github.io/ProjectoFinal/?caso=$casoId';
    final texto = '$nome desapareceu em $provincia. Partilhe para ajudar! Missing AO.\n$url';

    try {
      await Share.share(texto, subject: '🔍 $nome — Missing AO');

      if (_currentUser != null) {
        await FirebaseFirestore.instance.collection('users').doc(_currentUser!.uid).update({
          'stats.partilhas': FieldValue.increment(1),
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('🔗 Não foi possível partilhar.'), backgroundColor: _C.red));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cfg         = _statusCfg(d['status'] as String?);
    final nome        = d['nome']           as String? ?? 'Nome não informado';
    final idade       = d['idade']?.toString() ?? '?';
    final provincia   = d['provincia']      as String? ?? 'Angola';
    final ultimoLocal = d['ultimo_local']   as String? ?? 'Não informado';
    final info        = d['informacoes_adicionais'] as String? ?? '';
    final roupas      = d['roupas']         as String? ?? '';
    final dias        = _daysAgo();
    final letter      = nome.isNotEmpty ? nome[0].toUpperCase() : '?';

    // ── CORRIGIDO: a área tocável para abrir detalhes agora cobre SÓ o
    // header + imagem + corpo de informação. A faixa de ações (Apoiar,
    // Comentar, Partilhar) fica COMPLETAMENTE fora do GestureDetector,
    // como um bloco independente — assim não há mais zona de toque
    // ambígua perto desses botões, nem risco de o toque "escapar" para
    // o card e abrir os detalhes por engano.
    return Container(
      decoration: BoxDecoration(
        color: _C.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _C.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Área tocável: abre os detalhes completos ──────────────
          GestureDetector(
            onTap: _abrirDetalhes,
            behavior: HitTestBehavior.opaque,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Header ──
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
                  child: Row(
                    children: [
                      Container(
                        width: 42, height: 42,
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(colors: [Color(0xFF3D5AF1), _C.purple]),
                          shape: BoxShape.circle,
                        ),
                        child: Center(child: Text(letter, style: const TextStyle(color: _C.white, fontWeight: FontWeight.bold, fontSize: 16))),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(nome, style: const TextStyle(color: _C.white, fontWeight: FontWeight.w700, fontSize: 15)),
                            Text('$idade anos • $provincia', style: const TextStyle(color: _C.grey3, fontSize: 12)),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: cfg.bg,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: cfg.color.withOpacity(0.4)),
                        ),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(cfg.icon, size: 11, color: cfg.color),
                          const SizedBox(width: 4),
                          Text(cfg.label, style: TextStyle(color: cfg.color, fontSize: 11, fontWeight: FontWeight.w700)),
                        ]),
                      ),
                    ],
                  ),
                ),

                // ── Imagem ──
                _imageBytes != null
                    ? Image.memory(_imageBytes!, height: 260, width: double.infinity, fit: BoxFit.cover)
                    : Container(height: 200, color: _C.surface, child: const Center(child: Icon(Icons.person_rounded, color: _C.grey4, size: 64))),

                // ── Corpo ──
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.location_on_rounded, size: 14, color: _C.red),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(ultimoLocal, style: const TextStyle(color: _C.red, fontWeight: FontWeight.w600, fontSize: 13)),
                          ),
                          if (dias.isNotEmpty)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(color: const Color(0x26F59E0B), borderRadius: BorderRadius.circular(8)),
                              child: Text(dias, style: const TextStyle(color: _C.orange, fontSize: 10, fontWeight: FontWeight.w600)),
                            ),
                        ],
                      ),
                      if (info.isNotEmpty || roupas.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Text(
                          [if (info.isNotEmpty) info, if (roupas.isNotEmpty) 'Vestia: $roupas.'].join(' '),
                          style: const TextStyle(color: _C.grey2, fontSize: 13, height: 1.5),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],

                      // ── Dica de toque para abrir os detalhes completos ──
                      const Padding(
                        padding: EdgeInsets.only(top: 10),
                        child: Row(
                          children: [
                            Icon(Icons.touch_app_rounded, size: 12, color: _C.accent),
                            SizedBox(width: 4),
                            Text(
                              'Toque para ver detalhes completos',
                              style: TextStyle(color: _C.accent, fontSize: 11, fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // ── Separador visual claro entre a zona tocável e as acções ──
          const Divider(color: _C.border, height: 1),

          // ── Acções — FORA do GestureDetector de detalhes, com
          // padding próprio para dar mais "respiro" ao toque ──────────
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 6, 10, 10),
            child: Row(
              children: [
                _ActionBtn(
                  icon:  _apoiado ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                  label: '$apoiosCount Apoiar',
                  color: _apoiado ? _C.red : _C.grey2,
                  onTap: _isLoading ? null : _toggleApoio,
                ),
                _ActionBtn(
                  icon:  Icons.mode_comment_outlined,
                  label: '$comentariosCount Comentar',
                  color: _C.grey2,
                  onTap: _abrirComentarios,
                ),
                _ActionBtn(
                  icon:  Icons.send_rounded,
                  label: 'Partilhar',
                  color: _C.grey2,
                  onTap: _partilhar,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;
  const _ActionBtn({required this.icon, required this.label, required this.color, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 5),
              Text(label, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w500)),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── MODAL DE DETALHES COMPLETOS DO CASO ────────────────
// NOVO — mostra TODA a informação sem truncar, imagem completa (sem
// cortar, usando BoxFit.contain) e botão para abrir o caso directamente
// no mapa interativo (MapPage focado no casoId).
class _DetalhesCasoSheet extends StatelessWidget {
  final QueryDocumentSnapshot doc;
  final Uint8List? imageBytes;
  final String diasAgo;

  const _DetalhesCasoSheet({
    required this.doc,
    required this.imageBytes,
    required this.diasAgo,
  });

  Map<String, dynamic> get d => doc.data() as Map<String, dynamic>;

  @override
  Widget build(BuildContext context) {
    final cfg              = _statusCfg(d['status'] as String?);
    final nome             = d['nome']                  as String? ?? 'Nome não informado';
    final idade            = d['idade']?.toString()      ?? '?';
    final sexo             = d['sexo']                   as String? ?? '';
    final altura           = d['altura']                 as String? ?? '';
    final bi                = d['bi']                     as String? ?? '';
    final provincia        = d['provincia']              as String? ?? 'Angola';
    final municipio        = d['municipio']              as String? ?? '';
    final ultimoLocal      = d['ultimo_local']           as String? ?? 'Não informado';
    final horaDesap        = d['hora_desaparecimento']   as String? ?? '';
    final info             = d['informacoes_adicionais'] as String? ?? '';
    final roupas           = d['roupas']                 as String? ?? '';
    final deficiencia      = d['deficiencia']            as String? ?? '';
    final tipoDeficiencia  = d['tipo_deficiencia']       as String? ?? '';
    final temCoords        = d['lat'] != null && d['lng'] != null;

    return DraggableScrollableSheet(
      initialChildSize: 0.9,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) => Container(
        decoration: const BoxDecoration(
          color: _C.bg,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            // ── Alça de arrastar ──
            Container(
              width: 36, height: 4,
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              decoration: BoxDecoration(color: _C.grey4, borderRadius: BorderRadius.circular(2)),
            ),

            // ── Cabeçalho fixo ──
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 8, 8),
              child: Row(
                children: [
                  const Icon(Icons.badge_rounded, color: _C.accent, size: 18),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Detalhes do Caso',
                      style: TextStyle(color: _C.white, fontSize: 16, fontWeight: FontWeight.w700),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: _C.grey2),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            const Divider(color: _C.border, height: 1),

            // ── Conteúdo com scroll — tudo visível, nada truncado ──
            Expanded(
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                children: [
                  // ── Imagem completa, sem cortar ──
                  if (imageBytes != null)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        width: double.infinity,
                        color: _C.surface,
                        child: Image.memory(
                          imageBytes!,
                          fit: BoxFit.contain, // mostra a imagem inteira, sem cortar
                        ),
                      ),
                    )
                  else
                    Container(
                      height: 180,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: _C.surface,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Center(child: Icon(Icons.person_rounded, color: _C.grey4, size: 64)),
                    ),

                  const SizedBox(height: 16),

                  // ── Nome + status ──
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          nome,
                          style: const TextStyle(color: _C.white, fontSize: 20, fontWeight: FontWeight.w800),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: cfg.bg,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: cfg.color.withOpacity(0.4)),
                        ),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(cfg.icon, size: 12, color: cfg.color),
                          const SizedBox(width: 4),
                          Text(cfg.label, style: TextStyle(color: cfg.color, fontSize: 12, fontWeight: FontWeight.w700)),
                        ]),
                      ),
                    ],
                  ),
                  if (diasAgo.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text('Desapareceu $diasAgo', style: const TextStyle(color: _C.orange, fontSize: 13, fontWeight: FontWeight.w600)),
                  ],

                  const SizedBox(height: 20),

                  // ── Botão: ver no mapa ──
                  if (temCoords)
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () {
                          Navigator.pop(context); // fecha o modal
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => MapPage(casoId: doc.id)),
                          );
                        },
                        icon: const Icon(Icons.map_rounded, size: 18),
                        label: const Text('Ver no mapa interativo', style: TextStyle(fontWeight: FontWeight.w700)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _C.accent,
                          foregroundColor: _C.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          elevation: 0,
                        ),
                      ),
                    )
                  else
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: _C.card,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: _C.border),
                      ),
                      child: const Row(children: [
                        Icon(Icons.location_off_rounded, color: _C.grey3, size: 16),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Este caso não tem localização exacta registada no mapa.',
                            style: TextStyle(color: _C.grey3, fontSize: 12),
                          ),
                        ),
                      ]),
                    ),

                  const SizedBox(height: 20),

                  // ── Secção: Informações Pessoais ──
                  _secaoTitulo('Informações Pessoais'),
                  _campoDetalhe(Icons.cake_rounded, 'Idade', '$idade anos'),
                  if (sexo.isNotEmpty) _campoDetalhe(Icons.wc_rounded, 'Sexo', sexo),
                  if (altura.isNotEmpty) _campoDetalhe(Icons.height_rounded, 'Altura', altura),
                  if (bi.isNotEmpty) _campoDetalhe(Icons.badge_rounded, 'Nº do BI', bi),
                  if (deficiencia == 'Sim')
                    _campoDetalhe(
                      Icons.accessible_rounded,
                      'Deficiência',
                      tipoDeficiencia.isNotEmpty ? tipoDeficiencia : 'Sim',
                    ),

                  const SizedBox(height: 16),

                  // ── Secção: Localização e Data ──
                  _secaoTitulo('Local e Data do Desaparecimento'),
                  _campoDetalhe(
                    Icons.location_on_rounded,
                    'Último local visto',
                    ultimoLocal,
                    destaque: true,
                  ),
                  if (municipio.isNotEmpty || provincia.isNotEmpty)
                    _campoDetalhe(
                      Icons.map_rounded,
                      'Município / Província',
                      [municipio, provincia].where((s) => s.isNotEmpty).join(', '),
                    ),
                  if (horaDesap.isNotEmpty)
                    _campoDetalhe(Icons.access_time_rounded, 'Hora do desaparecimento', horaDesap),

                  const SizedBox(height: 16),

                  // ── Secção: Outras informações ──
                  if (roupas.isNotEmpty || info.isNotEmpty) ...[
                    _secaoTitulo('Outras Informações'),
                    if (roupas.isNotEmpty)
                      _campoDetalheTexto('Roupas que usava', roupas),
                    if (info.isNotEmpty)
                      _campoDetalheTexto('Informações adicionais', info),
                  ],

                  // NOVO — Secção: Relatado por (equivalente ao
                  // cd-relator-card do web) — carrega o perfil de quem
                  // relatou o caso e permite tocar para o abrir, tal como
                  // já acontece nos comentários e no painel admin.
                  if ((d['userId'] as String?)?.isNotEmpty == true) ...[
                    const SizedBox(height: 20),
                    _secaoTitulo('Relatado por'),
                    FutureBuilder<DocumentSnapshot>(
                      future: FirebaseFirestore.instance
                          .collection('users')
                          .doc(d['userId'] as String)
                          .get(),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState == ConnectionState.waiting) {
                          return const Padding(
                            padding: EdgeInsets.symmetric(vertical: 8),
                            child: Row(children: [
                              SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: _C.accent)),
                              SizedBox(width: 8),
                              Text('A carregar...', style: TextStyle(color: _C.grey3, fontSize: 12)),
                            ]),
                          );
                        }
                        // CORRIGIDO: antes qualquer falha (incluindo erro de
                        // permissão do Firestore) caía na mensagem genérica
                        // "não foi possível encontrar", escondendo a causa
                        // real. Agora distingue os dois casos.
                        if (snapshot.hasError) {
                          final msg = snapshot.error.toString();
                          final isPermissao = msg.contains('permission') || msg.contains('PERMISSION');
                          return Text(
                            isPermissao
                                ? 'Sem permissão para ver este perfil (regras do Firestore).'
                                : 'Erro ao carregar: $msg',
                            style: const TextStyle(color: _C.grey3, fontSize: 12),
                          );
                        }
                        if (!snapshot.hasData || !snapshot.data!.exists) {
                          return const Text(
                            'Este utilizador já não existe (conta removida).',
                            style: TextStyle(color: _C.grey3, fontSize: 12),
                          );
                        }

                        final autor = snapshot.data!.data() as Map<String, dynamic>;
                        final autorNome = autor['nome'] as String? ?? autor['email'] as String? ?? 'Utilizador';
                        final autorFotoB64 = autor['photoBase64'] as String?;
                        Uint8List? autorFotoBytes;
                        if (autorFotoB64 != null && autorFotoB64.contains(',')) {
                          try { autorFotoBytes = base64Decode(autorFotoB64.split(',').last); } catch (_) {}
                        }

                        return GestureDetector(
                          onTap: () {
                            Navigator.pop(context); // fecha este modal antes de navegar
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => ProfileScreen(targetUid: d['userId'] as String)),
                            );
                          },
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: _C.card,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: _C.border),
                            ),
                            child: Row(children: [
                              CircleAvatar(
                                radius: 20,
                                backgroundColor: _C.grey4,
                                backgroundImage: autorFotoBytes != null ? MemoryImage(autorFotoBytes) : null,
                                child: autorFotoBytes == null
                                    ? Text(
                                        autorNome.isNotEmpty ? autorNome[0].toUpperCase() : '?',
                                        style: const TextStyle(color: _C.white, fontWeight: FontWeight.bold),
                                      )
                                    : null,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  autorNome,
                                  style: const TextStyle(color: _C.white, fontWeight: FontWeight.w600, fontSize: 14),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const Icon(Icons.arrow_forward_ios_rounded, color: _C.accent, size: 12),
                            ]),
                          ),
                        );
                      },
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _secaoTitulo(String texto) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, top: 4),
      child: Text(
        texto,
        style: const TextStyle(color: _C.accent, fontSize: 13, fontWeight: FontWeight.w700, letterSpacing: 0.3),
      ),
    );
  }

  // Campo curto, em linha (label + valor)
  Widget _campoDetalhe(IconData icon, String label, String valor, {bool destaque = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: destaque ? _C.red : _C.grey3),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(color: _C.grey3, fontSize: 11)),
                const SizedBox(height: 2),
                Text(
                  valor,
                  style: TextStyle(
                    color: destaque ? _C.red : _C.grey1,
                    fontSize: 14,
                    fontWeight: destaque ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Campo longo, em bloco — para textos que podem ser grandes
  // (informações adicionais, roupas) — sem maxLines, sem ellipsis
  Widget _campoDetalheTexto(String label, String texto) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: _C.grey3, fontSize: 11)),
          const SizedBox(height: 6),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _C.card,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _C.border),
            ),
            child: Text(
              texto,
              style: const TextStyle(color: _C.grey1, fontSize: 13, height: 1.5),
              // SEM maxLines / overflow — mostra o texto completo
            ),
          ),
        ],
      ),
    );
  }
}

// ─── MODAL DE COMENTÁRIOS ────────────────────────────────
class ComentariosBottomSheet extends StatefulWidget {
  final String casoId;
  final String casoNome;
  const ComentariosBottomSheet({super.key, required this.casoId, required this.casoNome});

  @override
  State<ComentariosBottomSheet> createState() => _ComentariosBottomSheetState();
}

class _ComentariosBottomSheetState extends State<ComentariosBottomSheet> {
  final TextEditingController _commentCtrl = TextEditingController();
  final _currentUser = FirebaseAuth.instance.currentUser;
  bool _sending = false;

  Map<String, dynamic>? _myUserData;

  @override
  void initState() {
    super.initState();
    _loadMyData();
  }

  @override
  void dispose() {
    _commentCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadMyData() async {
    if (_currentUser == null) return;
    try {
      final snap = await FirebaseFirestore.instance.collection('users').doc(_currentUser!.uid).get();
      if (snap.exists && mounted) setState(() => _myUserData = snap.data());
    } catch (_) {}
  }

  Future<void> _enviarComentario() async {
    final texto = _commentCtrl.text.trim();
    if (texto.isEmpty || _currentUser == null || _sending) return;

    setState(() => _sending = true);
    try {
      final userData = _myUserData ?? {};

      await FirebaseFirestore.instance
          .collection('casos')
          .doc(widget.casoId)
          .collection('comentarios')
          .add({
        'texto':     texto,
        'autorId':   _currentUser!.uid,
        'autorNome': userData['nome'] ?? 'Utilizador',
        'autorFoto': userData['photoBase64'] ?? '',
        'criadoEm':  FieldValue.serverTimestamp(),
      });

      await FirebaseFirestore.instance.collection('casos').doc(widget.casoId).update({
        'comentarios': FieldValue.increment(1),
      });

      await FirebaseFirestore.instance.collection('users').doc(_currentUser!.uid).update({
        'stats.comentarios': FieldValue.increment(1),
      });

      _commentCtrl.clear();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao comentar: $e'), backgroundColor: _C.red));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _apagarComentario(String comentarioId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: _C.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Apagar comentário?', style: TextStyle(color: _C.white, fontSize: 16)),
        content: const Text('Esta acção não pode ser desfeita.', style: TextStyle(color: _C.grey2, fontSize: 13)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar', style: TextStyle(color: _C.grey2))),
          TextButton(onPressed: () => Navigator.pop(context, true),  child: const Text('Apagar',   style: TextStyle(color: _C.red))),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      await FirebaseFirestore.instance
          .collection('casos')
          .doc(widget.casoId)
          .collection('comentarios')
          .doc(comentarioId)
          .delete();

      await FirebaseFirestore.instance.collection('casos').doc(widget.casoId).update({
        'comentarios': FieldValue.increment(-1),
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao apagar: $e'), backgroundColor: _C.red));
      }
    }
  }

  Widget _buildAvatar(String? fotoB64, String nome, {double radius = 18}) {
    Uint8List? bytes;
    if (fotoB64 != null && fotoB64.contains(',')) {
      try { bytes = base64Decode(fotoB64.split(',').last); } catch (_) {}
    }
    return CircleAvatar(
      radius: radius,
      backgroundColor: _C.grey4,
      backgroundImage: bytes != null ? MemoryImage(bytes) : null,
      child: bytes == null
          ? Text(
              nome.isNotEmpty ? nome[0].toUpperCase() : '?',
              style: TextStyle(color: _C.white, fontSize: radius * 0.75, fontWeight: FontWeight.w700),
            )
          : null,
    );
  }

  // NOVO: abre o perfil de quem comentou — equivalente ao link para
  // profile.html?uid=... que já existe no web (comment-author-link).
  void _abrirPerfilAutor(String uid) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ProfileScreen(targetUid: uid)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) => Container(
        decoration: const BoxDecoration(
          color: _C.card,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            Container(
              width: 36, height: 4,
              margin: const EdgeInsets.only(top: 12, bottom: 0),
              decoration: BoxDecoration(color: _C.grey4, borderRadius: BorderRadius.circular(2)),
            ),

            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
              child: Row(
                children: [
                  const Icon(Icons.mode_comment_outlined, color: _C.accent, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Comentários · ${widget.casoNome}',
                      style: const TextStyle(color: _C.white, fontSize: 16, fontWeight: FontWeight.w700),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: _C.grey2),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),

            const Divider(color: _C.border, height: 1),

            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('casos')
                    .doc(widget.casoId)
                    .collection('comentarios')
                    .orderBy('criadoEm', descending: false)
                    .snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator(color: _C.accent));
                  }
                  if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                    return const Center(
                      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Icon(Icons.chat_bubble_outline_rounded, color: _C.grey4, size: 40),
                        SizedBox(height: 12),
                        Text('Seja o primeiro a comentar!', style: TextStyle(color: _C.grey3, fontSize: 14)),
                      ]),
                    );
                  }

                  final comments = snapshot.data!.docs;

                  return ListView.builder(
                    controller: scrollController,
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                    itemCount: comments.length,
                    itemBuilder: (context, index) {
                      final doc       = comments[index];
                      final c         = doc.data() as Map<String, dynamic>;
                      final cId       = doc.id;
                      final dt        = (c['criadoEm'] as Timestamp?)?.toDate() ?? DateTime.now();
                      final ts        = '${dt.hour.toString().padLeft(2,'0')}:${dt.minute.toString().padLeft(2,'0')} · ${dt.day}/${dt.month}';
                      final autorId   = c['autorId']   as String? ?? '';
                      final autorNome = c['autorNome'] as String? ?? 'Utilizador';
                      final autorFoto = c['autorFoto'] as String? ?? '';
                      final isAuthor  = _currentUser != null && _currentUser!.uid == autorId;

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // NOVO: avatar tocável — abre o perfil do autor,
                            // tal como já acontece no web (comment-avatar-link).
                            GestureDetector(
                              onTap: autorId.isNotEmpty ? () => _abrirPerfilAutor(autorId) : null,
                              child: _buildAvatar(autorFoto.isNotEmpty ? autorFoto : null, autorNome),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      // NOVO: nome também tocável — mesmo alvo do avatar.
                                      GestureDetector(
                                        onTap: autorId.isNotEmpty ? () => _abrirPerfilAutor(autorId) : null,
                                        child: Text(autorNome, style: const TextStyle(color: _C.white, fontWeight: FontWeight.w600, fontSize: 13)),
                                      ),
                                      const Spacer(),
                                      if (isAuthor)
                                        GestureDetector(
                                          onTap: () => _apagarComentario(cId),
                                          child: const Icon(Icons.delete_outline_rounded, color: _C.grey3, size: 16),
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 3),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                    decoration: BoxDecoration(
                                      color: _C.surface,
                                      borderRadius: const BorderRadius.only(
                                        topRight: Radius.circular(14),
                                        bottomLeft: Radius.circular(14),
                                        bottomRight: Radius.circular(14),
                                      ),
                                      border: Border.all(color: _C.border),
                                    ),
                                    child: Text(c['texto'] ?? '', style: const TextStyle(color: _C.grey1, fontSize: 13, height: 1.4)),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(ts, style: const TextStyle(color: _C.grey3, fontSize: 11)),
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

            Padding(
              padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
              child: Container(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                decoration: BoxDecoration(
                  color: _C.surface,
                  border: Border(top: BorderSide(color: _C.border)),
                ),
                child: Row(
                  children: [
                    _buildAvatar(
                      _myUserData?['photoBase64'] as String?,
                      _myUserData?['nome'] as String? ?? '',
                      radius: 16,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: _commentCtrl,
                        style: const TextStyle(color: _C.white, fontSize: 14),
                        decoration: InputDecoration(
                          hintText: 'Escreva um comentário...',
                          hintStyle: const TextStyle(color: _C.grey3, fontSize: 14),
                          filled: true,
                          fillColor: _C.card,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          isDense: true,
                        ),
                        onSubmitted: (_) => _enviarComentario(),
                        textInputAction: TextInputAction.send,
                      ),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: _sending ? null : _enviarComentario,
                      child: Container(
                        width: 38, height: 38,
                        decoration: BoxDecoration(
                          color: _sending ? _C.grey4 : _C.accent,
                          shape: BoxShape.circle,
                        ),
                        child: _sending
                            ? const Padding(
                                padding: EdgeInsets.all(10),
                                child: CircularProgressIndicator(color: _C.white, strokeWidth: 2),
                              )
                            : const Icon(Icons.send_rounded, color: _C.white, size: 18),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}