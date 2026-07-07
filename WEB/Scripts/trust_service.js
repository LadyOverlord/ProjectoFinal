// trust_service.js

import {
  doc, runTransaction, collection, orderBy, limit, query, getDocs,
  serverTimestamp, increment as firestoreIncrement,
} from "https://www.gstatic.com/firebasejs/12.8.0/firebase-firestore.js";
import { db } from "./firebase.js";
import { enviarEmailTrustStatus } from "./email_service.js";
// NOVO: push FCM ao suspender/reactivar, igual ao mobile
// (notification_service.dart → notificarSuspensao/notificarReactivacao).
import { enviarPushParaUid } from "./fcm_push.js";

const historicoRef = (uid) => collection(db, 'users', uid, 'trust_historico');

// NOVO: ponto único que dispara email + push sempre que uma conta muda
// de estado — evita repetir a mesma lógica em penalizar/reporNivel/
// ajustarScore. Falhas num canal não bloqueiam o outro nem a transação
// já concluída.
async function _notificarEstadoConta(uid, suspenso, motivoOuScore) {
  const titulo = suspenso ? '🚫 Conta Suspensa' : '✅ Conta Reactivada';
  const corpo = suspenso
    ? `A sua conta foi suspensa. Motivo: ${motivoOuScore || 'violação das diretrizes'}. Pode falar com o suporte a partir da app para pedir revisão.`
    : `A sua conta foi reactivada com ${motivoOuScore} pontos de Trust Score. Já pode voltar a usar a plataforma normalmente.`;

  try {
    await enviarEmailTrustStatus(uid, !suspenso, motivoOuScore);
  } catch (err) {
    console.warn('[trust_service] Falha ao enviar email de estado de conta:', err);
  }

  try {
    await enviarPushParaUid(uid, titulo, corpo, {
      tipo: 'status_conta',
      estado: suspenso ? 'suspensa' : 'reactivada',
    });
  } catch (err) {
    console.warn('[trust_service] Falha ao enviar push de estado de conta:', err);
  }
}

export async function penalizar(uid, pontos, motivo, adminUid, detalhe = '') {
  let passouASuspenso = false;

  await runTransaction(db, async (tx) => {
    const ref = doc(db, 'users', uid);
    const userDoc = await tx.get(ref);
    if (!userDoc.exists) throw new Error(`Usuário ${uid} não existe.`);

    const userData = userDoc.data();
    const scoreAtual = userData.trustScore ?? 100;
    const novoScore = Math.max(0, scoreAtual - pontos);
    const suspenso = novoScore <= 0;
    passouASuspenso = scoreAtual > 0 && suspenso;

    tx.update(ref, {
      trustScore: novoScore,
      isSuspended: suspenso,
      ...(suspenso && { suspendedAt: serverTimestamp(), suspensionReason: motivo }),
    });

    const histRef = doc(historicoRef(uid));
    tx.set(histRef, {
      tipo: 'penalizacao',
      motivo,
      pontos: -pontos,
      scorePrev: scoreAtual,
      scoreNovo: novoScore,
      adminUid,
      detalhe,
      criadoEm: serverTimestamp(),
    });
  });

  if (passouASuspenso) {
    await _notificarEstadoConta(uid, true, motivo);
  }
}

export async function reporNivel(uid, adminUid, scoreReposto = 60, motivo = 'reativacao_admin') {
  await runTransaction(db, async (tx) => {
    const ref = doc(db, 'users', uid);
    const userDoc = await tx.get(ref);
    if (!userDoc.exists) throw new Error(`Usuário ${uid} não existe.`);

    const scorePrev = userDoc.data().trustScore ?? 0;

    tx.update(ref, {
      trustScore: scoreReposto,
      isSuspended: false,
      suspendedAt: null,
      suspensionReason: '',
      reativadoPor: adminUid,
      reativadoEm: serverTimestamp(),
    });

    const histRef = doc(historicoRef(uid));
    tx.set(histRef, {
      tipo: 'reativacao',
      motivo,
      pontos: scoreReposto - scorePrev,
      scorePrev,
      scoreNovo: scoreReposto,
      adminUid,
      criadoEm: serverTimestamp(),
    });
  });

  await _notificarEstadoConta(uid, false, scoreReposto);
}

export async function ajustarScore(uid, delta, adminUid, motivo = 'ajuste_manual') {
  let passouASuspenso = false;

  await runTransaction(db, async (tx) => {
    const ref = doc(db, 'users', uid);
    const userDoc = await tx.get(ref);
    if (!userDoc.exists) throw new Error(`Usuário ${uid} não existe.`);

    const userData = userDoc.data();
    const scorePrev = userData.trustScore ?? 100;
    const novoScore = Math.min(100, Math.max(0, scorePrev + delta));
    const suspenso = novoScore <= 0;
    passouASuspenso = scorePrev > 0 && suspenso;

    tx.update(ref, {
      trustScore: novoScore,
      isSuspended: suspenso,
      ...(suspenso && { suspendedAt: serverTimestamp(), suspensionReason: motivo }),
    });

    const histRef = doc(historicoRef(uid));
    tx.set(histRef, {
      tipo: 'ajuste_manual',
      motivo,
      pontos: delta,
      scorePrev,
      scoreNovo: novoScore,
      adminUid,
      criadoEm: serverTimestamp(),
    });
  });

  if (passouASuspenso) {
    await _notificarEstadoConta(uid, true, motivo);
  }
}

export async function historico(uid) {
  const histRef = historicoRef(uid);
  const q = query(histRef, orderBy('criadoEm', 'desc'), limit(50));
  const snap = await getDocs(q);
  return snap.docs.map(doc => ({ id: doc.id, ...doc.data() }));
}

// CORRIGIDO: esta função devolvia 'suspended' | 'danger' | 'warning' | 'good'
// (nomes em inglês), mas o admin.css define as cores dos badges para as
// classes .normal / .aviso / .risco / .suspenso (nomes em português, os
// mesmos que o mobile usa no enum TrustEstado). Como as strings nunca
// batiam certo, os badges apareciam sem cor E os botões de filtro do
// painel Trust Scores (que comparam contra estes valores) nunca
// encontravam ninguém — excepto o filtro "Todos". Os limiares (0/29/59)
// também foram alinhados com os do mobile (TrustService.estadoDeScore).
export function estadoDeScore(score) {
  if (score <= 0) return 'suspenso';
  if (score <= 29) return 'risco';
  if (score <= 59) return 'aviso';
  return 'normal';
}

export function labelEstado(estado) {
  switch (estado) {
    case 'suspenso': return '🚫 Suspenso';
    case 'risco':    return '🔴 Risco';
    case 'aviso':    return '⚠ Aviso';
    default:         return '✅ Normal';
  }
}