// Scripts/trust_service.js
// ─────────────────────────────────────────────────────────────────────────────
// Equivalente web do trust_service.dart do mobile. Usa transacções do
// Firestore para garantir consistência entre o documento do utilizador e o
// registo em trust_historico.
//
// Protegido do lado do servidor pelas Firestore Security Rules — escrever
// em users/{uid} (update) e em users/{uid}/trust_historico exige
// role == 'admin' no documento de quem está autenticado. O facto de este
// código correr no browser (visível a qualquer pessoa que inspeccione o
// JS) não é um problema de segurança: só protege quem já é admin, e essa
// verificação é feita no servidor, não aqui.
// ─────────────────────────────────────────────────────────────────────────────

import { db } from "./firebase.js";
import {
  doc,
  runTransaction,
  collection,
  Timestamp,
} from "https://www.gstatic.com/firebasejs/12.8.0/firebase-firestore.js";

// ── Estados, espelhando TrustEstado do mobile ─────────────────────────────
export function estadoDeScore(score) {
  if (score <= 0) return "suspenso";
  if (score <= 29) return "risco";
  if (score <= 59) return "aviso";
  return "normal";
}

export function labelEstado(estado) {
  switch (estado) {
    case "normal": return "Normal";
    case "aviso": return "Aviso";
    case "risco": return "Risco";
    case "suspenso": return "Suspenso";
    default: return "—";
  }
}

// ── Penalizar utilizador (decrementa score) ───────────────────────────────
// Retorna o score resultante. Lança excepção se o utilizador não existir
// ou se a escrita for recusada pelas regras (ex.: quem chama não é admin).
export async function penalizar({ uid, motivo, pontos, adminUid, detalhe }) {
  if (!(pontos > 0)) throw new Error("pontos deve ser positivo");

  let novoScore = 0;

  await runTransaction(db, async (tx) => {
    const ref = doc(db, "users", uid);
    const snap = await tx.get(ref);
    if (!snap.exists()) {
      throw new Error(`penalizar: utilizador "${uid}" não encontrado.`);
    }

    const data = snap.data();
    const scoreActual = typeof data.trustScore === "number" ? data.trustScore : 100;
    novoScore = Math.max(0, Math.min(100, scoreActual - pontos));
    const suspenso = novoScore <= 0;

    tx.update(ref, {
      trustScore: novoScore,
      isSuspended: suspenso,
      suspendedAt: suspenso ? Timestamp.now() : (data.suspendedAt ?? null),
      suspensionReason: suspenso ? motivo : (data.suspensionReason ?? ""),
    });

    const histRef = doc(collection(db, "users", uid, "trust_historico"));
    tx.set(histRef, {
      tipo: "penalizacao",
      motivo,
      pontos: -pontos,
      scorePrev: scoreActual,
      scoreNovo: novoScore,
      adminUid: adminUid ?? null,
      detalhe: detalhe ?? null,
      criadoEm: Timestamp.now(),
    });
  });

  return novoScore;
}

// ── Ajuste manual de score (positivo ou negativo) ─────────────────────────
export async function ajustarScore({ uid, delta, adminUid, motivo = "ajuste_manual" }) {
  await runTransaction(db, async (tx) => {
    const ref = doc(db, "users", uid);
    const snap = await tx.get(ref);
    if (!snap.exists()) {
      throw new Error(`ajustarScore: utilizador "${uid}" não encontrado.`);
    }

    const scorePrev = typeof snap.data().trustScore === "number" ? snap.data().trustScore : 100;
    const novoScore = Math.max(0, Math.min(100, scorePrev + delta));
    const suspenso = novoScore <= 0;

    const update = { trustScore: novoScore, isSuspended: suspenso };
    if (suspenso) {
      update.suspendedAt = Timestamp.now();
      update.suspensionReason = motivo;
    }
    tx.update(ref, update);

    const histRef = doc(collection(db, "users", uid, "trust_historico"));
    tx.set(histRef, {
      tipo: "ajuste_manual",
      motivo,
      pontos: delta,
      scorePrev,
      scoreNovo: novoScore,
      adminUid,
      criadoEm: Timestamp.now(),
    });
  });
}

// ── Repor nível (reactivação pelo admin) ──────────────────────────────────
export async function reporNivel({ uid, adminUid, scoreReposto = 60, motivo = "reactivacao_admin" }) {
  const scoreSeguro = Math.max(1, Math.min(100, scoreReposto));

  await runTransaction(db, async (tx) => {
    const ref = doc(db, "users", uid);
    const snap = await tx.get(ref);
    if (!snap.exists()) {
      throw new Error(`reporNivel: utilizador "${uid}" não encontrado.`);
    }
    const scorePrev = typeof snap.data().trustScore === "number" ? snap.data().trustScore : 0;

    tx.update(ref, {
      trustScore: scoreSeguro,
      isSuspended: false,
      suspendedAt: null,
      suspensionReason: "",
      reativadoPor: adminUid,
      reativadoEm: Timestamp.now(),
    });

    const histRef = doc(collection(db, "users", uid, "trust_historico"));
    tx.set(histRef, {
      tipo: "reativacao",
      motivo,
      pontos: scoreSeguro - scorePrev,
      scorePrev,
      scoreNovo: scoreSeguro,
      adminUid,
      criadoEm: Timestamp.now(),
    });
  });
}

// ── Valores fixos de penalização, espelhando o mobile ─────────────────────
export const P_COMENTARIO_REMOVIDO = 10;
export const P_CASO_DESMENTIDO = 20;
export const P_CASO_REJEITADO = 15;
export const P_COMPORTAMENTO_ABUSIVO = 25;