/**
 * carousel.js — Carrossel dinâmico de anúncios
 * Lê da coleção "anuncios" no Firestore e renderiza em .anuncios
 *
 * CORRECÇÃO: Remove o where() + orderBy() em conjunto (exigia índice
 * composto no Firestore). Agora busca tudo e filtra/ordena em JS.
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
  container =
    document.getElementById("anuncios-container") ||
    document.querySelector(".anuncios");
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
}
