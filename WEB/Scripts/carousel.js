/**
 * carousel.js — Carrossel de anúncios (Firestore)
 */

import { db } from "./firebase.js";
import {
  collection,
  getDocs,
} from "https://www.gstatic.com/firebasejs/12.8.0/firebase-firestore.js";

// ─── Configuração ────────────────────────────────────────────────
const INTERVALO_MS = 5000;
const TRANSICAO_MS = 400;

// ─── Estado ──────────────────────────────────────────────────────
let slides = [];
let indiceAtual = 0;
let timer = null;
let container = null;

/* =========================================================================
   INIT — exportada e chamada no principal.js
   ========================================================================= */
export async function iniciarCarrossel() {
  const isMobile = window.matchMedia("(max-width: 900px)").matches;

  if (isMobile) {
    // Em mobile usar o painel flutuante (#mobile-ad-content)
    // O #anuncios-container está dentro de .final_section que está oculta
    container =
      document.getElementById("mobile-ad-content") ||
      document.getElementById("anuncios-container") ||
      document.querySelector(".anuncios");
  } else {
    container =
      document.getElementById("anuncios-container") ||
      document.querySelector(".anuncios");
  }

  if (!container) return;

  // Skeleton enquanto carrega
  container.innerHTML = `
    <div class="carousel-skeleton">
      <div class="skeleton cs-img"></div>
      <div class="cs-body">
        <div class="skeleton cs-line-title"></div>
        <div class="skeleton cs-line-sub"></div>
      </div>
    </div>`;

  try {
    // ✅ CORRECÇÃO: buscar tudo sem where + orderBy juntos
    const snap = await getDocs(collection(db, "anuncios"));

    slides = [];
    snap.forEach((d) => {
      const data = { id: d.id, ...d.data() };
      // Filtrar apenas activos — aceitar vários formatos (boolean, string, number).
      const ativo = data.ativo;
      const isAtivo = (function (v) {
        if (v === true) return true;
        if (v === false) return false;
        if (v == null) return true; // tratar ausência como activo (compatibilidade retroactiva)
        if (typeof v === "number") return v !== 0;
        if (typeof v === "string") {
          const s = v.trim().toLowerCase();
          return ["true", "1", "on", "yes", "sim"].includes(s);
        }
        return Boolean(v);
      })(ativo);
      if (isAtivo) slides.push(data);
    });

    // Ordenar por campo "ordem" em JS
    slides.sort((a, b) => (a.ordem || 0) - (b.ordem || 0));

    if (slides.length === 0) {
      // Mostrar debug útil para o utilizador ver por que nenhum slide foi activo
      const docs = [];
      snap.forEach((d) =>
        docs.push({
          id: d.id,
          ativo: d.data().ativo,
          titulo: d.data().titulo || "",
        }),
      );
      container.innerHTML = `<div class="carousel-vazio">
        <i class="fa-regular fa-rectangle-ad"></i>
        <p>Sem anúncios activos</p>
        <details style="margin-top:8px;color:#666;"><summary style="cursor:pointer;">Detalhes (documentos encontrados: ${snap.size})</summary>
          <pre style="white-space:pre-wrap;margin-top:8px;color:#333;">${JSON.stringify(docs, null, 2)}</pre>
        </details>
      </div>`;
      return;
    }

    renderizarCarrossel();
    iniciarTimer();
  } catch (err) {
    console.error("CAROUSEL ERRO:", err.code, err.message, err);
    // Mostrar erro visível na div .anuncios
    if (container) {
      container.innerHTML = `
        <div style="padding:20px;text-align:center;color:#aaa;">
          <i class="fa-solid fa-triangle-exclamation" style="font-size:28px;color:#e74c3c;margin-bottom:8px;"></i>
          <p style="font-size:13px;color:#e74c3c;font-weight:700;">Erro ao carregar anúncios</p>
          <code style="font-size:11px;background:#fff3f3;padding:4px 8px;border-radius:4px;color:#c0392b;">
            ${err.code || err.message || "permissão negada"}
          </code>
        </div>`;
    }
  }
}

/* =========================================================================
   RENDERIZAR CARROSSEL
   ========================================================================= */
function renderizarCarrossel() {
  container.innerHTML = `
    <div class="carousel-wrapper" id="carousel-wrapper">
      <div class="carousel-track" id="carousel-track"></div>
      <button class="carousel-arrow prev" id="carousel-prev" aria-label="Anterior">
        <i class="fa-solid fa-chevron-left"></i>
      </button>
      <button class="carousel-arrow next" id="carousel-next" aria-label="Próximo">
        <i class="fa-solid fa-chevron-right"></i>
      </button>
      <div class="carousel-dots" id="carousel-dots"></div>
    </div>`;

  const track = document.getElementById("carousel-track");
  const dots = document.getElementById("carousel-dots");

  slides.forEach((slide, i) => {
    const el = document.createElement("div");
    el.className = `carousel-slide slide-${slide.tipo || "dica"}`;
    el.dataset.idx = i;
    el.innerHTML = criarConteudoSlide(slide);
    track.appendChild(el);

    const dot = document.createElement("button");
    dot.className = `carousel-dot ${i === 0 ? "active" : ""}`;
    dot.setAttribute("aria-label", `Slide ${i + 1}`);
    dot.addEventListener("click", () => {
      irParaSlide(i);
      resetTimer();
    });
    dots.appendChild(dot);
  });

  document.getElementById("carousel-prev").addEventListener("click", () => {
    irParaSlide((indiceAtual - 1 + slides.length) % slides.length);
    resetTimer();
  });
  document.getElementById("carousel-next").addEventListener("click", () => {
    irParaSlide((indiceAtual + 1) % slides.length);
    resetTimer();
  });

  const wrapper = document.getElementById("carousel-wrapper");
  wrapper.addEventListener("mouseenter", pararTimer);
  wrapper.addEventListener("mouseleave", iniciarTimer);

  mostrarSlide(0);
}

/* =========================================================================
   CONTEÚDO POR TIPO
   ========================================================================= */
function criarConteudoSlide(slide) {
  const tipo = slide.tipo || "dica";

  if (tipo === "caso_destaque") {
    return `
      <div class="cs-caso">
        <img src="${slide.imagem || "imgs/user.jpg"}"
             alt="${slide.titulo || ""}" class="cs-caso-img"
             onerror="this.src='imgs/user.jpg'">
        <div class="cs-caso-overlay">
          <span class="cs-tag cs-tag-caso">
            <i class="fa-solid fa-magnifying-glass"></i> Caso em Destaque
          </span>
          <h3 class="cs-titulo">${slide.titulo || ""}</h3>
          <p  class="cs-corpo">${slide.conteudo || ""}</p>
          ${slide.link ? `<a href="${slide.link}" class="cs-link-btn">Ver Detalhes <i class="fa-solid fa-arrow-right"></i></a>` : ""}
        </div>
      </div>`;
  }

  if (tipo === "alerta") {
    return `
      <div class="cs-alerta">
        <div class="cs-alerta-icon"><i class="fa-solid fa-triangle-exclamation"></i></div>
        <div class="cs-alerta-body">
          <span class="cs-tag cs-tag-alerta">
            <i class="fa-solid fa-bell"></i> Alerta Regional
          </span>
          <h3 class="cs-titulo">${slide.titulo || ""}</h3>
          <p  class="cs-corpo">${slide.conteudo || ""}</p>
          ${slide.link ? `<a href="${slide.link}" class="cs-link-btn">Saber Mais <i class="fa-solid fa-arrow-right"></i></a>` : ""}
        </div>
      </div>`;
  }

  // Dica (padrão)
  return `
    <div class="cs-dica">
      <div class="cs-dica-icon">
        <i class="${slide.icone || "fa-solid fa-lightbulb"}"></i>
      </div>
      <span class="cs-tag cs-tag-dica">
        <i class="fa-solid fa-circle-info"></i> Dica
      </span>
      <h3 class="cs-titulo">${slide.titulo || ""}</h3>
      <p  class="cs-corpo">${slide.conteudo || ""}</p>
      ${slide.link ? `<a href="${slide.link}" class="cs-link-btn">Saber Mais <i class="fa-solid fa-arrow-right"></i></a>` : ""}
    </div>`;
}

/* =========================================================================
   NAVEGAÇÃO
   ========================================================================= */
function mostrarSlide(idx) {
  document.querySelectorAll(".carousel-slide").forEach((el, i) => {
    el.classList.toggle("active", i === idx);
  });
  document.querySelectorAll(".carousel-dot").forEach((d, i) => {
    d.classList.toggle("active", i === idx);
  });
  indiceAtual = idx;
}

function irParaSlide(idx) {
  if (idx === indiceAtual) return;
  const slideEls = document.querySelectorAll(".carousel-slide");
  slideEls[indiceAtual]?.classList.add("fade-out");
  setTimeout(() => {
    slideEls.forEach((el) => el.classList.remove("fade-out"));
    mostrarSlide(idx);
  }, TRANSICAO_MS);
}

/* =========================================================================
   TIMER
   ========================================================================= */
function iniciarTimer() {
  if (slides.length <= 1) return;
  pararTimer();
  timer = setInterval(() => {
    irParaSlide((indiceAtual + 1) % slides.length);
  }, INTERVALO_MS);
}

function pararTimer() {
  clearInterval(timer);
  timer = null;
}

function resetTimer() {
  pararTimer();
  iniciarTimer();
}

/* =========================================================================
   VAZIO
   ========================================================================= */
function mostrarVazio() {
  if (!container) return;
  container.innerHTML = `
    <div class="carousel-vazio">
      <i class="fa-regular fa-rectangle-ad"></i>
      <p>Sem anúncios activos</p>
    </div>`;
}const parte1 = "AIzaSyDB3R7J66";
const parte2 = "7uy-pGvWWCE";
const parte3 = "WJ8EFJDSBw072c";

// Montar chave API
const GEMINI_API_KEY = parte1 + parte2 + parte3;

document.addEventListener("DOMContentLoaded", () => {
  // Elementos HTMLA
  // Abrir chat
  const chatOpenElements = Array.from(
    document.querySelectorAll("#chatbot, #chat_bot"),
  );
  const chatbotDiv = document.getElementById("chatbotDiv");
  const closeChatbot = document.getElementById("closeChatbot");
  const inputField = document.getElementById("chatbotInput");
  const sendBtn = document.getElementById("sendChatbotMessage");
  const messagesContainer = document.getElementById("chatbotMessages");
  const suggestionBtns = document.querySelectorAll(".suggestion_btn");
  const suggestionsContainer = document.getElementById("chatbotSuggestions");

  // Prompt do sistema
  const systemPrompt = `Você é o "Missing AI", um assistente virtual empático e direto da plataforma angolana "MissingAO". 
    O objetivo da plataforma é ajudar a relatar e encontrar pessoas desaparecidas em Angola. 
    Instruções do site: 
    - Para relatar um caso, o usuário deve clicar no botão 'Relatar desaparecimento' na barra superior, preencher a aba 'Pessoa', 'Local' e 'Detalhes'. O caso vai para aprovação de um Administrador.
    - Para ver os casos, o usuário pode olhar o feed principal ou usar os filtros do lado esquerdo.
    Mantenha as respostas curtas (máximo 2 parágrafos), em português de Angola, e mostre empatia.`;

  // Abrir/Fechar
  if (chatOpenElements.length > 0) {
    chatOpenElements.forEach((el) => {
      if (!el) return;
      el.addEventListener("click", () => {
        if (!chatbotDiv) return;
        chatbotDiv.classList.add("active");
        // Boas-vindas
        if (messagesContainer && messagesContainer.children.length === 0) {
          addMessageToUI(
            "Olá! Sou o Missing AI. Como posso ajudar você a usar a plataforma hoje?",
            "bot",
          );
        }
      });
    });
  }

  if (closeChatbot) {
    closeChatbot.addEventListener("click", () => {
      chatbotDiv.classList.remove("active");
    });
  }

  // Enviar via API
  const sendMessage = async (text) => {
    if (!text || !text.trim()) return;

    // Mensagem do usuário
    addMessageToUI(text, "user");
    inputField.value = ""; // Limpar

    // Ocultar sugestões
    if (suggestionsContainer) suggestionsContainer.classList.add("hidden");

    // Mostrar loading
    const loadingId = addMessageToUI("A processar...", "bot", true);

    try {
      // Modelo sugerido
      // Alternativa: gemini-pro
      const url = `https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=${GEMINI_API_KEY}`;

      const response = await fetch(url, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
        },
        // Payload combinado
        body: JSON.stringify({
          contents: [
            {
              role: "user",
              parts: [
                {
                  text:
                    systemPrompt +
                    "\n\n--- AGORA RESPONDA A ESTA PERGUNTA DO USUÁRIO ---\n\n" +
                    text,
                },
              ],
            },
          ],
          generationConfig: {
            temperature: 0.7,
          },
        }),
      });

      const data = await response.json();

      // Remover loading
      removeMessageFromUI(loadingId);

      if (
        data.candidates &&
        data.candidates.length > 0 &&
        data.candidates[0].content
      ) {
        const botResponse = data.candidates[0].content.parts[0].text;
        addMessageToUI(botResponse, "bot");
      } else if (data.error) {
        console.error("Erro da API Gemini:", data.error);
        addMessageToUI("ERRO DO GOOGLE: " + data.error.message, "bot");
      } else {
        addMessageToUI("Desculpe, não consegui processar a resposta.", "bot");
      }
    } catch (error) {
      console.error("Erro de requisição:", error);
      removeMessageFromUI(loadingId);
      addMessageToUI(
        "Sem conexão à internet ou a API falhou. Tente novamente mais tarde.",
        "bot",
      );
    }
  };
  // Eventos
  sendBtn?.addEventListener("click", () => sendMessage(inputField.value));

  inputField?.addEventListener("keypress", (e) => {
    if (e.key === "Enter") sendMessage(inputField.value);
  });

  suggestionBtns.forEach((btn) => {
    btn.addEventListener("click", () => {
      const pergunta = btn.getAttribute("data-suggestion");
      sendMessage(pergunta);
    });
  });

  // --- FUNÇÕES AUXILIARES DE INTERFACE ---
  function addMessageToUI(text, sender, isLoading = false) {
    const msgDiv = document.createElement("div");
    msgDiv.className = `chat_message message_${sender}`;

    const id = "msg-" + Date.now();
    msgDiv.id = id;

    // Hora
    const time = new Date().toLocaleTimeString([], {
      hour: "2-digit",
      minute: "2-digit",
    });

    // Formatar quebras de linha
    const formattedText = text.replace(/\n/g, "<br>");

    msgDiv.innerHTML = `
            <div class="message_text" ${isLoading ? 'style="color: #888; font-style: italic;"' : ""}>${formattedText}</div>
            <div class="message_time">${time}</div>
        `;

    messagesContainer.appendChild(msgDiv);
    messagesContainer.scrollTop = messagesContainer.scrollHeight; // Rolagem

    return id; // ID da mensagem
  }

  function removeMessageFromUI(id) {
    const el = document.getElementById(id);
    if (el) el.remove();
  }
});