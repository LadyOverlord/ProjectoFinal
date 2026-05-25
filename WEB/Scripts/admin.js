import { auth, db, navigateToLogin } from "./firebase.js";
import {
  onAuthStateChanged,
  signOut,
} from "https://www.gstatic.com/firebasejs/12.8.0/firebase-auth.js";
import {
  doc,
  getDoc,
  collection,
  getDocs,
  query,
  where,
  updateDoc,
  deleteDoc,
  setDoc,
  addDoc,
  orderBy,
  serverTimestamp,
  increment as fsIncrement,
} from "https://www.gstatic.com/firebasejs/12.8.0/firebase-firestore.js";

// Estado global
let todosUsuarios = [];
let editandoId = null; // ID do anúncio em edição (null = novo)
let formularioConfigurado = false; // Guard: evita listeners duplicados

// Autenticação e segurança
onAuthStateChanged(auth, async (user) => {
  if (!user) {
    navigateToLogin();
    return;
  }
  try {
    const snap = await getDoc(doc(db, "users", user.uid));
    if (snap.exists() && snap.data().role === "admin") {
      document.body.style.display = "flex";
      iniciarAdmin();
    } else {
      window.location.href = "../index.html";
    }
  } catch {
    window.location.href = "../index.html";
  }
});

/* =========================================================================
   INIT
   ========================================================================= */
function iniciarAdmin() {
  configurarNavegacao();

  document
    .getElementById("btn-logout")
    .addEventListener("click", () =>
      signOut(auth).then(() => (window.location.href = "../index.html")),
    );

  // Pesquisa global de utilizadores
  document
    .querySelector(".search input")
    ?.addEventListener("keyup", (e) =>
      filtrarUsuarios(e.target.value.toLowerCase()),
    );

  // Configurar listeners do modal de edição de localização
  const btnCorrigir = document.getElementById("btn-corrigir-localizacoes");
  const btnFechar = document.getElementById("btn-fechar-modal");
  const btnCancelar = document.getElementById("btn-cancelar-modal");
  const btnSalvar = document.getElementById("btn-salvar-localizacao");

  if (btnCorrigir)
    btnCorrigir.addEventListener("click", abrirModalEditarLocalizacao);
  if (btnFechar)
    btnFechar.addEventListener("click", fecharModalEditarLocalizacao);
  if (btnCancelar)
    btnCancelar.addEventListener("click", fecharModalEditarLocalizacao);
  if (btnSalvar) btnSalvar.addEventListener("click", salvarLocalizacao);

  carregarDashboard();
  configurarFormularioAnuncio(); // ✅ chamado apenas UMA vez
}

/* =========================================================================
   NAVEGAÇÃO
   ========================================================================= */
function configurarNavegacao() {
  const links = document.querySelectorAll(".menu-link");
  const panels = document.querySelectorAll(".panel");
  const titulos = {
    dashboard: "Painel de Controle",
    users: "Gestão de Utilizadores",
    reports: "Aprovações Pendentes",
    config: "Gestão de Anúncios",
    "mapa-admin": "Mapa de Casos",
  };

  links.forEach((link) => {
    link.addEventListener("click", (e) => {
      e.preventDefault();
      links.forEach((l) => l.classList.remove("active"));
      panels.forEach((p) => p.classList.remove("active"));
      link.classList.add("active");
      const id = link.dataset.target;
      document.getElementById(id)?.classList.add("active");
      document.getElementById("nav-titulo").innerText = titulos[id] || "Admin";

      if (id === "dashboard") carregarDashboard();
      if (id === "users") carregarUsuarios();
      if (id === "reports") carregarAprovacoes();
      if (id === "config") carregarConfig();
      if (id === "mapa-admin") iniciarMapaAdmin();
    });
  });
}

/* =========================================================================
   DASHBOARD
   ========================================================================= */
async function carregarDashboard() {
  try {
    // Cada query é independente — se uma falhar não afecta as outras
    let usersCount = "—";
    try {
      const usersSnap = await getDocs(collection(db, "users"));
      usersCount =
        typeof usersSnap.size === "number"
          ? usersSnap.size
          : (() => {
              let c = 0;
              usersSnap.forEach(() => c++);
              return c;
            })();
    } catch (e) {
      usersCount = "—";
    }

    let pendCount = "—";
    try {
      const pendSnap = await getDocs(collection(db, "casos_pendentes"));
      pendCount =
        typeof pendSnap.size === "number"
          ? pendSnap.size
          : (() => {
              let c = 0;
              pendSnap.forEach(() => c++);
              return c;
            })();
    } catch (e) {
      pendCount = "—";
    }

    let aprovCount = "—";
    try {
      const aprovSnap = await getDocs(
        query(collection(db, "casos"), where("status", "==", "aprovado")),
      );
      aprovCount =
        typeof aprovSnap.size === "number"
          ? aprovSnap.size
          : (() => {
              let c = 0;
              aprovSnap.forEach(() => c++);
              return c;
            })();
    } catch (e) {
      aprovCount = "—";
    }

    document.getElementById("count-users").innerText = usersCount;
    document.getElementById("count-reports").innerText = pendCount;
    document.getElementById("count-aprovados").innerText = aprovCount;

    // Anúncios: query separada para não bloquear o resto
    try {
      const anuncSnap = await getDocs(collection(db, "anuncios"));
      const ativos = [];
      anuncSnap.forEach((d) => {
        const data = d.data();
        const ativo = data.ativo;
        const isAtivo = (function (v) {
          if (v === true) return true;
          if (v === false) return false;
          if (v == null) return true;
          if (typeof v === "number") return v !== 0;
          if (typeof v === "string") {
            const s = v.trim().toLowerCase();
            return ["true", "1", "on", "yes", "sim"].includes(s);
          }
          return Boolean(v);
        })(ativo);
        if (isAtivo) ativos.push(d);
      });
      document.getElementById("count-anuncios").innerText = ativos.length;
    } catch (_) {
      document.getElementById("count-anuncios").innerText = "—";
    }

    // Tabela casos ativos
    const activeBody = document.getElementById("active-cases-body");
    if (!activeBody) return;
    activeBody.innerHTML = `<tr><td colspan="4" class="tc">Carregando...</td></tr>`;

    const qAtivos = query(
      collection(db, "casos"),
      where("status", "in", ["aprovado", "encontrado", "desmentido"]),
    );
    const snapAtivos = await getDocs(qAtivos);

    activeBody.innerHTML = "";
    if (snapAtivos.empty) {
      activeBody.innerHTML = `<tr><td colspan="4" class="tc">Nenhum caso ativo.</td></tr>`;
      return;
    }

    snapAtivos.forEach((d) => {
      const data = d.data();
      const tr = document.createElement("tr");
      tr.style.borderBottom = "1px solid #eee";
      tr.innerHTML = `
        <td style="padding:10px;">${data.nome || "—"}</td>
        <td style="padding:10px;">${data.municipio || "—"}</td>
        <td style="padding:10px;">
          <select class="status-select admin-select-sm">
            <option value="aprovado"   ${data.status === "aprovado" ? "selected" : ""}>🔵 Ativo</option>
            <option value="encontrado" ${data.status === "encontrado" ? "selected" : ""}>🟢 Encontrado</option>
            <option value="desmentido" ${data.status === "desmentido" ? "selected" : ""}>⚫ Desmentido</option>
            <option value="rejeitado"  ${data.status === "rejeitado" ? "selected" : ""}>🔴 Arquivar</option>
          </select>
        </td>
        <td style="padding:10px;">
          <button class="btn-save-status btn-admin-sm" data-id="${d.id}">Guardar</button>
        </td>`;
      activeBody.appendChild(tr);
    });

    activeBody.querySelectorAll(".btn-save-status").forEach((btn) => {
      btn.addEventListener("click", async (e) => {
        const id = btn.dataset.id;
        const novoStatus = btn
          .closest("tr")
          .querySelector(".status-select").value;
        btn.innerText = "...";
        btn.disabled = true;
        try {
          await updateDoc(doc(db, "casos", id), { status: novoStatus });
          showAlert(`✅ Status actualizado: ${novoStatus}`, {
            onOk: carregarDashboard,
          });
        } catch (err) {
          showAlert("Erro: " + err.message);
          btn.innerText = "Guardar";
          btn.disabled = false;
        }
      });
    });
  } catch (err) {
    console.error("Erro dashboard:", err);
  }
}

/* =========================================================================
   UTILIZADORES
   ========================================================================= */
async function carregarUsuarios() {
  const tbody = document.getElementById("users-table-body");
  tbody.innerHTML = `<tr><td colspan="7" class="tc">
    <i class="fa-solid fa-spinner fa-spin"></i> Carregando utilizadores...
  </td></tr>`;
  try {
    const snap = await getDocs(collection(db, "users"));
    todosUsuarios = [];
    snap.forEach((d) => todosUsuarios.push({ id: d.id, ...d.data() }));

    // Actualizar total
    const totalEl = document.getElementById("users-total");
    if (totalEl) totalEl.textContent = todosUsuarios.length;

    aplicarFiltrosUsuarios();
    configurarFiltrosUsuarios();
  } catch (err) {
    console.error(
      "[Admin] Erro ao carregar utilizadores:",
      err.code,
      err.message,
    );
    tbody.innerHTML = `<tr><td colspan="7" class="tc" style="color:#e74c3c;">
      Erro: ${err.code || err.message}<br>
      <small>Verifique as Firestore Security Rules</small>
    </td></tr>`;
  }
}

// ── Configurar eventos dos filtros (chamado uma única vez) ────────────────────
let _filtrosConfigurados = false;
function configurarFiltrosUsuarios() {
  if (_filtrosConfigurados) return;
  _filtrosConfigurados = true;

  const ufSearch = document.getElementById("uf-search");
  const ufClear = document.getElementById("uf-search-clear");
  const ufAplicar = document.getElementById("uf-aplicar");
  const ufLimpar = document.getElementById("uf-limpar");
  const ufExportar = document.getElementById("btn-exportar-users");

  // Pesquisa em tempo real
  ufSearch?.addEventListener("input", () => {
    if (ufClear) ufClear.style.display = ufSearch.value ? "flex" : "none";
    aplicarFiltrosUsuarios();
  });
  ufClear?.addEventListener("click", () => {
    ufSearch.value = "";
    ufClear.style.display = "none";
    aplicarFiltrosUsuarios();
  });

  // Demais filtros aplicam ao mudar
  ["uf-role", "uf-provincia", "uf-data-de", "uf-data-ate", "uf-ordem"].forEach(
    (id) => {
      document
        .getElementById(id)
        ?.addEventListener("change", aplicarFiltrosUsuarios);
    },
  );

  ufAplicar?.addEventListener("click", aplicarFiltrosUsuarios);
  ufLimpar?.addEventListener("click", limparFiltrosUsuarios);

  // Exportar CSV
  ufExportar?.addEventListener("click", exportarCSVUsuarios);
}

function aplicarFiltrosUsuarios() {
  const termo = (document.getElementById("uf-search")?.value || "")
    .toLowerCase()
    .trim();
  const role = document.getElementById("uf-role")?.value || "";
  const provincia = document.getElementById("uf-provincia")?.value || "";
  const dataDe = document.getElementById("uf-data-de")?.value || "";
  const dataAte = document.getElementById("uf-data-ate")?.value || "";
  const ordem = document.getElementById("uf-ordem")?.value || "recente";

  let lista = todosUsuarios.filter((u) => {
    // Texto
    if (termo) {
      const campos = [u.nome || "", u.email || "", u.telefone || ""]
        .join(" ")
        .toLowerCase();
      if (!campos.includes(termo)) return false;
    }
    // Função
    if (role && (u.role || "user") !== role) return false;
    // Província
    if (provincia && (u.provincia || "").toLowerCase() !== provincia)
      return false;
    // Datas de cadastro
    if (dataDe || dataAte) {
      const raw = u.criadoEm;
      if (!raw) return !dataDe; // sem data: só aparece se não há filtro "de"
      const dt = raw.toDate ? raw.toDate() : new Date(raw);
      if (isNaN(dt)) return false;
      const dStr = dt.toISOString().slice(0, 10);
      if (dataDe && dStr < dataDe) return false;
      if (dataAte && dStr > dataAte) return false;
    }
    return true;
  });

  // Ordenação
  lista.sort((a, b) => {
    const toMs = (raw) => {
      if (!raw) return 0;
      const d = raw.toDate ? raw.toDate() : new Date(raw);
      return isNaN(d) ? 0 : d.getTime();
    };
    if (ordem === "recente") return toMs(b.criadoEm) - toMs(a.criadoEm);
    if (ordem === "antigo") return toMs(a.criadoEm) - toMs(b.criadoEm);
    if (ordem === "nome") return (a.nome || "").localeCompare(b.nome || "");
    if (ordem === "nome-desc")
      return (b.nome || "").localeCompare(a.nome || "");
    return 0;
  });

  const countEl = document.getElementById("users-filtro-count");
  if (countEl) {
    const temFiltro = termo || role || provincia || dataDe || dataAte;
    countEl.textContent = temFiltro
      ? `${lista.length} utilizador${lista.length !== 1 ? "es" : ""} encontrado${lista.length !== 1 ? "s" : ""}`
      : "";
  }

  renderizarTabelaUsuarios(lista);
}

function limparFiltrosUsuarios() {
  ["uf-search", "uf-role", "uf-provincia", "uf-data-de", "uf-data-ate"].forEach(
    (id) => {
      const el = document.getElementById(id);
      if (el) el.value = "";
    },
  );
  const ufOrd = document.getElementById("uf-ordem");
  if (ufOrd) ufOrd.value = "recente";
  const ufClear = document.getElementById("uf-search-clear");
  if (ufClear) ufClear.style.display = "none";
  aplicarFiltrosUsuarios();
}

function renderizarTabelaUsuarios(lista) {
  const tbody = document.getElementById("users-table-body");
  tbody.innerHTML = "";

  if (!lista.length) {
    tbody.innerHTML = `<tr><td colspan="7" class="tc" style="padding:28px;">
      <i class="fa-solid fa-users-slash" style="font-size:24px;color:#ddd;"></i><br>
      Nenhum utilizador encontrado
    </td></tr>`;
    return;
  }

  lista.forEach((user) => {
    // Data de cadastro
    const rawCriado = user.criadoEm;
    let dataCadastro = "—";
    if (rawCriado) {
      const dt = rawCriado.toDate ? rawCriado.toDate() : new Date(rawCriado);
      if (!isNaN(dt))
        dataCadastro = `${dt.getDate().toString().padStart(2, "0")}/${(dt.getMonth() + 1).toString().padStart(2, "0")}/${dt.getFullYear()}`;
    }

    // Localização GPS (se o utilizador partilhou)
    const temGPS = !!(user.lat && user.lng);
    const gpsHtml = temGPS
      ? `<span style="color:#2ecc71;font-size:12px;"><i class="fa-solid fa-location-dot"></i> Activa</span>`
      : `<span style="color:#ccc;font-size:12px;"><i class="fa-solid fa-location-dot"></i> Sem GPS</span>`;

    // Avatar
    const avatarHtml = user.photoBase64
      ? `<img src="${user.photoBase64}" style="width:32px;height:32px;border-radius:50%;object-fit:cover;flex-shrink:0;">`
      : `<span style="width:32px;height:32px;border-radius:50%;background:#e3f2fd;color:#0c7ab5;display:inline-flex;align-items:center;justify-content:center;font-size:14px;flex-shrink:0;"><i class="fa-solid fa-user"></i></span>`;

    tbody.innerHTML += `
      <tr style="border-bottom:1px solid #f2f2f2;">
        <td style="padding:10px;">
          <div style="display:flex;align-items:center;gap:9px;">
            ${avatarHtml}
            <div>
              <div style="font-weight:700;font-size:13px;color:#222;">${user.nome || "—"}</div>
              <div style="font-size:11px;color:#aaa;">#${user.id.slice(0, 8)}</div>
            </div>
          </div>
        </td>
        <td style="padding:10px;font-size:13px;color:#555;">${user.email || "—"}</td>
        <td style="padding:10px;">
          <span class="role-badge ${user.role === "admin" ? "role-admin" : "role-user"}">
            ${user.role || "user"}
          </span>
        </td>
        <td style="padding:10px;font-size:13px;color:#555;">${user.provincia || "—"}</td>
        <td style="padding:10px;font-size:12px;color:#555;">${dataCadastro}</td>
        <td style="padding:10px;">${gpsHtml}</td>
        <td style="padding:10px;">
          <div style="display:flex;gap:6px;align-items:center;">
            <a href="profile.html?uid=${user.id}" target="_blank"
               class="btn-admin-icon" title="Ver perfil">
              <i class="fa-solid fa-arrow-up-right-from-square" style="font-size:12px;"></i>
            </a>
          <button onclick="window.promoverUsuario('${user.id}','${user.role || "user"}')"
               class="btn-admin-icon" title="${user.role === "admin" ? "Rebaixar para user" : "Tornar admin"}">
              <i class="fa-solid fa-${user.role === "admin" ? "user-minus" : "user-shield"}" style="font-size:12px;"></i>
            </button>
            <button onclick="window.excluirUsuario('${user.id}')"
               class="btn-admin-icon btn-danger-icon" title="Remover utilizador">
              <i class="fa-solid fa-trash" style="font-size:12px;"></i>
            </button>
          </div>
        </td>
      </tr>`;
  });
}

// ── Promover/rebaixar utilizador ──────────────────────────────────────────────
window.promoverUsuario = async function (id, roleAtual) {
  const novoRole = roleAtual === "admin" ? "user" : "admin";
  const msg =
    novoRole === "admin"
      ? "Tornar este utilizador Admin?"
      : "Remover privilégios de Admin deste utilizador?";
  if (!confirm(msg)) return;
  try {
    await updateDoc(doc(db, "users", id), { role: novoRole });
    showAlert(`✅ Role actualizado para: ${novoRole}`, {
      onOk: carregarUsuarios,
    });
  } catch (e) {
    showAlert("Erro: " + e.message);
  }
};

// ── Exportar CSV ──────────────────────────────────────────────────────────────
function exportarCSVUsuarios() {
  const headers = [
    "Nome",
    "Email",
    "Função",
    "Província",
    "Telefone",
    "Cadastro",
    "GPS",
  ];
  const rows = todosUsuarios.map((u) => {
    const raw = u.criadoEm;
    let data = "";
    if (raw) {
      const d = raw.toDate ? raw.toDate() : new Date(raw);
      if (!isNaN(d)) data = d.toLocaleDateString("pt-AO");
    }
    return [
      u.nome || "",
      u.email || "",
      u.role || "user",
      u.provincia || "",
      u.telefone || "",
      data,
      u.lat && u.lng ? `${u.lat},${u.lng}` : "",
    ]
      .map((v) => `"${String(v).replace(/"/g, '""')}"`)
      .join(",");
  });
  const csv = [headers.join(","), ...rows].join("\n");
  const blob = new Blob(["\uFEFF" + csv], { type: "text/csv;charset=utf-8;" });
  const url = URL.createObjectURL(blob);
  const a = document.createElement("a");
  a.href = url;
  a.download = `utilizadores_${new Date().toISOString().slice(0, 10)}.csv`;
  a.click();
  URL.revokeObjectURL(url);
}

function filtrarUsuarios(termo) {
  const painel = document.getElementById("users");
  if (!painel.classList.contains("active"))
    document.querySelector('[data-target="users"]').click();
  const ufSearch = document.getElementById("uf-search");
  if (ufSearch) {
    ufSearch.value = termo;
  }
  aplicarFiltrosUsuarios();
}

window.excluirUsuario = async function (id) {
  if (!confirm("Remover este utilizador da base de dados?")) return;
  try {
    await deleteDoc(doc(db, "users", id));
    showAlert("Utilizador removido.", { onOk: carregarUsuarios });
  } catch (e) {
    showAlert("Erro: " + e.message);
  }
};

/* =========================================================================
   APROVAÇÕES
   ========================================================================= */
async function carregarAprovacoes() {
  const container = document.getElementById("reports-list");
  container.innerHTML = `<p class="tc">Buscando pendentes...</p>`;
  try {
    const snap = await getDocs(collection(db, "casos_pendentes"));
    container.innerHTML = "";
    if (snap.empty) {
      container.innerHTML = `<p class="tc" style="color:#666;margin-top:20px;">Nenhuma aprovação pendente.</p>`;
      return;
    }
    // Recolher casos e buscar perfis dos relatores em paralelo
    const casos = [];
    snap.forEach(d => casos.push({ id: d.id, ...d.data() }));

    const userSnaps = await Promise.all(
      casos.map(c =>
        c.userId
          ? getDoc(doc(db, "users", c.userId)).catch(() => null)
          : Promise.resolve(null)
      )
    );

    casos.forEach((data, i) => {
      const id   = data.id;
      const dias = calcularDias(data.data_desaparecimento);
      const tempo = dias === 0 ? "hoje" : `há ${dias} dias`;

      // Dados do utilizador que relatou
      const uSnap       = userSnaps[i];
      const relator     = uSnap?.exists() ? uSnap.data() : null;
      const rNome       = relator?.nome  || "Utilizador desconhecido";
      const rEmail      = relator?.email || "—";
      const rFoto       = relator?.photoBase64 || "";
      const rProv       = relator?.provincia ? ` · ${relator.provincia}` : "";
      const rUID        = data.userId || "";
      let   rMembro     = "—";
      if (relator?.criadoEm) {
        const dt = relator.criadoEm.toDate ? relator.criadoEm.toDate() : new Date(relator.criadoEm);
        if (!isNaN(dt)) rMembro = `${String(dt.getDate()).padStart(2,"0")}/${String(dt.getMonth()+1).padStart(2,"0")}/${dt.getFullYear()}`;
      }
      const rVerif = relator?.emailVerificado === false
        ? `<span class="relator-badge warn">⚠ Email não verificado</span>`
        : `<span class="relator-badge ok">✓ Verificado</span>`;

      const card = document.createElement("div");
      card.className = "card-aprovar";
      card.innerHTML = `
        <!-- Botão rejeitar -->
        <button class="top-menu-btn btn-rejeitar" data-id="${id}" title="Rejeitar caso">
          <i class="fa-solid fa-xmark"></i>
        </button>

        <!-- Foto + info do desaparecido -->
        <div class="card-header-admin">
          <img src="${data.imagem || "imgs/user.jpg"}" class="admin-avatar"
               onerror="this.src='imgs/user.jpg'" alt="Foto do desaparecido">
          <div class="admin-user-info">
            <h3>${data.nome || "Nome Desconhecido"}</h3>
            <p>${data.idade || "?"}${data.sexo ? " · " + data.sexo : ""} anos</p>
          </div>
        </div>

        <p class="card-desc">
          Desapareceu em <strong>${data.provincia || "local desconhecido"}</strong>
          ${data.municipio ? " — " + data.municipio : ""} <em>${tempo}</em>.
          ${data.ultimo_local
            ? `<br><i class="fa-solid fa-location-dot" style="color:#e07a5f;"></i> ${data.ultimo_local}`
            : ""}
        </p>

        <!-- Acções -->
        <div class="admin-actions" style="margin-bottom:0;">
          <button class="btn-docs"
            onclick="window.showAlert('BI: ${(data.bi||'N/A')}\nRoupas: ${(data.roupas||'N/A')}\nRelato: ${(data.informacoes_adicionais||'Sem detalhes')}')">
            <i class="fa-solid fa-file-lines"></i> Ver Detalhes
          </button>
          <button class="btn-approve-pub" data-id="${id}">
            <i class="fa-solid fa-circle-check"></i> Aprovar
          </button>
        </div>

        <!-- Mini perfil do relator -->
        <div class="relator-section">
          <span class="relator-label">
            <i class="fa-solid fa-user-pen"></i> Relatado por
          </span>
          <div class="relator-body">
            ${rFoto
              ? `<img src="${rFoto}" class="relator-avatar" onerror="this.style.display='none'" alt="">`
              : `<div class="relator-avatar-ph"><i class="fa-solid fa-user"></i></div>`}
            <div class="relator-info">
              <div class="relator-nome">${rNome} ${rVerif}</div>
              <div class="relator-meta">
                <span><i class="fa-solid fa-envelope"></i> ${rEmail}</span>
                <span><i class="fa-solid fa-calendar"></i> Membro desde ${rMembro}${rProv}</span>
              </div>
            </div>
            ${rUID
              ? `<a href="profile.html?uid=${rUID}" target="_blank" class="relator-link" title="Ver perfil">
                   <i class="fa-solid fa-arrow-up-right-from-square"></i>
                 </a>`
              : ""}
          </div>
        </div>`;
      container.appendChild(card);
    });

    // Aprovar
    container.querySelectorAll(".btn-approve-pub").forEach((btn) => {
      btn.addEventListener("click", async () => {
        const id = btn.dataset.id;
        btn.innerText = "Aprovando...";
        btn.disabled = true;
        try {
          const ref = doc(db, "casos_pendentes", id);
          const snap = await getDoc(ref);
          if (snap.exists()) {
            const casoData = snap.data();
            await setDoc(doc(db, "casos", id), {
              ...casoData,
              status: "aprovado",
            });
            await deleteDoc(ref);
            // Notificar o autor do caso por email
            await notificarAprovacaoCaso({ id, ...casoData });
            showAlert("✅ Publicação aprovada!", { onOk: carregarAprovacoes });
          }
        } catch (err) {
          showAlert("Erro: " + err.message);
          btn.disabled = false;
        }
      });
    });

    // Rejeitar
    container.querySelectorAll(".btn-rejeitar").forEach((btn) => {
      btn.addEventListener("click", async () => {
        const id = btn.closest("button").dataset.id;
        if (!confirm("Rejeitar este caso?")) return;
        try {
          await deleteDoc(doc(db, "casos_pendentes", id));
          carregarAprovacoes();
        } catch (err) {
          showAlert("Erro: " + err.message);
        }
      });
    });
  } catch (err) {
    console.error("ERRO popularSelectCasos:", err.code, err.message);
  }
}

/* =========================================================================
   CONFIGURAÇÕES — ANÚNCIOS (CRUD COMPLETO)
   ========================================================================= */
async function carregarConfig() {
  await Promise.all([carregarListaAnuncios(), popularSelectCasos()]);
  // formulário já configurado em iniciarAdmin()
}

// ── Lista de anúncios ─────────────────────────────────────────
async function carregarListaAnuncios() {
  const listEl = document.getElementById("anuncios-list");
  listEl.innerHTML = `<div class="admin-loader"><i class="fa-solid fa-spinner fa-spin"></i> Carregando...</div>`;

  try {
    // ✅ Busca tudo e ordena em JS (evita necessidade de índice Firestore)
    const snap = await getDocs(collection(db, "anuncios"));
    listEl.innerHTML = "";

    // Ordenar por campo "ordem" em JS
    const anuncios = [];
    snap.forEach((d) => anuncios.push({ id: d.id, ...d.data() }));
    anuncios.sort((a, b) => (a.ordem || 0) - (b.ordem || 0));

    if (anuncios.length === 0) {
      listEl.innerHTML = `<p class="tc" style="color:#999;padding:24px 0;">Nenhum anúncio criado ainda.</p>`;
      return;
    }

    anuncios.forEach((an) => {
      const tipoLabel =
        { dica: "💡 Dica", alerta: "🚨 Alerta", caso_destaque: "📢 Destaque" }[
          an.tipo
        ] || an.tipo;

      const isAtivo = (function (v) {
        if (v === true) return true;
        if (v === false) return false;
        if (v == null) return true;
        if (typeof v === "number") return v !== 0;
        if (typeof v === "string") {
          const s = v.trim().toLowerCase();
          return ["true", "1", "on", "yes", "sim"].includes(s);
        }
        return Boolean(v);
      })(an.ativo);

      const row = document.createElement("div");
      row.className = `anuncio-row ${isAtivo ? "" : "anuncio-inativo"}`;
      row.innerHTML = `
        <div class="anuncio-row-left">
          <span class="anuncio-ordem">#${an.ordem || "—"}</span>
          <span class="anuncio-tipo-badge tipo-${an.tipo}">${tipoLabel}</span>
          <div class="anuncio-row-info">
            <strong>${an.titulo || "Sem título"}</strong>
            <span>${(an.conteudo || "").slice(0, 80)}${(an.conteudo || "").length > 80 ? "..." : ""}</span>
          </div>
        </div>
        <div class="anuncio-row-actions">
          <label class="toggle-switch" title="${isAtivo ? "Desactivar" : "Activar"}">
            <input type="checkbox" class="toggle-ativo" data-id="${an.id}" ${isAtivo ? "checked" : ""}>
            <span class="toggle-slider"></span>
          </label>
          <button class="btn-admin-icon btn-edit-anuncio" data-id="${an.id}" title="Editar">
            <i class="fa-solid fa-pen"></i>
          </button>
          <button class="btn-admin-icon btn-delete-anuncio btn-danger-icon" data-id="${an.id}" title="Eliminar">
            <i class="fa-solid fa-trash"></i>
          </button>
        </div>`;
      listEl.appendChild(row);
    });

    // Toggle ativo/inativo
    listEl.querySelectorAll(".toggle-ativo").forEach((chk) => {
      chk.addEventListener("change", async () => {
        try {
          await updateDoc(doc(db, "anuncios", chk.dataset.id), {
            ativo: chk.checked,
          });
          chk
            .closest(".anuncio-row")
            .classList.toggle("anuncio-inativo", !chk.checked);
        } catch (err) {
          showAlert("Erro: " + err.message);
          chk.checked = !chk.checked;
        }
      });
    });

    // Editar
    listEl.querySelectorAll(".btn-edit-anuncio").forEach((btn) => {
      btn.addEventListener("click", async () => {
        const snap = await getDoc(doc(db, "anuncios", btn.dataset.id));
        if (!snap.exists()) return;
        preencherFormulario(btn.dataset.id, snap.data());
      });
    });

    // Eliminar
    listEl.querySelectorAll(".btn-delete-anuncio").forEach((btn) => {
      btn.addEventListener("click", async () => {
        if (!confirm("Eliminar este anúncio permanentemente?")) return;
        try {
          await deleteDoc(doc(db, "anuncios", btn.dataset.id));
          carregarListaAnuncios();
        } catch (err) {
          showAlert("Erro: " + err.message);
        }
      });
    });
  } catch (err) {
    console.error("ERRO ANUNCIOS:", err.code, err.message, err);
    listEl.innerHTML = `<div style="padding:20px;text-align:center;">
      <p style="color:#e74c3c;font-weight:700;margin-bottom:8px;">Erro ao carregar anúncios</p>
      <code style="background:#fff3f3;padding:6px 12px;border-radius:4px;font-size:12px;color:#c0392b;">
        ${err.code || err.message || "Erro desconhecido"}
      </code>
      <p style="color:#999;font-size:12px;margin-top:8px;">Verifique as Firestore Rules no Firebase Console</p>
    </div>`;
  }
}

// ── Popular select de casos aprovados ────────────────────────
async function popularSelectCasos() {
  const sel = document.getElementById("anuncio-caso-select");
  if (!sel) return;
  try {
    const snap = await getDocs(
      query(collection(db, "casos"), where("status", "==", "aprovado")),
    );
    sel.innerHTML = `<option value="">Selecione um caso...</option>`;
    snap.forEach((d) => {
      const opt = document.createElement("option");
      opt.value = d.id;
      opt.dataset.nome = d.data().nome || "";
      opt.dataset.imagem = d.data().imagem || "";
      opt.dataset.local = d.data().provincia || "";
      opt.textContent = `${d.data().nome || "Sem nome"} — ${d.data().municipio || ""}`;
      sel.appendChild(opt);
    });
  } catch (err) {
    console.error(err);
  }
}

// ── Formulário ────────────────────────────────────────────────
function configurarFormularioAnuncio() {
  if (formularioConfigurado) return; // ✅ evita listeners duplicados
  formularioConfigurado = true;

  // Mostrar/ocultar formulário
  document.getElementById("btn-toggle-form").addEventListener("click", () => {
    const wrapper = document.getElementById("anuncio-form-wrapper");
    wrapper.classList.toggle("hidden");
    if (!wrapper.classList.contains("hidden")) {
      resetarFormulario();
      wrapper.scrollIntoView({ behavior: "smooth" });
    }
  });

  document.getElementById("btn-cancelar-form").addEventListener("click", () => {
    document.getElementById("anuncio-form-wrapper").classList.add("hidden");
    resetarFormulario();
  });

  // Tipo → mostrar/ocultar campos relevantes
  document
    .getElementById("anuncio-tipo")
    .addEventListener("change", atualizarCamposVisiveis);

  // Quando selecionar caso → preencher título/imagem automaticamente
  document
    .getElementById("anuncio-caso-select")
    .addEventListener("change", function () {
      const opt = this.options[this.selectedIndex];
      if (opt.value) {
        document.getElementById("anuncio-titulo").value =
          opt.dataset.nome || "";
        document.getElementById("anuncio-imagem").value =
          opt.dataset.imagem || "";
      }
    });

  // Toggle label
  document
    .getElementById("anuncio-ativo")
    .addEventListener("change", function () {
      document.getElementById("toggle-label").innerText = this.checked
        ? "Activo"
        : "Inactivo";
    });

  // Guardar
  document
    .getElementById("btn-salvar-anuncio")
    .addEventListener("click", salvarAnuncio);
}

function atualizarCamposVisiveis() {
  const tipo = document.getElementById("anuncio-tipo").value;
  document.getElementById("field-caso").style.display =
    tipo === "caso_destaque" ? "flex" : "none";
  document.getElementById("field-icone").style.display =
    tipo === "dica" ? "flex" : "none";
  document.getElementById("field-imagem").style.display =
    tipo !== "dica" ? "flex" : "none";
}

function resetarFormulario() {
  editandoId = null;
  document.getElementById("form-titulo-label").innerHTML =
    `<i class="fa-solid fa-pen"></i> Criar Novo Anúncio`;
  document.getElementById("btn-salvar-anuncio").innerHTML =
    `<i class="fa-solid fa-floppy-disk"></i> Guardar Anúncio`;
  document.getElementById("anuncio-tipo").value = "dica";
  document.getElementById("anuncio-titulo").value = "";
  document.getElementById("anuncio-conteudo").value = "";
  document.getElementById("anuncio-icone").value = "fa-solid fa-lightbulb";
  document.getElementById("anuncio-imagem").value = "";
  document.getElementById("anuncio-link").value = "";
  document.getElementById("anuncio-ordem").value = "1";
  document.getElementById("anuncio-ativo").checked = true;
  document.getElementById("toggle-label").innerText = "Activo";
  document.getElementById("anuncio-caso-select").value = "";
  atualizarCamposVisiveis();
}

function preencherFormulario(id, data) {
  editandoId = id;
  document.getElementById("anuncio-form-wrapper").classList.remove("hidden");
  document.getElementById("form-titulo-label").innerHTML =
    `<i class="fa-solid fa-pen-to-square"></i> Editar Anúncio`;
  document.getElementById("btn-salvar-anuncio").innerHTML =
    `<i class="fa-solid fa-floppy-disk"></i> Actualizar Anúncio`;

  document.getElementById("anuncio-tipo").value = data.tipo || "dica";
  document.getElementById("anuncio-titulo").value = data.titulo || "";
  document.getElementById("anuncio-conteudo").value = data.conteudo || "";
  document.getElementById("anuncio-icone").value =
    data.icone || "fa-solid fa-lightbulb";
  document.getElementById("anuncio-imagem").value = data.imagem || "";
  document.getElementById("anuncio-link").value = data.link || "";
  document.getElementById("anuncio-ordem").value = data.ordem || 1;
  document.getElementById("anuncio-ativo").checked = data.ativo !== false;
  document.getElementById("toggle-label").innerText =
    data.ativo !== false ? "Activo" : "Inactivo";
  atualizarCamposVisiveis();
  document
    .getElementById("anuncio-form-wrapper")
    .scrollIntoView({ behavior: "smooth" });
}

async function salvarAnuncio() {
  const btn = document.getElementById("btn-salvar-anuncio");
  btn.disabled = true;
  btn.innerHTML = `<i class="fa-solid fa-spinner fa-spin"></i> Guardando...`;

  const tipo = document.getElementById("anuncio-tipo").value;

  // Para caso_destaque: pegar imagem do caso selecionado se não digitou URL
  let imagem = document.getElementById("anuncio-imagem").value.trim();
  if (tipo === "caso_destaque" && !imagem) {
    const sel = document.getElementById("anuncio-caso-select");
    imagem = sel.options[sel.selectedIndex]?.dataset.imagem || "";
  }

  const dados = {
    tipo,
    titulo: document.getElementById("anuncio-titulo").value.trim(),
    conteudo: document.getElementById("anuncio-conteudo").value.trim(),
    icone:
      document.getElementById("anuncio-icone").value.trim() ||
      "fa-solid fa-lightbulb",
    imagem,
    link: document.getElementById("anuncio-link").value.trim(),
    ordem: parseInt(document.getElementById("anuncio-ordem").value) || 1,
    ativo: document.getElementById("anuncio-ativo").checked,
    casoId:
      tipo === "caso_destaque"
        ? document.getElementById("anuncio-caso-select").value
        : "",
    atualizadoEm: new Date().toISOString(),
  };

  if (!dados.titulo) {
    showAlert("Por favor, preencha o Título.");
    btn.disabled = false;
    btn.innerHTML = `<i class="fa-solid fa-floppy-disk"></i> Guardar Anúncio`;
    return;
  }

  try {
    if (editandoId) {
      await updateDoc(doc(db, "anuncios", editandoId), dados);
    } else {
      dados.criadoEm = new Date().toISOString();
      await addDoc(collection(db, "anuncios"), dados);
    }

    showAlert(
      editandoId ? "✅ Anúncio actualizado!" : "✅ Anúncio criado com sucesso!",
      {
        onOk: () => {
          document
            .getElementById("anuncio-form-wrapper")
            .classList.add("hidden");
          resetarFormulario();
          carregarListaAnuncios();
        },
      },
    );
  } catch (err) {
    showAlert("Erro ao guardar: " + err.message);
  } finally {
    btn.disabled = false;
    btn.innerHTML = `<i class="fa-solid fa-floppy-disk"></i> Guardar Anúncio`;
  }
}

// ── Coordenadas por Província (Angola) ─────────────────────────────────
const COORDS_PROV_ADMIN = {
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

let mapaAdminInst = null;
let mapaAdminMarkers = [];

/* =========================================================================
   MAPA ADMIN — inicializar e carregar todos os casos aprovados
   ========================================================================= */
async function iniciarMapaAdmin() {
  const el = document.getElementById("mapa-admin-container");
  if (!el) return;

  // Carregar casos aprovados, encontrados e desmentidos
  let casos = [];
  try {
    const snap = await getDocs(
      query(
        collection(db, "casos"),
        where("status", "in", ["aprovado", "encontrado", "desmentido"]),
      ),
    );
    snap.forEach((d) => casos.push({ id: d.id, ...d.data() }));
  } catch (err) {
    console.error("Erro ao carregar casos para mapa:", err);
    return;
  }

  // Aguardar Google Maps
  function tentarIniciar() {
    if (typeof google === "undefined") {
      setTimeout(tentarIniciar, 300);
      return;
    }
    renderMapaAdmin(el, casos);
  }
  tentarIniciar();
}

function renderMapaAdmin(el, casos) {
  if (!mapaAdminInst) {
    mapaAdminInst = new google.maps.Map(el, {
      center: { lat: -11.2027, lng: 17.8739 },
      zoom: 5,
      mapTypeControl: false,
      streetViewControl: false,
    });
  }

  // Limpar marcadores
  mapaAdminMarkers.forEach((m) => m.setMap(null));
  mapaAdminMarkers = [];

  const infoWindow = new google.maps.InfoWindow();

  const corStatus = {
    aprovado: "#0c7ab5",
    encontrado: "#2ecc71",
    desmentido: "#95a5a6",
  };

  casos.forEach((caso) => {
    let lat = caso.lat ? parseFloat(caso.lat) : null;
    let lng = caso.lng ? parseFloat(caso.lng) : null;
    if (!lat || !lng) {
      const prov = (caso.provincia || "").toLowerCase().replace(/ /g, "_");
      const coords = COORDS_PROV_ADMIN[prov];
      if (!coords) return;
      lat = coords.lat + (Math.random() - 0.5) * 0.6;
      lng = coords.lng + (Math.random() - 0.5) * 0.6;
    }

    const cor = corStatus[caso.status] || "#0c7ab5";
    const marker = new google.maps.Marker({
      position: { lat, lng },
      map: mapaAdminInst,
      title: caso.nome || "Desconhecido",
      icon: {
        path: google.maps.SymbolPath.CIRCLE,
        scale: 10,
        fillColor: cor,
        fillOpacity: 0.9,
        strokeColor: "#ffffff",
        strokeWeight: 2,
      },
    });

    const img = caso.imagem
      ? `<img src="${caso.imagem}" style="width:100%;height:70px;object-fit:cover;border-radius:6px;margin-bottom:6px;">`
      : "";
    const labelStatus =
      {
        aprovado: "🔵 Activo",
        encontrado: "🟢 Encontrado",
        desmentido: "⚫ Desmentido",
      }[caso.status] || caso.status;

    marker.addListener("click", () => {
      infoWindow.setContent(`
        <div style="font-family:'Quicksand',sans-serif;max-width:180px;">
          ${img}
          <strong style="font-size:13px;">${caso.nome || "—"}</strong><br>
          <span style="color:#666;font-size:11px;">${caso.municipio || caso.provincia || "Angola"}</span><br>
          <span style="font-size:11px;">${labelStatus}</span>
        </div>`);
      infoWindow.open(mapaAdminInst, marker);
    });

    mapaAdminMarkers.push(marker);
  });

  // Lista resumo abaixo do mapa
  const listaEl = document.getElementById("mapa-admin-lista");
  if (listaEl) {
    const total = casos.length;
    const ativos = casos.filter((c) => c.status === "aprovado").length;
    const enc = casos.filter((c) => c.status === "encontrado").length;
    listaEl.innerHTML = `
      <div style="display:flex;gap:12px;flex-wrap:wrap;">
        <div class="card-stat" style="flex:1;min-width:120px;">
          <span class="card-stat-icon" style="background:#e3f2fd;color:#0c7ab5;">
            <i class="fa-solid fa-location-dot"></i>
          </span>
          <div><h3>Total no Mapa</h3><p class="stat-big">${total}</p></div>
        </div>
        <div class="card-stat" style="flex:1;min-width:120px;">
          <span class="card-stat-icon" style="background:#e3f2fd;color:#0c7ab5;">
            <i class="fa-solid fa-magnifying-glass"></i>
          </span>
          <div><h3>A Procurar</h3><p class="stat-big">${ativos}</p></div>
        </div>
        <div class="card-stat" style="flex:1;min-width:120px;">
          <span class="card-stat-icon" style="background:#e8f5e9;color:#2ecc71;">
            <i class="fa-solid fa-circle-check"></i>
          </span>
          <div><h3>Encontrados</h3><p class="stat-big">${enc}</p></div>
        </div>
      </div>`;
  }
}

/* =========================================================================
   UTILITÁRIOS
   ========================================================================= */

/* =========================================================================
   NOTIFICAÇÃO POR EMAIL — ALERTA GERAL (EmailJS)
   ========================================================================= */
async function notificarAprovacaoCaso(casoData) {
  try {
    // 1. Buscar todos os emails de todos os utilizadores registados
    const usersSnap = await getDocs(collection(db, "users"));
    const listaEmails = [];
    
    usersSnap.forEach((userDoc) => {
        const email = userDoc.data().email;
        if (email) listaEmails.push(email); 
    });

    // 2. Junta todos os e-mails separados por vírgula para o BCC (Cópia Oculta)
    const emailsFormatados = listaEmails.join(",");

    // 3. Disparar Alerta Geral via EmailJS
    if (emailsFormatados.length > 0) {
        const templateParams = {
            bcc_emails: emailsFormatados,
            nome_desaparecido: casoData.nome || "Desconhecido",
            idade: casoData.idade || "?",
            local: (casoData.ultimo_local || "") + (casoData.municipio ? " - " + casoData.municipio : ""),
            data: casoData.data_desaparecimento || "Data desconhecida",
            roupas: casoData.roupas || "Não informado",
            info: casoData.informacoes_adicionais || "Sem informações adicionais."
        };

        // ATENÇÃO: Substitui pelos teus IDs do EmailJS!
        emailjs.send("service_8fq9usa", "template_366wv9e", templateParams)
            .then(function(response) {
                console.log("[EmailJS] Alerta geral enviado com sucesso!", response.status);
            }, function(error) {
                console.error("[EmailJS] Falha ao enviar alerta...", error);
            });
    }
  } catch (err) {
    console.warn("[EmailJS] Erro ao disparar alerta de e-mail:", err);
  }
}

function calcularDias(dataString) {
  if (!dataString) return 0;
  const d = new Date(dataString);
  if (isNaN(d)) return 0;
  return Math.ceil(Math.abs(new Date() - d) / 86400000);
}

/* =========================================================================
   EDITAR LOCALIZAÇÃO - Corrigir casos antigos sem coordenadas
   ========================================================================= */
let mapaEditarInst = null;
let casoEmEdicao = null;
let coordenada_selecionada = null;

function abrirModalEditarLocalizacao() {
  const modal = document.getElementById("modal-editar-localizacao");
  modal.classList.remove("hidden");

  setTimeout(() => {
    if (!mapaEditarInst) {
      inicializarMapaEditar();
    }
    carregarCasosSemCoordenadas();
  }, 100);
}

function fecharModalEditarLocalizacao() {
  const modal = document.getElementById("modal-editar-localizacao");
  modal.classList.add("hidden");
  casoEmEdicao = null;
  coordenada_selecionada = null;
  document.getElementById("btn-salvar-localizacao").disabled = true;
}

async function carregarCasosSemCoordenadas() {
  const lista = document.getElementById("lista-casos-sem-coord");
  lista.innerHTML = `<div style="padding:16px;text-align:center;"><i class="fa-solid fa-spinner fa-spin"></i> Carregando...</div>`;

  try {
    const snap = await getDocs(
      query(
        collection(db, "casos"),
        where("status", "in", ["aprovado", "encontrado", "desmentido"]),
      ),
    );

    let casosSemCoord = [];
    snap.forEach((d) => {
      const data = d.data();
      if (!data.lat || !data.lng) {
        casosSemCoord.push({ id: d.id, ...data });
      }
    });

    if (casosSemCoord.length === 0) {
      lista.innerHTML = `<div style="padding:16px;text-align:center;color:#666;">✅ Todos os casos têm localização!</div>`;
      document.getElementById("btn-corrigir-localizacoes").disabled = true;
      return;
    }

    lista.innerHTML = "";
    casosSemCoord.forEach((caso) => {
      const item = document.createElement("div");
      item.style.cssText =
        "padding:12px;border-bottom:1px solid #eee;cursor:pointer;transition:background 0.2s;";
      item.innerHTML = `
        <div style="font-weight:600;color:#333;">${caso.nome || "Sem nome"}</div>
        <div style="font-size:12px;color:#666;">${caso.municipio || caso.provincia}</div>
        <div style="font-size:11px;color:#999;">ID: ${caso.id.substring(0, 8)}...</div>
      `;
      item.addEventListener(
        "mouseover",
        () => (item.style.background = "#f5f5f5"),
      );
      item.addEventListener(
        "mouseout",
        () => (item.style.background = "transparent"),
      );
      item.addEventListener("click", () => selecionarCasoParaEditar(caso));
      lista.appendChild(item);
    });
  } catch (err) {
    lista.innerHTML = `<div style="padding:16px;color:#e74c3c;">Erro ao carregar casos</div>`;
    console.error(err);
  }
}

function selecionarCasoParaEditar(caso) {
  casoEmEdicao = caso;
  coordenada_selecionada = null;

  const infoEl = document.getElementById("info-localizacao-selecionada");
  infoEl.innerHTML = `<strong>${caso.nome}</strong><br>${caso.municipio || caso.provincia}<br><span style="color:#999;">Aguardando localização no mapa...</span>`;

  document.getElementById("btn-salvar-localizacao").disabled = true;

  // Destacar item na lista
  document.querySelectorAll("#lista-casos-sem-coord > div").forEach((el) => {
    el.style.background = el.textContent.includes(caso.nome)
      ? "#e3f2fd"
      : "transparent";
  });
}

function inicializarMapaEditar() {
  const mapEl = document.getElementById("mapa-editar-localizacao");
  if (!mapEl) return;

  if (typeof google === "undefined") {
    setTimeout(inicializarMapaEditar, 300);
    return;
  }

  mapaEditarInst = new google.maps.Map(mapEl, {
    center: { lat: -11.2027, lng: 17.8739 },
    zoom: 6,
    mapTypeControl: false,
    streetViewControl: false,
  });

  mapaEditarInst.addListener("click", (e) => {
    if (!casoEmEdicao) {
      showAlert("Selecione um caso à esquerda primeiro.");
      return;
    }

    coordenada_selecionada = {
      lat: e.latLng.lat(),
      lng: e.latLng.lng(),
    };

    const infoEl = document.getElementById("info-localizacao-selecionada");
    infoEl.innerHTML = `<strong>${casoEmEdicao.nome}</strong><br>${casoEmEdicao.municipio || casoEmEdicao.provincia}<br><span style="color:#0c7ab5;">📍 Lat: ${coordenada_selecionada.lat.toFixed(4)}, Lng: ${coordenada_selecionada.lng.toFixed(4)}</span>`;

    document.getElementById("btn-salvar-localizacao").disabled = false;

    // Limpar marcadores anteriores e adicionar novo
    mapaEditarInst.setCenter(coordenada_selecionada);
  });
}

async function salvarLocalizacao() {
  if (!casoEmEdicao || !coordenada_selecionada) {
    showAlert("Selecione um caso e uma localização.");
    return;
  }

  const btn = document.getElementById("btn-salvar-localizacao");
  btn.disabled = true;
  btn.innerHTML = `<i class="fa-solid fa-spinner fa-spin"></i> Salvando...`;

  try {
    await updateDoc(doc(db, "casos", casoEmEdicao.id), {
      lat: coordenada_selecionada.lat.toString(),
      lng: coordenada_selecionada.lng.toString(),
    });

    showAlert(
      `✅ Localização de "${casoEmEdicao.nome}" guardada com sucesso!`,
      {
        onOk: () => {
          casoEmEdicao = null;
          coordenada_selecionada = null;
          carregarCasosSemCoordenadas();
          iniciarMapaAdmin(); // Atualizar mapa principal
          btn.innerHTML = `<i class="fa-solid fa-save"></i> Salvar Localização`;
          btn.disabled = true;
        },
      },
    );
  } catch (err) {
    showAlert(`Erro ao guardar: ${err.message}`);
    btn.innerHTML = `<i class="fa-solid fa-save"></i> Salvar Localização`;
    btn.disabled = false;
  }
}