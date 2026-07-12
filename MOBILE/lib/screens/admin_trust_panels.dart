// lib/screens/admin_trust_panels.dart
// ─────────────────────────────────────────────────────────────────────────────
// Três painéis novos para o AdminPage:
//
//  1. AdminComentariosPanel  — lista comentários de TODOS os casos com botão
//                              de apagar + penalização automática do autor
//
//  2. AdminTrustPanel        — lista todos os utilizadores com Trust Score,
//                              filtros por estado, histórico individual e
//                              ajuste manual de score
//
//  3. AdminSuportePanel      — lista pedidos de suporte de utilizadores
//                              suspensos, com histórico do chat e botões de
//                              reactivar / manter suspensão
//
// INTEGRAÇÃO NO admin_page.dart:
//   a) Adicionar imports deste ficheiro
//   b) Adicionar 3 entradas no _MenuContent:
//        _item('comentarios', Icons.mode_comment_rounded, 'Comentários',  section, onNav)
//        _item('trust',       Icons.shield_rounded,       'Trust Scores', section, onNav)
//        _item('suporte',     Icons.support_agent_rounded,'Suporte',      section, onNav)
//   c) No _buildContent() do AdminPage, adicionar os 3 casos:
//        case 'comentarios': return AdminComentariosPanel();
//        case 'trust':       return AdminTrustPanel();
//        case 'suporte':     return AdminSuportePanel();
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/trust_service.dart';

// ─── PALETA (espelho da classe _C do admin_page.dart) ────────────────────────
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
  static const purple     = Color(0xFF9B5DE5);
  static const purpleSoft = Color(0x269B5DE5);
  static const white      = Color(0xFFFFFFFF);
  static const grey1      = Color(0xFFE4E4E7);
  static const grey2      = Color(0xFFA1A1AA);
  static const grey3      = Color(0xFF52525B);
  static const grey4      = Color(0xFF3F3F46);
}

// ─────────────────────────────────────────────────────────────────────────────
// 1. PAINEL DE COMENTÁRIOS — admin apaga + penaliza
// ─────────────────────────────────────────────────────────────────────────────
class AdminComentariosPanel extends StatefulWidget {
  const AdminComentariosPanel({super.key});

  @override
  State<AdminComentariosPanel> createState() => _AdminComentariosPanelState();
}

class _AdminComentariosPanelState extends State<AdminComentariosPanel> {
  final _db      = FirebaseFirestore.instance;
  final _adminUid = FirebaseAuth.instance.currentUser?.uid ?? '';

  // Todos os comentários de todos os casos, carregados de forma assíncrona
  List<Map<String, dynamic>> _comentarios = [];
  bool _loading = true;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    setState(() => _loading = true);
    try {
      // Busca todos os casos aprovados
      final casosSnap = await _db.collection('casos')
          .where('status', whereIn: ['aprovado', 'encontrado', 'desmentido'])
          .get();

      final lista = <Map<String, dynamic>>[];

      for (final casoDoc in casosSnap.docs) {
        final casoData = casoDoc.data();
        final casoId   = casoDoc.id;
        final casoNome = casoData['nome'] as String? ?? 'Caso sem nome';

        final comsSnap = await _db
            .collection('casos')
            .doc(casoId)
            .collection('comentarios')
            .orderBy('criadoEm', descending: true)
            .get();

        for (final comDoc in comsSnap.docs) {
          lista.add({
            'id':        comDoc.id,
            'casoId':    casoId,
            'casoNome':  casoNome,
            ...comDoc.data(),
          });
        }
      }

      // Ordena globalmente por data desc
      lista.sort((a, b) {
        final ta = (a['criadoEm'] as Timestamp?)?.toDate() ?? DateTime(2000);
        final tb = (b['criadoEm'] as Timestamp?)?.toDate() ?? DateTime(2000);
        return tb.compareTo(ta);
      });

      if (mounted) setState(() { _comentarios = lista; _loading = false; });
    } catch (e) {
      if (mounted) setState(() => _loading = false);
      debugPrint('Erro ao carregar comentários: $e');
    }
  }

  List<Map<String, dynamic>> get _filtrados {
    if (_query.isEmpty) return _comentarios;
    final q = _query.toLowerCase();
    return _comentarios.where((c) {
      return (c['texto']     as String? ?? '').toLowerCase().contains(q)
          || (c['autorNome'] as String? ?? '').toLowerCase().contains(q)
          || (c['casoNome']  as String? ?? '').toLowerCase().contains(q);
    }).toList();
  }

  Future<void> _apagarComentario(Map<String, dynamic> com) async {
    final autorId   = com['autorId']  as String? ?? '';
    final autorNome = com['autorNome'] as String? ?? 'Utilizador';
    final texto     = com['texto']    as String? ?? '';

    // Pede confirmação e escolha de penalização
    int? pontos = await showDialog<int>(
      context: context,
      builder: (_) => _ConfirmarApagamento(autorNome: autorNome, texto: texto),
    );
    if (pontos == null || !mounted) return;

    try {
      // 1. Apaga o comentário
      await _db
          .collection('casos')
          .doc(com['casoId'] as String)
          .collection('comentarios')
          .doc(com['id'] as String)
          .delete();

      // 2. Decrementa contador no caso
      await _db.collection('casos').doc(com['casoId'] as String).update({
        'comentarios': FieldValue.increment(-1),
      });

      // 3. Penaliza o autor (se aplicável)
      if (autorId.isNotEmpty && pontos > 0) {
        await TrustService.instance.penalizar(
          uid:      autorId,
          motivo:   'comentario_removido',
          pontos:   pontos,
          adminUid: _adminUid,
          detalhe:  'Comentário apagado: "${texto.length > 60 ? texto.substring(0, 60) + '…' : texto}"',
        );
      }

      if (mounted) {
        setState(() => _comentarios.removeWhere((c) => c['id'] == com['id']));
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(pontos > 0
            ? 'Comentário apagado. −$pontos pontos aplicados a $autorNome.'
            : 'Comentário apagado sem penalização.'),
          backgroundColor: _C.green,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Erro: $e'), backgroundColor: _C.red,
          behavior: SnackBarBehavior.floating,
        ));
      }
    }
  }

  String _formatTs(dynamic raw) {
    if (raw == null) return '—';
    final dt = raw is Timestamp ? raw.toDate() : DateTime.tryParse(raw.toString());
    if (dt == null) return '—';
    return '${dt.day.toString().padLeft(2,'0')}/${dt.month.toString().padLeft(2,'0')}/${dt.year} ${dt.hour.toString().padLeft(2,'0')}:${dt.minute.toString().padLeft(2,'0')}';
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: _C.accent));
    }

    final filtrados = _filtrados;

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Cabeçalho
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Comentários',
                      style: TextStyle(color: _C.white, fontSize: 20, fontWeight: FontWeight.w800)),
                    Text('${_comentarios.length} comentário(s) no total',
                      style: const TextStyle(color: _C.grey3, fontSize: 12)),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.refresh_rounded, color: _C.grey2),
                onPressed: _carregar,
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Pesquisa
          _SearchField(
            hint: 'Pesquisar por texto, autor ou caso...',
            onChanged: (v) => setState(() => _query = v),
          ),
          const SizedBox(height: 16),

          if (filtrados.isEmpty)
            const Expanded(
              child: Center(
                child: Text('Nenhum comentário encontrado.',
                  style: TextStyle(color: _C.grey3, fontSize: 14)),
              ),
            )
          else
            Expanded(
              child: RefreshIndicator(
                onRefresh: _carregar,
                color: _C.accent,
                child: ListView.builder(
                  itemCount: filtrados.length,
                  itemBuilder: (_, i) {
                    final com = filtrados[i];
                    return _ComentarioCard(
                      com: com,
                      formatTs: _formatTs,
                      onDelete: () => _apagarComentario(com),
                    );
                  },
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ComentarioCard extends StatelessWidget {
  final Map<String, dynamic> com;
  final String Function(dynamic) formatTs;
  final VoidCallback onDelete;
  const _ComentarioCard({required this.com, required this.formatTs, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final autorNome = com['autorNome'] as String? ?? 'Utilizador';
    final texto     = com['texto']    as String? ?? '';
    final casoNome  = com['casoNome'] as String? ?? '—';
    final ts        = formatTs(com['criadoEm']);
    final fotoB64   = com['autorFoto'] as String? ?? '';

    Uint8List? fotoBytes;
    if (fotoB64.contains(',')) {
      try { fotoBytes = base64Decode(fotoB64.split(',').last); } catch (_) {}
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _C.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _C.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: avatar + autor + caso
          Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: _C.grey4,
                backgroundImage: fotoBytes != null ? MemoryImage(fotoBytes) : null,
                child: fotoBytes == null
                    ? Text(autorNome.isNotEmpty ? autorNome[0].toUpperCase() : '?',
                        style: const TextStyle(color: _C.white, fontWeight: FontWeight.bold))
                    : null,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(autorNome,
                      style: const TextStyle(color: _C.white, fontWeight: FontWeight.w600, fontSize: 13)),
                    Row(
                      children: [
                        const Icon(Icons.person_search_rounded, size: 10, color: _C.grey3),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text('Caso: $casoNome',
                            style: const TextStyle(color: _C.grey3, fontSize: 11),
                            overflow: TextOverflow.ellipsis),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // Botão apagar
              GestureDetector(
                onTap: onDelete,
                child: Container(
                  width: 34, height: 34,
                  decoration: BoxDecoration(
                    color: _C.redSoft,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: _C.red.withValues(alpha: 0.3)),
                  ),
                  child: const Icon(Icons.delete_outline_rounded, color: _C.red, size: 16),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Texto do comentário
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: _C.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _C.border),
            ),
            child: Text(texto,
              style: const TextStyle(color: _C.grey1, fontSize: 13, height: 1.4)),
          ),
          const SizedBox(height: 6),

          // Timestamp
          Text(ts, style: const TextStyle(color: _C.grey3, fontSize: 11)),
        ],
      ),
    );
  }
}

// Diálogo de confirmação de apagamento com escolha de penalização
class _ConfirmarApagamento extends StatefulWidget {
  final String autorNome, texto;
  const _ConfirmarApagamento({required this.autorNome, required this.texto});
  @override
  State<_ConfirmarApagamento> createState() => _ConfirmarApagamentoState();
}

class _ConfirmarApagamentoState extends State<_ConfirmarApagamento> {
  int _pontos = TrustService.pComentarioRemovido; // 10 por defeito

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: _C.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text('Apagar Comentário',
        style: TextStyle(color: _C.white, fontSize: 16, fontWeight: FontWeight.w700)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Autor: ${widget.autorNome}',
            style: const TextStyle(color: _C.grey2, fontSize: 13)),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: _C.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _C.border),
            ),
            child: Text(
              widget.texto.length > 120
                  ? '${widget.texto.substring(0, 120)}…'
                  : widget.texto,
              style: const TextStyle(color: _C.grey1, fontSize: 12, height: 1.4),
            ),
          ),
          const SizedBox(height: 16),
          const Text('Penalização ao autor:',
            style: TextStyle(color: _C.grey2, fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          ...[ 0, 5, 10, 20 ].map((p) => RadioListTile<int>(
            value: p,
            groupValue: _pontos,
            onChanged: (v) => setState(() => _pontos = v!),
            dense: true,
            activeColor: _C.accent,
            title: Text(
              p == 0 ? 'Sem penalização' : '−$p pontos de Trust Score',
              style: TextStyle(
                color: p == 0 ? _C.grey2 : _C.red,
                fontSize: 13,
              ),
            ),
          )),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, null),
          child: const Text('Cancelar', style: TextStyle(color: _C.grey2)),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, _pontos),
          style: ElevatedButton.styleFrom(
            backgroundColor: _C.red,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          child: const Text('Apagar', style: TextStyle(color: _C.white, fontWeight: FontWeight.w700)),
        ),
      ],
    );
  }
}


// ─────────────────────────────────────────────────────────────────────────────
// 2. PAINEL DE TRUST SCORES
// ─────────────────────────────────────────────────────────────────────────────
class AdminTrustPanel extends StatefulWidget {
  final TextEditingController? searchCtrl;
  const AdminTrustPanel({super.key, this.searchCtrl});

  @override
  State<AdminTrustPanel> createState() => _AdminTrustPanelState();
}

class _AdminTrustPanelState extends State<AdminTrustPanel> {
  final _db       = FirebaseFirestore.instance;
  final _adminUid = FirebaseAuth.instance.currentUser?.uid ?? '';

  List<Map<String, dynamic>> _users = [];
  bool   _loading      = true;
  String _filtroEstado = '';
  String _query        = '';

  @override
  void initState() {
    super.initState();
    widget.searchCtrl?.addListener(_onSearch);
    _carregar();
  }

  @override
  void dispose() {
    widget.searchCtrl?.removeListener(_onSearch);
    super.dispose();
  }

  void _onSearch() {
    if (mounted) setState(() => _query = widget.searchCtrl?.text.toLowerCase() ?? '');
  }

  Future<void> _carregar() async {
    setState(() => _loading = true);
    final snap = await _db.collection('users').get();
    // CORRIGIDO: carregava TODOS os utilizadores, incluindo admins — que
    // não devem ter Trust Score (não faz sentido uma conta admin ser
    // suspensa por pontuação, já que é ela própria, geralmente, quem
    // aplica essas penalizações a utilizadores comuns). Filtra aqui em
    // vez de na query do Firestore, para não precisar de um índice novo.
    final lista = snap.docs
        .map((d) => {'id': d.id, ...d.data()})
        .where((u) => (u['role'] ?? 'user') != 'admin')
        .toList();
    lista.sort((a, b) {
      final sa = (a['trustScore'] as int?) ?? 100;
      final sb = (b['trustScore'] as int?) ?? 100;
      return sa.compareTo(sb);
    });
    if (mounted) setState(() { _users = lista; _loading = false; });
  }

  List<Map<String, dynamic>> get _filtrados {
    return _users.where((u) {
      final score  = (u['trustScore'] as int?) ?? 100;
      final estado = TrustService.estadoDeScore(score);
      final label  = TrustService.labelEstado(estado).toLowerCase();
      if (_filtroEstado.isNotEmpty && label != _filtroEstado.toLowerCase()) return false;
      if (_query.isNotEmpty) {
        final h = '${u['nome'] ?? ''} ${u['email'] ?? ''}'.toLowerCase();
        if (!h.contains(_query)) return false;
      }
      return true;
    }).toList();
  }

  Future<void> _verHistorico(Map<String, dynamic> user) async {
    final uid  = user['id'] as String;
    final nome = user['nome'] as String? ?? user['email'] as String? ?? uid;
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (_) => _HistoricoCompletoDialog(uid: uid, nome: nome, userData: user),
    );
  }

  Future<void> _ajustarScore(Map<String, dynamic> user) async {
    final uid   = user['id'] as String;
    final nome  = user['nome'] as String? ?? user['email'] as String? ?? uid;
    final score = (user['trustScore'] as int?) ?? 100;

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _AjustarScoreDialog(nome: nome, scoreActual: score),
    );
    if (result == null || !mounted) return;

    final delta  = result['delta']  as int;
    final motivo = result['motivo'] as String;

    // CORRIGIDO: antes, se TrustService.ajustarScore lançasse uma excepção
    // (ex.: regras de segurança do Firestore a recusar a escrita), a função
    // abortava em silêncio — _carregar() e o SnackBar nunca eram alcançados,
    // e o utilizador não tinha qualquer indicação de que o ajuste falhou.
    try {
      await TrustService.instance.ajustarScore(
        uid: uid, delta: delta, adminUid: _adminUid, motivo: motivo,
      );
      await _carregar();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Score de $nome ajustado em ${delta >= 0 ? '+' : ''}$delta.'),
          backgroundColor: delta >= 0 ? _C.green : _C.red,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Erro ao ajustar score: $e'),
          backgroundColor: _C.red,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ));
      }
    }
  }

  Future<void> _reativar(Map<String, dynamic> user) async {
    final uid  = user['id'] as String;
    final nome = user['nome'] as String? ?? user['email'] as String? ?? uid;

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: _C.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Reactivar $nome?',
          style: const TextStyle(color: _C.white, fontSize: 16, fontWeight: FontWeight.w700)),
        // ── CORRIGIDO: string com quebra de linha real dentro de aspas
        // simples não compila em Dart. Usa '\n' explícito.
        content: const Text(
          'A conta será reactivada com 60 pontos de Trust Score (estado "Aviso").\nO utilizador poderá voltar a interagir com a plataforma.',
          style: TextStyle(color: _C.grey2, fontSize: 13, height: 1.5)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar', style: TextStyle(color: _C.grey2)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: _C.green,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Reactivar', style: TextStyle(color: _C.white, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );

    if (ok != true || !mounted) return;
    await TrustService.instance.reporNivel(uid: uid, adminUid: _adminUid);
    await _carregar();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Conta de $nome reactivada com 60 pontos.'),
        backgroundColor: _C.green,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ));
    }
  }

  Color _corScore(int score) {
    if (score <= 0)  return _C.red;
    if (score <= 29) return _C.orange;
    if (score <= 59) return _C.orange;
    return _C.green;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator(color: _C.accent));

    final filtrados = _filtrados;
    const estados   = ['', 'Normal', 'Aviso', 'Risco', 'Suspenso'];

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Trust Scores',
                      style: TextStyle(color: _C.white, fontSize: 20, fontWeight: FontWeight.w800)),
                    Text('${_users.length} utilizadores · ordenados por score crescente',
                      style: const TextStyle(color: _C.grey3, fontSize: 12)),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.refresh_rounded, color: _C.grey2),
                onPressed: _carregar,
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Filtros de estado (chips horizontais)
          SizedBox(
            height: 34,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: estados.map((e) {
                final active = _filtroEstado == e;
                final label  = e.isEmpty ? 'Todos' : e;
                return GestureDetector(
                  onTap: () => setState(() => _filtroEstado = e),
                  child: Container(
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: active ? _C.accent : _C.card,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: active ? _C.accent : _C.border),
                    ),
                    child: Text(label,
                      style: TextStyle(
                        color: active ? _C.white : _C.grey2,
                        fontSize: 12,
                        fontWeight: active ? FontWeight.w700 : FontWeight.w400,
                      )),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 14),

          if (filtrados.isEmpty)
            const Expanded(
              child: Center(
                child: Text('Nenhum utilizador encontrado.',
                  style: TextStyle(color: _C.grey3, fontSize: 14)),
              ),
            )
          else
            Expanded(
              child: ListView.builder(
                itemCount: filtrados.length,
                itemBuilder: (_, i) {
                  final u      = filtrados[i];
                  final score  = (u['trustScore'] as int?) ?? 100;
                  final estado = TrustService.estadoDeScore(score);
                  final isSusp = ((u['isSuspended'] as bool?) ?? false) || score <= 0;

                  return Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: _C.card,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: isSusp ? _C.red.withValues(alpha: 0.4) : _C.border,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 40, height: 40,
                              decoration: BoxDecoration(
                                color: isSusp ? _C.redSoft : _C.accentSoft,
                                shape: BoxShape.circle,
                              ),
                              child: Center(
                                child: Text(
                                  ((u['nome'] as String? ?? u['email'] as String? ?? 'U'))[0].toUpperCase(),
                                  style: TextStyle(
                                    color: isSusp ? _C.red : _C.accent,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    u['nome'] as String? ?? u['email'] as String? ?? '—',
                                    style: const TextStyle(color: _C.white, fontWeight: FontWeight.w600, fontSize: 14),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  Text(
                                    u['email'] as String? ?? '—',
                                    style: const TextStyle(color: _C.grey3, fontSize: 11),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                            _EstadoBadge(estado: estado),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Text('$score/100',
                              style: TextStyle(
                                color: _corScore(score),
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              )),
                            const SizedBox(width: 10),
                            Expanded(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: LinearProgressIndicator(
                                  value: score / 100,
                                  backgroundColor: _C.border,
                                  color: _corScore(score),
                                  minHeight: 6,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            _SmallBtn(
                              icon: Icons.history_rounded,
                              label: 'Histórico',
                              color: _C.accent,
                              colorSoft: _C.accentSoft,
                              onTap: () => _verHistorico(u),
                            ),
                            const SizedBox(width: 8),
                            _SmallBtn(
                              icon: Icons.tune_rounded,
                              label: 'Ajustar',
                              color: _C.orange,
                              colorSoft: _C.orangeSoft,
                              onTap: () => _ajustarScore(u),
                            ),
                            if (isSusp) ...[
                              const SizedBox(width: 8),
                              _SmallBtn(
                                icon: Icons.lock_open_rounded,
                                label: 'Reactivar',
                                color: _C.green,
                                colorSoft: _C.greenSoft,
                                onTap: () => _reativar(u),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 3. PAINEL DE SUPORTE — pedidos de reactivação dos utilizadores suspensos
// ─────────────────────────────────────────────────────────────────────────────
class AdminSuportePanel extends StatefulWidget {
  const AdminSuportePanel({super.key});

  @override
  State<AdminSuportePanel> createState() => _AdminSuportePanelState();
}

class _AdminSuportePanelState extends State<AdminSuportePanel> {
  final _db       = FirebaseFirestore.instance;
  final _adminUid = FirebaseAuth.instance.currentUser?.uid ?? '';

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Cabeçalho
          StreamBuilder<QuerySnapshot>(
            stream: _db.collection('suporte_suspensao')
                .where('status', isEqualTo: 'pendente')
                .snapshots(),
            builder: (_, snap) {
              final count = snap.data?.docs.length ?? 0;
              return Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Pedidos de Suporte',
                          style: TextStyle(color: _C.white, fontSize: 20, fontWeight: FontWeight.w800)),
                        Text('$count pedido(s) pendente(s)',
                          style: const TextStyle(color: _C.grey3, fontSize: 12)),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 16),

          // Lista de pedidos
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _db.collection('suporte_suspensao')
                  .orderBy('criadoEm', descending: true)
                  .snapshots(),
              builder: (_, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator(color: _C.accent));
                }

                final docs = snap.data?.docs ?? [];
                if (docs.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 70, height: 70,
                          decoration: const BoxDecoration(color: _C.greenSoft, shape: BoxShape.circle),
                          child: const Icon(Icons.support_agent_rounded, color: _C.green, size: 34),
                        ),
                        const SizedBox(height: 14),
                        const Text('Nenhum pedido de suporte.',
                          style: TextStyle(color: _C.white, fontSize: 16, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 4),
                        const Text('Tudo em dia!',
                          style: TextStyle(color: _C.grey3, fontSize: 13)),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  itemCount: docs.length,
                  itemBuilder: (_, i) => _PedidoSuporteCard(
                    doc: docs[i],
                    adminUid: _adminUid,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _PedidoSuporteCard extends StatefulWidget {
  final DocumentSnapshot doc;
  final String adminUid;
  const _PedidoSuporteCard({required this.doc, required this.adminUid});
  @override
  State<_PedidoSuporteCard> createState() => _PedidoSuporteCardState();
}

class _PedidoSuporteCardState extends State<_PedidoSuporteCard> {
  bool _expanded = false;
  bool _loading  = false;

  Map<String, dynamic> get d => widget.doc.data() as Map<String, dynamic>;

  String _formatTs(dynamic raw) {
    if (raw == null) return '—';
    final dt = raw is Timestamp ? raw.toDate() : DateTime.tryParse(raw.toString());
    if (dt == null) return '—';
    return '${dt.day.toString().padLeft(2,'0')}/${dt.month.toString().padLeft(2,'0')}/${dt.year} às ${dt.hour.toString().padLeft(2,'0')}:${dt.minute.toString().padLeft(2,'0')}';
  }

  Future<void> _reativar() async {
    final uid  = d['uid']  as String? ?? '';
    final nome = d['nome'] as String? ?? d['email'] as String? ?? uid;
    if (uid.isEmpty) return;

    setState(() => _loading = true);
    try {
      await TrustService.instance.reporNivel(uid: uid, adminUid: widget.adminUid);

      // Marca o pedido como resolvido
      await FirebaseFirestore.instance
          .collection('suporte_suspensao')
          .doc(widget.doc.id)
          .update({
        'status':      'resolvido',
        'resolvidoPor': widget.adminUid,
        'resolvidoEm':  Timestamp.now(),
        'accao':        'reativacao',
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Conta de $nome reactivada com 60 pontos.'),
          backgroundColor: _C.green,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Erro: $e'), backgroundColor: _C.red,
          behavior: SnackBarBehavior.floating,
        ));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _manterSuspensao() async {
    await FirebaseFirestore.instance
        .collection('suporte_suspensao')
        .doc(widget.doc.id)
        .update({
      'status':      'resolvido',
      'resolvidoPor': widget.adminUid,
      'resolvidoEm':  Timestamp.now(),
      'accao':        'suspensao_mantida',
    });
  }

  // NOVO: busca o documento actual do utilizador (não o snapshot do
  // pedido, que só tem os campos guardados no momento da criação) e abre
  // o mesmo _HistoricoCompletoDialog usado no painel Trust Scores.
  Future<void> _verHistoricoCompleto() async {
    final uid = d['uid'] as String? ?? '';
    if (uid.isEmpty) return;
    try {
      final snap = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      if (!mounted) return;
      if (!snap.exists) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Utilizador não encontrado (pode ter sido removido).'),
          backgroundColor: _C.red, behavior: SnackBarBehavior.floating,
        ));
        return;
      }
      final userData = <String, dynamic>{'id': uid, ...snap.data()!};
      showDialog(
        context: context,
        builder: (_) => _HistoricoCompletoDialog(
          uid: uid,
          nome: userData['nome'] as String? ?? userData['email'] as String? ?? uid,
          userData: userData,
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Erro ao carregar histórico: $e'),
          backgroundColor: _C.red, behavior: SnackBarBehavior.floating,
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final nome    = d['nome']             as String? ?? d['email'] as String? ?? '—';
    final email   = d['email']            as String? ?? '—';
    final score   = (d['trustScore']      as int?)    ?? 0;
    final motivo  = d['suspensionReason'] as String? ?? '—';
    final data    = _formatTs(d['criadoEm']);
    final status  = d['status']           as String? ?? 'pendente';
    final historico = (d['historico']     as List?)   ?? [];
    final isPendente = status == 'pendente';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: _C.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isPendente ? _C.orange.withValues(alpha: 0.4) : _C.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Container(
                  width: 44, height: 44,
                  decoration: BoxDecoration(
                    color: isPendente ? _C.orangeSoft : _C.border,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    isPendente ? Icons.pending_rounded : Icons.check_circle_rounded,
                    color: isPendente ? _C.orange : _C.grey3,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(nome,
                        style: const TextStyle(color: _C.white, fontWeight: FontWeight.w700, fontSize: 15)),
                      Text(email,
                        style: const TextStyle(color: _C.grey3, fontSize: 11),
                        overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
                // Badge pendente/resolvido
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: isPendente ? _C.orangeSoft : _C.greenSoft,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    isPendente ? 'PENDENTE' : 'RESOLVIDO',
                    style: TextStyle(
                      color: isPendente ? _C.orange : _C.green,
                      fontSize: 9, fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Score + motivo + data
            _InfoRow(Icons.shield_rounded,      'Trust Score', '$score/100', _C.red),
            _InfoRow(Icons.info_outline_rounded, 'Motivo',      motivo,      _C.orange),
            _InfoRow(Icons.calendar_today_rounded,'Pedido em',  data,        _C.grey2),

            // NOVO: antes só se via o histórico do chat — que mostra o que
            // o utilizador DISSE, não o que ele FEZ. Este botão liga
            // directamente ao histórico real de actividade (casos,
            // comentários, penalizações), já construído no painel Trust
            // Scores mas até agora sem qualquer ligação a partir daqui.
            const SizedBox(height: 10),
            GestureDetector(
              onTap: _verHistoricoCompleto,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: _C.accentSoft,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: _C.accent.withValues(alpha: 0.3)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.history_rounded, size: 15, color: _C.accent),
                    SizedBox(width: 8),
                    Text('Ver histórico completo de actividade',
                      style: TextStyle(color: _C.accent, fontSize: 12, fontWeight: FontWeight.w600)),
                    Spacer(),
                    Icon(Icons.arrow_forward_ios_rounded, size: 11, color: _C.accent),
                  ],
                ),
              ),
            ),

            // Expandir histórico do chat
            const SizedBox(height: 10),
            GestureDetector(
              onTap: () => setState(() => _expanded = !_expanded),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: _C.surface,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: _C.border),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.chat_bubble_outline_rounded, size: 14, color: _C.grey2),
                    const SizedBox(width: 8),
                    Text('Histórico do chat (${historico.length} mensagens)',
                      style: const TextStyle(color: _C.grey2, fontSize: 12)),
                    const Spacer(),
                    Icon(_expanded ? Icons.expand_less : Icons.expand_more,
                      color: _C.grey3, size: 18),
                  ],
                ),
              ),
            ),

            if (_expanded) ...[
              const SizedBox(height: 8),
              Container(
                constraints: const BoxConstraints(maxHeight: 280),
                decoration: BoxDecoration(
                  color: _C.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _C.border),
                ),
                child: ListView.builder(
                  shrinkWrap: true,
                  padding: const EdgeInsets.all(12),
                  itemCount: historico.length,
                  itemBuilder: (_, i) {
                    final m      = historico[i] as Map;
                    final isUser = m['isUser'] as bool? ?? false;
                    final texto  = m['texto']  as String? ?? '';
                    final hora   = m['hora']   as String? ?? '';
                    final dt     = DateTime.tryParse(hora);
                    final ts     = dt != null
                        ? '${dt.hour.toString().padLeft(2,'0')}:${dt.minute.toString().padLeft(2,'0')}'
                        : '';

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Row(
                        mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          if (!isUser)
                            Container(
                              width: 24, height: 24,
                              decoration: const BoxDecoration(color: _C.accentSoft, shape: BoxShape.circle),
                              child: const Icon(Icons.support_agent_rounded, color: _C.accent, size: 12),
                            ),
                          if (!isUser) const SizedBox(width: 6),
                          Flexible(
                            child: Column(
                              crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: isUser ? _C.accent : _C.card,
                                    borderRadius: BorderRadius.circular(10),
                                    border: isUser ? null : Border.all(color: _C.border),
                                  ),
                                  child: Text(texto,
                                    style: TextStyle(
                                      color: isUser ? _C.white : _C.grey1,
                                      fontSize: 12, height: 1.4,
                                    )),
                                ),
                                if (ts.isNotEmpty)
                                  Text(ts, style: const TextStyle(color: _C.grey3, fontSize: 10)),
                              ],
                            ),
                          ),
                          if (isUser) const SizedBox(width: 6),
                          if (isUser)
                            Container(
                              width: 24, height: 24,
                              decoration: const BoxDecoration(color: _C.purpleSoft, shape: BoxShape.circle),
                              child: const Icon(Icons.person_rounded, color: _C.purple, size: 12),
                            ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],

            // Botões de acção (só para pedidos pendentes)
            if (isPendente) ...[
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _loading ? null : _manterSuspensao,
                      icon: const Icon(Icons.block_rounded, size: 15),
                      label: const Text('Manter suspensão'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _C.red,
                        side: const BorderSide(color: _C.red),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton.icon(
                      onPressed: _loading ? null : _reativar,
                      icon: _loading
                          ? const SizedBox(width: 14, height: 14,
                              child: CircularProgressIndicator(color: _C.white, strokeWidth: 2))
                          : const Icon(Icons.lock_open_rounded, size: 15),
                      label: const Text('Reactivar conta',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _C.green,
                        foregroundColor: _C.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        elevation: 0,
                      ),
                    ),
                  ),
                ],
              ),
            ],

            // Se resolvido, mostra quando e por quem
            if (!isPendente) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: _C.greenSoft,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: _C.green.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle_rounded, color: _C.green, size: 14),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Resolvido em ${_formatTs(d['resolvidoEm'])} · ${d['accao'] == 'reativacao' ? 'Conta reactivada' : 'Suspensão mantida'}',
                        style: const TextStyle(color: _C.green, fontSize: 11),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}


// ─────────────────────────────────────────────────────────────────────────────
// DIÁLOGOS AUXILIARES
// ─────────────────────────────────────────────────────────────────────────────

// _HistoricoCompletoDialog — histórico real de actividade do utilizador
// Carrega de forma assíncrona:
//   • Comentários feitos (casos/*/comentarios onde autorId == uid)
//   • Apoios dados (casos onde apoios array contém uid, ou stats.apoios)
//   • Casos criados (casos onde userId == uid)
//   • Penalizações de Trust Score (users/{uid}/trust_historico)
class _HistoricoCompletoDialog extends StatefulWidget {
  final String uid, nome;
  final Map<String, dynamic> userData;
  const _HistoricoCompletoDialog({required this.uid, required this.nome, required this.userData});
  @override
  State<_HistoricoCompletoDialog> createState() => _HistoricoCompletoDialogState();
}

class _HistoricoCompletoDialogState extends State<_HistoricoCompletoDialog>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;
  final _db = FirebaseFirestore.instance;

  // Dados por separador
  List<Map<String, dynamic>> _casos       = [];
  List<Map<String, dynamic>> _comentarios = [];
  List<Map<String, dynamic>> _penalizacoes = [];
  bool _loading = true;
  // CORRIGIDO: um erro por separador em vez de um único _erro global.
  // Antes, se a 1ª consulta falhasse (ex.: índice em falta), as outras
  // duas nunca chegavam a correr e o diálogo inteiro ficava em erro,
  // mesmo que os dados de "Penalizações" estivessem perfeitamente acessíveis.
  String? _erroCasos;
  String? _erroComentarios;
  String? _erroPenalizacoes;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    _carregar();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _carregar() async {
    setState(() {
      _loading = true;
      _erroCasos = null; _erroComentarios = null; _erroPenalizacoes = null;
    });

    // 1. Casos criados pelo utilizador
    // CORRIGIDO: a query estava a ordenar por 'criadoEm', mas os documentos
    // da colecção 'casos' guardam a data com o nome 'createdAt' (ver
    // create_caso_dialog.dart e o feed em home_page.dart, que já usa
    // 'createdAt' correctamente). O Firestore exclui automaticamente da
    // consulta qualquer documento que não tenha o campo usado no orderBy —
    // como NENHUM documento tem 'criadoEm', a consulta devolvia sempre
    // zero resultados, para qualquer utilizador, mesmo com casos aprovados
    // reais. O índice composto antigo (userId + criadoEm) nunca vai ser
    // utilizado agora — pode apagá-lo na consola e criar um novo com
    // userId + createdAt.
    try {
      final casosSnap = await _db.collection('casos')
          .where('userId', isEqualTo: widget.uid)
          .orderBy('createdAt', descending: true)
          .limit(50)
          .get();
      _casos = casosSnap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
    } catch (e) {
      _erroCasos = e.toString();
    }

    // 2. Comentários feitos em todos os casos (collectionGroup)
    // ATENÇÃO: collectionGroup + where + orderBy exige índice composto
    // com scope "Collection group" (não "Collection") — erro comum.
    try {
      final todosComsSnap = await _db.collectionGroup('comentarios')
          .where('autorId', isEqualTo: widget.uid)
          .orderBy('criadoEm', descending: true)
          .limit(100)
          .get();
      _comentarios = todosComsSnap.docs.map((d) {
        // Extrair casoId do path: casos/{casoId}/comentarios/{comId}
        final parts  = d.reference.path.split('/');
        final casoId = parts.length >= 2 ? parts[1] : '—';
        return {'id': d.id, 'casoId': casoId, ...d.data()};
      }).toList();
    } catch (e) {
      _erroComentarios = e.toString();
    }

    // 3. Penalizações e reactivações do TrustService
    // Apenas orderBy num único campo — não exige índice composto.
    try {
      final trustSnap = await _db
          .collection('users').doc(widget.uid)
          .collection('trust_historico')
          .orderBy('criadoEm', descending: true)
          .limit(50)
          .get();
      _penalizacoes = trustSnap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
    } catch (e) {
      _erroPenalizacoes = e.toString();
    }

    if (mounted) setState(() => _loading = false);
  }

  String _fmt(dynamic raw) {
    if (raw == null) return '—';
    final dt = raw is Timestamp ? raw.toDate() : DateTime.tryParse(raw.toString());
    if (dt == null) return '—';
    return '${dt.day.toString().padLeft(2,'0')}/${dt.month.toString().padLeft(2,'0')}/${dt.year} ${dt.hour.toString().padLeft(2,'0')}:${dt.minute.toString().padLeft(2,'0')}';
  }

  Color _statusColor(String? s) {
    switch (s) {
      case 'aprovado':   return _C.accent;
      case 'encontrado': return _C.green;
      case 'desmentido': return _C.orange;
      case 'rejeitado':  return _C.red;
      default:           return _C.grey3;
    }
  }

  @override
  Widget build(BuildContext context) {
    final score    = (widget.userData['trustScore'] as int?) ?? 100;
    final isSusp   = (widget.userData['isSuspended'] as bool?) ?? false;
    final stats    = widget.userData['stats'] as Map<String, dynamic>? ?? {};
    final apoios   = (stats['apoios']      as int?) ?? 0;
    final partilhas= (stats['partilhas']   as int?) ?? 0;

    return Dialog(
      backgroundColor: _C.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: _C.border),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 32),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460, maxHeight: 680),
        child: Column(
          children: [
            // ── Cabeçalho ────────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 8, 0),
              child: Row(
                children: [
                  Container(
                    width: 38, height: 38,
                    decoration: BoxDecoration(
                      color: isSusp ? _C.redSoft : _C.accentSoft,
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        widget.nome.isNotEmpty ? widget.nome[0].toUpperCase() : '?',
                        style: TextStyle(
                          color: isSusp ? _C.red : _C.accent,
                          fontWeight: FontWeight.bold, fontSize: 16,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(widget.nome,
                          style: const TextStyle(color: _C.white, fontSize: 15, fontWeight: FontWeight.w700),
                          overflow: TextOverflow.ellipsis),
                        Text('Trust Score: $score/100  ·  ${isSusp ? "SUSPENSO" : "Activo"}',
                          style: TextStyle(
                            color: isSusp ? _C.red : score <= 59 ? _C.orange : _C.green,
                            fontSize: 11, fontWeight: FontWeight.w600,
                          )),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: _C.grey2),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),

            // ── Mini-stats rápidas ────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: Row(
                children: [
                  _MiniStat('Casos', _casos.length.toString(),   Icons.search_rounded,          _C.accent),
                  const SizedBox(width: 8),
                  _MiniStat('Comentários', _comentarios.length.toString(), Icons.mode_comment_rounded, _C.purple),
                  const SizedBox(width: 8),
                  _MiniStat('Apoios', apoios.toString(),          Icons.favorite_rounded,        _C.red),
                  const SizedBox(width: 8),
                  _MiniStat('Partilhas', partilhas.toString(),    Icons.send_rounded,            _C.green),
                ],
              ),
            ),

            const SizedBox(height: 10),
            const Divider(color: _C.border, height: 1),

            // ── Tabs ─────────────────────────────────────────────────────────
            TabBar(
              controller: _tabs,
              labelColor: _C.accent,
              unselectedLabelColor: _C.grey3,
              indicatorColor: _C.accent,
              labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
              tabs: [
                Tab(text: 'Casos (${_casos.length})'),
                Tab(text: 'Comentários (${_comentarios.length})'),
                Tab(text: 'Penalizações (${_penalizacoes.length})'),
              ],
            ),
            const Divider(color: _C.border, height: 1),

            // ── Conteúdo das tabs ─────────────────────────────────────────────
            Expanded(
              child: _loading
                ? const Center(child: CircularProgressIndicator(color: _C.accent))
                : TabBarView(
                      controller: _tabs,
                      children: [
                        // Tab 0 — Casos
                        _erroCasos != null
                          ? _errorTab(_erroCasos!)
                          : _casos.isEmpty
                          ? _emptyTab('Nenhum caso reportado ainda.')
                          : ListView.builder(
                              padding: const EdgeInsets.all(12),
                              itemCount: _casos.length,
                              itemBuilder: (_, i) {
                                final c      = _casos[i];
                                final status = c['status'] as String? ?? '—';
                                final nome   = c['nome']   as String? ?? 'Sem nome';
                                final prov   = c['provincia'] as String? ?? '—';
                                final dt     = _fmt(c['createdAt']);
                                final cor    = _statusColor(status);
                                return Container(
                                  margin: const EdgeInsets.only(bottom: 8),
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: _C.surface,
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(color: _C.border),
                                  ),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 36, height: 36,
                                        decoration: BoxDecoration(
                                          color: cor.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
                                        child: Icon(Icons.person_search_rounded, color: cor, size: 18),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(nome, style: const TextStyle(color: _C.white, fontSize: 13, fontWeight: FontWeight.w600)),
                                            Text('$prov  ·  $dt', style: const TextStyle(color: _C.grey3, fontSize: 11)),
                                          ],
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: cor.withValues(alpha: 0.12),
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Text(status.toUpperCase(),
                                          style: TextStyle(color: cor, fontSize: 9, fontWeight: FontWeight.w800)),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),

                        // Tab 1 — Comentários
                        _erroComentarios != null
                          ? _errorTab(_erroComentarios!)
                          : _comentarios.isEmpty
                          ? _emptyTab('Nenhum comentário feito ainda.')
                          : ListView.builder(
                              padding: const EdgeInsets.all(12),
                              itemCount: _comentarios.length,
                              itemBuilder: (_, i) {
                                final c     = _comentarios[i];
                                final texto = c['texto']   as String? ?? '—';
                                final dt    = _fmt(c['criadoEm']);
                                final casoId= c['casoId']  as String? ?? '—';
                                return Container(
                                  margin: const EdgeInsets.only(bottom: 8),
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: _C.surface,
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(color: _C.border),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          const Icon(Icons.mode_comment_rounded, color: _C.purple, size: 13),
                                          const SizedBox(width: 6),
                                          Expanded(
                                            child: Text('Caso: $casoId',
                                              style: const TextStyle(color: _C.grey3, fontSize: 11),
                                              overflow: TextOverflow.ellipsis),
                                          ),
                                          Text(dt, style: const TextStyle(color: _C.grey3, fontSize: 10)),
                                        ],
                                      ),
                                      const SizedBox(height: 6),
                                      Text(texto,
                                        style: const TextStyle(color: _C.grey1, fontSize: 12, height: 1.4),
                                        maxLines: 3, overflow: TextOverflow.ellipsis),
                                    ],
                                  ),
                                );
                              },
                            ),

                        // Tab 2 — Penalizações Trust Score
                        _erroPenalizacoes != null
                          ? _errorTab(_erroPenalizacoes!)
                          : _penalizacoes.isEmpty
                          ? _emptyTab('Nenhuma penalização ou ajuste registado.')
                          : ListView.builder(
                              padding: const EdgeInsets.all(12),
                              itemCount: _penalizacoes.length,
                              itemBuilder: (_, i) {
                                final h      = _penalizacoes[i];
                                final pontos = (h['pontos'] as int?) ?? 0;
                                final motivo = h['motivo']  as String? ?? '—';
                                final prev   = (h['scorePrev'] as int?) ?? 0;
                                final novo   = (h['scoreNovo'] as int?) ?? 0;
                                final dt     = _fmt(h['criadoEm']);
                                final detalhe= h['detalhe'] as String? ?? '';
                                final cor    = pontos > 0 ? _C.green : pontos < 0 ? _C.red : _C.grey3;
                                return Container(
                                  margin: const EdgeInsets.only(bottom: 8),
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: _C.surface,
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(color: _C.border),
                                  ),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 40, height: 40,
                                        decoration: BoxDecoration(
                                          color: cor.withValues(alpha: 0.12), shape: BoxShape.circle),
                                        child: Center(
                                          child: Text(
                                            pontos >= 0 ? '+$pontos' : '$pontos',
                                            style: TextStyle(color: cor, fontSize: 12, fontWeight: FontWeight.w800),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(motivo, style: const TextStyle(color: _C.white, fontSize: 12, fontWeight: FontWeight.w600)),
                                            Text('$prev → $novo pts  ·  $dt',
                                              style: const TextStyle(color: _C.grey3, fontSize: 10)),
                                            if (detalhe.isNotEmpty)
                                              Text(detalhe,
                                                style: const TextStyle(color: _C.grey3, fontSize: 10),
                                                maxLines: 2, overflow: TextOverflow.ellipsis),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptyTab(String msg) => Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.inbox_rounded, color: _C.grey4, size: 40),
        const SizedBox(height: 10),
        Text(msg, style: const TextStyle(color: _C.grey3, fontSize: 13)),
      ],
    ),
  );

  // NOVO: erro isolado por separador, com botão para tentar novamente
  // sem perder os dados que já carregaram com sucesso nos outros separadores.
  Widget _errorTab(String msg) => Center(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline_rounded, color: _C.orange, size: 32),
          const SizedBox(height: 10),
          const Text('Erro ao carregar estes dados.',
            style: TextStyle(color: _C.white, fontWeight: FontWeight.w600, fontSize: 13)),
          const SizedBox(height: 6),
          Text(msg, style: const TextStyle(color: _C.grey3, fontSize: 11), textAlign: TextAlign.center),
          const SizedBox(height: 12),
          TextButton.icon(
            onPressed: _carregar,
            icon: const Icon(Icons.refresh_rounded, size: 14),
            label: const Text('Tentar novamente'),
            style: TextButton.styleFrom(foregroundColor: _C.accent),
          ),
        ],
      ),
    ),
  );
}

class _MiniStat extends StatelessWidget {
  final String label, valor;
  final IconData icon;
  final Color color;
  const _MiniStat(this.label, this.valor, this.icon, this.color);
  @override
  Widget build(BuildContext context) => Expanded(
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: _C.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _C.border),
      ),
      child: Column(children: [
        Icon(icon, color: color, size: 14),
        const SizedBox(height: 4),
        Text(valor, style: TextStyle(color: color, fontSize: 14, fontWeight: FontWeight.w800)),
        Text(label, style: const TextStyle(color: _C.grey3, fontSize: 9), textAlign: TextAlign.center),
      ]),
    ),
  );
}
// Diálogo de ajuste manual de score
class _AjustarScoreDialog extends StatefulWidget {
  final String nome;
  final int scoreActual;
  const _AjustarScoreDialog({required this.nome, required this.scoreActual});
  @override
  State<_AjustarScoreDialog> createState() => _AjustarScoreDialogState();
}

class _AjustarScoreDialogState extends State<_AjustarScoreDialog> {
  double _sliderVal = 0.0;
  String _motivo    = 'ajuste_manual';
  late TextEditingController _motivoCtrl;

  int get _delta => _sliderVal.round();

  @override
  void initState() {
    super.initState();
    _motivoCtrl = TextEditingController(text: _motivo);
    _motivoCtrl.addListener(() {
      if (mounted) setState(() => _motivo = _motivoCtrl.text);
    });
  }

  @override
  void dispose() {
    _motivoCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final preview = (widget.scoreActual + _delta).clamp(0, 100);
    return AlertDialog(
      backgroundColor: _C.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text('Ajustar score — ${widget.nome}',
        style: const TextStyle(color: _C.white, fontSize: 15, fontWeight: FontWeight.w700)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Score actual → preview
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('${widget.scoreActual}',
                style: const TextStyle(color: _C.grey2, fontSize: 22, fontWeight: FontWeight.w800)),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: Icon(Icons.arrow_forward_rounded, color: _C.grey3, size: 18),
              ),
              Text('$preview',
                style: TextStyle(
                  color: preview <= 0 ? _C.red : preview <= 29 ? _C.orange : _C.green,
                  fontSize: 28, fontWeight: FontWeight.w800,
                )),
            ],
          ),
          const SizedBox(height: 16),

          // Slider de -50 a +50, passos de 5
          Slider(
            value: _sliderVal,
            min: -50, max: 50,
            divisions: 20,
            activeColor: _delta < 0 ? _C.red : _delta > 0 ? _C.green : _C.grey3,
            inactiveColor: _C.border,
            label: _delta == 0 ? '0' : _delta > 0 ? '+$_delta' : '$_delta',
            onChanged: (v) => setState(() => _sliderVal = v),
          ),
          Text(
            _delta == 0
              ? 'Mova o slider para ajustar'
              : _delta > 0
                ? '+$_delta pontos  (${widget.scoreActual} → $preview)'
                : '$_delta pontos  (${widget.scoreActual} → $preview)',
            style: TextStyle(
              color: _delta < 0 ? _C.red : _delta > 0 ? _C.green : _C.grey3,
              fontSize: 12, fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 14),

          // Motivo
          TextField(
            controller: _motivoCtrl,
            style: const TextStyle(color: _C.white, fontSize: 13),
            decoration: InputDecoration(
              labelText: 'Motivo',
              labelStyle: const TextStyle(color: _C.grey3, fontSize: 12),
              filled: true,
              fillColor: _C.surface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: _C.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: _C.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: _C.accent),
              ),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, null),
          child: const Text('Cancelar', style: TextStyle(color: _C.grey2)),
        ),
        ElevatedButton(
          onPressed: _delta == 0
              ? null
              : () => Navigator.pop(context, {
                  'delta':  _delta,
                  'motivo': _motivo.trim().isEmpty ? 'ajuste_manual' : _motivo.trim(),
                }),
          style: ElevatedButton.styleFrom(
            backgroundColor: _delta < 0 ? _C.red : _C.green,
            disabledBackgroundColor: _C.grey4,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          child: Text(
            _delta == 0
              ? 'Aplicar'
              : _delta > 0
                ? 'Adicionar +$_delta pts'
                : 'Remover ${_delta.abs()} pts',
            style: const TextStyle(color: _C.white, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}


// ─────────────────────────────────────────────────────────────────────────────
// WIDGETS AUXILIARES REUTILIZÁVEIS
// ─────────────────────────────────────────────────────────────────────────────

class _SearchField extends StatelessWidget {
  final String hint;
  final void Function(String) onChanged;
  const _SearchField({required this.hint, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 42,
      decoration: BoxDecoration(
        color: _C.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _C.border),
      ),
      child: Row(
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 12),
            child: Icon(Icons.search_rounded, color: _C.grey3, size: 18),
          ),
          Expanded(
            child: TextField(
              style: const TextStyle(color: _C.grey1, fontSize: 14),
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: const TextStyle(color: _C.grey3, fontSize: 14),
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}

class _SmallBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color, colorSoft;
  final VoidCallback onTap;
  const _SmallBtn({
    required this.icon, required this.label,
    required this.color, required this.colorSoft,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: colorSoft,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 13),
            const SizedBox(width: 5),
            Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

class _EstadoBadge extends StatelessWidget {
  final TrustEstado estado;
  const _EstadoBadge({required this.estado});

  Color get _cor {
    switch (estado) {
      case TrustEstado.normal:   return _C.green;
      case TrustEstado.aviso:    return _C.orange;
      case TrustEstado.risco:    return _C.orange;
      case TrustEstado.suspenso: return _C.red;
    }
  }

  Color get _corSoft {
    switch (estado) {
      case TrustEstado.normal:   return _C.greenSoft;
      case TrustEstado.aviso:    return _C.orangeSoft;
      case TrustEstado.risco:    return _C.orangeSoft;
      case TrustEstado.suspenso: return _C.redSoft;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: _corSoft,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _cor.withValues(alpha: 0.4)),
      ),
      child: Text(
        TrustService.labelEstado(estado).toUpperCase(),
        style: TextStyle(color: _cor, fontSize: 9, fontWeight: FontWeight.w800),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label, value;
  final Color color;
  const _InfoRow(this.icon, this.label, this.value, this.color);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 8),
          Text('$label: ', style: const TextStyle(color: _C.grey3, fontSize: 12)),
          Expanded(
            child: Text(value,
              style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }
}