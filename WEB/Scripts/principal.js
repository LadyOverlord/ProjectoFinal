import { auth, db } from "./firebase.js";
import {
  collection,
  addDoc,
  getDocs,
  getDoc,
  query,
  where,
  doc,
  updateDoc,
  arrayUnion,
  arrayRemove,
  increment,
  orderBy,
  serverTimestamp,
} from "https://www.gstatic.com/firebasejs/12.8.0/firebase-firestore.js";
import {
  onAuthStateChanged,
} from "https://www.gstatic.com/firebasejs/12.8.0/firebase-auth.js";

// ─── Estado Global ───────────────────────────────────────────────
let todosOsCasos = [];
let currentUser  = null;

// Rastreia qual secção de comentários está aberta { casoId: bool }
const comentariosAbertos = {};

// ─── Auth State ──────────────────────────────────────────────────
onAuthStateChanged(auth, (user) => {
  currentUser = user;
  // Atualiza UI dos botões ao mudar estado de auth
  atualizarBotoesApoio();
});

// ─── DOM Ready ───────────────────────────────────────────────────
document.addEventListener("DOMContentLoaded", async function () {
  configurarNavegacaoModal();
  configurarLogicaMunicipios();
  configurarLogicaDeficiencia();

  await carregarCasos();

  document.getElementById("enviarRelato")?.addEventListener("click", enviarRelato);
  document.querySelector(".caracter button")?.addEventListener("click", aplicarFiltros);
});

/* =========================================================================
   1. CARREGAR E EXIBIR CASOS (FEED)
   ========================================================================= */

// Gera N cards esqueleto no container
function mostrarSkeletons(container, n = 3) {
  container.innerHTML = "";
  for (let i = 0; i < n; i++) {
    container.insertAdjacentHTML("beforeend", `
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
      </div>
    `);
  }
}

async function carregarCasos() {
  const container = document.querySelector(".casos_main");

  // Mostrar skeletons enquanto carrega
  mostrarSkeletons(container, 3);

  try {
    const q             = query(collection(db, "casos"));
    const querySnapshot = await getDocs(q);
    // Limpa skeletons assim que os dados chegam — renderizarCasos faz container.innerHTML=""

    todosOsCasos = [];

    querySnapshot.forEach((docSnap) => {
      let data = docSnap.data();
      data.id  = docSnap.id;

      if (data.status && data.status !== "pendente" && data.status !== "rejeitado") {
        todosOsCasos.push(data);
      }
    });

    renderizarCasos(todosOsCasos);
  } catch (error) {
    console.error("Erro ao carregar casos:", error);
  }
}

function renderizarCasos(lista) {
  const container = document.querySelector(".casos_main");
  container.innerHTML = "";

  if (lista.length === 0) {
    container.innerHTML =
      "<p style='padding:20px; text-align:center; color:#888; font-family:var(--font-base);'>Nenhum caso encontrado.</p>";
    return;
  }

  lista.forEach((caso) => {
    const dias         = calcularDias(caso.data_desaparecimento);
    const textoTempo   = dias === 0 ? "Hoje" : `Há ${dias} dias`;
    const statusTexto  = caso.status === "aprovado" ? "Ativo" : (caso.status || "");
    const apoiosCount  = caso.apoios || 0;
    const comentariosCount = caso.comentarios || 0;

    // Saber se o user atual já apoiou
    const jaApoiou = currentUser && Array.isArray(caso.apoiadoPor) && caso.apoiadoPor.includes(currentUser.uid);

    const div = document.createElement("div");
    div.className  = "feed-card";
    div.dataset.id = caso.id;

    div.innerHTML = `
      <!-- HEADER DO CARD -->
      <div class="card-header">
        <img src="${caso.imagem || "imgs/user.jpg"}" class="avatar-small" alt="Avatar" onerror="this.src='imgs/user.jpg'">
        <div class="header-info">
          <h4>${caso.nome || "Nome Desconhecido"}</h4>
          <span>${caso.idade || "?"} anos • ${caso.municipio || "Angola"}</span>
        </div>
        <div style="margin-left:auto; text-align:right;">
          <span class="status-badge status-${caso.status}">${statusTexto}</span>
        </div>
      </div>

      <!-- IMAGEM PRINCIPAL -->
      <img src="${caso.imagem || "imgs/user.jpg"}" class="card-main-image" alt="Foto Desaparecido" onerror="this.src='imgs/user.jpg'">

      <!-- CORPO DO CARD -->
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

        <!-- Contadores -->
        <div class="card-counters">
          <span class="counter-item">
            <i class="fa-solid fa-heart" style="color:#e74c3c;"></i>
            <span id="apoios-count-${caso.id}">${apoiosCount}</span> apoios
          </span>
          <span class="counter-item">
            <i class="fa-regular fa-comment" style="color:#0c7ab5;"></i>
            <span id="comentarios-count-${caso.id}">${comentariosCount}</span> comentários
          </span>
        </div>

        <!-- BOTÕES DE AÇÃO -->
        <div class="card-actions">
          <button class="btn-action btn-apoiar ${jaApoiou ? "apoiado" : ""}"
                  data-id="${caso.id}"
                  title="${jaApoiou ? "Deixar de apoiar" : "Apoiar este caso"}">
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

        <!-- SECÇÃO DE COMENTÁRIOS (oculta por padrão) -->
        <div class="comments-section" id="comments-${caso.id}" style="display:none;">
          <div class="comments-loading" id="loading-${caso.id}">
            <i class="fa-solid fa-spinner fa-spin"></i> Carregando comentários...
          </div>
          <div class="comments-list" id="comments-list-${caso.id}"></div>
          <div class="comment-input-row">
            <img src="${currentUser?.photoURL || "imgs/user.jpg"}" class="comment-avatar" id="comment-avatar-${caso.id}" onerror="this.src='imgs/user.jpg'">
            <input type="text"
                   class="comment-input"
                   id="comment-input-${caso.id}"
                   placeholder="Escreva um comentário...">
            <button class="btn-send-comment" data-id="${caso.id}">
              <i class="fa-solid fa-paper-plane"></i>
            </button>
          </div>
        </div>
      </div>
    `;

    container.appendChild(div);
  });

  // Adicionar eventos após renderizar
  registarEventosBotoes();
}

// ─── Registar Eventos nos Botões ─────────────────────────────────
function registarEventosBotoes() {
  // APOIAR
  document.querySelectorAll(".btn-apoiar").forEach((btn) => {
    btn.addEventListener("click", () => toggleApoio(btn.dataset.id, btn));
  });

  // COMENTAR
  document.querySelectorAll(".btn-comentar").forEach((btn) => {
    btn.addEventListener("click", () => toggleComentarios(btn.dataset.id));
  });

  // PARTILHAR
  document.querySelectorAll(".btn-partilhar").forEach((btn) => {
    btn.addEventListener("click", () =>
      partilharCaso(btn.dataset.id, btn.dataset.nome, btn.dataset.provincia)
    );
  });

  // ENVIAR COMENTÁRIO
  document.querySelectorAll(".btn-send-comment").forEach((btn) => {
    btn.addEventListener("click", () => enviarComentario(btn.dataset.id));
  });

  // Enter no input de comentário
  document.querySelectorAll(".comment-input").forEach((input) => {
    input.addEventListener("keydown", (e) => {
      if (e.key === "Enter" && !e.shiftKey) {
        e.preventDefault();
        const casoId = input.id.replace("comment-input-", "");
        enviarComentario(casoId);
      }
    });
  });
}

// ─── Atualizar botões Apoiar quando auth muda ─────────────────────
function atualizarBotoesApoio() {
  document.querySelectorAll(".btn-apoiar").forEach((btn) => {
    const casoId = btn.dataset.id;
    const caso   = todosOsCasos.find((c) => c.id === casoId);
    if (!caso) return;

    const jaApoiou = currentUser && Array.isArray(caso.apoiadoPor) && caso.apoiadoPor.includes(currentUser.uid);
    btn.className  = `btn-action btn-apoiar ${jaApoiou ? "apoiado" : ""}`;
    btn.innerHTML  = `<i class="fa-${jaApoiou ? "solid" : "regular"} fa-heart"></i> ${jaApoiou ? "Apoiando" : "Apoiar"}`;
  });
}

/* =========================================================================
   2. APOIAR — Toggle apoio num caso
   ========================================================================= */

async function toggleApoio(casoId, btn) {
  if (!currentUser) {
    showAlert("Faça login para apoiar um caso.");
    return;
  }

  btn.disabled = true;

  try {
    const casoRef  = doc(db, "casos", casoId);
    const casoSnap = await getDoc(casoRef);

    if (!casoSnap.exists()) {
      showAlert("Caso não encontrado.");
      return;
    }

    const apoiadoPor = casoSnap.data().apoiadoPor || [];
    const jaApoiou   = apoiadoPor.includes(currentUser.uid);

    if (jaApoiou) {
      // Remover apoio
      await updateDoc(casoRef, {
        apoiadoPor: arrayRemove(currentUser.uid),
        apoios:     increment(-1),
      });

      btn.classList.remove("apoiado");
      btn.innerHTML = `<i class="fa-regular fa-heart"></i> Apoiar`;

      // Atualizar contador local
      const casoLocal = todosOsCasos.find((c) => c.id === casoId);
      if (casoLocal) {
        casoLocal.apoiadoPor = casoLocal.apoiadoPor.filter((uid) => uid !== currentUser.uid);
        casoLocal.apoios     = Math.max(0, (casoLocal.apoios || 0) - 1);
      }
    } else {
      // Adicionar apoio
      await updateDoc(casoRef, {
        apoiadoPor: arrayUnion(currentUser.uid),
        apoios:     increment(1),
      });

      btn.classList.add("apoiado");
      btn.innerHTML = `<i class="fa-solid fa-heart"></i> Apoiando`;

      // Atualizar contador local
      const casoLocal = todosOsCasos.find((c) => c.id === casoId);
      if (casoLocal) {
        if (!casoLocal.apoiadoPor) casoLocal.apoiadoPor = [];
        casoLocal.apoiadoPor.push(currentUser.uid);
        casoLocal.apoios = (casoLocal.apoios || 0) + 1;
      }
    }

    // Atualizar contador na UI
    const countEl = document.getElementById(`apoios-count-${casoId}`);
    const casoLocal = todosOsCasos.find((c) => c.id === casoId);
    if (countEl && casoLocal) countEl.innerText = casoLocal.apoios || 0;

  } catch (err) {
    console.error("Erro ao apoiar:", err);
    showAlert("Erro ao processar apoio. Tente novamente.");
  } finally {
    btn.disabled = false;
  }
}

/* =========================================================================
   3. COMENTÁRIOS — Abrir/fechar e carregar comentários
   ========================================================================= */

async function toggleComentarios(casoId) {
  const section = document.getElementById(`comments-${casoId}`);
  if (!section) return;

  const estaAberto = comentariosAbertos[casoId];

  if (estaAberto) {
    section.style.display = "none";
    comentariosAbertos[casoId] = false;
  } else {
    section.style.display = "block";
    comentariosAbertos[casoId] = true;
    await carregarComentarios(casoId);

    // Atualizar avatar se o user estiver logado
    if (currentUser) {
      const avatarEl = document.getElementById(`comment-avatar-${casoId}`);
      // Tentar carregar foto do perfil do Firestore
      try {
        const userSnap = await getDoc(doc(db, "users", currentUser.uid));
        if (userSnap.exists() && userSnap.data().photoBase64) {
          if (avatarEl) avatarEl.src = userSnap.data().photoBase64;
        }
      } catch (_) {}
    }

    // Focar input
    document.getElementById(`comment-input-${casoId}`)?.focus();
  }
}

async function carregarComentarios(casoId) {
  const loadingEl = document.getElementById(`loading-${casoId}`);
  const listEl    = document.getElementById(`comments-list-${casoId}`);

  if (!listEl) return;
  if (loadingEl) loadingEl.style.display = "flex";

  try {
    const q    = query(
      collection(db, "casos", casoId, "comentarios"),
      orderBy("criadoEm", "asc")
    );
    const snap = await getDocs(q);

    if (loadingEl) loadingEl.style.display = "none";
    listEl.innerHTML = "";

    if (snap.empty) {
      listEl.innerHTML = `<p class="no-comments">Seja o primeiro a comentar!</p>`;
      return;
    }

    snap.forEach((docSnap) => {
      const c  = docSnap.data();
      const dt = c.criadoEm?.toDate ? c.criadoEm.toDate() : new Date();
      const timeStr = `${String(dt.getHours()).padStart(2, "0")}:${String(dt.getMinutes()).padStart(2, "0")} · ${dt.getDate()}/${dt.getMonth() + 1}`;

      const item = document.createElement("div");
      item.className = "comment-item";
      item.innerHTML = `
        <img src="${c.autorFoto || "imgs/user.jpg"}" class="comment-avatar" onerror="this.src='imgs/user.jpg'">
        <div class="comment-bubble">
          <span class="comment-author">${c.autorNome || "Utilizador"}</span>
          <p class="comment-text">${escapeHtml(c.texto)}</p>
          <span class="comment-time">${timeStr}</span>
        </div>
      `;
      listEl.appendChild(item);
    });

    // Scroll para o último comentário
    listEl.scrollTop = listEl.scrollHeight;

  } catch (err) {
    console.error("Erro ao carregar comentários:", err);
    if (loadingEl) loadingEl.style.display = "none";
    if (listEl) listEl.innerHTML = `<p class="no-comments" style="color:#e74c3c;">Erro ao carregar comentários.</p>`;
  }
}

async function enviarComentario(casoId) {
  if (!currentUser) {
    showAlert("Faça login para comentar.");
    return;
  }

  const inputEl = document.getElementById(`comment-input-${casoId}`);
  if (!inputEl) return;

  const texto = inputEl.value.trim();
  if (!texto) return;

  const btnSend = document.querySelector(`.btn-send-comment[data-id="${casoId}"]`);
  if (btnSend) { btnSend.disabled = true; btnSend.innerHTML = `<i class="fa-solid fa-spinner fa-spin"></i>`; }

  try {
    // Buscar dados do user para o comentário
    const userSnap = await getDoc(doc(db, "users", currentUser.uid));
    const userData = userSnap.exists() ? userSnap.data() : {};

    // Guardar comentário na subcoleção
    await addDoc(collection(db, "casos", casoId, "comentarios"), {
      texto,
      autorId:   currentUser.uid,
      autorNome: userData.nome || "Utilizador",
      autorFoto: userData.photoBase64 || "",
      criadoEm:  serverTimestamp(),
    });

    // Incrementar contador de comentários no documento principal
    await updateDoc(doc(db, "casos", casoId), {
      comentarios: increment(1),
    });

    // Atualizar contador local
    const casoLocal = todosOsCasos.find((c) => c.id === casoId);
    if (casoLocal) casoLocal.comentarios = (casoLocal.comentarios || 0) + 1;
    const countEl = document.getElementById(`comentarios-count-${casoId}`);
    if (countEl && casoLocal) countEl.innerText = casoLocal.comentarios;

    // Limpar input e recarregar comentários
    inputEl.value = "";
    await carregarComentarios(casoId);

  } catch (err) {
    console.error("Erro ao comentar:", err);
    showAlert("Erro ao enviar comentário. Tente novamente.");
  } finally {
    if (btnSend) { btnSend.disabled = false; btnSend.innerHTML = `<i class="fa-solid fa-paper-plane"></i>`; }
  }
}

/* =========================================================================
   4. PARTILHAR
   ========================================================================= */

async function partilharCaso(casoId, nome, provincia) {
  const url   = `${window.location.origin}${window.location.pathname}?caso=${casoId}`;
  const title = `🔍 Ajude a encontrar: ${nome}`;
  const text  = `${nome} desapareceu em ${provincia || "Angola"}. Partilhe para ajudar na busca! Missing AO.`;

  if (navigator.share) {
    try {
      await navigator.share({ title, text, url });
    } catch (err) {
      if (err.name !== "AbortError") copiarParaClipboard(url);
    }
  } else {
    copiarParaClipboard(url);
  }
}

function copiarParaClipboard(texto) {
  navigator.clipboard
    .writeText(texto)
    .then(() => showAlert("✅ Link copiado para a área de transferência!"))
    .catch(() => showAlert(`Partilhe este link:\n${texto}`));
}

/* =========================================================================
   5. ENVIAR RELATO
   ========================================================================= */

async function enviarRelato() {
  const user = auth.currentUser;
  if (!user) {
    showAlert("Você precisa estar logado para relatar um caso.");
    return;
  }

  const btn       = document.getElementById("enviarRelato");
  btn.innerText   = "Processando...";
  btn.disabled    = true;

  try {
    const nome               = document.querySelector('input[name="nome"]').value;
    const idade              = document.querySelector('input[name="idade"]').value;
    const sexo               = document.querySelector('select[name="sexo"]').value;
    const provincia          = document.getElementById("provincia_relatar").value;
    const municipio          = document.getElementById("municipio_relatar").value;
    const ultimo_local       = document.querySelector('input[name="ultimo_local"]').value;
    const roupas             = document.querySelector('input[name="roupas"]').value;
    const data_desaparecimento = document.querySelector('input[name="data_desaparecimento"]').value;
    const info               = document.getElementById("informacoes_adicionais").value;
    const deficiencia        = document.getElementById("deficiencia").value;
    const tipoDeficiencia    = document.getElementById("tipo_deficiencia_input").value;

    if (!nome || !provincia || !municipio) {
      showAlert("Preencha pelo menos Nome, Província e Município.");
      throw new Error("Campos obrigatórios vazios.");
    }

    const fileInput   = document.querySelector('input[name="imagem"]');
    let imagemBase64  = null;

    if (fileInput.files.length > 0) {
      const file = fileInput.files[0];
      if (file.size > 1000 * 1024) {
        showAlert("A imagem é muito grande (máximo 1000KB).");
        btn.innerText = "Relatar";
        btn.disabled  = false;
        return;
      }
      imagemBase64 = await lerArquivoComoBase64(file);
    }

    const dados = {
      userId:                 user.uid,
      autorEmail:             user.email,
      status:                 "pendente",
      createdAt:              new Date().toISOString(),
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
      tipo_deficiencia:       deficiencia === "sim" ? tipoDeficiencia : "",
      imagem:                 imagemBase64,
      apoios:                 0,
      apoiadoPor:             [],
      comentarios:            0,
    };

    await addDoc(collection(db, "casos_pendentes"), dados);

    showAlert("Caso relatado com sucesso! Aguarde aprovação do administrador.");
    document.getElementById("relatarSec").style.display = "none";

    document.querySelectorAll("#relatarSec input, #relatarSec textarea").forEach((i) => (i.value = ""));
    document.querySelectorAll("#relatarSec select").forEach((s) => (s.selectedIndex = 0));

  } catch (err) {
    if (err.message !== "Campos obrigatórios vazios.") {
      console.error(err);
      showAlert("Erro ao enviar: " + err.message);
    }
  } finally {
    btn.innerText = "Relatar";
    btn.disabled  = false;
  }
}

function lerArquivoComoBase64(file) {
  return new Promise((resolve, reject) => {
    const reader   = new FileReader();
    reader.onload  = () => resolve(reader.result);
    reader.onerror = (error) => reject(error);
    reader.readAsDataURL(file);
  });
}

/* =========================================================================
   6. NAVEGAÇÃO DO MODAL
   ========================================================================= */

function configurarNavegacaoModal() {
  const relatarSec = document.getElementById("relatarSec");
  const relatarBtn = document.getElementById("relatar");
  const closeBtn   = relatarSec?.querySelector("header button");

  const abas = {
    pessoa:   { link: document.getElementById("pessoaActive"),   div: document.getElementById("pessoaDiv") },
    local:    { link: document.getElementById("localActive"),    div: document.getElementById("localDiv") },
    detalhes: { link: document.getElementById("detalhesActive"), div: document.getElementById("detalhesDiv") },
  };

  function showTab(nomeAba) {
    Object.values(abas).forEach((item) => {
      if (item.div)  item.div.style.display  = "none";
      if (item.link) item.link.classList.remove("active");
    });
    if (abas[nomeAba]) {
      abas[nomeAba].div.style.display  = "flex";
      abas[nomeAba].link.classList.add("active");
    }
  }

  Object.keys(abas).forEach((key) => {
    abas[key].link?.addEventListener("click", (e) => { e.preventDefault(); showTab(key); });
  });

  relatarBtn?.addEventListener("click", () => {
    if (!auth.currentUser) { showAlert("Faça login para relatar."); return; }
    relatarSec.style.display = "flex";
    showTab("pessoa");
  });

  closeBtn?.addEventListener("click", () => { relatarSec.style.display = "none"; });
}

/* =========================================================================
   7. UTILITÁRIOS
   ========================================================================= */

function configurarLogicaMunicipios() {
  const municipiosPorProvincia = {
    luanda:   ["Belas","Cacuaco","Cazenga","Ícolo e Bengo","Luanda","Quilamba Quiaxi","Talatona","Viana"],
    benguela: ["Baía Farta","Balombo","Benguela","Bocoio","Caimbambo","Catumbela","Chongoroi","Cubal","Ganda","Lobito"],
    huambo:   ["Bailundo","Catchiungo","Caála","Ecunha","Huambo","Londuimbali","Longonjo","Mungo","Tchicala-Tcholoanga","Tchindjenje","Ucuma"],
  };

  function atualizarSelect(provinciaVal, selectMun, divMun) {
    if (!selectMun) return;
    selectMun.innerHTML = '<option value="" hidden>Selecione o município</option>';
    if (provinciaVal && municipiosPorProvincia[provinciaVal]) {
      municipiosPorProvincia[provinciaVal].forEach((mun) => {
        const opt       = document.createElement("option");
        opt.value       = mun.toLowerCase().replace(/ /g, "_");
        opt.textContent = mun;
        selectMun.appendChild(opt);
      });
      if (divMun) divMun.style.display = "block";
      selectMun.required = true;
    } else {
      if (divMun) divMun.style.display = "none";
      selectMun.required = false;
    }
  }

  document.getElementById("provincia")?.addEventListener("change", function () {
    atualizarSelect(this.value, document.getElementById("municipio"), document.getElementById("municipio-field"));
  });

  document.getElementById("provincia_relatar")?.addEventListener("change", function () {
    atualizarSelect(this.value, document.getElementById("municipio_relatar"), document.getElementById("municipio-field-relatar"));
  });
}

function configurarLogicaDeficiencia() {
  const defSelect   = document.getElementById("deficiencia");
  const tipoDefField = document.getElementById("tipo_deficiencia_field");
  if (defSelect && tipoDefField) {
    defSelect.addEventListener("change", () => {
      tipoDefField.style.display = defSelect.value === "sim" ? "block" : "none";
      if (defSelect.value !== "sim") document.getElementById("tipo_deficiencia_input").value = "";
    });
  }
}

function aplicarFiltros() {
  const provincia = document.getElementById("provincia").value;
  const sexo      = document.getElementById("sexo").value;

  const filtrados = todosOsCasos.filter((caso) => {
    let passou = true;
    if (provincia && caso.provincia !== provincia) passou = false;
    if (sexo      && caso.sexo      !== sexo)      passou = false;
    return passou;
  });

  renderizarCasos(filtrados);
}

function calcularDias(dataString) {
  if (!dataString) return 0;
  const dataPassada = new Date(dataString);
  const hoje        = new Date();
  if (isNaN(dataPassada)) return 0;
  return Math.ceil(Math.abs(hoje - dataPassada) / (1000 * 60 * 60 * 24));
}

function escapeHtml(texto) {
  const div       = document.createElement("div");
  div.appendChild(document.createTextNode(texto));
  return div.innerHTML;
}