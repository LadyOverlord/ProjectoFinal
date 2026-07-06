// Scripts/suporte_suspensao.js
// ─────────────────────────────────────────────────────────────────────────────
// Ecrã de suporte para utilizadores suspensos — versão web, com o MESMO
// fluxo do mobile (SuspendedPage): menu inicial → diretrizes OU chat.
// Tema claro (o mobile usa tema escuro; aqui mantém-se o visual claro já
// usado no resto da app web).
//
// Fluxo:
//   1. Cabeçalho (sempre visível): trust score, motivo, botão Sair.
//   2. Corpo dinâmico, 3 estados:
//        'menu'       → dois cartões: "Reler as diretrizes" / "Falar com o suporte"
//        'diretrizes' → texto das diretrizes + botão para ir ao chat
//        'chat'       → conversa com IA (Gemini) + botão "Falar com o admin",
//                       que grava o pedido em suporte_suspensao/ para o
//                       painel de Suporte do admin ler.
//
// Usa a mesma GEMINI_API_KEY global definida em chatbot.js (script clássico
// carregado antes deste, por isso já está disponível quando este módulo
// corre — ver ordem dos <script> no index.html).
// ─────────────────────────────────────────────────────────────────────────────

import {
  addDoc,
  collection,
  Timestamp,
} from "https://www.gstatic.com/firebasejs/12.8.0/firebase-firestore.js";
import { db, auth } from "./firebase.js";

const _diretrizesTexto = `
<h4 style="margin:0 0 14px;color:#222;font-size:15px;">📋 Diretrizes da Comunidade</h4>

<p style="margin:0 0 12px;"><strong>1. Informação verdadeira</strong><br>
Apenas relate casos reais. Informações falsas prejudicam famílias e consomem recursos de busca.</p>

<p style="margin:0 0 12px;"><strong>2. Respeito</strong><br>
Trate todos os utilizadores e familiares com respeito. Comentários ofensivos ou discriminatórios não são tolerados.</p>

<p style="margin:0 0 12px;"><strong>3. Comentários construtivos</strong><br>
Comente apenas se tiver informações úteis. Evite especulações infundadas.</p>

<p style="margin:0 0 12px;"><strong>4. Privacidade</strong><br>
Não partilhe dados pessoais de terceiros sem autorização.</p>

<p style="margin:0 0 18px;"><strong>5. Não abuse do sistema</strong><br>
Não crie casos duplicados, não apoie casos sabendo que são falsos e não use a plataforma para outros fins.</p>

<div style="background:#eef7fb;border-radius:10px;padding:12px 14px;font-size:13px;color:#333;line-height:1.6;">
  <strong>Como funciona o Trust Score:</strong><br>
  • Começa em 100 pontos<br>
  • Comentário removido: −10 pontos<br>
  • Caso desmentido: −20 pontos<br>
  • Caso rejeitado por informação falsa: −15 pontos<br>
  • Score = 0: acesso suspenso
</div>
`;

// Estado da sessão actual — persiste enquanto o overlay está aberto,
// mesmo ao navegar entre menu/diretrizes/chat.
let _historico = [];
let _uid = null;
let _userData = null;
let _pedidoEnviado = false;
let _chatIniciado = false;

// ── Ponto de entrada público ─────────────────────────────────────────────────
window.mostrarSuporteSuspensao = function (uid, userData) {
  if (document.getElementById("suporte-suspensao-overlay")) return;
  _uid = uid;
  _userData = userData;
  _historico = [];
  _pedidoEnviado = false;
  _chatIniciado = false;

  const score = typeof userData.trustScore === "number" ? userData.trustScore : 0;
  const motivo = userData.suspensionReason || "violação das diretrizes";
  const nome = userData.nome || userData.email || "Utilizador";

  const overlay = document.createElement("div");
  overlay.id = "suporte-suspensao-overlay";
  overlay.style.cssText = `
    position: fixed; inset: 0; z-index: 25000;
    display: flex; flex-direction: column;
    background: #f8f9fa; font-family: var(--font-base, 'Quicksand', sans-serif);
  `;

  overlay.innerHTML = `
    <!-- Cabeçalho -->
    <div style="background:#fff;border-bottom:1px solid #e6e9ec;padding:14px 20px;display:flex;align-items:center;gap:12px;flex-shrink:0;">
      <div style="width:40px;height:40px;border-radius:50%;background:#fee2e2;display:flex;align-items:center;justify-content:center;flex-shrink:0;">
        <i class="fa-solid fa-ban" style="color:#dc2626;font-size:16px;"></i>
      </div>
      <div style="flex:1;min-width:0;">
        <div style="font-weight:700;font-size:15px;color:#222;">Conta Suspensa</div>
        <div style="font-size:12px;color:#868e96;">Olá, ${_escHtml(nome)}</div>
      </div>
      <button id="ss-btn-logout" style="background:none;border:1px solid #e6e9ec;border-radius:8px;padding:6px 12px;font-size:12px;color:#868e96;cursor:pointer;font-family:inherit;">
        <i class="fa-solid fa-right-from-bracket"></i> Sair
      </button>
    </div>

    <!-- Info da suspensão -->
    <div style="background:#fff;border-bottom:1px solid #e6e9ec;padding:14px 20px;flex-shrink:0;">
      <div style="display:flex;gap:16px;flex-wrap:wrap;align-items:center;">
        <div style="display:flex;align-items:center;gap:8px;">
          <span style="font-size:12px;color:#868e96;">Trust Score:</span>
          <div style="background:#fee2e2;border-radius:6px;padding:2px 10px;font-size:12px;font-weight:700;color:#dc2626;">${score}/100</div>
        </div>
        <div style="display:flex;align-items:center;gap:8px;">
          <span style="font-size:12px;color:#868e96;">Motivo:</span>
          <span style="font-size:12px;color:#343a40;">${_escHtml(motivo)}</span>
        </div>
      </div>
    </div>

    <!-- Corpo dinâmico (menu | diretrizes | chat) -->
    <div id="ss-body" style="flex:1;overflow-y:auto;"></div>

    <!-- Barra de input do chat — só visível no estado 'chat' -->
    <div id="ss-chat-inputbar" style="display:none;background:#fff;border-top:1px solid #e6e9ec;padding:12px 16px;flex-shrink:0;">
      <div id="ss-btn-admin-wrap" style="margin-bottom:10px;max-width:640px;margin-left:auto;margin-right:auto;">
        <button id="ss-btn-admin" style="width:100%;padding:10px;border:none;border-radius:8px;background:#16a34a;color:#fff;font-weight:700;font-size:13px;cursor:pointer;font-family:inherit;display:flex;align-items:center;justify-content:center;gap:8px;">
          <i class="fa-solid fa-paper-plane"></i> Falar com o admin
        </button>
      </div>
      <div style="display:flex;gap:8px;max-width:640px;margin:0 auto;">
        <input id="ss-input" type="text" placeholder="Escreva uma mensagem..."
          style="flex:1;border:1px solid #d3d8dd;border-radius:8px;padding:10px 14px;font-size:13px;font-family:inherit;outline:none;">
        <button id="ss-send" style="width:40px;height:40px;border:none;border-radius:8px;background:#0c7ab5;color:#fff;cursor:pointer;display:flex;align-items:center;justify-content:center;flex-shrink:0;">
          <i class="fa-solid fa-paper-plane" style="font-size:14px;"></i>
        </button>
      </div>
    </div>
  `;

  document.body.appendChild(overlay);
  _injetarEstilos();

  document.getElementById("ss-btn-logout").addEventListener("click", async () => {
    const { signOut } = await import("https://www.gstatic.com/firebasejs/12.8.0/firebase-auth.js");
    await signOut(auth);
    window.location.reload();
  });

  document.getElementById("ss-send").addEventListener("click", () => _enviarMensagem());
  document.getElementById("ss-input").addEventListener("keypress", (e) => {
    if (e.key === "Enter") _enviarMensagem();
  });
  document.getElementById("ss-btn-admin").addEventListener("click", _enviarPedidoAdmin);

  _renderBody("menu");
};

// Injecta uma única vez o hover dos cartões do menu (:hover não dá para
// fazer só com style inline).
function _injetarEstilos() {
  if (document.getElementById("ss-styles")) return;
  const style = document.createElement("style");
  style.id = "ss-styles";
  style.textContent = `
    .ss-menu-card { transition: transform .15s ease, box-shadow .15s ease, border-color .15s ease; }
    .ss-menu-card:hover { transform: translateY(-2px); box-shadow: 0 6px 18px rgba(0,0,0,0.08); }
  `;
  document.head.appendChild(style);
}

// ── Renderização do corpo dinâmico ────────────────────────────────────────
function _renderBody(estado) {
  const body = document.getElementById("ss-body");
  const inputBar = document.getElementById("ss-chat-inputbar");
  if (!body) return;

  if (estado === "menu") {
    inputBar.style.display = "none";
    body.innerHTML = `
      <div style="padding:40px 24px;text-align:center;max-width:420px;margin:0 auto;">
        <div style="width:76px;height:76px;border-radius:50%;background:#fee2e2;display:flex;align-items:center;justify-content:center;margin:0 auto 20px;">
          <i class="fa-solid fa-headset" style="color:#dc2626;font-size:32px;"></i>
        </div>
        <h2 style="margin:0 0 6px;font-size:19px;color:#222;">Como posso ajudar?</h2>
        <p style="margin:0 0 28px;color:#868e96;font-size:13px;">Escolha uma opção abaixo para continuar.</p>

        <div class="ss-menu-card" data-action="diretrizes" style="display:flex;align-items:center;gap:14px;background:#fff;border:1.5px solid #e6e9ec;border-radius:14px;padding:16px;margin-bottom:12px;cursor:pointer;text-align:left;">
          <div style="width:44px;height:44px;border-radius:12px;background:#fef3c7;display:flex;align-items:center;justify-content:center;flex-shrink:0;">
            <i class="fa-solid fa-book" style="color:#d97706;font-size:18px;"></i>
          </div>
          <div style="flex:1;">
            <div style="font-weight:700;font-size:14px;color:#222;">Reler as diretrizes</div>
            <div style="font-size:12px;color:#868e96;">Entenda o que levou à suspensão</div>
          </div>
          <i class="fa-solid fa-chevron-right" style="color:#d97706;font-size:13px;"></i>
        </div>

        <div class="ss-menu-card" data-action="chat" style="display:flex;align-items:center;gap:14px;background:#fff;border:1.5px solid #e6e9ec;border-radius:14px;padding:16px;cursor:pointer;text-align:left;">
          <div style="width:44px;height:44px;border-radius:12px;background:#e3f2fd;display:flex;align-items:center;justify-content:center;flex-shrink:0;">
            <i class="fa-solid fa-comment" style="color:#0c7ab5;font-size:18px;"></i>
          </div>
          <div style="flex:1;">
            <div style="font-weight:700;font-size:14px;color:#222;">Falar com o suporte</div>
            <div style="font-size:12px;color:#868e96;">Solicitar reactivação da conta</div>
          </div>
          <i class="fa-solid fa-chevron-right" style="color:#0c7ab5;font-size:13px;"></i>
        </div>
      </div>
    `;
    body.querySelector('[data-action="diretrizes"]').addEventListener("click", () => _renderBody("diretrizes"));
    body.querySelector('[data-action="chat"]').addEventListener("click", () => _renderBody("chat"));
    return;
  }

  if (estado === "diretrizes") {
    inputBar.style.display = "none";
    body.innerHTML = `
      <div style="padding:20px 20px 28px;max-width:520px;margin:0 auto;">
        <button id="ss-btn-voltar-menu" style="background:none;border:none;color:#0c7ab5;font-size:13px;font-weight:600;cursor:pointer;display:flex;align-items:center;gap:6px;padding:0 0 16px;font-family:inherit;">
          <i class="fa-solid fa-arrow-left"></i> Voltar
        </button>
        <div style="background:#fff;border:1px solid #e6e9ec;border-radius:14px;padding:20px;font-size:13px;color:#444;line-height:1.6;">
          ${_diretrizesTexto}
        </div>
        <button id="ss-btn-ir-chat" style="width:100%;margin-top:18px;padding:12px;border:none;border-radius:10px;background:#0c7ab5;color:#fff;font-weight:700;font-size:14px;cursor:pointer;font-family:inherit;display:flex;align-items:center;justify-content:center;gap:8px;">
          <i class="fa-solid fa-comment"></i> Falar com o suporte
        </button>
      </div>
    `;
    body.querySelector("#ss-btn-voltar-menu").addEventListener("click", () => _renderBody("menu"));
    body.querySelector("#ss-btn-ir-chat").addEventListener("click", () => _renderBody("chat"));
    return;
  }

  if (estado === "chat") {
    inputBar.style.display = "block";
    body.innerHTML = `<div id="ss-messages" style="padding:16px 20px;display:flex;flex-direction:column;gap:12px;max-width:640px;margin:0 auto;width:100%;box-sizing:border-box;"></div>`;

    // Redesenha as mensagens já existentes — se o utilizador foi às
    // diretrizes e voltou ao chat, o histórico mantém-se.
    _historico.forEach((m) => _renderMensagemDOM(m.text, m.role === "user"));

    if (!_chatIniciado) {
      _chatIniciado = true;
      _adicionarMensagem("👋 Olá! A sua conta está suspensa.", "bot");
      _adicionarMensagem(
        "Posso ajudá-lo(a) de duas formas:\n\n1️⃣ Reler as diretrizes da comunidade\n2️⃣ Enviar um pedido de reactivação ao suporte",
        "bot",
      );
    }

    document.getElementById("ss-input")?.focus();
  }
}

// ── Enviar mensagem ao Gemini ─────────────────────────────────────────────
async function _enviarMensagem() {
  const input = document.getElementById("ss-input");
  const texto = (input?.value || "").trim();
  if (!texto) return;
  input.value = "";

  _adicionarMensagem(texto, "user");
  _historico.push({ role: "user", text: texto });

  const loadingId = _adicionarMensagem("A processar...", "bot", true);

  try {
    const score = typeof _userData?.trustScore === "number" ? _userData.trustScore : 0;
    const motivo = _userData?.suspensionReason || "violação das diretrizes";

    const systemPrompt = `Você é o assistente de suporte da plataforma Missing AO, uma plataforma angolana de rastreio de pessoas desaparecidas.

CONTEXTO IMPORTANTE:
- Este utilizador está SUSPENSO. O seu Trust Score chegou a ${score}/100.
- Motivo da suspensão: "${motivo}"
- O utilizador pode apenas: conversar com este assistente e pedir revisão ao admin humano.

COMPORTAMENTO:
- Seja empático mas claro sobre a situação.
- Explique que a reactivação depende de revisão humana pelo admin.
- Se pedir para falar com o suporte humano, diga que pode carregar no botão "Falar com o admin".
- Respostas curtas, máximo 3 parágrafos.
- Responda SEMPRE em português de Angola (informal mas respeitoso).

HISTÓRICO DESTA CONVERSA:
${_historico.slice(0, -1).map(m => `${m.role === "user" ? "Utilizador" : "Assistente"}: ${m.text}`).join("\n")}`;

    const url = `https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=${GEMINI_API_KEY}`;

    const response = await fetch(url, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        contents: [{
          role: "user",
          parts: [{ text: systemPrompt + "\n\n--- MENSAGEM ACTUAL ---\n\n" + texto }],
        }],
        generationConfig: { temperature: 0.7 },
      }),
    });

    const data = await response.json();
    _removerMensagem(loadingId);

    if (data.candidates?.[0]?.content) {
      const resposta = data.candidates[0].content.parts[0].text;
      _adicionarMensagem(resposta, "bot");
      _historico.push({ role: "bot", text: resposta });
    } else if (data.error) {
      _adicionarMensagem("Erro: " + data.error.message, "bot");
    } else {
      _adicionarMensagem("Não consegui responder. Tente novamente.", "bot");
    }
  } catch (err) {
    _removerMensagem(loadingId);
    _adicionarMensagem("Sem ligação. Verifique a sua internet e tente novamente.", "bot");
  }
}

// ── Enviar pedido ao admin (grava em suporte_suspensao/) ──────────────────────
async function _enviarPedidoAdmin() {
  if (_pedidoEnviado) return;

  const confirmado = confirm(
    "O histórico desta conversa e os dados da sua conta serão enviados ao administrador para análise.\n\nDeseja continuar?"
  );
  if (!confirmado) return;

  const btn = document.getElementById("ss-btn-admin");
  if (btn) { btn.disabled = true; btn.textContent = "A enviar..."; }

  try {
    await addDoc(collection(db, "suporte_suspensao"), {
      uid:              _uid,
      email:            _userData?.email || "",
      nome:             _userData?.nome  || _userData?.email || "",
      trustScore:       _userData?.trustScore ?? 0,
      suspensionReason: _userData?.suspensionReason || "",
      suspendedAt:      _userData?.suspendedAt || null,
      historico:        _historico.map(m => ({
        texto:  m.text,
        isUser: m.role === "user",
        hora:   new Date().toISOString(),
      })),
      status:    "pendente",
      criadoEm: Timestamp.now(),
    });

    _pedidoEnviado = true;
    if (btn) {
      btn.disabled = true;
      btn.style.background = "#868e96";
      btn.innerHTML = '<i class="fa-solid fa-check"></i> Pedido enviado';
    }
    _adicionarMensagem(
      "✅ O seu pedido foi enviado! O administrador irá analisar e responder em breve. Obrigado pela paciência.",
      "bot"
    );
  } catch (err) {
    if (btn) { btn.disabled = false; btn.innerHTML = '<i class="fa-solid fa-paper-plane"></i> Falar com o admin'; }
    alert("Erro ao enviar o pedido: " + err.message);
  }
}

// ── Auxiliares de UI ─────────────────────────────────────────────────────────
function _adicionarMensagem(texto, sender, isLoading = false) {
  return _renderMensagemDOM(texto, sender === "user", isLoading);
}

// CORRIGIDO: o texto passa agora sempre por _escHtml() antes de entrar no
// innerHTML — antes, uma mensagem escrita pelo próprio utilizador (ou uma
// resposta da IA) era inserida sem qualquer escaping, o que permitia que
// HTML/JS colado no campo de texto fosse executado no browser da própria
// pessoa. As mensagens internas (boas-vindas, confirmações) usam '\n'
// para quebras de linha em vez de '<br>' directo, exactamente para
// poderem passar por este mesmo escaping em segurança.
function _renderMensagemDOM(texto, isUser, isLoading = false) {
  const container = document.getElementById("ss-messages");
  if (!container) return null;

  const id = "ss-msg-" + Date.now() + "-" + Math.random().toString(36).slice(2, 7);
  const hora = new Date().toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" });
  const textoSeguro = _escHtml(texto).replace(/\n/g, "<br>");

  const div = document.createElement("div");
  div.id = id;
  div.style.cssText = `display:flex;flex-direction:column;align-items:${isUser ? "flex-end" : "flex-start"};gap:3px;`;
  div.innerHTML = `
    <div style="
      max-width: 80%;
      padding: 10px 14px;
      border-radius: ${isUser ? "14px 14px 4px 14px" : "14px 14px 14px 4px"};
      background: ${isUser ? "#0c7ab5" : "#fff"};
      color: ${isUser ? "#fff" : "#343a40"};
      font-size: 13px;
      line-height: 1.5;
      border: ${isUser ? "none" : "1px solid #e6e9ec"};
      ${isLoading ? "color:#868e96;font-style:italic;" : ""}
    ">${textoSeguro}</div>
    <span style="font-size:10px;color:#adb5bd;">${hora}</span>
  `;

  container.appendChild(div);
  container.scrollTop = container.scrollHeight;
  return id;
}

function _removerMensagem(id) {
  document.getElementById(id)?.remove();
}

function _escHtml(str) {
  return String(str || "")
    .replace(/&/g, "&amp;").replace(/</g, "&lt;")
    .replace(/>/g, "&gt;").replace(/"/g, "&quot;");
}