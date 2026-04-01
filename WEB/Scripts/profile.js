import { auth, db } from "./firebase.js";
import {
  onAuthStateChanged,
  signOut,
} from "https://www.gstatic.com/firebasejs/12.8.0/firebase-auth.js";
import {
  doc,
  getDoc,
  getDocs,
  updateDoc,
  collection,
  query,
  where,
} from "https://www.gstatic.com/firebasejs/12.8.0/firebase-firestore.js";

// ─── Estado Global ───────────────────────────────────────────────
let currentUID  = null;
let mesCasos    = [];   // Casos que o utilizador submeteu
let casosApoios = [];   // Casos que o utilizador apoia

// ─── Autenticação ────────────────────────────────────────────────
onAuthStateChanged(auth, async (user) => {
  if (!user) {
    window.location.href = "login_cadastro.html";
    return;
  }
  currentUID = user.uid;
  await carregarPerfil(user);
  await Promise.all([
    carregarMeusCasos(user.uid),
    carregarCasosApoiados(user.uid),
  ]);
});

/* =========================================================================
   CARREGAR PERFIL DO UTILIZADOR
   ========================================================================= */
async function carregarPerfil(user) {
  try {
    const docSnap = await getDoc(doc(db, "users", user.uid));
    if (!docSnap.exists()) return;

    const data = docSnap.data();
    const nome = data.nome || "Utilizador";

    // Preencher campos
    document.getElementById("p-nome").innerText         = nome;
    document.getElementById("topbar-username").innerText = nome;
    document.querySelector("#p-email span").innerText   = data.email || user.email || "—";
    document.querySelector("#p-local span").innerText   =
      [data.municipio, data.provincia].filter(Boolean).join(", ") || "Localização não definida";

    // Foto de perfil
    if (data.photoBase64) mostrarFoto(data.photoBase64);

  } catch (err) {
    console.error("Erro ao carregar perfil:", err);
  }
}

/* =========================================================================
   FOTO DE PERFIL
   ========================================================================= */
function mostrarFoto(base64) {
  const img         = document.getElementById("profile-photo");
  const placeholder = document.getElementById("avatar-placeholder");
  img.src           = base64;
  img.classList.remove("hidden");
  placeholder.style.display = "none";
}

function comprimirImagem(file, maxDim = 300, quality = 0.82) {
  return new Promise((resolve, reject) => {
    const reader   = new FileReader();
    reader.onerror = () => reject(new Error("Erro ao ler ficheiro."));
    reader.onload  = (e) => {
      const img    = new Image();
      img.onerror  = () => reject(new Error("Imagem inválida."));
      img.onload   = () => {
        let { width, height } = img;
        if (width > height) {
          if (width > maxDim) { height = Math.round(height * maxDim / width); width = maxDim; }
        } else {
          if (height > maxDim) { width = Math.round(width * maxDim / height); height = maxDim; }
        }
        const canvas = document.createElement("canvas");
        canvas.width  = width;
        canvas.height = height;
        canvas.getContext("2d").drawImage(img, 0, 0, width, height);
        resolve(canvas.toDataURL("image/jpeg", quality));
      };
      img.src = e.target.result;
    };
    reader.readAsDataURL(file);
  });
}

async function guardarFotoFirestore(base64) {
  if (!currentUID) return;
  const loader = document.getElementById("upload-loader");
  loader.classList.remove("hidden");
  try {
    await updateDoc(doc(db, "users", currentUID), { photoBase64: base64 });
    mostrarFoto(base64);
    mostrarNotificacao("✅ Foto actualizada com sucesso!");
  } catch (err) {
    mostrarNotificacao("❌ Erro ao guardar foto.");
  } finally {
    loader.classList.add("hidden");
  }
}

function acionarUploadFoto() {
  document.getElementById("photo-input").click();
}

document.getElementById("avatar-trigger").addEventListener("click", acionarUploadFoto);

document.getElementById("photo-input").addEventListener("change", async (e) => {
  const file = e.target.files[0];
  if (!file) return;

  const tiposPermitidos = ["image/jpeg", "image/png", "image/webp", "image/gif"];
  if (!tiposPermitidos.includes(file.type)) {
    mostrarNotificacao("⚠️ Formato não suportado. Use JPG, PNG ou WEBP.");
    e.target.value = "";
    return;
  }
  if (file.size > 5 * 1024 * 1024) {
    mostrarNotificacao("⚠️ Ficheiro demasiado grande (máximo 5 MB).");
    e.target.value = "";
    return;
  }
  try {
    const base64 = await comprimirImagem(file);
    await guardarFotoFirestore(base64);
  } catch (err) {
    mostrarNotificacao("❌ Não foi possível processar a imagem.");
  }
  e.target.value = "";
});

/* =========================================================================
   CARREGAR MEUS CASOS
   — Busca em casos_pendentes (pendentes) + casos (aprovados/outros)
   ========================================================================= */
async function carregarMeusCasos(uid) {
  const grid = document.getElementById("grid-meus-casos");

  try {
    // Casos pendentes (submetidos mas ainda não aprovados)
    const qPendentes   = query(collection(db, "casos_pendentes"), where("userId", "==", uid));
    const snapPendentes = await getDocs(qPendentes);

    // Casos já aprovados/ativos
    const qAprovados   = query(collection(db, "casos"), where("userId", "==", uid));
    const snapAprovados = await getDocs(qAprovados);

    mesCasos = [];

    snapPendentes.forEach((d) => mesCasos.push({ id: d.id, ...d.data(), _origem: "pendente" }));
    snapAprovados.forEach((d) => mesCasos.push({ id: d.id, ...d.data(), _origem: "casos" }));

    // Calcular estatísticas
    const aprovados = mesCasos.filter((c) => c.status === "aprovado" || c.status === "encontrado" || c.status === "desmentido").length;
    const pendentes = mesCasos.filter((c) => !c.status || c.status === "pendente").length;

    // Apoios totais recebidos nos casos aprovados
    const totalApoiosRecebidos = mesCasos.reduce((acc, c) => acc + (c.apoios || 0), 0);

    // Atualizar stats desktop + mobile
    setStatAll("stat-aprovados", aprovados);
    setStatAll("stat-pendentes", pendentes);
    document.getElementById("total-apoios-received").innerText = totalApoiosRecebidos;

    // Renderizar grid
    renderizarGrid(mesCasos, grid, "meus");

  } catch (err) {
    console.error("Erro ao carregar casos:", err);
    grid.innerHTML = `<div class="ig-grid-empty"><i class="fa-solid fa-circle-exclamation"></i><p>Erro ao carregar casos.</p></div>`;
  }
}

/* =========================================================================
   CARREGAR CASOS APOIADOS
   — Busca casos onde apoiadoPor contém o uid do utilizador
   ========================================================================= */
async function carregarCasosApoiados(uid) {
  const grid = document.getElementById("grid-apoios");

  try {
    const q    = query(collection(db, "casos"), where("apoiadoPor", "array-contains", uid));
    const snap = await getDocs(q);

    casosApoios = [];
    snap.forEach((d) => casosApoios.push({ id: d.id, ...d.data() }));

    // Atualizar contador de Apoios
    setStatAll("stat-apoios", casosApoios.length);

    renderizarGrid(casosApoios, grid, "apoios");

  } catch (err) {
    console.error("Erro ao carregar apoios:", err);
    grid.innerHTML = `<div class="ig-grid-empty"><i class="fa-solid fa-circle-exclamation"></i><p>Erro ao carregar apoios.</p></div>`;
  }
}

/* =========================================================================
   RENDERIZAR GRID (Instagram)
   ========================================================================= */
function renderizarGrid(lista, gridEl, tipo) {
  gridEl.innerHTML = "";

  if (lista.length === 0) {
    const msgVazio = tipo === "apoios"
      ? "Ainda não apoiou nenhum caso."
      : "Ainda não submeteu nenhum caso.";
    const iconVazio = tipo === "apoios" ? "fa-heart" : "fa-clipboard";

    gridEl.innerHTML = `
      <div class="ig-grid-empty">
        <i class="fa-solid ${iconVazio}"></i>
        <p>${msgVazio}</p>
      </div>
    `;
    return;
  }

  lista.forEach((caso) => {
    const item = document.createElement("div");
    item.className        = "ig-grid-item";
    item.dataset.id       = caso.id;
    item.dataset.origem   = caso._origem || "casos";
    const statusClass     = caso.status || "pendente";
    const apoiosCount     = caso.apoios  || 0;
    const comentCount     = caso.comentarios || 0;

    if (caso.imagem) {
      item.innerHTML = `
        <img src="${caso.imagem}" alt="${caso.nome}" onerror="this.parentElement.innerHTML=getPlaceholderHtml('${caso.nome}')">
        <div class="ig-grid-badge ${statusClass}">${statusClass}</div>
        <div class="ig-grid-overlay">
          <span class="ig-grid-stat"><i class="fa-solid fa-heart"></i> ${apoiosCount}</span>
          <span class="ig-grid-stat"><i class="fa-solid fa-comment"></i> ${comentCount}</span>
        </div>
      `;
    } else {
      item.innerHTML = `
        <div class="ig-grid-placeholder">
          <i class="fa-solid fa-user"></i>
          <span>${caso.nome || "Sem nome"}</span>
        </div>
        <div class="ig-grid-badge ${statusClass}">${statusClass}</div>
        <div class="ig-grid-overlay">
          <span class="ig-grid-stat"><i class="fa-solid fa-heart"></i> ${apoiosCount}</span>
          <span class="ig-grid-stat"><i class="fa-solid fa-comment"></i> ${comentCount}</span>
        </div>
      `;
    }

    item.addEventListener("click", () => abrirLightbox(caso));
    gridEl.appendChild(item);
  });
}

// Usado pelo onerror do img (precisa ser global)
window.getPlaceholderHtml = (nome) => `
  <div class="ig-grid-placeholder">
    <i class="fa-solid fa-user"></i>
    <span>${nome || "Sem nome"}</span>
  </div>
`;

/* =========================================================================
   LIGHTBOX
   ========================================================================= */
function abrirLightbox(caso) {
  const lb = document.getElementById("caso-lightbox");

  document.getElementById("lb-img").src         = caso.imagem || "imgs/user.jpg";
  document.getElementById("lb-nome").innerText  = caso.nome   || "Sem nome";

  const status  = document.getElementById("lb-status");
  status.innerText  = caso.status || "pendente";
  status.className  = `status-badge status-${caso.status || "pendente"}`;

  const detalhes = [
    caso.idade       ? `${caso.idade} anos`                   : null,
    caso.sexo        ? caso.sexo                               : null,
    caso.municipio   ? `📍 ${caso.municipio}, ${caso.provincia || ""}` : null,
    caso.ultimo_local ? `Último local: ${caso.ultimo_local}`   : null,
    caso.roupas      ? `Vestia: ${caso.roupas}`               : null,
    caso.informacoes_adicionais || null,
  ].filter(Boolean).join(" · ");

  document.getElementById("lb-detalhes").innerText      = detalhes || "Sem detalhes disponíveis.";
  document.getElementById("lb-apoios").innerHTML        = `<i class="fa-solid fa-heart"></i> ${caso.apoios || 0} apoios`;
  document.getElementById("lb-comentarios").innerHTML   = `<i class="fa-regular fa-comment"></i> ${caso.comentarios || 0} comentários`;

  lb.classList.remove("hidden");
  document.body.style.overflow = "hidden";
}

function fecharLightbox() {
  document.getElementById("caso-lightbox").classList.add("hidden");
  document.body.style.overflow = "";
}

document.getElementById("lightbox-close").addEventListener("click", fecharLightbox);
document.getElementById("lightbox-backdrop").addEventListener("click", fecharLightbox);
document.addEventListener("keydown", (e) => { if (e.key === "Escape") fecharLightbox(); });

/* =========================================================================
   TABS
   ========================================================================= */
document.querySelectorAll(".ig-tab").forEach((tab) => {
  tab.addEventListener("click", () => {
    document.querySelectorAll(".ig-tab").forEach((t) => t.classList.remove("active"));
    document.querySelectorAll(".ig-tab-content").forEach((c) => c.classList.remove("active"));

    tab.classList.add("active");
    const targetId = tab.dataset.tab;
    document.getElementById(targetId)?.classList.add("active");
  });
});

/* =========================================================================
   MENU DE OPÇÕES
   ========================================================================= */
const optionsMenu = document.getElementById("options-menu");
const backdrop    = document.getElementById("menu-backdrop");

function abrirMenu() {
  optionsMenu.classList.remove("hidden");
  backdrop.classList.remove("hidden");
}
function fecharMenu() {
  optionsMenu.classList.add("hidden");
  backdrop.classList.add("hidden");
}

document.getElementById("btn-open-menu").addEventListener("click", abrirMenu);
document.getElementById("btn-edit-profile").addEventListener("click", abrirMenu);
document.getElementById("btn-cancel-menu").addEventListener("click", fecharMenu);
backdrop.addEventListener("click", fecharMenu);

document.getElementById("btn-change-photo").addEventListener("click", () => {
  fecharMenu();
  setTimeout(acionarUploadFoto, 200);
});

/* =========================================================================
   LOGOUT
   ========================================================================= */
document.getElementById("btn-logout").addEventListener("click", () => {
  signOut(auth)
    .then(() => (window.location.href = "login_cadastro.html"))
    .catch((err) => mostrarNotificacao("❌ Erro ao sair: " + err.message));
});

/* =========================================================================
   UTILITÁRIOS
   ========================================================================= */

// Atualiza stat em desktop e mobile ao mesmo tempo
function setStatAll(baseId, value) {
  const el  = document.getElementById(baseId);
  const elM = document.getElementById(baseId + "-m");
  if (el)  el.innerText  = value;
  if (elM) elM.innerText = value;
}

function mostrarNotificacao(msg) {
  if (typeof window.showAlert === "function") {
    window.showAlert(msg);
    return;
  }
  const toast = document.createElement("div");
  toast.innerText = msg;
  Object.assign(toast.style, {
    position: "fixed", bottom: "24px", left: "50%",
    transform: "translateX(-50%)", background: "#222", color: "#fff",
    padding: "12px 22px", borderRadius: "10px", fontSize: "14px",
    fontFamily: "var(--font-base)", zIndex: "9999",
    boxShadow: "0 4px 16px rgba(0,0,0,0.25)", maxWidth: "90vw", textAlign: "center",
  });
  document.body.appendChild(toast);
  setTimeout(() => {
    toast.style.opacity = "0";
    toast.style.transition = "opacity 0.4s";
    setTimeout(() => toast.remove(), 500);
  }, 3000);
}