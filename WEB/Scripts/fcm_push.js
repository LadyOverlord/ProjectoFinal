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

import { db, storage } from "./firebase.js";
import {
  collection,
  getDocs,
  addDoc,
  doc,
  getDoc,
  Timestamp,
} from "https://www.gstatic.com/firebasejs/12.8.0/firebase-firestore.js";
import {
  ref,
  uploadString,
  getDownloadURL,
} from "https://www.gstatic.com/firebasejs/12.8.0/firebase-storage.js";
import {
  FCM_CLIENT_EMAIL,
  FCM_PRIVATE_KEY,
  FIREBASE_PROJECT_ID,
} from "./fcm_config.js";

/* =========================================================================
   IMAGEM DA NOTIFICAÇÃO
   O FCM só consegue mostrar imagem numa notificação se ela estiver
   acessível por um URL público (http/https) — não aceita base64
   directamente. As fotos dos casos estão guardadas como base64 no
   Firestore, por isso fazemos aqui o upload para o Firebase Storage e
   usamos o link resultante. Ficam guardadas em alertas_push/{casoId}.jpg
   — reenviar o mesmo caso substitui o ficheiro, não acumula lixo.
   ========================================================================= */
async function _obterUrlImagem(casoId, imagemBase64) {
  if (!imagemBase64 || !imagemBase64.startsWith("data:image")) return null;
  try {
    const imgRef = ref(storage, `alertas_push/${casoId}.jpg`);

    // CORRIGIDO: se o bucket do Storage não tiver CORS configurado para
    // este origin (é o que os erros "blocked by CORS policy" na consola
    // significam), o SDK do Firebase tenta repetir o upload sozinho
    // durante bastante tempo (o valor por omissão é ~2 minutos) antes de
    // desistir. Isso fazia parecer que o push "não enviou", quando na
    // verdade estava só preso à espera da foto. Com Promise.race, damos
    // no máximo 5 segundos à foto — se não conseguir nesse tempo, a
    // notificação segue sem foto e sem atrasar mais nada.
    const comLimiteDeTempo = Promise.race([
      uploadString(imgRef, imagemBase64, "data_url"),
      new Promise((_, reject) =>
        setTimeout(() => reject(new Error("Tempo esgotado (5s) a subir a imagem")), 5000),
      ),
    ]);

    await comLimiteDeTempo;
    return await getDownloadURL(imgRef);
  } catch (err) {
    console.warn(
      "[Push FCM] Não foi possível preparar a imagem para a notificação " +
        "(a notificação segue sem foto, sem ficar à espera). Se o erro for " +
        "de CORS, é preciso configurar CORS no bucket do Storage " +
        "(gsutil cors set) para este código conseguir subir imagens a partir " +
        "do browser:",
      err,
    );
    return null;
  }
}

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
async function _enviarParaToken(accessToken, token, title, body, data, imagemUrl = null) {
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
          notification: {
            title,
            body,
            ...(imagemUrl ? { image: imagemUrl } : {}),
          },
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
            // NOVO — no iOS, a imagem só aparece se o app tiver uma
            // Notification Service Extension configurada no Xcode; sem
            // isso este campo é ignorado em silêncio (a notificação
            // continua a chegar, só sem a foto).
            ...(imagemUrl ? { fcm_options: { image: imagemUrl } } : {}),
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

  console.log(
    `[Push FCM] Caso: "${casoData.nome}" — a comparar contra município="${municipioAlvo || "(vazio)"}", província="${provinciaAlvo || "(vazio)"}"`,
  );

  const usersSnap = await getDocs(collection(db, "users"));
  const tokens = new Set();

  // NOVO — diagnóstico: mostra, utilizador a utilizador, porque é que
  // foi ou não incluído. Isto distingue os 3 cenários possíveis quando
  // "não chega a ninguém":
  //   1. Ninguém tem fcmToken (nunca abriram a app / negaram notificações)
  //   2. Têm token, mas município/província guardados não batem com o caso
  //   3. Têm token e batem — mas falha depois no envio (CORS, credenciais)
  let comToken = 0;
  const diagnostico = [];

  usersSnap.forEach((doc) => {
    const u = doc.data();
    const token = u.fcmToken;
    if (!token) return;
    comToken++;

    if (doc.id === casoData.userId) {
      tokens.add(token);
      diagnostico.push({
        uid: doc.id,
        municipio: "—",
        provincia: "—",
        incluido: true,
        motivo: "autor do caso",
      });
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

    diagnostico.push({
      uid: doc.id,
      municipio: uMunicipio || "(vazio)",
      provincia: uProvincia || "(vazio)",
      incluido: deveNotificar,
      motivo: deveNotificar ? "região coincide" : "região não coincide",
    });

    if (deveNotificar) tokens.add(token);
  });

  console.log(
    `[Push FCM] ${comToken} de ${usersSnap.size} utilizadores têm fcmToken guardado.`,
  );
  if (comToken === 0) {
    console.warn(
      "[Push FCM] NENHUM utilizador tem fcmToken — ninguém vai receber " +
        "push, mesmo que a região coincida. Confirma se a app mobile já " +
        "pediu permissão de notificações e gravou o token em users/{uid}.fcmToken.",
    );
  } else {
    console.table(diagnostico);
  }
  console.log(`[Push FCM] Total a notificar: ${tokens.size}.`);

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

  // NOVO — sobe a foto do desaparecido para o Storage uma única vez
  // (não por cada destinatário) e reutiliza o mesmo URL em todos os envios.
  const imagemUrl = await _obterUrlImagem(casoData.id, casoData.imagem);
  console.log(
    imagemUrl
      ? `[Push FCM] Notificação vai incluir foto: ${imagemUrl}`
      : "[Push FCM] Caso sem foto (ou falha ao preparar) — notificação segue só com texto.",
  );

  const accessToken = await _obterAccessToken();

  let enviados = 0;
  for (const token of tokens) {
    try {
      const ok = await _enviarParaToken(accessToken, token, title, body, dataPayload, imagemUrl);
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