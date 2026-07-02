// lib/services/trust_service.dart
// ─────────────────────────────────────────────────────────────────────────────
// Serviço centralizado para gestão do Trust Score.
// Usa transações Firestore para garantir consistência.
//
// PENALIZAÇÕES PADRÃO:
//   comentario_removido   → −10
//   caso_desmentido       → −20
//   caso_rejeitado        → −15
//   comportamento_abusivo → −25
//
// ESTADOS:
//   100 – 60  → normal      (acesso total)
//    59 – 30  → aviso       (acesso total, mas com aviso visível)
//    29 –  1  → risco       (bloqueado de criar; pode comentar e apoiar)
//       0     → suspenso    (só chatbot; não pode interagir com nada)
// ─────────────────────────────────────────────────────────────────────────────

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'notification_service.dart'; // ← NOVO: notificar suspensão/reactivação

enum TrustEstado { normal, aviso, risco, suspenso }

class TrustService {
  TrustService._();
  static final TrustService instance = TrustService._();

  final _db = FirebaseFirestore.instance;

  // ── Determina o estado a partir do score numérico ─────────────────────────
  static TrustEstado estadoDeScore(int score) {
    if (score <= 0)  return TrustEstado.suspenso;
    if (score <= 29) return TrustEstado.risco;
    if (score <= 59) return TrustEstado.aviso;
    return TrustEstado.normal;
  }

  static String labelEstado(TrustEstado estado) {
    switch (estado) {
      case TrustEstado.normal:   return 'Normal';
      case TrustEstado.aviso:    return 'Aviso';
      case TrustEstado.risco:    return 'Risco';
      case TrustEstado.suspenso: return 'Suspenso';
    }
  }

  // ── Penalizar utilizador (decrementa score) ───────────────────────────────
  // Retorna o score resultante após a penalização.
  Future<int> penalizar({
    required String uid,
    required String motivo,       // ex: 'comentario_removido'
    required int pontos,          // valor positivo — será subtraído
    String? adminUid,
    String? detalhe,              // texto extra para o histórico
  }) async {
    assert(pontos > 0, 'pontos deve ser positivo');

    int novoScore = 0;
    bool passouASuspenso = false; // NOVO: só notifica na transição, não em cada penalização adicional

    await _db.runTransaction((tx) async {
      final ref  = _db.collection('users').doc(uid);
      final snap = await tx.get(ref);
      // CORRIGIDO: antes, se o documento não existisse, a transacção
      // terminava em silêncio (sem throw) e o chamador via "sucesso"
      // mesmo sem nenhuma escrita ter ocorrido.
      if (!snap.exists) {
        throw StateError('TrustService.penalizar: utilizador "$uid" não encontrado em users/$uid.');
      }

      final data        = snap.data()!;
      final scoreActual = (data['trustScore'] as int?) ?? 100;
      novoScore         = (scoreActual - pontos).clamp(0, 100);
      final suspenso    = novoScore <= 0;
      passouASuspenso   = scoreActual > 0 && suspenso;

      tx.update(ref, {
        'trustScore':        novoScore,
        'isSuspended':       suspenso,
        'suspendedAt':       suspenso ? Timestamp.now() : data['suspendedAt'],
        'suspensionReason':  suspenso ? motivo : (data['suspensionReason'] ?? ''),
      });

      // Regista no histórico de penalizações do utilizador
      final histRef = ref.collection('trust_historico').doc();
      tx.set(histRef, {
        'tipo':       'penalizacao',
        'motivo':     motivo,
        'pontos':     -pontos,
        'scorePrev':  scoreActual,
        'scoreNovo':  novoScore,
        'adminUid':   adminUid,
        'detalhe':    detalhe,
        'criadoEm':   Timestamp.now(),
      });
    });

    // NOVO: notifica só depois da transacção confirmar com sucesso, e só
    // na transição de activo → suspenso (não em cada penalização seguinte
    // a alguém que já estava suspenso).
    if (passouASuspenso) {
      NotificationService.instance.notificarSuspensao(uid: uid, motivo: motivo);
    }

    debugPrint('TrustService.penalizar → uid=$uid motivo=$motivo −$pontos → score=$novoScore');
    return novoScore;
  }

  // ── Repor nível do utilizador (acção do admin) ────────────────────────────
  Future<void> reporNivel({
    required String uid,
    required String adminUid,
    int scoreReposto = 60,        // repõe para "aviso" por defeito, não para 100
    String motivo = 'reactivacao_admin',
  }) async {
    final scoreSeguro = scoreReposto.clamp(1, 100);

    await _db.runTransaction((tx) async {
      final ref  = _db.collection('users').doc(uid);
      final snap = await tx.get(ref);
      if (!snap.exists) {
        throw StateError('TrustService.reporNivel: utilizador "$uid" não encontrado em users/$uid.');
      }

      final scorePrev = (snap.data()?['trustScore'] as int?) ?? 0;

      tx.update(ref, {
        'trustScore':       scoreSeguro,
        'isSuspended':      false,
        'suspendedAt':      null,
        'suspensionReason': '',
        'reativadoPor':     adminUid,
        'reativadoEm':      Timestamp.now(),
      });

      final histRef = ref.collection('trust_historico').doc();
      tx.set(histRef, {
        'tipo':      'reativacao',
        'motivo':    motivo,
        'pontos':    scoreSeguro - scorePrev,
        'scorePrev': scorePrev,
        'scoreNovo': scoreSeguro,
        'adminUid':  adminUid,
        'criadoEm':  Timestamp.now(),
      });
    });

    // NOVO: notifica sempre — reporNivel só é chamado para contas que
    // estavam suspensas, por isso não precisa da mesma guarda de transição
    // usada em penalizar().
    NotificationService.instance.notificarReactivacao(uid: uid, score: scoreSeguro);

    debugPrint('TrustService.reporNivel → uid=$uid score=$scoreReposto admin=$adminUid');
  }

  // ── Ajuste manual de score pelo admin (positivo ou negativo) ─────────────
  Future<void> ajustarScore({
    required String uid,
    required int delta,           // pode ser negativo ou positivo
    required String adminUid,
    String motivo = 'ajuste_manual',
  }) async {
    bool passouASuspenso = false; // NOVO

    await _db.runTransaction((tx) async {
      final ref  = _db.collection('users').doc(uid);
      final snap = await tx.get(ref);
      if (!snap.exists) {
        throw StateError('TrustService.ajustarScore: utilizador "$uid" não encontrado em users/$uid.');
      }

      final scorePrev = (snap.data()?['trustScore'] as int?) ?? 100;
      final novoScore = (scorePrev + delta).clamp(0, 100);
      final suspenso  = novoScore <= 0;
      passouASuspenso = scorePrev > 0 && suspenso;

      tx.update(ref, {
        'trustScore':       novoScore,
        'isSuspended':      suspenso,
        if (suspenso) 'suspendedAt': Timestamp.now(),
        if (suspenso) 'suspensionReason': motivo,
      });

      final histRef = ref.collection('trust_historico').doc();
      tx.set(histRef, {
        'tipo':      'ajuste_manual',
        'motivo':    motivo,
        'pontos':    delta,
        'scorePrev': scorePrev,
        'scoreNovo': novoScore,
        'adminUid':  adminUid,
        'criadoEm':  Timestamp.now(),
      });
    });

    // NOVO
    if (passouASuspenso) {
      NotificationService.instance.notificarSuspensao(uid: uid, motivo: motivo);
    }
  }

  // ── Buscar histórico de um utilizador ─────────────────────────────────────
  Future<List<Map<String, dynamic>>> historico(String uid) async {
    final snap = await _db
        .collection('users')
        .doc(uid)
        .collection('trust_historico')
        .orderBy('criadoEm', descending: true)
        .limit(50)
        .get();
    return snap.docs.map((d) => {'id': d.id, ...d.data()}).toList();
  }

  // ── Valores fixos de penalização ─────────────────────────────────────────
  static const int pComentarioRemovido   = 10;
  static const int pCasoDesmentido       = 20;
  static const int pCasoRejeitado        = 15;
  static const int pComportamentoAbusivo = 25;
}
