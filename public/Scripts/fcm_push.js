// Scripts/fcm_push.js
//
// Envia notificações push (FCM) directamente do browser, assinando o
// JWT da conta de serviço com a Web Crypto API — o mesmo que o mobile
// faz com dart_jsonwebtoken, só que aqui em JavaScript puro.
//
// Se vires na consola "Failed to fetch" ou "blocked by CORS policy"
// nos pedidos para oauth2.googleapis.com ou fcm.googleapis.com, é
// exactamente a limitação que foi avisada: estes endpoints não
// costumam responder com cabeçalhos CORS para pedidos vindos de
// páginas web. Isso confirma que, para isto funcionar de forma fiável,
// vai ser preciso algum intermediário (mesmo que mínimo) a receber o
// pedido primeiro.

import { db } from "./firebase.js";
import {
  collection,
  getDocs,
  addDoc,
  doc,
  getDoc,
  Timestamp,
} from "https://www.gstatic.com/firebasejs/12.8.0/firebase-firestore.js";
import {
  FCM_CLIENT_EMAIL,
  FCM_PRIVATE_KEY,
  FIREBASE_PROJECT_ID,
} from "./fcm_config.js";

/* =========================================================================
   BASE64URL
   ========================================================================= */
function _b64urlFromBytes(bytes) {
  let binary = "";
  bytes.forEach((b) => (binary += String.fromCharCode(b)));
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}
function _b64urlFromString(str) {
  return _b64urlFromBytes(new TextEncoder().encode(str));
}

/* =========================================================================
   IMPORTAR A CHAVE PRIVADA PARA A WEB CRYPTO API
   ========================================================================= */
async function _importPrivateKey(pem) {
  // Aceita tanto "\n" literais (como vêm no JSON descarregado) como
  // quebras de linha reais (se colares o valor já formatado).
  const pemBody = pem
    .replace(/\\n/g, "\n")
    .replace("-----BEGIN PRIVATE KEY-----", "")
    .replace("-----END PRIVATE KEY-----", "")
    .replace(/\s+/g, "");

  const der = Uint8Array.from(atob(pemBody), (c) => c.charCodeAt(0));

  return crypto.subtle.importKey(
    "pkcs8",
    der.buffer,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
}

/* =========================================================================
   CONSTRUIR E ASSINAR O JWT (RS256)
   ========================================================================= */
async function _criarJwtAssinado() {
  const agora = Math.floor(Date.now() / 1000);
  const header = { alg: "RS256", typ: "JWT" };
  const claims = {
    iss: FCM_CLIENT_EMAIL,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: "https://oauth2.googleapis.com/token",
    iat: agora,
    exp: agora + 3600,
  };

  const semAssinar = `${_b64urlFromString(JSON.stringify(header))}.${_b64urlFromString(JSON.stringify(claims))}`;
  const chave = await _importPrivateKey(FCM_PRIVATE_KEY);
  const assinatura = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    chave,
    new TextEncoder().encode(semAssinar),
  );

  return `${semAssinar}.${_b64urlFromBytes(new Uint8Array(assinatura))}`;
}

/* =========================================================================
   TROCAR O JWT POR UM ACCESS TOKEN OAUTH2
   ========================================================================= */
async function _obterAccessToken() {
  const jwt = await _criarJwtAssinado();

  const resp = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: jwt,
    }),
  });

  if (!resp.ok) {
    throw new Error(`Falha a obter access token (${resp.status}): ${await resp.text()}`);
  }
  const data = await resp.json();
  return data.access_token;
}

/* =========================================================================
   ENVIAR UMA MENSAGEM FCM A UM ÚNICO TOKEN
   ========================================================================= */
async function _enviarParaToken(accessToken, token, title, body, data) {
  const resp = await fetch(
    `https://fcm.googleapis.com/v1/projects/${FIREBASE_PROJECT_ID}/messages:send`,
    {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${accessToken}`,
      },
      body: JSON.stringify({
        message: {
          token,
          notification: { title, body },
          data,
          android: {
            priority: "high",
            notification: {
              channel_id: "amber_alert_channel_v2",
              sound: "amber_alert",
              visibility: "public",
            },
          },
          apns: {
            payload: {
              aps: {
                sound: "amber_alert.aiff",
                badge: 1,
                "interruption-level": "critical",
              },
            },
          },
        },
      }),
    },
  );
  return resp.ok;
}

/* =========================================================================
   PONTO DE ENTRADA — mesma lógica de correspondência regional do mobile
   (notification_service.dart → enviarAlertaDesaparecido)
   ========================================================================= */
export async function enviarAlertaDesaparecidoWeb(casoData) {
  const municipioAlvo = (casoData.municipio || "").toLowerCase().trim();
  const provinciaAlvo = (casoData.provincia || "").toLowerCase().trim();

  const usersSnap = await getDocs(collection(db, "users"));
  const tokens = new Set();

  usersSnap.forEach((doc) => {
    const u = doc.data();
    const token = u.fcmToken;
    if (!token) return;

    if (doc.id === casoData.userId) {
      tokens.add(token);
      return;
    }

    let deveNotificar = false;
    const locActual = u.localizacaoActual || null;
    const uMunicipio = ((locActual && locActual.municipio) || u.municipio || "").toLowerCase().trim();
    const uProvincia = ((locActual && locActual.provincia) || u.provincia || "").toLowerCase().trim();

    if (municipioAlvo && uMunicipio) {
      deveNotificar = uMunicipio.includes(municipioAlvo) || municipioAlvo.includes(uMunicipio);
    } else if (provinciaAlvo && uProvincia) {
      deveNotificar = uProvincia.includes(provinciaAlvo) || provinciaAlvo.includes(uProvincia);
    } else if (!locActual && !u.municipio && !u.provincia) {
      deveNotificar = true; // sem localização conhecida — notifica por defeito
    }

    if (deveNotificar) tokens.add(token);
  });

  const title = `⚠️ ALERTA — ${casoData.nome || "Desconhecido"} desapareceu!`;
  const body = [
    casoData.ultimo_local ? `📍 ${casoData.ultimo_local}` : null,
    casoData.municipio ? `🏙️ ${casoData.municipio}, ${casoData.provincia || ""}` : null,
    casoData.idade ? `${casoData.idade} anos` : null,
    casoData.sexo || null,
    casoData.roupas ? `Vestia: ${casoData.roupas}` : null,
    casoData.informacoes_adicionais || null,
  ]
    .filter(Boolean)
    .join(" · ");

  const dataPayload = {
    casoId: casoData.id || "",
    tipo: "alerta_desaparecido",
    nome: casoData.nome || "",
    municipio: casoData.municipio || "",
  };

  const accessToken = await _obterAccessToken();

  let enviados = 0;
  for (const token of tokens) {
    try {
      const ok = await _enviarParaToken(accessToken, token, title, body, dataPayload);
      if (ok) enviados++;
    } catch (err) {
      console.warn("[Push FCM] Falha a enviar para um token:", err);
    }
  }

  await addDoc(collection(db, "alertas"), {
    casoId: casoData.id || "",
    nome: casoData.nome || "",
    provincia: casoData.provincia || "",
    municipio: casoData.municipio || "",
    ultimoLocal: casoData.ultimo_local || "",
    autorUserId: casoData.userId || "",
    criadoEm: Timestamp.now(),
    tokensEnviados: enviados,
    origem: "web-direct",
  });

  return { enviados, totalTokens: tokens.size };
}

/* =========================================================================
   NOVO — NOTIFICAR UM ÚNICO UTILIZADOR (usado para suspensão/reactivação
   de conta, ao contrário de enviarAlertaDesaparecidoWeb que notifica
   vários utilizadores de uma região). Mesma lógica do
   notification_service.dart do mobile (notificarSuspensao/notificarReactivacao).
   ========================================================================= */
export async function enviarPushParaUid(uid, title, body, data = {}) {
  try {
    const userSnap = await getDoc(doc(db, "users", uid));
    if (!userSnap.exists()) return false;
    const token = userSnap.data().fcmToken;
    if (!token) return false; // utilizador nunca abriu a app mobile — sem token, sem push

    const accessToken = await _obterAccessToken();
    return await _enviarParaToken(accessToken, token, title, body, data);
  } catch (err) {
    console.warn("[Push FCM] Falha ao enviar notificação individual:", err);
    return false;
  }
}