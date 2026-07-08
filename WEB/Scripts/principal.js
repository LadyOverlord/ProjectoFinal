import { auth, db, navigateToLogin, navigateToTarget } from "./firebase.js";
import {
  collection,
  addDoc,
  getDocs,
  getDoc,
  onSnapshot,
  query,
  where,
  doc,
  updateDoc,
  deleteDoc,
  arrayUnion,
  arrayRemove,
  increment,
  orderBy,
  serverTimestamp,
} from "https://www.gstatic.com/firebasejs/12.8.0/firebase-firestore.js";
import { onAuthStateChanged } from "https://www.gstatic.com/firebasejs/12.8.0/firebase-auth.js";
import { iniciarCarrossel } from "./carousel.js";
import { versaoTermosActual, mostrarGateTermos, mostrarTermosLeitura } from "./termos.js"; // ← NOVO
 
(async () => {
  try {
    const snap = await getDocs(collection(db, "casos"));
    let total = 0,
      encontrados = 0;
    snap.forEach((d) => {
      total++;
      if (d.data().status === "encontrado") encontrados++;
    });
    const elTotal = document.getElementById("s-casos");
    const elEnc = document.getElementById("s-enc");
    if (elTotal) elTotal.textContent = total;
    if (elEnc) elEnc.textContent = encontrados;
  } catch (_) {
    /* silencioso — apenas decorativo */
  }
})();
 

// Prefixo de caminho: "" quando servido de WEB/, "WEB/" quando servido da raiz do repo
const _pathPrefix = /\/WEB(\/|$)/i.test(window.location.pathname) ? '' : 'WEB/';

// Estado global
let todosOsCasos = [];
let currentUser = null;
let mapaDesaparecidos = null; // instância do Google Map principal
let mapaForm = null; // instância do Google Map no formulário
let mapaFormMarker = null; // marcador arrastável no formulário
const comentariosAbertos = {};
const comentariosReplyingTo = {}; // { [casoId]: { id: commentId, author: authorName } }
let navAvatarUnsub = null;

// Coordenadas por província (Angola)
const COORDS_PROVINCIA = {
  luanda: { lat: -8.8368, lng: 13.2343 },
  benguela: { lat: -12.5763, lng: 13.4055 },
  huambo: { lat: -12.776, lng: 15.7388 },
  bié: { lat: -12.3764, lng: 17.0557 },
  cabinda: { lat: -5.55, lng: 12.2 },
  cuando_cubango: { lat: -16.93, lng: 19.8 },
  cuanza_norte: { lat: -9.2, lng: 14.7 },
  cuanza_sul: { lat: -10.9, lng: 14.3 },
  cunene: { lat: -16.9, lng: 15.8 },
  huíla: { lat: -14.92, lng: 13.5 },
  lunda_norte: { lat: -8.65, lng: 20.4 },
  lunda_sul: { lat: -10.0, lng: 21.0 },
  malanje: { lat: -9.54, lng: 16.34 },
  moxico: { lat: -11.86, lng: 19.92 },
  namibe: { lat: -15.1961, lng: 12.1522 },
  uíge: { lat: -7.61, lng: 15.06 },
  zaire: { lat: -6.1, lng: 12.85 },
};

// Estado de autenticação
onAuthStateChanged(auth, async (user) => {
  // Remover listener anterior, se existir
  if (typeof navAvatarUnsub === "function") {
    try {
      navAvatarUnsub();
    } catch (e) {
      /* ignore */
    }
    navAvatarUnsub = null;
  }

  currentUser = user;
  atualizarBotoesApoio();

  if (user) {
    // ← ADICIONA AQUI:
    if (user.emailVerified) {
      updateDoc(doc(db, "users", user.uid), { emailVerificado: true }).catch(() => {});
    }

    // Subscrever alterações em tempo real ao documento do user
    try {
      navAvatarUnsub = onSnapshot(
        doc(db, "users", user.uid),
        (snap) => {
          if (!snap.exists()) return;
          const data = snap.data();
          const src = data.photoBase64 || user.photoURL || "imgs/user.jpg";
          document.querySelectorAll(".nav-avatar").forEach((img) => {
            try {
              img.src = src;
            } catch (e) {
              /* ignore */
            }
          });

          // NOVO: detecção de suspensão em tempo real, equivalente ao
          // StreamBuilder do AuthCheck no mobile. Reaproveita este
          // listener já existente em vez de criar outro novo — chega em
          // directo assim que um admin suspender a conta, mesmo que o
          // utilizador já esteja a usar a app nesse momento.
          // NOVO: gate de Termos e Condições — vem ANTES da verificação de
          // suspensão de propósito, tal como no mobile: aceitar os termos
          // actuais é mais fundamental do que qualquer outro estado da
          // conta, incluindo estar suspenso.
          if (data.termosVersao !== versaoTermosActual) {
            mostrarGateTermos(db, user.uid, () => {
              // Depois de aceitar, o próprio onSnapshot volta a disparar
              // com o campo actualizado — não é preciso recarregar a página.
            });
            return;
          }

          const score = typeof data.trustScore === "number" ? data.trustScore : 100;
          const suspenso = data.isSuspended === true || score <= 0;
          if (suspenso && !window._avisoSuspensaoMostrado) {
            window._avisoSuspensaoMostrado = true;
            if (typeof window.mostrarSuporteSuspensao === "function") {
              window.mostrarSuporteSuspensao(user.uid, data);
            } else {
              showAlert(
                `A sua conta está suspensa. Motivo: ${data.suspensionReason || "violação das diretrizes"}. ` +
                `Para pedir revisão, contacte o suporte por email: suporte@missingao.co.ao`,
                { onOk: () => { navigateToTarget("index.html"); } },
              );
            }
          } else if (!suspenso) {
            window._avisoSuspensaoMostrado = false;
            document.getElementById("suporte-suspensao-overlay")?.remove();
          }

          // NOVO: mostra o botão de acesso ao painel admin no cabeçalho,
          // equivalente ao ícone condicional que já existe no mobile
          // (home_page.dart, _isAdmin). Fica escondido por defeito no
          // HTML — só aparece depois de confirmado o role.
          // DIAGNÓSTICO TEMPORÁRIO — remover depois de confirmar que
          // funciona. Ajuda a ver exactamente onde está a falhar.
          console.log("[admin-btn] onSnapshot disparado. role =", data.role);
          const btnAdmin = document.getElementById("btn-admin-panel");
          console.log("[admin-btn] elemento encontrado?", btnAdmin);
          if (btnAdmin) {
            btnAdmin.style.display = data.role === "admin" ? "" : "none";
            console.log("[admin-btn] display definido para:", btnAdmin.style.display);
          }
        },
        (err) => {
          console.warn("Erro no snapshot do avatar:", err);
        },
      );
    } catch (err) {
      // fallback: carregar uma vez
      try {
        await updateNavAvatar(user);
      } catch (_) {}
    }
  } else {
    document.querySelectorAll(".nav-avatar").forEach((img) => {
      try {
        img.src = "imgs/user.jpg";
      } catch (e) {
        /* ignore */
      }
    });
  }
});

// DOM ready
document.addEventListener("DOMContentLoaded", async function () {
  configurarNavegacaoModal();
  configurarLogicaMunicipios();
  configurarPreviewFoto();
  configurarLogicaDeficiencia();
  configurarFiltros();

  // Modal de detalhes do caso — fechar
  document
    .getElementById("casoDetalhesClose")
    ?.addEventListener("click", fecharDetalhesCaso);
  document
    .getElementById("casoDetalhesBackdrop")
    ?.addEventListener("click", fecharDetalhesCaso);

  try {
    await iniciarCarrossel();
  } catch (err) {
    console.warn("Carrossel:", err.message);
  }

  await carregarCasos();

  // Inicializar barra de busca (depois de carregar casos)
  if (typeof setupSearchBar === "function") setupSearchBar();
  if (typeof setupMobileUI === "function") setupMobileUI();

  document
    .getElementById("enviarRelato")
    ?.addEventListener("click", enviarRelato);

  // NOVO: link "Termos" no rodapé — versão só de leitura, disponível a
  // qualquer visitante, mesmo sem sessão iniciada (convidados incluídos).
  document
    .getElementById("footer-termos")
    ?.addEventListener("click", (e) => {
      e.preventDefault();
      mostrarTermosLeitura();
    });
});

/* =========================================================================
   GOOGLE MAPS — MAPA PRINCIPAL
   ========================================================================= */
function iniciarMapaPrincipal(casos) {
  const el = document.getElementById("mapa-desaparecidos");
  if (!el || typeof google === "undefined") return;

  // Criar mapa centrado em Angola
  if (!mapaDesaparecidos) {
    mapaDesaparecidos = new google.maps.Map(el, {
      center: { lat: -11.2027, lng: 17.8739 },
      zoom: 5,
      mapTypeControl: false,
      streetViewControl: false,
      fullscreenControl: true,
      styles: [
        {
          featureType: "poi",
          elementType: "labels",
          stylers: [{ visibility: "off" }],
        },
      ],
    });
  }

  // Limpar marcadores anteriores
  if (window._mapaMarkers) window._mapaMarkers.forEach((m) => m.setMap(null));
  window._mapaMarkers = [];

  const infoWindow = new google.maps.InfoWindow();

  casos.forEach((caso) => {
    // Obter coordenadas: do documento ou da tabela por província
    let lat = caso.lat ? parseFloat(caso.lat) : null;
    let lng = caso.lng ? parseFloat(caso.lng) : null;

    if (!lat || !lng) {
      const prov = (caso.provincia || "").toLowerCase().replace(/ /g, "_");
      const coords = COORDS_PROVINCIA[prov];
      if (!coords) return;
      // Dispersar aleatoriamente dentro da província (±0.3 graus)
      lat = coords.lat + (Math.random() - 0.5) * 0.6;
      lng = coords.lng + (Math.random() - 0.5) * 0.6;
    }

    // Cor do marcador por status
    const corStatus =
      {
        aprovado: "#0c7ab5",
        encontrado: "#2ecc71",
        desmentido: "#95a5a6",
      }[caso.status] || "#0c7ab5";

    const marker = new google.maps.Marker({
      position: { lat, lng },
      map: mapaDesaparecidos,
      title: caso.nome || "Desconhecido",
      icon: {
        path: google.maps.SymbolPath.CIRCLE,
        scale: 9,
        fillColor: corStatus,
        fillOpacity: 0.9,
        strokeColor: "#ffffff",
        strokeWeight: 2,
      },
    });
    marker.casoId = caso.id; // referência para abrirCasoNoMapa()

    const dias = calcularDias(caso.data_desaparecimento);
    const tempo = dias === 0 ? "hoje" : `há ${dias} dias`;
    const img = caso.imagem
      ? `<img src="${caso.imagem}" style="width:100%;height:80px;object-fit:cover;border-radius:6px;margin-bottom:8px;">`
      : "";

    marker.addListener("click", () => {
      infoWindow.setContent(`
        <div style="font-family:'Quicksand',sans-serif;max-width:200px;">
          ${img}
          <strong style="font-size:14px;">${caso.nome || "—"}</strong><br>
          <span style="color:#666;font-size:12px;">${caso.idade || "?"}  anos • ${caso.municipio || caso.provincia || "Angola"}</span><br>
          <span style="color:#888;font-size:11px;">Desapareceu ${tempo}</span>
        </div>`);
      infoWindow.open(mapaDesaparecidos, marker);
    });

    window._mapaMarkers.push(marker);
  });

  // Atualizar contagem
  const contEl = document.getElementById("mapa-contagem");
  if (contEl)
    contEl.innerText = `${window._mapaMarkers.length} caso${window._mapaMarkers.length !== 1 ? "s" : ""}`;
}

/* =========================================================================
   GOOGLE MAPS — MAPA NO FORMULÁRIO (picker de localização)
   ========================================================================= */
function iniciarMapaForm() {
  const el = document.getElementById("mapa-form");
  if (!el || typeof google === "undefined" || mapaForm) return;

  mapaForm = new google.maps.Map(el, {
    center: { lat: -8.8368, lng: 13.2343 }, // Luanda por padrão
    zoom: 12,
    mapTypeControl: false,
    streetViewControl: false,
    fullscreenControl: false,
  });

  const geocoder = new google.maps.Geocoder();

  mapaForm.addListener("click", (e) => {
    const pos = e.latLng;

    // Move ou cria marcador
    if (mapaFormMarker) {
      mapaFormMarker.setPosition(pos);
    } else {
      mapaFormMarker = new google.maps.Marker({
        position: pos,
        map: mapaForm,
        draggable: true,
        animation: google.maps.Animation.DROP,
        icon: {
          url: "https://maps.google.com/mapfiles/ms/icons/red-dot.png",
        },
      });
      mapaFormMarker.addListener("dragend", (ev) => {
        atualizarCoordsForm(ev.latLng, geocoder);
      });
    }

    atualizarCoordsForm(pos, geocoder);
  });

  // Botão limpar
  document.getElementById("mapa-form-limpar")?.addEventListener("click", () => {
    if (mapaFormMarker) {
      mapaFormMarker.setMap(null);
      mapaFormMarker = null;
    }
    document.getElementById("lat_relatar").value = "";
    document.getElementById("lng_relatar").value = "";
    document.getElementById("mapa-form-coords").style.display = "none";
  });

  // Quando a província muda no formulário, centrar o mapa nela
  document
    .getElementById("provincia_relatar")
    ?.addEventListener("change", function () {
      const prov = this.value.toLowerCase().replace(/ /g, "_");
      const coords = COORDS_PROVINCIA[prov];
      if (coords && mapaForm) {
        mapaForm.setCenter(coords);
        mapaForm.setZoom(10);
      }
    });
}

function atualizarCoordsForm(latLng, geocoder) {
  const lat = latLng.lat().toFixed(6);
  const lng = latLng.lng().toFixed(6);

  document.getElementById("lat_relatar").value = lat;
  document.getElementById("lng_relatar").value = lng;

  const coordsDiv = document.getElementById("mapa-form-coords");
  const addrEl = document.getElementById("mapa-form-addr");

  coordsDiv.style.display = "flex";
  if (addrEl) addrEl.innerText = `Lat: ${lat}, Lng: ${lng}`;

  // Geocodificação reversa para mostrar nome do local
  geocoder.geocode(
    { location: { lat: parseFloat(lat), lng: parseFloat(lng) } },
    (results, status) => {
      if (status === "OK" && results[0]) {
        const addr = results[0].formatted_address;
        if (addrEl) addrEl.innerText = addr;
        // Pré-preencher campo de último local se estiver vazio
        const ultimoLocalInput = document.getElementById("ultimo_local_input");
        if (ultimoLocalInput && !ultimoLocalInput.value) {
          ultimoLocalInput.value = addr.split(",")[0]; // primeiro componente
        }
      }
    },
  );
}

/* =========================================================================
   1. CARREGAR E EXIBIR CASOS (FEED)
   ========================================================================= */
function mostrarSkeletons(container, n = 3) {
  container.innerHTML = "";
  for (let i = 0; i < n; i++) {
    container.insertAdjacentHTML(
      "beforeend",
      `
      <div class="feed-card-skeleton">
        <div class="sk-header">
          <div class="skeleton sk-avatar"></div>
          <div class="sk-header-text">
            <div class="skeleton sk-line-name"></div>
            <div class="skeleton sk-line-sub"></div>
          </div>
        </div>
        <div class="skeleton sk-image"></div>
        <div class="sk-body">
          <div class="skeleton sk-title"></div>
          <div class="skeleton sk-text-long"></div>
          <div class="skeleton sk-text-med"></div>
          <div class="skeleton sk-text-short"></div>
          <div class="sk-actions">
            <div class="skeleton sk-btn"></div>
            <div class="skeleton sk-btn"></div>
            <div class="skeleton sk-btn"></div>
          </div>
        </div>
      </div>`,
    );
  }
}

async function carregarCasos() {
  const container = document.querySelector(".casos_main");
  mostrarSkeletons(container, 3);

  try {
    const snap = await getDocs(query(collection(db, "casos")));
    todosOsCasos = [];
    snap.forEach((d) => {
      const data = { id: d.id, ...d.data() };
      if (
        data.status &&
        data.status !== "pendente" &&
        data.status !== "rejeitado"
      ) {
        todosOsCasos.push(data);
      }
    });

    renderizarCasos(todosOsCasos);
    atualizarContadorResultados(todosOsCasos.length);

    // Iniciar mapa após carregar casos (Google Maps pode ainda não estar pronto)
    aguardarGoogleMapsEIniciar();
  } catch (err) {
    console.error("Erro ao carregar casos:", err);
    container.innerHTML = `<p style="padding:20px;color:#e74c3c;font-family:var(--font-base);">
      Erro ao carregar casos.</p>`;
  }
}

// Aguarda a API do Google Maps estar disponível (script com defer)
function aguardarGoogleMapsEIniciar() {
  if (typeof google !== "undefined") {
    iniciarMapaPrincipal(todosOsCasos);
  } else {
    setTimeout(aguardarGoogleMapsEIniciar, 300);
  }
}

function renderizarCasos(lista) {
  const container = document.querySelector(".casos_main");
  container.innerHTML = "";

  if (lista.length === 0) {
    container.innerHTML = `
      <div class="feed-vazio">
        <i class="fa-solid fa-magnifying-glass"></i>
        <p>Nenhum caso encontrado com estes filtros.</p>
        <button onclick="window.limparFiltros()" class="btn-limpar-inline">Limpar filtros</button>
      </div>`;
    return;
  }

  lista.forEach((caso) => {
    const dias = calcularDias(caso.data_desaparecimento);
    const textoTempo = dias === 0 ? "Hoje" : `Há ${dias} dias`;
    const statusTexto =
      caso.status === "aprovado" ? "Ativo" : caso.status || "";
    const apoiosCount = caso.apoios || 0;
    const comentCount = caso.comentarios || 0;
    const jaApoiou =
      currentUser &&
      Array.isArray(caso.apoiadoPor) &&
      caso.apoiadoPor.includes(currentUser.uid);

    const div = document.createElement("div");
    div.className = "feed-card";
    div.dataset.id = caso.id;

    div.innerHTML = `
      <div class="card-header">
        <img src="${caso.imagem || "imgs/user.jpg"}" class="avatar-small" alt="Avatar" onerror="this.src='imgs/user.jpg'">
        <div class="header-info">
          <h4>${caso.nome || "Nome Desconhecido"}</h4>
          <span>${caso.idade || "?"} anos • ${caso.municipio || "Angola"}</span>
        </div>
        <div style="margin-left:auto;display:flex;align-items:center;gap:6px;">
          <span class="status-badge status-${caso.status}">${statusTexto}</span>
          <button class="btn-card-menu" data-id="${caso.id}" title="Mais opções">
            <i class="fa-solid fa-ellipsis-vertical"></i>
          </button>
        </div>
      </div>
       <img src="${caso.imagem || "imgs/user.jpg"}" class="card-main-image"
         alt="Foto" onerror="this.src='imgs/user.jpg'">
      <div class="card-body">
        <h3 class="card-title">${caso.nome}</h3>
        <div class="card-details">
          <strong>Último local visto:</strong> ${caso.ultimo_local || "Não informado"}<br>
          <span class="time-badge"><i class="fa-regular fa-clock"></i> ${textoTempo}</span>
        </div>
        <p class="card-details" style="margin-top:10px;">
          Desapareceu em ${caso.provincia || "Local incerto"}.
          ${caso.roupas ? `Vestia: ${caso.roupas}.` : ""}
          ${caso.informacoes_adicionais || ""}
        </p>
        <div class="card-counters">
          <span class="counter-item">
            <i class="fa-solid fa-heart" style="color:#e74c3c;"></i>
            <span id="apoios-count-${caso.id}">${apoiosCount}</span> apoios
          </span>
          <span class="counter-item">
            <i class="fa-regular fa-comment" style="color:#0c7ab5;"></i>
            <span id="comentarios-count-${caso.id}">${comentCount}</span> comentários
          </span>
        </div>
        <div class="card-actions">
          <button class="btn-action btn-apoiar ${jaApoiou ? "apoiado" : ""}" data-id="${caso.id}">
            <i class="fa-${jaApoiou ? "solid" : "regular"} fa-heart"></i>
            ${jaApoiou ? "Apoiando" : "Apoiar"}
          </button>
          <button class="btn-action btn-comentar" data-id="${caso.id}">
            <i class="fa-regular fa-comment"></i> Comentar
          </button>
          <button class="btn-action btn-partilhar" data-id="${caso.id}"
                  data-nome="${caso.nome}" data-provincia="${caso.provincia || ""}">
            <i class="fa-solid fa-share-nodes"></i> Partilhar
          </button>
        </div>
        <div class="comments-section" id="comments-${caso.id}" style="display:none;">
          <div class="comments-loading" id="loading-${caso.id}">
            <i class="fa-solid fa-spinner fa-spin"></i> Carregando comentários...
          </div>
          <div class="comments-list" id="comments-list-${caso.id}"></div>
          <div class="comment-input-row">
              <img src="imgs/user.jpg" class="comment-avatar"
                id="comment-avatar-${caso.id}" onerror="this.src='imgs/user.jpg'">
            <input type="text" class="comment-input"
                   id="comment-input-${caso.id}" placeholder="Escreva um comentário...">
            <button class="btn-send-comment" data-id="${caso.id}">
              <i class="fa-solid fa-paper-plane"></i>
            </button>
          </div>
        </div>
      </div>`;

    container.appendChild(div);
  });

  registarEventosBotoes();
}

function atualizarBotoesApoio() {
  document.querySelectorAll(".btn-apoiar").forEach((btn) => {
    const caso = todosOsCasos.find((c) => c.id === btn.dataset.id);
    if (!caso) return;
    const jaApoiou =
      currentUser &&
      Array.isArray(caso.apoiadoPor) &&
      caso.apoiadoPor.includes(currentUser.uid);
    btn.className = `btn-action btn-apoiar ${jaApoiou ? "apoiado" : ""}`;
    btn.innerHTML = `<i class="fa-${jaApoiou ? "solid" : "regular"} fa-heart"></i> ${jaApoiou ? "Apoiando" : "Apoiar"}`;
  });
}

function registarEventosBotoes() {
  document
    .querySelectorAll(".btn-apoiar")
    .forEach((btn) =>
      btn.addEventListener("click", () => toggleApoio(btn.dataset.id, btn)),
    );
  document
    .querySelectorAll(".btn-comentar")
    .forEach((btn) =>
      btn.addEventListener("click", () => toggleComentarios(btn.dataset.id)),
    );
  document
    .querySelectorAll(".btn-partilhar")
    .forEach((btn) =>
      btn.addEventListener("click", () =>
        partilharCaso(btn.dataset.id, btn.dataset.nome, btn.dataset.provincia),
      ),
    );
  document
    .querySelectorAll(".btn-send-comment")
    .forEach((btn) =>
      btn.addEventListener("click", () => enviarComentario(btn.dataset.id)),
    );
  document.querySelectorAll(".comment-input").forEach((input) =>
    input.addEventListener("keydown", (e) => {
      if (e.key === "Enter" && !e.shiftKey) {
        e.preventDefault();
        enviarComentario(input.id.replace("comment-input-", ""));
      }
    }),
  );
  document.querySelectorAll(".btn-card-menu").forEach((btn) =>
    btn.addEventListener("click", (e) => {
      e.stopPropagation();
      abrirMenuCard(btn.dataset.id, btn);
    }),
  );
}

/* =========================================================================
   MENU DE OPÇÕES DO CARD — Ver detalhes / Ver no mapa
   ========================================================================= */
function abrirMenuCard(casoId, btnEl) {
  const popover = document.getElementById("cardMenuPopover");
  const backdrop = document.getElementById("cardMenuBackdrop");
  const btnDetalhes = document.getElementById("cardMenuDetalhes");
  const btnMapa = document.getElementById("cardMenuMapa");
  if (!popover || !backdrop) return;

  // Posicionar o popover por baixo do botão clicado
  const rect = btnEl.getBoundingClientRect();
  const popW = 220;
  let left = rect.right - popW;
  if (left < 8) left = 8;
  popover.style.top = `${rect.bottom + window.scrollY + 6}px`;
  popover.style.left = `${left + window.scrollX}px`;

  popover.classList.remove("hidden");
  backdrop.classList.remove("hidden");

  const fechar = () => {
    popover.classList.add("hidden");
    backdrop.classList.add("hidden");
  };
  backdrop.onclick = fechar;

  btnDetalhes.onclick = () => {
    fechar();
    abrirDetalhesCaso(casoId);
  };
  btnMapa.onclick = () => {
    fechar();
    abrirCasoNoMapa(casoId);
  };
}

/* =========================================================================
   MODAL — VER MAIS DETALHES (com perfil de quem relatou)
   ========================================================================= */
async function abrirDetalhesCaso(casoId) {
  const caso = todosOsCasos.find((c) => c.id === casoId);
  if (!caso) return;

  const overlay = document.getElementById("casoDetalhesOverlay");
  const body = document.getElementById("casoDetalhesBody");
  if (!overlay || !body) return;

  const dias = calcularDias(caso.data_desaparecimento);
  const tempo = dias === 0 ? "Hoje" : `Há ${dias} dias`;

  // Estado de carregamento enquanto busca o perfil de quem relatou
  body.innerHTML = `
    <img src="${caso.imagem || "imgs/user.jpg"}" class="cd-foto" onerror="this.src='imgs/user.jpg'">
    <div class="cd-content">
      <h2 class="cd-nome">${caso.nome || "Nome desconhecido"}</h2>
      <span class="status-badge status-${caso.status}">${caso.status === "aprovado" ? "Ativo" : caso.status || ""}</span>

      <div class="cd-grid">
        <div class="cd-item"><span>Idade</span><strong>${caso.idade || "—"}</strong></div>
        <div class="cd-item"><span>Sexo</span><strong>${caso.sexo || "—"}</strong></div>
        <div class="cd-item"><span>Altura</span><strong>${caso.altura || "—"}</strong></div>
        <div class="cd-item"><span>Desaparecido</span><strong>${tempo}</strong></div>
      </div>

      <div class="cd-section">
        <h4><i class="fa-solid fa-location-dot"></i> Localização</h4>
        <p>${caso.ultimo_local || "Não informado"} — ${caso.municipio ? caso.municipio + ", " : ""}${caso.provincia || "Angola"}</p>
      </div>

      ${
        caso.roupas
          ? `
      <div class="cd-section">
        <h4><i class="fa-solid fa-shirt"></i> Vestimenta</h4>
        <p>${caso.roupas}</p>
      </div>`
          : ""
      }
      ${
        caso.tipo_deficiencia
          ? `
      <div class="cd-section">
        <h4><i class="fa-solid fa-wheelchair"></i> Deficiência</h4>
        <p>${caso.tipo_deficiencia}</p>
      </div>`
          : ""
      }

      ${
        caso.informacoes_adicionais
          ? `
      <div class="cd-section">
        <h4><i class="fa-solid fa-circle-info"></i> Informações adicionais</h4>
        <p>${caso.informacoes_adicionais}</p>
      </div>`
          : ""
      }

      <div class="cd-section cd-relator" id="cd-relator-box">
        <h4><i class="fa-solid fa-user-pen"></i> Relatado por</h4>
        <div class="cd-relator-loading">
          <i class="fa-solid fa-spinner fa-spin"></i> A carregar...
        </div>
      </div>
    </div>`;

  overlay.classList.remove("hidden");

  // Buscar perfil de quem relatou (assíncrono, não bloqueia abertura do modal)
  const relatorBox = document.getElementById("cd-relator-box");
  if (!caso.userId) {
    relatorBox.innerHTML = `<h4><i class="fa-solid fa-user-pen"></i> Relatado por</h4><p style="color:#999;font-size:13px;">Informação não disponível.</p>`;
    return;
  }
  try {
    const uSnap = await getDoc(doc(db, "users", caso.userId));
    if (!uSnap.exists()) {
      relatorBox.innerHTML = `<h4><i class="fa-solid fa-user-pen"></i> Relatado por</h4><p style="color:#999;font-size:13px;">Utilizador não encontrado.</p>`;
      return;
    }
    const u = uSnap.data();
    relatorBox.innerHTML = `
      <h4><i class="fa-solid fa-user-pen"></i> Relatado por</h4>
      <a href="${_pathPrefix}profile.html?uid=${caso.userId}" class="cd-relator-card" target="_blank">
        ${
          u.photoBase64
            ? `<img src="${u.photoBase64}" class="cd-relator-avatar" alt="">`
            : `<div class="cd-relator-avatar-ph"><i class="fa-solid fa-user"></i></div>`
        }
        <div class="cd-relator-info">
          <strong>${u.nome || "Utilizador"}</strong>
          <span>Visitar perfil <i class="fa-solid fa-arrow-right"></i></span>
        </div>
      </a>`;
  } catch (err) {
    relatorBox.innerHTML = `<h4><i class="fa-solid fa-user-pen"></i> Relatado por</h4><p style="color:#999;font-size:13px;">Erro ao carregar perfil.</p>`;
  }
}

function fecharDetalhesCaso() {
  document.getElementById("casoDetalhesOverlay")?.classList.add("hidden");
}

/* =========================================================================
   ABRIR CASO NO MAPA
   ========================================================================= */
function abrirCasoNoMapa(casoId) {
  const sectionMap = document.querySelector(".section_map");
  const isMobileView = window.innerWidth <= 900;

  const focar = () => {
    if (typeof google === "undefined" || !window._mapaMarkers) return;
    const marker = window._mapaMarkers.find((m) => m.casoId === casoId);
    if (!marker || !mapaDesaparecidos) return;
    mapaDesaparecidos.panTo(marker.getPosition());
    mapaDesaparecidos.setZoom(12);
    google.maps.event.trigger(marker, "click");
    marker.setAnimation(google.maps.Animation.BOUNCE);
    setTimeout(() => marker.setAnimation(null), 1400);
  };

  if (isMobileView && sectionMap) {
    // Abrir overlay do mapa em mobile
    sectionMap.classList.add("mobile-active", "show-map");
    sectionMap.classList.remove("show-filters");
    setTimeout(() => {
      iniciarMapaPrincipal(todosOsCasos);
      setTimeout(focar, 350);
    }, 100);
  } else {
    // Desktop: scroll até o mapa e focar
    document
      .getElementById("mapa-desaparecidos")
      ?.scrollIntoView({ behavior: "smooth", block: "center" });
    setTimeout(focar, 400);
  }
}

/* =========================================================================
   2. APOIAR
   ========================================================================= */
async function toggleApoio(casoId, btn) {
  if (!currentUser) {
    showAlert("Faça login para apoiar um caso.", {
      onOk: () => navigateToLogin(),
    });
    return;
  }
  btn.disabled = true;
  try {
    const casoRef = doc(db, "casos", casoId);
    const casoSnap = await getDoc(casoRef);
    if (!casoSnap.exists()) return;
    const apoiadoPor = casoSnap.data().apoiadoPor || [];
    const jaApoiou = apoiadoPor.includes(currentUser.uid);
    if (jaApoiou) {
      await updateDoc(casoRef, {
        apoiadoPor: arrayRemove(currentUser.uid),
        apoios: increment(-1),
      });
      btn.classList.remove("apoiado");
      btn.innerHTML = `<i class="fa-regular fa-heart"></i> Apoiar`;
      const local = todosOsCasos.find((c) => c.id === casoId);
      if (local) {
        local.apoiadoPor = local.apoiadoPor.filter(
          (u) => u !== currentUser.uid,
        );
        local.apoios = Math.max(0, (local.apoios || 0) - 1);
      }
    } else {
      await updateDoc(casoRef, {
        apoiadoPor: arrayUnion(currentUser.uid),
        apoios: increment(1),
      });
      btn.classList.add("apoiado");
      btn.innerHTML = `<i class="fa-solid fa-heart"></i> Apoiando`;
      const local = todosOsCasos.find((c) => c.id === casoId);
      if (local) {
        if (!local.apoiadoPor) local.apoiadoPor = [];
        local.apoiadoPor.push(currentUser.uid);
        local.apoios = (local.apoios || 0) + 1;
      }
      // Rastrear stats do utilizador para emblemas
      await incrementarStatUser("apoios");
    }
    const countEl = document.getElementById(`apoios-count-${casoId}`);
    const local = todosOsCasos.find((c) => c.id === casoId);
    if (countEl && local) countEl.innerText = local.apoios || 0;
  } catch (err) {
    console.error("Erro ao apoiar:", err);
    showAlert("Erro ao processar apoio.");
  } finally {
    btn.disabled = false;
  }
}

/* =========================================================================
   3. COMENTÁRIOS
   ========================================================================= */
async function toggleComentarios(casoId) {
  const section = document.getElementById(`comments-${casoId}`);
  if (!section) return;
  const aberto = comentariosAbertos[casoId];
  if (aberto) {
    section.style.display = "none";
    comentariosAbertos[casoId] = false;
  } else {
    section.style.display = "block";
    comentariosAbertos[casoId] = true;
    await carregarComentarios(casoId);
    if (currentUser) {
      try {
        const uSnap = await getDoc(doc(db, "users", currentUser.uid));
        if (uSnap.exists() && uSnap.data().photoBase64) {
          const av = document.getElementById(`comment-avatar-${casoId}`);
          if (av) av.src = uSnap.data().photoBase64;
        }
      } catch (_) {}
    }
    document.getElementById(`comment-input-${casoId}`)?.focus();
  }
}

async function carregarComentarios(casoId) {
  const loadingEl = document.getElementById(`loading-${casoId}`);
  const listEl = document.getElementById(`comments-list-${casoId}`);
  if (!listEl) return;
  if (loadingEl) loadingEl.style.display = "flex";
  try {
    const q = query(
      collection(db, "casos", casoId, "comentarios"),
      orderBy("criadoEm", "asc"),
    );
    const snap = await getDocs(q);
    if (loadingEl) loadingEl.style.display = "none";
    listEl.innerHTML = "";
    if (snap.empty) {
      listEl.innerHTML = `<p class="no-comments">Seja o primeiro a comentar!</p>`;
      return;
    }

    // Construir árvore de comentários (suporta replies via parentId)
    const items = [];
    snap.forEach((d) => items.push({ id: d.id, ...d.data() }));
    const map = {};
    items.forEach((it) => (map[it.id] = { ...it, id: it.id, children: [] }));
    const roots = [];
    items.forEach((it) => {
      const node = map[it.id];
      if (it.parentId && map[it.parentId]) {
        map[it.parentId].children.push(node);
      } else {
        roots.push(node);
      }
    });

    function pad(n) {
      return String(n).padStart(2, "0");
    }

    function renderNode(node, depth = 0) {
      const dt = node.criadoEm?.toDate ? node.criadoEm.toDate() : new Date();
      const ts = `${pad(dt.getHours())}:${pad(dt.getMinutes())} · ${dt.getDate()}/${dt.getMonth() + 1}`;
      const isAuthor = currentUser && node.autorId === currentUser.uid;
      const parentName =
        node.parentId && map[node.parentId]
          ? map[node.parentId].autorNome
          : null;

      const el = document.createElement("div");
      el.className = `comment-item${depth > 0 ? " comment-reply" : ""}`;
      el.dataset.commentId = node.id;
      el.innerHTML = `
        <a href="${_pathPrefix}profile.html?uid=${node.autorId}" class="comment-avatar-link" title="Ver perfil">
          <img src="${node.autorFoto || "imgs/user.jpg"}" class="comment-avatar" onerror="this.src='imgs/user.jpg'">
        </a>
        <div class="comment-bubble">
          <div class="comment-header">
            <a href="${_pathPrefix}profile.html?uid=${node.autorId}" class="comment-author-link">
              <span class="comment-author">${node.autorNome || "Utilizador"}</span>
            </a>
            <div style="margin-left:auto;display:flex;gap:6px;align-items:center;">
              <button class="btn-reply" data-comment="${node.id}" data-author="${encodeURIComponent(node.autorNome || "Utilizador")}" title="Responder">
                <i class="fa-solid fa-reply"></i>
              </button>
              ${isAuthor ? `<button class="btn-delete-comment" data-caso="${casoId}" data-comentario="${node.id}" title="Apagar comentário"><i class="fa-solid fa-trash-can"></i></button>` : ""}
            </div>
          </div>
          ${node.parentId && parentName ? `<div class="comment-reply-to">Resposta a <a href=\"${_pathPrefix}profile.html?uid=${map[node.parentId].autorId}\">${escapeHtml(parentName)}</a></div>` : node.parentId && !parentName ? `<div class="comment-reply-to">Resposta a comentário removido</div>` : ""}
          <p class="comment-text">${escapeHtml(node.texto)}</p>
          <span class="comment-time">${ts}</span>
        </div>`;

      listEl.appendChild(el);

      if (node.children && node.children.length) {
        node.children.forEach((c) => renderNode(c, depth + 1));
      }
    }

    roots.forEach((r) => renderNode(r, 0));

    // Eventos: reply
    listEl.querySelectorAll(".btn-reply").forEach((btn) => {
      btn.addEventListener("click", (e) => {
        const commentId = btn.dataset.comment;
        const author = btn.dataset.author
          ? decodeURIComponent(btn.dataset.author)
          : "Utilizador";
        setReplyTo(casoId, commentId, author);
      });
    });

    // Eventos de apagar comentário (com cascade)
    listEl.querySelectorAll(".btn-delete-comment").forEach((btn) => {
      btn.addEventListener("click", async () => {
        if (!confirm("Apagar este comentário?")) return;
        try {
          const deleted = await apagarComentario(
            btn.dataset.caso,
            btn.dataset.comentario,
          );
        } catch (err) {
          console.error(err);
          showAlert("Erro ao apagar comentário.");
        }
        await carregarComentarios(casoId);
      });
    });

    // Scroll para fim
    listEl.scrollTop = listEl.scrollHeight;
  } catch (err) {
    if (loadingEl) loadingEl.style.display = "none";
    if (listEl)
      listEl.innerHTML = `<p class="no-comments" style="color:#e74c3c;">Erro ao carregar.</p>`;
  }
}

function setReplyTo(casoId, commentId, author) {
  comentariosReplyingTo[casoId] = { id: commentId, author };
  const section = document.getElementById(`comments-${casoId}`);
  if (!section) return;
  // Mostrar barra de "respondendo a"
  let row = section.querySelector(".comment-input-row");
  if (!row) return;
  let bar = section.querySelector(".replying-to");
  if (!bar) {
    bar = document.createElement("div");
    bar.className = "replying-to";
    row.parentNode.insertBefore(bar, row);
  }
  bar.innerHTML = `Respondendo a <strong>${escapeHtml(author)}</strong> <button class="cancel-reply" title="Cancelar resposta">×</button>`;
  bar
    .querySelector(".cancel-reply")
    .addEventListener("click", () => clearReplyTo(casoId));
  const input = document.getElementById(`comment-input-${casoId}`);
  if (input) input.focus();
}

function clearReplyTo(casoId) {
  delete comentariosReplyingTo[casoId];
  const section = document.getElementById(`comments-${casoId}`);
  if (!section) return;
  const bar = section.querySelector(".replying-to");
  if (bar) bar.remove();
}

async function enviarComentario(casoId) {
  if (!currentUser) {
    showAlert("Faça login para comentar.", { onOk: () => navigateToLogin() });
    return;
  }
  const inputEl = document.getElementById(`comment-input-${casoId}`);
  if (!inputEl) return;
  const texto = inputEl.value.trim();
  if (!texto) return;
  const btnSend = document.querySelector(
    `.btn-send-comment[data-id="${casoId}"]`,
  );
  if (btnSend) {
    btnSend.disabled = true;
    btnSend.innerHTML = `<i class="fa-solid fa-spinner fa-spin"></i>`;
  }
  try {
    const uSnap = await getDoc(doc(db, "users", currentUser.uid));
    const userData = uSnap.exists() ? uSnap.data() : {};
    const parentId = comentariosReplyingTo[casoId]?.id || null;
    await addDoc(collection(db, "casos", casoId, "comentarios"), {
      texto,
      parentId,
      autorId: currentUser.uid,
      autorNome: userData.nome || "Utilizador",
      autorFoto: userData.photoBase64 || "",
      criadoEm: serverTimestamp(),
    });
    await updateDoc(doc(db, "casos", casoId), { comentarios: increment(1) });
    const local = todosOsCasos.find((c) => c.id === casoId);
    if (local) local.comentarios = (local.comentarios || 0) + 1;
    // Rastrear stats do utilizador para emblemas
    await incrementarStatUser("comentarios");
    const countEl = document.getElementById(`comentarios-count-${casoId}`);
    if (countEl && local) countEl.innerText = local.comentarios;
    inputEl.value = "";
    clearReplyTo(casoId);
    await carregarComentarios(casoId);
  } catch (err) {
    console.error("Erro ao comentar:", err);
    showAlert("Erro ao enviar comentário.");
  } finally {
    if (btnSend) {
      btnSend.disabled = false;
      btnSend.innerHTML = `<i class="fa-solid fa-paper-plane"></i>`;
    }
  }
}

/* =========================================================================
   4. PARTILHAR
   ========================================================================= */
async function partilharCaso(casoId, nome, provincia) {
  const url = `${window.location.origin}${window.location.pathname}?caso=${casoId}`;
  const text = `${nome} desapareceu em ${provincia || "Angola"}. Partilhe para ajudar! Missing AO.`;
  if (navigator.share) {
    try {
      await navigator.share({ title: `🔍 ${nome}`, text, url });
      if (currentUser) await incrementarStatUser("partilhas");
      return;
    } catch (_) {}
  }
  navigator.clipboard
    .writeText(url)
    .then(async () => {
      showAlert("✅ Link copiado!");
      if (currentUser) await incrementarStatUser("partilhas");
    })
    .catch(() => showAlert(`Partilhe:\n${url}`));
}

/* =========================================================================
   5. FILTROS — todos funcionais
   ========================================================================= */
function configurarFiltros() {
  document
    .querySelector(".caracter button[data-action='aplicar']")
    ?.addEventListener("click", aplicarFiltros);
  document
    .querySelector(".caracter button[data-action='limpar']")
    ?.addEventListener("click", window.limparFiltros);

  // Filtro em tempo real ao mudar qualquer select
  [
    "provincia",
    "municipio",
    "sexo",
    "faixaEtaria",
    "periodo",
    "status-filtro",
  ].forEach((id) =>
    document.getElementById(id)?.addEventListener("change", aplicarFiltros),
  );

  // Deficiência (checkbox)
  document
    .getElementById("com_deficiencia")
    ?.addEventListener("change", aplicarFiltros);
}

function aplicarFiltros() {
  const provincia = document.getElementById("provincia")?.value || "";
  const municipio = document.getElementById("municipio")?.value || "";
  const sexo = document.getElementById("sexo")?.value || "";
  const faixaEtaria = document.getElementById("faixaEtaria")?.value || "";
  const periodo = document.getElementById("periodo")?.value || "";
  const status = document.getElementById("status-filtro")?.value || "";
  const comDeficiencia =
    document.getElementById("com_deficiencia")?.checked || false;

  const agora = new Date();

  const filtrados = todosOsCasos.filter((caso) => {
    // Província
    if (provincia && (caso.provincia || "").toLowerCase() !== provincia)
      return false;
    // Município
    if (
      municipio &&
      (caso.municipio || "").toLowerCase().replace(/ /g, "_") !== municipio
    )
      return false;
    // Sexo
    if (sexo && caso.sexo !== sexo) return false;

    // Faixa etária — a partir do campo "idade"
    if (faixaEtaria) {
      const idadeNum = parseInt(caso.idade) || 0;
      if (faixaEtaria === "crianca" && !(idadeNum >= 0 && idadeNum <= 12))
        return false;
      if (faixaEtaria === "adolescente" && !(idadeNum >= 13 && idadeNum <= 17))
        return false;
      if (faixaEtaria === "adulto" && !(idadeNum >= 18 && idadeNum <= 59))
        return false;
      if (faixaEtaria === "idoso" && !(idadeNum >= 60)) return false;
    }

    // Período — tempo desde o desaparecimento
    if (periodo && caso.data_desaparecimento) {
      const dataCaso = new Date(caso.data_desaparecimento);
      if (!isNaN(dataCaso)) {
        const diasDiff = Math.floor((agora - dataCaso) / 86400000);
        if (periodo === "24h" && diasDiff > 1) return false;
        if (periodo === "7d" && diasDiff > 7) return false;
        if (periodo === "30d" && diasDiff > 30) return false;
        if (periodo === "mais30" && diasDiff <= 30) return false;
      }
    }

    // Status
    if (status) {
      if (status === "ativo" && caso.status !== "aprovado") return false;
      if (status === "encontrado" && caso.status !== "encontrado") return false;
      if (status === "desmentido" && caso.status !== "desmentido") return false;
    }

    // Deficiência
    if (comDeficiencia && caso.deficiencia !== "sim") return false;

    return true;
  });

  renderizarCasos(filtrados);
  atualizarContadorResultados(filtrados.length);
  destacarFiltrosAtivos();

  // Actualizar mapa com casos filtrados
  if (typeof google !== "undefined") iniciarMapaPrincipal(filtrados);
}

window.limparFiltros = function () {
  [
    "provincia",
    "municipio",
    "sexo",
    "faixaEtaria",
    "periodo",
    "status-filtro",
  ].forEach((id) => {
    const el = document.getElementById(id);
    if (el) el.value = "";
  });
  const chk = document.getElementById("com_deficiencia");
  if (chk) chk.checked = false;
  const munField = document.getElementById("municipio-field");
  if (munField) munField.style.display = "none";
  renderizarCasos(todosOsCasos);
  atualizarContadorResultados(todosOsCasos.length);
  destacarFiltrosAtivos();
  if (typeof google !== "undefined") iniciarMapaPrincipal(todosOsCasos);
};

function atualizarContadorResultados(n) {
  const el = document.getElementById("resultado-count");
  if (!el) return;
  el.textContent =
    n === 0
      ? "Sem resultados"
      : `${n} caso${n !== 1 ? "s" : ""} encontrado${n !== 1 ? "s" : ""}`;
}

function destacarFiltrosAtivos() {
  const ids = [
    "provincia",
    "municipio",
    "sexo",
    "faixaEtaria",
    "periodo",
    "status-filtro",
  ];
  const checkId = "com_deficiencia";
  const temAtivo =
    ids.some((id) => {
      const el = document.getElementById(id);
      return el && el.value;
    }) ||
    document.getElementById(checkId)?.checked ||
    false;
  const btnLimpar = document.querySelector(
    ".caracter button[data-action='limpar']",
  );
  const btnAplicar = document.querySelector(
    ".caracter button[data-action='aplicar']",
  );
  if (btnLimpar) btnLimpar.style.display = temAtivo ? "block" : "none";
  if (btnAplicar) btnAplicar.classList.toggle("filtro-ativo", temAtivo);
}

/* =========================================================================
   6. ENVIAR RELATO
   ========================================================================= */
async function enviarRelato() {
  const user = auth.currentUser;
  if (!user) {
    showAlert("Você precisa estar logado para relatar um caso.", {
      onOk: () => navigateToLogin(),
    });
    return;
  }

  // NOVO: verificação defensiva de suspensão do lado do cliente — só UX,
  // não é a barreira real. A barreira que não pode ser contornada está
  // nas Firestore Security Rules (isSuspended() em casos_pendentes),
  // que recusam a escrita de qualquer forma, mesmo que este código
  // nunca chegasse a correr.
  try {
    const uSnap = await getDoc(doc(db, "users", user.uid));
    if (uSnap.exists()) {
      const uData = uSnap.data();
      const score = typeof uData.trustScore === "number" ? uData.trustScore : 100;
      if (uData.isSuspended === true || score <= 0) {
        showAlert(
          "A sua conta está suspensa. Não é possível relatar casos neste momento. " +
          "Contacte o suporte por email: suporte@missingao.co.ao",
        );
        return;
      }
    }
  } catch (_) {
    // Falha de rede não deve bloquear — a regra do Firestore continua a proteger a escrita.
  }

  const btn = document.getElementById("enviarRelato");
  btn.innerText = "Processando...";
  btn.disabled = true;

  try {
    const nome = document.querySelector('input[name="nome"]').value;
    const idade = document.querySelector('input[name="idade"]').value;
    const sexo =
      document.querySelector('select[name="sexo"]')?.value ||
      document.getElementById("sexo-form")?.value ||
      "";
    const provincia = document.getElementById("provincia_relatar").value;
    const municipio = document.getElementById("municipio_relatar").value;
    const ultimo_local =
      document.getElementById("ultimo_local_input")?.value ||
      document.querySelector('input[name="ultimo_local"]')?.value ||
      "";
    const roupas = document.querySelector('input[name="roupas"]').value;
    const data_desaparecimento = document.querySelector(
      'input[name="data_desaparecimento"]',
    ).value;
    const info = document.getElementById("informacoes_adicionais").value;
    const deficiencia = document.getElementById("deficiencia").value;
    const tipoDeficiencia = document.getElementById(
      "tipo_deficiencia_input",
    ).value;
    const lat = document.getElementById("lat_relatar")?.value || null;
    const lng = document.getElementById("lng_relatar")?.value || null;

    if (!nome || !provincia || !municipio) {
      showAlert("Preencha pelo menos Nome, Província e Município.");
      throw new Error("Campos obrigatórios vazios.");
    }

    const fileInput = document.querySelector('input[name="imagem"]');
    let imagemBase64 = null;
    if (fileInput?.files.length > 0) {
      const file = fileInput.files[0];
      if (file.size > 1000 * 1024) {
        showAlert("A imagem é muito grande (máximo 1000KB).");
        btn.innerText = "Relatar";
        btn.disabled = false;
        return;
      }
      imagemBase64 = await lerArquivoComoBase64(file);
    }

    const dados = {
      userId: user.uid,
      autorEmail: user.email,
      status: "pendente",
      createdAt: new Date().toISOString(),
      nome,
      idade,
      sexo,
      provincia,
      municipio,
      ultimo_local,
      roupas,
      data_desaparecimento,
      informacoes_adicionais: info,
      deficiencia,
      tipo_deficiencia: deficiencia === "sim" ? tipoDeficiencia : "",
      imagem: imagemBase64,
      apoios: 0,
      apoiadoPor: [],
      comentarios: 0,
    };

    // Guardar coordenadas se o utilizador marcou no mapa
    if (lat && lng) {
      dados.lat = parseFloat(lat);
      dados.lng = parseFloat(lng);
    }

    await addDoc(collection(db, "casos_pendentes"), dados);

    showAlert("Caso relatado com sucesso! Aguarde aprovação.");
    document.getElementById("relatarSec").style.display = "none";
    document
      .querySelectorAll("#relatarSec input, #relatarSec textarea")
      .forEach((i) => (i.value = ""));
    document
      .querySelectorAll("#relatarSec select")
      .forEach((s) => (s.selectedIndex = 0));
    // Limpar mapa form
    if (mapaFormMarker) {
      mapaFormMarker.setMap(null);
      mapaFormMarker = null;
    }
    document.getElementById("mapa-form-coords").style.display = "none";
  } catch (err) {
    if (err.message !== "Campos obrigatórios vazios.") {
      console.error(err);
      showAlert("Erro: " + err.message);
    }
  } finally {
    btn.innerText = "Relatar";
    btn.disabled = false;
  }
}

function lerArquivoComoBase64(file) {
  return new Promise((resolve, reject) => {
    const r = new FileReader();
    r.onload = () => resolve(r.result);
    r.onerror = (e) => reject(e);
    r.readAsDataURL(file);
  });
}

/* =========================================================================
   7. MODAL DE RELATO — Navegação entre abas
   ========================================================================= */
function configurarNavegacaoModal() {
  const relatarSec = document.getElementById("relatarSec");
  const relatarBtn = document.getElementById("relatar");
  const closeBtn = relatarSec?.querySelector("header button");
  const abas = {
    pessoa: {
      link: document.getElementById("pessoaActive"),
      div: document.getElementById("pessoaDiv"),
    },
    local: {
      link: document.getElementById("localActive"),
      div: document.getElementById("localDiv"),
    },
    detalhes: {
      link: document.getElementById("detalhesActive"),
      div: document.getElementById("detalhesDiv"),
    },
  };

  function showTab(nome) {
    Object.values(abas).forEach((a) => {
      if (a.div) a.div.style.display = "none";
      if (a.link) a.link.classList.remove("active");
    });
    if (abas[nome]) {
      abas[nome].div.style.display = "flex";
      abas[nome].link.classList.add("active");
    }
    // Iniciar mapa do formulário quando abre aba Local
    if (nome === "local") {
      setTimeout(() => {
        if (typeof google !== "undefined") iniciarMapaForm();
      }, 100);
    }
  }

  Object.keys(abas).forEach((k) =>
    abas[k].link?.addEventListener("click", (e) => {
      e.preventDefault();
      showTab(k);
    }),
  );

  relatarBtn?.addEventListener("click", () => {
    if (!auth.currentUser) {
      showAlert("Faça login para relatar.", { onOk: () => navigateToLogin() });
      return;
    }
    relatarSec.style.display = "flex";
    showTab("pessoa");
  });
  closeBtn?.addEventListener("click", () => {
    relatarSec.style.display = "none";
  });
}

/* =========================================================================
   8. UTILITÁRIOS
   ========================================================================= */
/* =========================================================================
   PRÉ-VISUALIZAÇÃO CIRCULAR DA FOTO (formulário de relato)
   ========================================================================= */
function configurarPreviewFoto() {
  const trigger = document.getElementById("foto-upload-trigger");
  const input = document.getElementById("input-imagem-relato");
  const previewImg = document.getElementById("foto-preview-img");
  const placeholder = document.getElementById("foto-upload-placeholder");
  if (!trigger || !input) return;

  trigger.addEventListener("click", () => input.click());

  input.addEventListener("change", () => {
    const file = input.files?.[0];
    if (!file) return;

    const reader = new FileReader();
    reader.onload = (e) => {
      previewImg.src = e.target.result;
      previewImg.classList.remove("hidden");
      placeholder.classList.add("hidden");
      trigger.classList.add("has-image");
    };
    reader.readAsDataURL(file);
  });
}

function configurarLogicaMunicipios() {
  const municipiosPorProvincia = {
    luanda: [
      "Belas",
      "Cacuaco",
      "Cazenga",
      "Ícolo e Bengo",
      "Luanda",
      "Quilamba Quiaxi",
      "Talatona",
      "Viana",
    ],
    benguela: [
      "Baía Farta",
      "Balombo",
      "Benguela",
      "Bocoio",
      "Caimbambo",
      "Catumbela",
      "Chongoroi",
      "Cubal",
      "Ganda",
      "Lobito",
    ],
    huambo: [
      "Bailundo",
      "Catchiungo",
      "Caála",
      "Ecunha",
      "Huambo",
      "Londuimbali",
      "Longonjo",
      "Mungo",
      "Tchicala-Tcholoanga",
      "Tchindjenje",
      "Ucuma",
    ],
  };
  function atualizarSelect(val, sel, divEl) {
    if (!sel) return;
    sel.innerHTML = '<option value="" hidden>Selecione o município</option>';
    if (val && municipiosPorProvincia[val]) {
      municipiosPorProvincia[val].forEach((m) => {
        const o = document.createElement("option");
        o.value = m.toLowerCase().replace(/ /g, "_");
        o.textContent = m;
        sel.appendChild(o);
      });
      if (divEl) divEl.style.display = "block";
      sel.required = true;
    } else {
      if (divEl) divEl.style.display = "none";
      sel.required = false;
    }
  }
  document.getElementById("provincia")?.addEventListener("change", function () {
    atualizarSelect(
      this.value,
      document.getElementById("municipio"),
      document.getElementById("municipio-field"),
    );
    aplicarFiltros();
  });
  document
    .getElementById("provincia_relatar")
    ?.addEventListener("change", function () {
      atualizarSelect(
        this.value,
        document.getElementById("municipio_relatar"),
        document.getElementById("municipio-field-relatar"),
      );
      // Centrar mapa do formulário na província selecionada
      if (typeof google !== "undefined" && mapaForm) {
        const coords =
          COORDS_PROVINCIA[this.value.toLowerCase().replace(/ /g, "_")];
        if (coords) {
          mapaForm.setCenter(coords);
          mapaForm.setZoom(10);
        }
      }
    });
}

function configurarLogicaDeficiencia() {
  const d = document.getElementById("deficiencia");
  const f = document.getElementById("tipo_deficiencia_field");
  if (d && f)
    d.addEventListener("change", () => {
      f.style.display = d.value === "sim" ? "block" : "none";
      if (d.value !== "sim")
        document.getElementById("tipo_deficiencia_input").value = "";
    });
}

/* =========================================================================
   HELPERS — Stats de utilizador (para sistema de emblemas) + Apagar comentário
   ========================================================================= */

// Incrementa uma stat do utilizador no Firestore (apoios, comentarios, partilhas)
async function incrementarStatUser(campo) {
  if (!currentUser) return;
  try {
    await updateDoc(doc(db, "users", currentUser.uid), {
      [`stats.${campo}`]: increment(1),
    });
  } catch (err) {
    // Falha silenciosa — não bloquear a acção principal
    console.warn("[Stats]", err.message);
  }
}

// Apagar comentário (só o próprio autor)
async function apagarComentarioRec(casoId, comentarioId) {
  // Remove um comentário e todas as suas respostas recursivamente.
  const ref = doc(db, "casos", casoId, "comentarios", comentarioId);
  const snap = await getDoc(ref);
  if (!snap.exists()) return 0;
  const data = snap.data();
  if (data.autorId !== currentUser.uid) {
    throw new Error("Permissão negada");
  }
  // Apagar filhos recursivamente
  const q = query(
    collection(db, "casos", casoId, "comentarios"),
    where("parentId", "==", comentarioId),
  );
  const children = await getDocs(q);
  let total = 0;
  for (const d of children.docs) {
    total += await apagarComentarioRec(casoId, d.id);
  }
  await deleteDoc(ref);
  return total + 1;
}

async function apagarComentario(casoId, comentarioId) {
  if (!currentUser) return 0;
  try {
    const deletedCount = await apagarComentarioRec(casoId, comentarioId);
    if (deletedCount > 0) {
      await updateDoc(doc(db, "casos", casoId), {
        comentarios: increment(-deletedCount),
      });
      // Actualizar contador local
      const local = todosOsCasos.find((c) => c.id === casoId);
      if (local)
        local.comentarios = Math.max(
          0,
          (local.comentarios || deletedCount) - deletedCount,
        );
      const countEl = document.getElementById(`comentarios-count-${casoId}`);
      if (countEl && local) countEl.innerText = local.comentarios;
    }
    return deletedCount;
  } catch (err) {
    console.error("Erro ao apagar comentário:", err);
    showAlert("Não foi possível apagar o comentário.");
    return 0;
  }
}

function calcularDias(dataString) {
  if (!dataString) return 0;
  const d = new Date(dataString);
  if (isNaN(d)) return 0;
  return Math.ceil(Math.abs(new Date() - d) / 86400000);
}

function escapeHtml(texto) {
  const d = document.createElement("div");
  d.appendChild(document.createTextNode(texto));
  return d.innerHTML;
}

/* =========================================================================
   BARRA DE BUSCA + HISTÓRICO
   - Histórico local em localStorage (key: searchHistory)
   - Se o utilizador estiver autenticado, também guarda em users/{uid}/searches
   - Mostra dropdown com últimas pesquisas e permite limpar
   ========================================================================= */
function setupSearchBar() {
  const searchEl = document.querySelector(".search");
  if (!searchEl) return;
  const input = document.getElementById("search-input");
  const btn = document.getElementById("search-btn");
  let historyEl = document.getElementById("search-history");
  if (!historyEl) {
    historyEl = document.createElement("div");
    historyEl.id = "search-history";
    historyEl.className = "search-history";
    searchEl.appendChild(historyEl);
  }

  async function showHistory() {
    const local = loadLocalHistory();
    let remote = [];
    if (currentUser) {
      try {
        remote = await getFirestoreHistory();
      } catch (e) {
        remote = [];
      }
    }
    const merged = [];
    (remote || []).forEach((q) => {
      if (q && !merged.includes(q)) merged.push(q);
    });
    (local || []).forEach((q) => {
      if (q && !merged.includes(q)) merged.push(q);
    });
    renderSearchHistory(merged.slice(0, 10));
    historyEl.style.display = "block";
    historyEl.setAttribute("aria-hidden", "false");
  }

  function hideHistory() {
    historyEl.style.display = "none";
    historyEl.setAttribute("aria-hidden", "true");
  }

  function filterHistory(term) {
    const t = (term || "").toLowerCase();
    historyEl.querySelectorAll(".search-history-item").forEach((it) => {
      const txt = (it.dataset.q || "").toLowerCase();
      it.style.display = txt.includes(t) ? "flex" : "none";
    });
  }

  input?.addEventListener("focus", () => showHistory());
  input?.addEventListener("input", (e) => filterHistory(e.target.value));
  input?.addEventListener("keydown", (e) => {
    if (e.key === "Enter") {
      e.preventDefault();
      doSearch(input.value);
      hideHistory();
    }
  });
  btn?.addEventListener("click", (e) => {
    e.preventDefault();
    doSearch(input.value);
    hideHistory();
  });

  document.addEventListener("click", (e) => {
    if (!searchEl.contains(e.target)) hideHistory();
  });
}

function renderSearchHistory(list) {
  const el = document.getElementById("search-history");
  if (!el) return;
  el.innerHTML = "";
  const top = document.createElement("div");
  top.className = "search-history-top";
  const topLabel = document.createElement("span");
  topLabel.textContent = "Pesquisas recentes";
  top.appendChild(topLabel);
  const title = document.createElement("div");
  title.textContent = "Pesquisas recentes";
  const clearBtn = document.createElement("button");
  clearBtn.className = "search-history-clear";
  clearBtn.textContent = "Limpar";
  clearBtn.addEventListener("click", clearHistory);
  top.appendChild(title);
  top.appendChild(clearBtn);
  el.appendChild(top);

  if (!list || list.length === 0) {
    const empty = document.createElement("div");
    empty.className = "search-history-empty";
    empty.textContent = "Nenhuma pesquisa anterior";
    el.appendChild(empty);
    return;
  }

  list.forEach((q) => {
    const it = document.createElement("div");
    it.className = "search-history-item";
    it.dataset.q = q;
    // ícone de relógio + termo + seta discreta
    it.innerHTML = `
      <i class="fa-regular fa-clock"></i>
      <span class="search-history-term">${escapeHtml(q)}</span>
      <i class="fa-solid fa-arrow-up-left" style="color:#ccc;font-size:11px;"></i>`;
    it.addEventListener("click", () => {
      document.getElementById("search-input").value = q;
      doSearch(q);
      document.getElementById("search-history").style.display = "none";
    });
    el.appendChild(it);
  });
}

function loadLocalHistory() {
  try {
    return JSON.parse(localStorage.getItem("searchHistory") || "[]");
  } catch (e) {
    return [];
  }
}

function setLocalHistory(arr) {
  localStorage.setItem(
    "searchHistory",
    JSON.stringify((arr || []).slice(0, 10)),
  );
}

async function getFirestoreHistory() {
  if (!currentUser) return [];
  try {
    const snap = await getDocs(
      query(
        collection(db, "users", currentUser.uid, "searches"),
        orderBy("at", "desc"),
      ),
    );
    const arr = [];
    snap.forEach((d) => arr.push(d.data().q));
    return arr;
  } catch (e) {
    return [];
  }
}

async function clearHistory() {
  setLocalHistory([]);
  const el = document.getElementById("search-history");
  if (el)
    el.innerHTML =
      '<div class="search-history-empty">Nenhuma pesquisa anterior</div>';
  if (!currentUser) return;
  try {
    const snap = await getDocs(
      collection(db, "users", currentUser.uid, "searches"),
    );
    const dels = [];
    snap.forEach((d) => {
      dels.push(deleteDoc(d.ref));
    });
    await Promise.all(dels);
  } catch (e) {
    console.warn("Falha ao limpar histórico remoto", e);
  }
}

function saveSearchEntryLocal(q) {
  if (!q || !q.trim()) return;
  const arr = loadLocalHistory().filter((x) => x !== q);
  arr.unshift(q);
  setLocalHistory(arr.slice(0, 10));
}

async function saveSearchEntryRemote(q) {
  if (!currentUser) return;
  try {
    await addDoc(collection(db, "users", currentUser.uid, "searches"), {
      q,
      at: serverTimestamp(),
    });
  } catch (e) {
    /* ignore */
  }
}

function saveSearchEntry(q) {
  saveSearchEntryLocal(q);
  // fire-and-forget remote
  if (currentUser) saveSearchEntryRemote(q).catch(() => {});
}

function doSearch(q) {
  const term = (q || "").trim();
  if (!term) {
    renderizarCasos(todosOsCasos);
    atualizarContadorResultados(todosOsCasos.length);
    if (typeof google !== "undefined") iniciarMapaPrincipal(todosOsCasos);
    return;
  }
  const ql = term.toLowerCase();
  const filtrados = todosOsCasos.filter((c) =>
    (
      "" +
      (c.nome || "") +
      " " +
      (c.ultimo_local || "") +
      " " +
      (c.provincia || "") +
      " " +
      (c.informacoes_adicionais || "")
    )
      .toLowerCase()
      .includes(ql),
  );
  renderizarCasos(filtrados);
  atualizarContadorResultados(filtrados.length);
  if (typeof google !== "undefined") iniciarMapaPrincipal(filtrados);
  saveSearchEntry(term);
}

/* =========================================================================
   MOBILE UI: bottom menu + mobile ad window + overlays
   ========================================================================= */
function setupMobileUI() {
  const mobileAd = document.getElementById("mobile-ad");
  const mobileAdContent = document.getElementById("mobile-ad-content");
  const anuncios = document.getElementById("anuncios-container");
  // O carousel.js já detecta se está em mobile e renderiza directamente
  // no #mobile-ad-content — não é necessário copiar HTML aqui.

  const toggle = document.getElementById("mobile-ad-toggle"); // antigo (compat)
  const ad = document.getElementById("mobile-ad");
  const openBtn = document.getElementById("mobile-ad-open");
  const btnMin = document.getElementById("mobile-ad-minimize");
  const btnClose = document.getElementById("mobile-ad-close");
  const adHeader = document.getElementById("mobile-ad-header");

  function openAd() {
    ad.style.display = "";
    ad.classList.remove("minimized");
    if (openBtn) openBtn.style.display = "none";
  }
  function minimizeAd() {
    ad.classList.toggle("minimized");
  }
  function closeAd() {
    ad.style.display = "none";
    ad.classList.remove("minimized");
    if (openBtn) openBtn.style.display = "flex";
  }

  // Novos botões de controlo
  if (btnMin) btnMin.addEventListener("click", minimizeAd);
  if (btnClose) btnClose.addEventListener("click", closeAd);

  // Clicar no header minimizado → expandir
  if (adHeader) {
    adHeader.addEventListener("click", (e) => {
      if (
        ad.classList.contains("minimized") &&
        !e.target.closest(".mobile-ad-btn")
      ) {
        openAd();
      }
    });
  }

  // Botão flutuante reabre
  if (openBtn) openBtn.addEventListener("click", openAd);

  // Manter compatibilidade com toggle antigo (escondido)
  if (toggle) toggle.addEventListener("click", minimizeAd);

  const mbMap = document.getElementById("mb-map");
  const mbFiltros = document.getElementById("mb-filtros");
  const mbProfile = document.getElementById("mb-profile");
  const mbRelatar = document.getElementById("mb-relatar");
  const sectionMap = document.querySelector(".section_map");

  mbMap?.addEventListener("click", () => {
    if (!sectionMap) return;
    sectionMap.classList.toggle("mobile-active");
    sectionMap.classList.remove("show-filters");
    if (sectionMap.classList.contains("mobile-active")) {
      sectionMap.classList.add("show-map");
      if (typeof iniciarMapaPrincipal === "function")
        iniciarMapaPrincipal(todosOsCasos);
    } else {
      sectionMap.classList.remove("show-map");
    }
  });

  mbFiltros?.addEventListener("click", () => {
    if (!sectionMap) return;
    sectionMap.classList.toggle("mobile-active");
    sectionMap.classList.add("show-filters");
  });

  mbProfile?.addEventListener("click", () => {
    navigateToTarget("profile.html");
  });

  mbRelatar?.addEventListener("click", () => {
    document.getElementById("relatar")?.click();
  });

  const mobileClose = document.getElementById("mobile-map-close");
  mobileClose?.addEventListener("click", () => {
    document
      .querySelector(".section_map")
      ?.classList.remove("mobile-active", "show-filters", "show-map");
  });
}

// Atualiza avatar na barra de navegação com a foto do utilizador (se existir)
async function updateNavAvatar(user) {
  const els = document.querySelectorAll(".nav-avatar");
  if (!els || els.length === 0) return;
  if (!user) {
    els.forEach((img) => {
      try {
        img.src = "imgs/user.jpg";
      } catch (e) {
        /* ignore */
      }
    });
    return;
  }
  try {
    const uSnap = await getDoc(doc(db, "users", user.uid));
    if (uSnap.exists()) {
      const data = uSnap.data();
      if (data.photoBase64) {
        els.forEach((img) => {
          try {
            img.src = data.photoBase64;
          } catch (e) {
            /* ignore */
          }
        });
        return;
      }
    }
    // fallback para photoURL do auth ou imagem padrão
    const fallback = user.photoURL || "imgs/user.jpg";
    els.forEach((img) => {
      try {
        img.src = fallback;
      } catch (e) {
        /* ignore */
      }
    });
  } catch (err) {
    console.warn("Erro ao actualizar avatar nav:", err);
    els.forEach((img) => {
      try {
        img.src = "imgs/user.jpg";
      } catch (e) {
        /* ignore */
      }
    });
  }
}