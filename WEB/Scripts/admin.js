import { auth, db, navigateToLogin, navigateToTarget } from "./firebase.js";
import {
  onAuthStateChanged,
  signOut,
} from "https://www.gstatic.com/firebasejs/12.8.0/firebase-auth.js";
import {
  doc,
  getDoc,
  collection,
  collectionGroup,
  getDocs,
  query,
  where,
  updateDoc,
  deleteDoc,
  deleteField,
  setDoc,
  addDoc,
  orderBy,
  limit,
  serverTimestamp,
  increment as fsIncrement,
} from "https://www.gstatic.com/firebasejs/12.8.0/firebase-firestore.js";
import {
  penalizar,
  ajustarScore,
  reporNivel,
  estadoDeScore,
  labelEstado,
  historico,
} from "./trust_service.js";
// NOVO: envio de push FCM directamente do browser (chave da conta de
// serviço em fcm_config.js). Ver aviso no topo de fcm_push.js.
import { enviarAlertaDesaparecidoWeb } from "./fcm_push.js";
// CORRIGIDO: o import antigo tinha "P_CASO_REJEITADO", que não existe em
// trust_service.js. Um import ES module para um nome que não é exportado
// pelo módulo de destino é um erro fatal de carregamento (SyntaxError:
// "does not provide an export named ...") — o script inteiro falha antes
// de correr uma única linha, e por isso o <body> (que começa com
// display:none no CSS) nunca é revelado. Era esta a causa principal do
// ecrã em branco, juntamente com o bloco de React/JSX que tentaste inserir.

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
      navigateToTarget("index.html");
    }
  } catch {
    navigateToTarget("index.html");
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
      signOut(auth).then(() => navigateToTarget("index.html")),
    );

  document
    .getElementById("btn-voltar-app")
    ?.addEventListener("click", () => navigateToTarget("index.html"));

  document
    .querySelector(".search input")
    ?.addEventListener("keyup", (e) =>
      filtrarUsuarios(e.target.value.toLowerCase()),
    );

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
  configurarFormularioAnuncio();

  // NOVO: menu lateral responsivo (drawer) em ecrãs pequenos.
  configurarMenuMobile();

  // NOVO: liga os controlos dos 3 painéis novos (Comentários, Trust
  // Scores, Suporte). Feito uma única vez, tal como o resto do ficheiro.
  configurarPainelTrustEComentarios();

  // NOVO: a barra de pesquisa do topo só filtra Utilizadores — antes
  // ficava sempre visível em todos os painéis e, ao escrever nela em
  // qualquer outro sítio (Aprovações, Anúncios, etc.), saltava sempre
  // para Utilizadores sem aviso. Agora só aparece nesse painel.
  // Dashboard é o painel activo por defeito ao abrir, por isso escondemos.
  _atualizarBarraPesquisaTopo("dashboard");
}

// ── Mostra a barra de pesquisa do topo só no painel Utilizadores ─────────
function _atualizarBarraPesquisaTopo(id) {
  const searchWrap = document.querySelector("nav .search");
  if (searchWrap) searchWrap.style.display = id === "users" ? "flex" : "none";
}

// NOVO: menu lateral em ecrãs pequenos vira um "drawer" que desliza —
// o botão hambúrguer abre-o, tocar fora (no fundo escurecido) ou
// escolher uma secção fecha-o outra vez.
function configurarMenuMobile() {
  const btn = document.getElementById("btn-menu-mobile");
  const sidebar = document.querySelector(".options");
  const backdrop = document.getElementById("sidebar-backdrop");
  if (!btn || !sidebar || !backdrop) return;

  const abrir = () => {
    sidebar.classList.add("open");
    backdrop.classList.add("active");
  };
  const fechar = () => {
    sidebar.classList.remove("open");
    backdrop.classList.remove("active");
  };

  btn.addEventListener("click", abrir);
  backdrop.addEventListener("click", fechar);

  // Ao escolher uma secção no telemóvel, o menu fecha-se sozinho para
  // revelar o conteúdo. Em ecrã largo isto não faz diferença nenhuma
  // (o menu nem tem a classe "open" para remover).
  document.querySelectorAll(".menu-link[data-target]").forEach((link) => {
    link.addEventListener("click", fechar);
  });
}

/* =========================================================================
   NAVEGAÇÃO
   ========================================================================= */
function configurarNavegacao() {
  const links = document.querySelectorAll(".menu-link[data-target]");
  const panels = document.querySelectorAll(".panel");
  const titulos = {
    dashboard: "Painel de Controle",
    users: "Gestão de Utilizadores",
    reports: "Aprovações Pendentes",
    config: "Gestão de Anúncios",
    "mapa-admin": "Mapa de Casos",
    // NOVO
    comentarios: "Moderação de Comentários",
    trust: "Trust Scores",
    suporte: "Pedidos de Suporte",
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
      _atualizarBarraPesquisaTopo(id);

      if (id === "dashboard") carregarDashboard();
      if (id === "users") carregarUsuarios();
      if (id === "reports") carregarAprovacoes();
      if (id === "config") carregarConfig();
      if (id === "mapa-admin") iniciarMapaAdmin();
      // NOVO
      if (id === "comentarios") carregarComentariosAdmin();
      if (id === "trust") carregarTrustScores();
      if (id === "suporte") carregarSuporte();
    });
  });
}

/* =========================================================================
   DASHBOARD
   ========================================================================= */
async function carregarDashboard() {
  try {
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

let _filtrosConfigurados = false;
function configurarFiltrosUsuarios() {
  if (_filtrosConfigurados) return;
  _filtrosConfigurados = true;

  const ufSearch = document.getElementById("uf-search");
  const ufClear = document.getElementById("uf-search-clear");
  const ufAplicar = document.getElementById("uf-aplicar");
  const ufLimpar = document.getElementById("uf-limpar");
  const ufExportar = document.getElementById("btn-exportar-users");

  ufSearch?.addEventListener("input", () => {
    if (ufClear) ufClear.style.display = ufSearch.value ? "flex" : "none";
    aplicarFiltrosUsuarios();
  });
  ufClear?.addEventListener("click", () => {
    ufSearch.value = "";
    ufClear.style.display = "none";
    aplicarFiltrosUsuarios();
  });

  ["uf-role", "uf-provincia", "uf-data-de", "uf-data-ate", "uf-ordem"].forEach(
    (id) => {
      document
        .getElementById(id)
        ?.addEventListener("change", aplicarFiltrosUsuarios);
    },
  );

  ufAplicar?.addEventListener("click", aplicarFiltrosUsuarios);
  ufLimpar?.addEventListener("click", limparFiltrosUsuarios);
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
    if (termo) {
      const campos = [u.nome || "", u.email || "", u.telefone || ""]
        .join(" ")
        .toLowerCase();
      if (!campos.includes(termo)) return false;
    }
    if (role && (u.role || "user") !== role) return false;
    if (provincia && (u.provincia || "").toLowerCase() !== provincia)
      return false;
    if (dataDe || dataAte) {
      const raw = u.criadoEm;
      if (!raw) return !dataDe;
      const dt = raw.toDate ? raw.toDate() : new Date(raw);
      if (isNaN(dt)) return false;
      const dStr = dt.toISOString().slice(0, 10);
      if (dataDe && dStr < dataDe) return false;
      if (dataAte && dStr > dataAte) return false;
    }
    return true;
  });

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
    const rawCriado = user.criadoEm;
    let dataCadastro = "—";
    if (rawCriado) {
      const dt = rawCriado.toDate ? rawCriado.toDate() : new Date(rawCriado);
      if (!isNaN(dt))
        dataCadastro = `${dt.getDate().toString().padStart(2, "0")}/${(dt.getMonth() + 1).toString().padStart(2, "0")}/${dt.getFullYear()}`;
    }

    const temGPS = !!(user.lat && user.lng);
    const gpsHtml = temGPS
      ? `<span style="color:#2ecc71;font-size:12px;"><i class="fa-solid fa-location-dot"></i> Activa</span>`
      : `<span style="color:#ccc;font-size:12px;"><i class="fa-solid fa-location-dot"></i> Sem GPS</span>`;

    const avatarHtml = user.photoBase64
      ? `<img src="${user.photoBase64}" style="width:32px;height:32px;border-radius:50%;object-fit:cover;flex-shrink:0;">`
      : `<span style="width:32px;height:32px;border-radius:50%;background:#e3f2fd;color:#0c7ab5;display:inline-flex;align-items:center;justify-content:center;font-size:14px;flex-shrink:0;"><i class="fa-solid fa-user"></i></span>`;

    const score = typeof user.trustScore === "number" ? user.trustScore : 100;
    const estado = estadoDeScore(score);
    const estadoBadge = `<span class="trust-badge ${estado}">${labelEstado(estado)} · ${score}/100</span>`;

    tbody.innerHTML += `
      <tr style="border-bottom:1px solid #f2f2f2;">
        <td style="padding:10px;">
          <div style="display:flex;align-items:center;gap:9px;">
            ${avatarHtml}
            <div>
              <div style="font-weight:700;font-size:13px;color:#222;">${user.nome || "—"}</div>
              <div style="font-size:11px;color:#aaa;">#${user.id.slice(0, 8)}</div>
              ${estadoBadge}
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
            <button onclick="window.abrirHistoricoUsuario('${user.id}','${(user.nome || user.email || "").replace(/'/g, "\\'")}')"
               class="btn-admin-icon" title="Ver histórico completo">
              <i class="fa-solid fa-clock-rotate-left" style="font-size:12px;"></i>
            </button>
            <!-- REMOVIDO: botão de Suspender/Reactivar. Passou a ser
                 exclusivo do painel Trust Scores — o mobile nunca teve
                 este botão aqui, só lá; agora o web também não. -->
            <button onclick="window.excluirUsuario('${user.id}')"
               class="btn-admin-icon btn-danger-icon" title="Remover utilizador">
              <i class="fa-solid fa-trash" style="font-size:12px;"></i>
            </button>
          </div>
        </td>
      </tr>`;
  });
}


// REMOVIDO: window.suspenderUsuario() — deixou de haver um botão
// dedicado de "Suspender" (nem aqui, nem no mobile, que nunca teve). A
// suspensão passa a acontecer só como consequência de baixar o Trust
// Score (botão "Ajustar", no painel Trust Scores) até chegar a 0 —
// exactamente como o mobile já funcionava. reactivarUsuario mantém-se,
// é usado pelo botão "Reactivar" desse mesmo painel.
window.reactivarUsuario = async function (uid, nome) {
  if (!confirm(`Reactivar a conta de "${nome}" com 60 pontos de Trust Score?`)) return;
  try {
    await reporNivel(uid, auth.currentUser?.uid);
    showAlert(`✅ Conta de ${nome} reactivada com 60 pontos.`, { onOk: carregarUsuarios });
  } catch (e) {
    showAlert("Erro: " + e.message);
  }
};

// ── Promover/rebaixar utilizador ──────────────────────────────────────────────
window.promoverUsuario = async function (id, roleAtual) {
  const novoRole = roleAtual === "admin" ? "user" : "admin";
  const msg =
    novoRole === "admin"
      ? "Tornar este utilizador Admin?"
      : "Remover privilégios de Admin deste utilizador?";
  if (!confirm(msg)) return;
  try {
    // NOVO: admins não têm Trust Score — remove-o ao promover (some
    // logo da lista de Trust Scores, já filtrada por role) e repõe um
    // valor limpo (100) ao voltar a ser utilizador comum.
    // CORRIGIDO: não limpava suspendedAt/suspensionReason — se a conta
    // alguma vez tivesse sido suspensa antes (mesmo que já reactivada
    // depois), esses campos ficavam por limpar em qualquer dos dois
    // sentidos, criando um estado incoerente (ex: isSuspended:false e
    // trustScore:100 mas com um suspendedAt antigo ainda lá parado).
    const dados =
      novoRole === "admin"
        ? { role: novoRole, trustScore: deleteField(), isSuspended: deleteField(), suspensionReason: deleteField(), suspendedAt: deleteField() }
        : { role: novoRole, trustScore: 100, isSuspended: false, suspensionReason: deleteField(), suspendedAt: deleteField() };
    await updateDoc(doc(db, "users", id), dados);
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
    const casos = [];
    snap.forEach((d) => casos.push({ id: d.id, ...d.data() }));

    const userSnaps = await Promise.all(
      casos.map((c) =>
        c.userId
          ? getDoc(doc(db, "users", c.userId)).catch(() => null)
          : Promise.resolve(null),
      ),
    );

    casos.forEach((data, i) => {
      const id = data.id;
      const dias = calcularDias(data.data_desaparecimento);
      const tempo = dias === 0 ? "hoje" : `há ${dias} dias`;

      const uSnap = userSnaps[i];
      const relator = uSnap?.exists() ? uSnap.data() : null;
      const rNome = relator?.nome || "Utilizador desconhecido";
      const rEmail = relator?.email || "—";
      const rFoto = relator?.photoBase64 || "";
      const rProv = relator?.provincia ? ` · ${relator.provincia}` : "";
      const rUID = data.userId || "";
      let rMembro = "—";
      if (relator?.criadoEm) {
        const dt = relator.criadoEm.toDate
          ? relator.criadoEm.toDate()
          : new Date(relator.criadoEm);
        if (!isNaN(dt))
          rMembro = `${String(dt.getDate()).padStart(2, "0")}/${String(dt.getMonth() + 1).padStart(2, "0")}/${dt.getFullYear()}`;
      }
      const rVerif =
        relator?.emailVerificado === false
          ? `<span class="relator-badge warn">⚠ Email não verificado</span>`
          : `<span class="relator-badge ok">✓ Verificado</span>`;

      const card = document.createElement("div");
      card.className = "card-aprovar";
      card.innerHTML = `
        <button class="top-menu-btn btn-rejeitar" data-id="${id}" title="Rejeitar caso">
          <i class="fa-solid fa-xmark"></i>
        </button>

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
          ${
            data.ultimo_local
              ? `<br><i class="fa-solid fa-location-dot" style="color:#e07a5f;"></i> ${data.ultimo_local}`
              : ""
          }
        </p>

        <div class="admin-actions" style="margin-bottom:0;">
          <button class="btn-docs">
            <i class="fa-solid fa-file-lines"></i> Ver Detalhes
          </button>
          <button class="btn-approve-pub" data-id="${id}">
            <i class="fa-solid fa-circle-check"></i> Aprovar
          </button>
        </div>

        <div class="relator-section">
          <span class="relator-label">
            <i class="fa-solid fa-user-pen"></i> Relatado por
          </span>
          <div class="relator-body">
            ${
              rFoto
                ? `<img src="${rFoto}" class="relator-avatar" onerror="this.style.display='none'" alt="">`
                : `<div class="relator-avatar-ph"><i class="fa-solid fa-user"></i></div>`
            }
            <div class="relator-info">
              <div class="relator-nome">${rNome} ${rVerif}</div>
              <div class="relator-meta">
                <span><i class="fa-solid fa-envelope"></i> ${rEmail}</span>
                <span><i class="fa-solid fa-calendar"></i> Membro desde ${rMembro}${rProv}</span>
              </div>
            </div>
            ${
              rUID
                ? `<a href="profile.html?uid=${rUID}" target="_blank" class="relator-link" title="Ver perfil">
                   <i class="fa-solid fa-arrow-up-right-from-square"></i>
                 </a>`
                : ""
            }
          </div>
        </div>`;
      container.appendChild(card);

      const btnDocsEl = card.querySelector(".btn-docs");
      if (btnDocsEl) {
        btnDocsEl.addEventListener("click", () => {
          openCasoDetalhesModal(data, relator);
        });
      }
    });

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
            await notificarAprovacaoCaso({ id, ...casoData }); // email (EmailJS)
            await notificarPushMobile({ id, ...casoData }); // push FCM (Cloud Function)
            showAlert("✅ Publicação aprovada!", { onOk: carregarAprovacoes });
          }
        } catch (err) {
          showAlert("Erro: " + err.message);
          btn.disabled = false;
        }
      });
    });

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
}

async function carregarListaAnuncios() {
  const listEl = document.getElementById("anuncios-list");
  listEl.innerHTML = `<div class="admin-loader"><i class="fa-solid fa-spinner fa-spin"></i> Carregando...</div>`;

  try {
    const snap = await getDocs(collection(db, "anuncios"));
    listEl.innerHTML = "";

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

    listEl.querySelectorAll(".btn-edit-anuncio").forEach((btn) => {
      btn.addEventListener("click", async () => {
        const snap = await getDoc(doc(db, "anuncios", btn.dataset.id));
        if (!snap.exists()) return;
        preencherFormulario(btn.dataset.id, snap.data());
      });
    });

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

function configurarFormularioAnuncio() {
  if (formularioConfigurado) return;
  formularioConfigurado = true;

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

  document
    .getElementById("anuncio-tipo")
    .addEventListener("change", atualizarCamposVisiveis);

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

  document
    .getElementById("anuncio-ativo")
    .addEventListener("change", function () {
      document.getElementById("toggle-label").innerText = this.checked
        ? "Activo"
        : "Inactivo";
    });

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

async function iniciarMapaAdmin() {
  const el = document.getElementById("mapa-admin-container");
  if (!el) return;

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
   NOTIFICAÇÃO POR EMAIL — ALERTA GERAL (EmailJS)
   ========================================================================= */
async function notificarAprovacaoCaso(casoData) {
  try {
    const usersSnap = await getDocs(collection(db, "users"));
    const listaEmails = [];

    usersSnap.forEach((userDoc) => {
      const email = userDoc.data().email;
      if (email) listaEmails.push(email);
    });

    const emailsFormatados = listaEmails.join(",");

    // ATENÇÃO — Se estás a ver o email chegar só a UM destinatário: isto
    // quase sempre é configuração do TEMPLATE no painel do EmailJS, não
    // deste código. Vai a Email Templates → este template → separador
    // "Settings" → campo "Bcc" → coloca lá {{bcc_emails}}. Sem isso, o
    // EmailJS ignora este parâmetro e só entrega ao endereço fixo no
    // campo "To Email" do template.
    if (emailsFormatados.length > 0) {
      const templateParams = {
        bcc_emails: emailsFormatados,
        nome_desaparecido: casoData.nome || "Desconhecido",
        idade: casoData.idade || "?",
        local:
          (casoData.ultimo_local || "") +
          (casoData.municipio ? " - " + casoData.municipio : ""),
        data: casoData.data_desaparecimento || "Data desconhecida",
        roupas: casoData.roupas || "Não informado",
        info: casoData.informacoes_adicionais || "Sem informações adicionais.",
      };

      emailjs.send("service_8fq9usa", "template_366wv9e", templateParams).then(
        function (response) {
          console.log(
            "[EmailJS] Alerta geral enviado com sucesso!",
            response.status,
          );
        },
        function (error) {
          console.error("[EmailJS] Falha ao enviar alerta...", error);
        },
      );
    }
  } catch (err) {
    console.warn("[EmailJS] Erro ao disparar alerta de e-mail:", err);
  }
}

/* =========================================================================
   NOTIFICAÇÃO PUSH (FCM) — directamente do browser
   Quando um caso é aprovado no web, isto chega também aos telemóveis
   com a app instalada. A chave da conta de serviço vive em
   fcm_config.js e é usada aqui mesmo no cliente — ver os avisos em
   fcm_push.js sobre o que isso implica.
   ========================================================================= */
async function notificarPushMobile(casoData) {
  try {
    const resultado = await enviarAlertaDesaparecidoWeb(casoData);
    console.log("[Push FCM] Notificações enviadas:", resultado);
  } catch (err) {
    // Se aparecer aqui um erro de CORS ("Failed to fetch", "blocked by
    // CORS policy"), é a limitação já esperada: os endpoints da Google
    // usados para assinar/enviar não costumam aceitar pedidos vindos
    // directamente de páginas web. Não bloqueia a aprovação do caso
    // nem o envio do email, que já terminaram antes desta chamada.
    console.warn("[Push FCM] Erro ao enviar (ver fcm_push.js para contexto):", err);
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
let mapaEditarMarker = null; // NOVO: marcador visível da posição seleccionada/actual
let casoEmEdicao = null;
let coordenada_selecionada = null;
let _todosCasosEditarLoc = []; // NOVO: guarda a lista completa para a pesquisa filtrar em memória
let _queryEditarLoc = "";

function abrirModalEditarLocalizacao() {
  const modal = document.getElementById("modal-editar-localizacao");
  modal.classList.remove("hidden");

  setTimeout(() => {
    if (!mapaEditarInst) {
      inicializarMapaEditar();
    }
    carregarTodosCasosParaEditarLocalizacao();
  }, 100);

  // Liga a pesquisa uma única vez (o modal é reaberto várias vezes, mas
  // os elementos do DOM já existem desde o carregamento da página).
  _configurarPesquisaEditarLocalizacao();
}

let _pesquisaLocConfigurada = false;
function _configurarPesquisaEditarLocalizacao() {
  if (_pesquisaLocConfigurada) return;
  _pesquisaLocConfigurada = true;

  const input = document.getElementById("loc-edit-search");
  const clearBtn = document.getElementById("loc-edit-search-clear");

  input?.addEventListener("input", (e) => {
    _queryEditarLoc = e.target.value.toLowerCase().trim();
    if (clearBtn) clearBtn.style.display = _queryEditarLoc ? "flex" : "none";
    _renderizarListaEditarLocalizacao();
  });

  clearBtn?.addEventListener("click", () => {
    if (input) input.value = "";
    _queryEditarLoc = "";
    clearBtn.style.display = "none";
    _renderizarListaEditarLocalizacao();
  });
}

function fecharModalEditarLocalizacao() {
  const modal = document.getElementById("modal-editar-localizacao");
  modal.classList.add("hidden");
  casoEmEdicao = null;
  coordenada_selecionada = null;
  mapaEditarMarker?.setMap(null);
  mapaEditarMarker = null;
  document.getElementById("btn-salvar-localizacao").disabled = true;
}

// Considera coordenadas válidas só se existirem e forem números reais.
function _temCoordValidas(caso) {
  if (!caso.lat || !caso.lng) return false;
  const lat = parseFloat(caso.lat);
  const lng = parseFloat(caso.lng);
  return !isNaN(lat) && !isNaN(lng);
}

// CORRIGIDO: antes só listava os casos SEM localização — não havia forma
// nenhuma de corrigir/mover a localização de um caso que já tivesse GPS,
// mesmo que estivesse errada. Agora lista TODOS os casos activos; os que
// ainda não têm GPS aparecem primeiro (mais urgentes), e cada item mostra
// se já tem localização ou não. O botão "Corrigir Localizações" deixa de
// ficar desactivado quando todos têm GPS — agora serve sempre, para
// corrigir qualquer caso.
async function carregarTodosCasosParaEditarLocalizacao() {
  const lista = document.getElementById("lista-casos-sem-coord");
  lista.innerHTML = `<div style="padding:16px;text-align:center;"><i class="fa-solid fa-spinner fa-spin"></i> Carregando...</div>`;

  try {
    const snap = await getDocs(
      query(
        collection(db, "casos"),
        where("status", "in", ["aprovado", "encontrado", "desmentido"]),
      ),
    );

    const todos = [];
    snap.forEach((d) => todos.push({ id: d.id, ...d.data() }));

    // Casos sem GPS primeiro — são os mais urgentes de corrigir.
    todos.sort((a, b) => (_temCoordValidas(a) ? 1 : 0) - (_temCoordValidas(b) ? 1 : 0));

    _todosCasosEditarLoc = todos;
    document.getElementById("btn-corrigir-localizacoes").disabled = false;
    _renderizarListaEditarLocalizacao();
  } catch (err) {
    lista.innerHTML = `<div style="padding:16px;color:#e74c3c;">Erro ao carregar casos</div>`;
    console.error(err);
  }
}

function _renderizarListaEditarLocalizacao() {
  const lista = document.getElementById("lista-casos-sem-coord");
  if (!lista) return;

  let filtrados = _todosCasosEditarLoc;
  if (_queryEditarLoc) {
    filtrados = filtrados.filter((c) =>
      `${c.nome || ""} ${c.municipio || ""} ${c.provincia || ""}`
        .toLowerCase()
        .includes(_queryEditarLoc),
    );
  }

  if (_todosCasosEditarLoc.length === 0) {
    lista.innerHTML = `<div style="padding:16px;text-align:center;color:#666;">Nenhum caso activo encontrado.</div>`;
    return;
  }

  if (filtrados.length === 0) {
    lista.innerHTML = `<div style="padding:16px;text-align:center;color:#999;">Nenhum resultado para "${escapeHtml(_queryEditarLoc)}".</div>`;
    return;
  }

  lista.innerHTML = "";
  filtrados.forEach((caso) => {
    const temGPS = _temCoordValidas(caso);
    const item = document.createElement("div");
    item.dataset.casoId = caso.id;
    item.style.cssText =
      "padding:12px;border-bottom:1px solid #eee;cursor:pointer;transition:background 0.2s;display:flex;align-items:center;justify-content:space-between;gap:10px;";
    item.innerHTML = `
      <div style="min-width:0;">
        <div style="font-weight:600;color:#333;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;">${escapeHtml(caso.nome || "Sem nome")}</div>
        <div style="font-size:12px;color:#666;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;">${escapeHtml(caso.municipio || caso.provincia || "—")}</div>
      </div>
      <span style="flex-shrink:0;font-size:11px;font-weight:700;display:flex;align-items:center;gap:4px;color:${temGPS ? "#2ecc71" : "#f0a500"};">
        <i class="fa-solid ${temGPS ? "fa-location-crosshairs" : "fa-location-dot"}"></i>
        ${temGPS ? "Tem GPS" : "Sem GPS"}
      </span>
    `;
    item.addEventListener("mouseover", () => {
      if (casoEmEdicao?.id !== caso.id) item.style.background = "#f5f5f5";
    });
    item.addEventListener("mouseout", () => {
      if (casoEmEdicao?.id !== caso.id) item.style.background = "transparent";
    });
    item.addEventListener("click", () => selecionarCasoParaEditar(caso));
    if (casoEmEdicao?.id === caso.id) item.style.background = "#e3f2fd";
    lista.appendChild(item);
  });
}

// CORRIGIDO/NOVO: se o caso já tiver coordenadas, pré-carrega o marcador
// nessa posição em vez de começar em branco — assim o admin vê logo onde
// o caso está marcado actualmente e só precisa de tocar num novo ponto
// se quiser corrigir.
function selecionarCasoParaEditar(caso) {
  casoEmEdicao = caso;

  const infoEl = document.getElementById("info-localizacao-selecionada");
  const temGPS = _temCoordValidas(caso);

  mapaEditarMarker?.setMap(null);
  mapaEditarMarker = null;

  if (temGPS) {
    const lat = parseFloat(caso.lat);
    const lng = parseFloat(caso.lng);
    coordenada_selecionada = { lat, lng };

    infoEl.innerHTML = `<strong>${escapeHtml(caso.nome)}</strong><br>${escapeHtml(caso.municipio || caso.provincia || "")}<br><span style="color:#0c7ab5;">📍 Localização actual: ${lat.toFixed(4)}, ${lng.toFixed(4)} — toque num novo ponto para mover</span>`;
    document.getElementById("btn-salvar-localizacao").disabled = false;

    if (mapaEditarInst) {
      mapaEditarMarker = new google.maps.Marker({
        position: coordenada_selecionada,
        map: mapaEditarInst,
        icon: { url: "https://maps.google.com/mapfiles/ms/icons/orange-dot.png" },
      });
      mapaEditarInst.setCenter(coordenada_selecionada);
      mapaEditarInst.setZoom(13);
    }
  } else {
    coordenada_selecionada = null;
    infoEl.innerHTML = `<strong>${escapeHtml(caso.nome)}</strong><br>${escapeHtml(caso.municipio || caso.provincia || "")}<br><span style="color:#999;">Aguardando localização no mapa...</span>`;
    document.getElementById("btn-salvar-localizacao").disabled = true;
  }

  // Realça o item seleccionado na lista sem depender do texto (usa o id).
  document.querySelectorAll("#lista-casos-sem-coord > div").forEach((el) => {
    el.style.background = el.dataset.casoId === caso.id ? "#e3f2fd" : "transparent";
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
    infoEl.innerHTML = `<strong>${escapeHtml(casoEmEdicao.nome)}</strong><br>${escapeHtml(casoEmEdicao.municipio || casoEmEdicao.provincia || "")}<br><span style="color:#0c7ab5;">📍 Lat: ${coordenada_selecionada.lat.toFixed(4)}, Lng: ${coordenada_selecionada.lng.toFixed(4)}</span>`;

    document.getElementById("btn-salvar-localizacao").disabled = false;

    // NOVO: mostra um marcador visível no ponto escolhido — antes o
    // clique só actualizava o texto, sem nenhuma marca no mapa.
    mapaEditarMarker?.setMap(null);
    mapaEditarMarker = new google.maps.Marker({
      position: coordenada_selecionada,
      map: mapaEditarInst,
      icon: { url: "https://maps.google.com/mapfiles/ms/icons/orange-dot.png" },
    });

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
          mapaEditarMarker?.setMap(null);
          mapaEditarMarker = null;
          carregarTodosCasosParaEditarLocalizacao();
          iniciarMapaAdmin();
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

/* =========================================================================
   MODAL: Detalhes do Caso
   ========================================================================= */
function openCasoDetalhesModal(data, relator) {
  const modal = document.getElementById("modal-caso-detalhes");
  const content = document.getElementById("modal-caso-content");
  if (!modal || !content) {
    const text = buildCasoDetalhesText(data, relator);
    showAlert(text);
    return;
  }

  const rows = [];
  const keys = Object.keys(data || {}).sort();
  keys.forEach((k) => {
    let v = data[k];
    if (v == null || v === "") v = "—";
    else if (v && typeof v.toDate === "function") {
      try {
        const d = v.toDate();
        v = isNaN(d) ? String(v) : d.toLocaleDateString("pt-AO");
      } catch (_) {}
    } else if (typeof v === "object") {
      try {
        v = JSON.stringify(v);
      } catch (_) {}
    }
    rows.push({ k, v });
  });

  const expected = [
    "nome",
    "idade",
    "sexo",
    "bi",
    "provincia",
    "municipio",
    "ultimo_local",
    "data_desaparecimento",
    "roupas",
    "informacoes_adicionais",
    "telefone",
    "email",
    "status",
  ];

  const merged = [];
  expected.forEach((k) => {
    const found = rows.find((r) => r.k === k);
    if (found) merged.push(found);
    else merged.push({ k, v: "—" });
  });

  rows.forEach((r) => {
    if (!expected.includes(r.k)) merged.push(r);
  });

  let html = `<div style="display:flex;flex-direction:column;gap:8px;">
    <div style="display:flex;gap:12px;flex-wrap:wrap;align-items:flex-start;">
      <div style="flex:1;min-width:220px">
        <h4>Resumo</h4>
        <div style="background:#f8f8f8;padding:10px;border-radius:6px;">
          <strong style="display:block;font-size:15px;margin-bottom:6px;">${data.nome || "—"}</strong>
          <div style="font-size:13px;color:#666;">${data.idade || "—"}${data.sexo ? " · " + data.sexo : ""}</div>
          <div style="margin-top:8px;font-size:13px;color:#444;">${data.provincia || "—"}${data.municipio ? " — " + data.municipio : ""}</div>
        </div>
      </div>
      <div style="flex:2;min-width:320px">
        <h4>Campos</h4>
        <table style="width:100%;border-collapse:collapse">
          <tbody>
  `;

  merged.forEach((r) => {
    html += `<tr style="border-bottom:1px solid #eee"><td style="padding:6px 8px;width:36%"><strong>${r.k}</strong></td><td style="padding:6px 8px;color:#333">${escapeHtml(String(r.v))}</td></tr>`;
  });

  html += `</tbody></table></div></div><div style="margin-top:8px;">
    <h4>Relator</h4>
    <div style="background:#fafafa;padding:10px;border-radius:6px;">
      <div><strong>${relator?.nome || "—"}</strong> ${relator?.emailVerificado === false ? '<span style="color:#e67e22">⚠ Email não verificado</span>' : ""}</div>
      <div style="color:#666;margin-top:6px;">${relator?.email || "—"}</div>
    </div>
  </div></div>`;

  content.innerHTML = html;
  modal.classList.remove("hidden");

  document.getElementById("modal-caso-fechar").onclick = closeCasoDetalhesModal;
  document.getElementById("modal-caso-fechar-2").onclick =
    closeCasoDetalhesModal;
  document.getElementById("modal-caso-copiar").onclick = () => {
    const text = buildCasoDetalhesText(data, relator);
    try {
      navigator.clipboard.writeText(text);
      showAlert("Detalhes copiados para a área de transferência.");
    } catch (e) {
      showAlert(text);
    }
  };
}

function closeCasoDetalhesModal() {
  const modal = document.getElementById("modal-caso-detalhes");
  if (modal) modal.classList.add("hidden");
}

function buildCasoDetalhesText(data, relator) {
  const lines = [];
  Object.keys(data || {})
    .sort()
    .forEach((k) => {
      let v = data[k];
      if (v == null || v === "") v = "—";
      else if (v && typeof v.toDate === "function") {
        try {
          v = v.toDate().toLocaleDateString("pt-AO");
        } catch (_) {}
      } else if (typeof v === "object") {
        try {
          v = JSON.stringify(v);
        } catch (_) {
          v = String(v);
        }
      }
      lines.push(`${k}: ${v}`);
    });
  lines.push("");
  lines.push("=== Relator ===");
  lines.push(`nome: ${relator?.nome || "—"}`);
  lines.push(`email: ${relator?.email || "—"}`);
  return lines.join("\n");
}

function escapeHtml(str) {
  return String(str)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/\"/g, "&quot;")
    .replace(/'/g, "&#039;");
}

/* =========================================================================
   HISTÓRICO COMPLETO DO UTILIZADOR
   ========================================================================= */
function formatarDataHist(raw) {
  if (!raw) return "—";
  const dt = raw.toDate ? raw.toDate() : new Date(raw);
  if (isNaN(dt)) return "—";
  return `${String(dt.getDate()).padStart(2, "0")}/${String(dt.getMonth() + 1).padStart(2, "0")}/${dt.getFullYear()} ${String(dt.getHours()).padStart(2, "0")}:${String(dt.getMinutes()).padStart(2, "0")}`;
}

let _histTabsConfigurados = false;
function configurarTabsHistorico() {
  if (_histTabsConfigurados) return;
  _histTabsConfigurados = true;

  document.querySelectorAll(".hist-tab-btn").forEach((btn) => {
    btn.addEventListener("click", () => {
      document
        .querySelectorAll(".hist-tab-btn")
        .forEach((b) => b.classList.remove("active"));
      document
        .querySelectorAll(".hist-tab-content")
        .forEach((c) => c.classList.add("hidden"));

      btn.classList.add("active");
      document.getElementById(btn.dataset.tab)?.classList.remove("hidden");
    });
  });

  document
    .getElementById("modal-historico-fechar")
    ?.addEventListener("click", () =>
      document.getElementById("modal-historico").classList.add("hidden"),
    );
}

window.abrirHistoricoUsuario = async function (uid, nome) {
  configurarTabsHistorico();

  const modal = document.getElementById("modal-historico");
  document.getElementById("modal-historico-nome").innerHTML =
    `<i class="fa-solid fa-clock-rotate-left"></i> Histórico — ${escapeHtml(nome)}`;
  modal.classList.remove("hidden");

  const scoreEl = document.getElementById("modal-historico-score");
  scoreEl.textContent = "A carregar...";
  try {
    const uSnap = await getDoc(doc(db, "users", uid));
    const score = uSnap.exists() && typeof uSnap.data().trustScore === "number"
      ? uSnap.data().trustScore
      : 100;
    scoreEl.textContent = `Trust Score actual: ${score}/100`;
  } catch (_) {
    scoreEl.textContent = "";
  }

  const casosEl = document.getElementById("hist-casos");
  casosEl.innerHTML = "A carregar...";
  try {
    const snap = await getDocs(
      query(
        collection(db, "casos"),
        where("userId", "==", uid),
        orderBy("createdAt", "desc"),
        limit(50),
      ),
    );
    if (snap.empty) {
      casosEl.innerHTML = `<p class="hist-empty">Nenhum caso reportado ainda.</p>`;
    } else {
      casosEl.innerHTML = "";
      snap.forEach((d) => {
        const c = d.data();
        casosEl.innerHTML += `
          <div class="hist-item">
            <strong>${escapeHtml(c.nome || "Sem nome")}</strong> — ${escapeHtml(c.status || "—")}
            <small>${escapeHtml(c.provincia || "—")} · ${formatarDataHist(c.createdAt)}</small>
          </div>`;
      });
    }
  } catch (err) {
    casosEl.innerHTML = `<p class="hist-erro">Erro ao carregar: ${escapeHtml(err.message)}</p>`;
  }

  const comEl = document.getElementById("hist-comentarios");
  comEl.innerHTML = "A carregar...";
  try {
    const snap = await getDocs(
      query(
        collectionGroup(db, "comentarios"),
        where("autorId", "==", uid),
        orderBy("criadoEm", "desc"),
        limit(100),
      ),
    );
    if (snap.empty) {
      comEl.innerHTML = `<p class="hist-empty">Nenhum comentário feito ainda.</p>`;
    } else {
      comEl.innerHTML = "";
      snap.forEach((d) => {
        const c = d.data();
        comEl.innerHTML += `
          <div class="hist-item">
            ${escapeHtml(c.texto || "—")}
            <small>${formatarDataHist(c.criadoEm)}</small>
          </div>`;
      });
    }
  } catch (err) {
    comEl.innerHTML = `<p class="hist-erro">Erro ao carregar: ${escapeHtml(err.message)}</p>`;
  }

  const penEl = document.getElementById("hist-penalizacoes");
  penEl.innerHTML = "A carregar...";
  try {
    const histPen = await historico(uid);
    if (histPen.length === 0) {
      penEl.innerHTML = `<p class="hist-empty">Nenhuma penalização ou ajuste registado.</p>`;
    } else {
      penEl.innerHTML = "";
      histPen.forEach((h) => {
        const pontos = typeof h.pontos === "number" ? h.pontos : 0;
        const cor = pontos >= 0 ? "var(--color-success)" : "var(--color-danger)";
        penEl.innerHTML += `
          <div class="hist-item">
            <strong style="color:${cor};">${pontos >= 0 ? "+" : ""}${pontos}</strong> — ${escapeHtml(h.motivo || "—")}
            <small>${h.scorePrev ?? "?"} → ${h.scoreNovo ?? "?"} pts · ${formatarDataHist(h.criadoEm)}</small>
          </div>`;
      });
    }
  } catch (err) {
    penEl.innerHTML = `<p class="hist-erro">Erro ao carregar: ${escapeHtml(err.message)}</p>`;
  }
};

/* =========================================================================
   NOVO — COMENTÁRIOS (moderação global), TRUST SCORES e SUPORTE
   Tudo em JavaScript puro (DOM + template literals), no MESMO estilo do
   resto deste ficheiro — NADA de React/JSX, que foi a causa do ecrã em
   branco na tentativa anterior.
   ========================================================================= */

// ── Comentários ────────────────────────────────────────────────────────────
let _todosComentariosAdmin = [];

async function carregarComentariosAdmin() {
  const listEl = document.getElementById("comentarios-list");
  if (!listEl) return;
  listEl.innerHTML = `<div class="admin-loader"><i class="fa-solid fa-spinner fa-spin"></i> Carregando comentários...</div>`;
  try {
    const casosSnap = await getDocs(
      query(
        collection(db, "casos"),
        where("status", "in", ["aprovado", "encontrado", "desmentido"]),
      ),
    );
    const lista = [];
    for (const casoDoc of casosSnap.docs) {
      const casoData = casoDoc.data();
      const comsSnap = await getDocs(
        query(
          collection(db, "casos", casoDoc.id, "comentarios"),
          orderBy("criadoEm", "desc"),
        ),
      );
      comsSnap.forEach((c) => {
        lista.push({
          id: c.id,
          casoId: casoDoc.id,
          casoNome: casoData.nome || "Sem nome",
          ...c.data(),
        });
      });
    }
    lista.sort((a, b) => {
      const ta = a.criadoEm?.toDate ? a.criadoEm.toDate().getTime() : 0;
      const tb = b.criadoEm?.toDate ? b.criadoEm.toDate().getTime() : 0;
      return tb - ta;
    });
    _todosComentariosAdmin = lista;
    renderizarComentariosAdmin(lista);
  } catch (err) {
    listEl.innerHTML = `<p class="tc" style="color:#e74c3c;padding:20px 0;">Erro: ${escapeHtml(err.message)}</p>`;
  }
}

function renderizarComentariosAdmin(lista) {
  const listEl = document.getElementById("comentarios-list");
  if (!listEl) return;

  if (lista.length === 0) {
    listEl.innerHTML = `<p class="tc" style="padding:24px 0;color:#999;">Nenhum comentário encontrado.</p>`;
    return;
  }

  listEl.innerHTML = "";
  lista.forEach((c) => {
    const dt = c.criadoEm?.toDate ? c.criadoEm.toDate() : null;
    const ts = dt
      ? `${String(dt.getDate()).padStart(2, "0")}/${String(dt.getMonth() + 1).padStart(2, "0")}/${dt.getFullYear()} ${String(dt.getHours()).padStart(2, "0")}:${String(dt.getMinutes()).padStart(2, "0")}`
      : "—";
    const row = document.createElement("div");
    row.className = "hist-item";
    row.style.cssText =
      "display:flex;gap:12px;align-items:flex-start;padding:12px 0;";
    row.innerHTML = `
      <div style="flex:1;min-width:0;">
        <div style="font-size:12px;color:var(--gray-500);margin-bottom:4px;">
          <strong style="color:var(--gray-700);">${escapeHtml(c.autorNome || "Utilizador")}</strong>
          · caso: ${escapeHtml(c.casoNome)} · ${ts}
        </div>
        <div style="font-size:13px;color:var(--gray-700);">${escapeHtml(c.texto || "—")}</div>
      </div>
      <button class="btn-danger-sm btn-apagar-comentario"
        data-caso="${c.casoId}" data-com="${c.id}"
        data-autor="${c.autorId || ""}"
        data-nome="${(c.autorNome || "").replace(/"/g, "&quot;")}"
        title="Apagar comentário">
        <i class="fa-solid fa-trash"></i>
      </button>`;
    listEl.appendChild(row);
  });

  listEl.querySelectorAll(".btn-apagar-comentario").forEach((btn) => {
    btn.addEventListener("click", () =>
      abrirConfirmarApagarComentario(btn.dataset),
    );
  });
}

function abrirConfirmarApagarComentario({ caso, com, autor, nome }) {
  const pontosStr = prompt(
    `Apagar comentário de "${nome || "utilizador"}".\n\nPenalização ao autor (pontos a retirar do Trust Score):\n0 = sem penalização, ou 5, 10, 20...`,
    "10",
  );
  if (pontosStr === null) return;
  const pontos = parseInt(pontosStr, 10);
  if (isNaN(pontos) || pontos < 0) {
    showAlert("Valor inválido.");
    return;
  }
  _apagarComentarioAdmin(caso, com, autor, pontos);
}

async function _apagarComentarioAdmin(casoId, comentarioId, autorId, pontos) {
  try {
    await deleteDoc(doc(db, "casos", casoId, "comentarios", comentarioId));
    await updateDoc(doc(db, "casos", casoId), {
      comentarios: fsIncrement(-1),
    });
    if (autorId && pontos > 0) {
      await penalizar(
        autorId,
        pontos,
        "comentario_removido",
        auth.currentUser?.uid,
        "Comentário apagado pelo painel de Moderação (web).",
      );
    }
    showAlert(
      pontos > 0
        ? `✅ Comentário apagado. −${pontos} pontos aplicados ao autor.`
        : "✅ Comentário apagado.",
      { onOk: carregarComentariosAdmin },
    );
  } catch (err) {
    showAlert("Erro: " + err.message);
  }
}

// ── Trust Scores ─────────────────────────────────────────────────────────
let _todosUsuariosTrust = [];
let _filtroEstadoTrust = "";
let _queryTrust = ""; // NOVO — texto de pesquisa por nome/email
let _ajustarScoreAlvo = null;

async function carregarTrustScores() {
  const listEl = document.getElementById("trust-list");
  if (!listEl) return;
  listEl.innerHTML = `<div class="admin-loader"><i class="fa-solid fa-spinner fa-spin"></i> Carregando...</div>`;
  try {
    // CORRIGIDO: carregava TODOS os utilizadores, incluindo admins —
    // que não devem ter Trust Score (essa pontuação é um conceito só de
    // utilizadores comuns). Filtra aqui em vez de na query do Firestore
    // para não precisar de um índice novo, já que esta colecção não é
    // grande.
    const snap = await getDocs(collection(db, "users"));
    const lista = [];
    snap.forEach((d) => {
      const u = { id: d.id, ...d.data() };
      if ((u.role || "user") === "user") lista.push(u);
    });
    lista.sort((a, b) => (a.trustScore ?? 100) - (b.trustScore ?? 100));
    _todosUsuariosTrust = lista;
    renderizarTrustScores(lista);
  } catch (err) {
    listEl.innerHTML = `<p class="tc" style="color:#e74c3c;padding:20px 0;">Erro: ${escapeHtml(err.message)}</p>`;
  }
}

function renderizarTrustScores(lista) {
  const listEl = document.getElementById("trust-list");
  if (!listEl) return;

  // NOVO: os dois filtros (estado + texto) aplicam-se em conjunto —
  // antes só existia o filtro de estado.
  let filtrados = _filtroEstadoTrust
    ? lista.filter((u) => estadoDeScore(u.trustScore ?? 100) === _filtroEstadoTrust)
    : lista;

  if (_queryTrust) {
    filtrados = filtrados.filter((u) =>
      `${u.nome || ""} ${u.email || ""}`.toLowerCase().includes(_queryTrust),
    );
  }

  const countEl = document.getElementById("trust-filtro-count");
  if (countEl) {
    countEl.textContent =
      _filtroEstadoTrust || _queryTrust
        ? `${filtrados.length} utilizador${filtrados.length !== 1 ? "es" : ""} encontrado${filtrados.length !== 1 ? "s" : ""}`
        : "";
  }

  if (filtrados.length === 0) {
    listEl.innerHTML = `<p class="tc" style="padding:24px 0;color:#999;">Nenhum utilizador encontrado.</p>`;
    return;
  }

  listEl.innerHTML = "";
  filtrados.forEach((u) => {
    const score = u.trustScore ?? 100;
    const estado = estadoDeScore(score);
    const isSusp = u.isSuspended === true || score <= 0;
    const corBarra =
      score <= 0
        ? "var(--color-danger)"
        : score <= 59
          ? "var(--color-warning)"
          : "var(--color-success)";
    const row = document.createElement("div");
    // CORRIGIDO: usava a classe partilhada .anuncio-row (feita para a
    // lista de Anúncios), que é um único flex row sem quebra entre o
    // nome/email e a barra+badge+botões. Em ecrãs de telemóvel isso
    // deixava quase zero espaço para o nome (aparecia cortado a 2-3
    // letras) porque a barra+badge+2 botões, sem encolher, ocupavam
    // quase toda a largura. Agora usa uma classe própria (.trust-row)
    // que empilha em coluna abaixo de 640px — ver admin.css.
    row.className = "trust-row";
    row.innerHTML = `
      <div class="trust-row-info">
        <strong>${escapeHtml(u.nome || u.email || "—")}</strong>
        <span>${escapeHtml(u.email || "—")}</span>
      </div>
      <div class="trust-row-meta">
        <div class="trust-row-bar">
          <div class="trust-row-bar-fill" style="width:${Math.max(0, Math.min(100, score))}%;background:${corBarra};"></div>
        </div>
        <span class="trust-badge ${estado}">${labelEstado(estado)} · ${score}/100</span>
        <button class="btn-admin-sm btn-trust-historico" data-id="${u.id}" data-nome="${(u.nome || u.email || "").replace(/"/g, "&quot;")}">Histórico</button>
        <button class="btn-admin-sm btn-trust-ajustar" data-id="${u.id}" data-nome="${(u.nome || u.email || "").replace(/"/g, "&quot;")}" data-score="${score}">Ajustar</button>
        ${
          isSusp
            ? `<button class="btn-admin-icon btn-success-icon btn-trust-reactivar" data-id="${u.id}" data-nome="${(u.nome || u.email || "").replace(/"/g, "&quot;")}" title="Reactivar"><i class="fa-solid fa-lock-open"></i></button>`
            : ""
        }
      </div>`;
    listEl.appendChild(row);
  });

  listEl.querySelectorAll(".btn-trust-historico").forEach((btn) =>
    btn.addEventListener("click", () =>
      window.abrirHistoricoUsuario(btn.dataset.id, btn.dataset.nome),
    ),
  );
  listEl.querySelectorAll(".btn-trust-ajustar").forEach((btn) =>
    btn.addEventListener("click", () =>
      abrirModalAjustarScore(
        btn.dataset.id,
        btn.dataset.nome,
        parseInt(btn.dataset.score, 10),
      ),
    ),
  );
  listEl.querySelectorAll(".btn-trust-reactivar").forEach((btn) =>
    btn.addEventListener("click", () =>
      window.reactivarUsuario(btn.dataset.id, btn.dataset.nome),
    ),
  );
}

// NOVO: score actual do utilizador em edição, usado para calcular a
// pré-visualização em tempo real enquanto se arrasta o slider (igual ao
// _AjustarScoreDialog do mobile).
let _ajustarScoreAtualValor = 100;

function abrirModalAjustarScore(uid, nome, scoreAtual) {
  _ajustarScoreAlvo = uid;
  _ajustarScoreAtualValor = scoreAtual;

  const nomeEl = document.getElementById("ajustar-score-nome");
  if (nomeEl) nomeEl.textContent = nome;

  const slider = document.getElementById("ajustar-score-slider");
  if (slider) slider.value = "-10";

  const motivoEl = document.getElementById("ajustar-score-motivo");
  if (motivoEl) motivoEl.value = "";

  _atualizarPreviewAjusteScore();
  document.getElementById("modal-ajustar-score")?.classList.remove("hidden");
}

// Actualiza os números "score actual → preview" e a legenda dos pontos
// sempre que o slider é movido.
function _atualizarPreviewAjusteScore() {
  const slider = document.getElementById("ajustar-score-slider");
  if (!slider) return;
  const delta = parseInt(slider.value, 10);
  const atual = _ajustarScoreAtualValor;
  const preview = Math.max(0, Math.min(100, atual + delta));

  const atualEl = document.getElementById("ajustar-score-atual");
  if (atualEl) atualEl.textContent = atual;

  const previewEl = document.getElementById("ajustar-score-preview");
  if (previewEl) {
    previewEl.textContent = preview;
    previewEl.style.color =
      preview <= 0
        ? "var(--color-danger)"
        : preview <= 59
          ? "var(--color-warning)"
          : "var(--color-success)";
  }

  const labelEl = document.getElementById("ajustar-score-delta-label");
  if (labelEl) {
    labelEl.textContent =
      delta === 0 ? "Sem alteração" : `${delta > 0 ? "+" : ""}${delta} pontos`;
    labelEl.style.color =
      delta > 0
        ? "var(--color-success)"
        : delta < 0
          ? "var(--color-danger)"
          : "var(--gray-500)";
  }
}

// ── Suporte ───────────────────────────────────────────────────────────────
async function carregarSuporte() {
  const listEl = document.getElementById("suporte-list");
  if (!listEl) return;
  listEl.innerHTML = `<div class="admin-loader"><i class="fa-solid fa-spinner fa-spin"></i> Carregando...</div>`;
  try {
    const snap = await getDocs(
      query(collection(db, "suporte_suspensao"), orderBy("criadoEm", "desc")),
    );
    if (snap.empty) {
      listEl.innerHTML = `<p class="tc" style="padding:30px 0;color:#999;">Nenhum pedido de suporte.</p>`;
      return;
    }
    listEl.innerHTML = "";
    snap.forEach((d) => {
      const s = d.data();
      const pendente = (s.status || "pendente") === "pendente";
      const dt = s.criadoEm?.toDate ? s.criadoEm.toDate() : null;
      const ts = dt
        ? `${String(dt.getDate()).padStart(2, "0")}/${String(dt.getMonth() + 1).padStart(2, "0")}/${dt.getFullYear()}`
        : "—";
      const historicoChat = s.historico || [];

      const card = document.createElement("div");
      card.className = "card-aprovar card-suporte";
      card.style.borderLeft = `4px solid ${pendente ? "var(--color-warning)" : "var(--color-success)"}`;
      const score = s.trustScore ?? 0;
      card.innerHTML = `
        <div class="card-header-admin" style="align-items:flex-start;">
          <div style="width:48px;height:48px;border-radius:50%;flex-shrink:0;display:flex;align-items:center;justify-content:center;
            background:${pendente ? "var(--color-warning-soft)" : "var(--color-success-soft)"};">
            <i class="fa-solid ${pendente ? "fa-hourglass-half" : "fa-circle-check"}"
               style="font-size:18px;color:${pendente ? "var(--color-warning)" : "var(--color-success)"};"></i>
          </div>
          <div class="admin-user-info" style="flex:1;min-width:0;">
            <h3>${escapeHtml(s.nome || s.email || "—")}</h3>
            <p><i class="fa-solid fa-envelope" style="opacity:.6;margin-right:4px;"></i>${escapeHtml(s.email || "—")}</p>
          </div>
          <span class="trust-badge ${pendente ? "risco" : "normal"}" style="flex-shrink:0;">
            ${pendente ? "PENDENTE" : "RESOLVIDO"}
          </span>
        </div>

        <!-- NOVO: barra de score visual, igual em espírito ao painel Trust Scores -->
        <div style="display:flex;align-items:center;gap:10px;margin:14px 0 16px;padding:10px 14px;background:var(--gray-50);border-radius:var(--radius-md);">
          <span style="font-size:13px;font-weight:800;color:var(--color-danger);min-width:52px;">${score}/100</span>
          <div style="flex:1;height:6px;background:var(--gray-200);border-radius:3px;overflow:hidden;">
            <div style="width:${Math.max(0, Math.min(100, score))}%;height:100%;background:var(--color-danger);"></div>
          </div>
        </div>

        <p class="card-desc" style="margin-bottom:16px;">
          <strong>Motivo da suspensão:</strong> ${escapeHtml(s.suspensionReason || "—")}
          <br><span style="color:var(--gray-400);font-size:12px;">Pedido enviado em ${ts}</span>
        </p>

        <!-- NOVO: o histórico do chat só mostra o que o utilizador DISSE,
             não o que ele FEZ. Este botão abre o mesmo modal de histórico
             completo (casos, comentários, penalizações) já usado no
             painel Trust Scores — igual ao mobile. -->
        <button class="btn-approve-pub btn-ver-historico-completo"
          data-uid="${s.uid || ""}"
          data-nome="${(s.nome || s.email || "").replace(/"/g, "&quot;")}"
          style="width:100%;margin-bottom:10px;justify-content:center;">
          <i class="fa-solid fa-clock-rotate-left"></i> Ver histórico completo de actividade
        </button>

        <button class="btn-docs btn-ver-historico-chat" data-key="${d.id}" style="width:100%;justify-content:center;">
          <i class="fa-solid fa-comments"></i> Ver histórico do chat (${historicoChat.length})
        </button>
        <div class="hist-chat-box hist-chat-${d.id}" style="display:none;margin-top:12px;max-height:260px;overflow-y:auto;background:var(--gray-50);border-radius:10px;padding:10px;"></div>
        ${
          pendente
            ? `<div class="admin-actions" style="margin-top:16px;">
                 <button class="btn-docs btn-suporte-manter" data-id="${d.id}">Manter suspensão</button>
                 <button class="btn-approve-pub btn-suporte-reactivar" data-id="${d.id}" data-uid="${s.uid || ""}" data-nome="${(s.nome || s.email || "").replace(/"/g, "&quot;")}">
                   <i class="fa-solid fa-lock-open"></i> Reactivar conta
                 </button>
               </div>`
            : `<div style="margin-top:14px;padding:10px 14px;background:var(--color-success-soft);border-radius:var(--radius-md);font-size:12px;color:var(--color-success);display:flex;align-items:center;gap:8px;">
                 <i class="fa-solid fa-circle-check"></i>
                 Resolvido ${s.accao === "reativacao" ? "— conta reactivada" : "— suspensão mantida"}
               </div>`
        }
      `;
      listEl.appendChild(card);

      card
        .querySelector(".btn-ver-historico-completo")
        .addEventListener("click", (e) => {
          const uid = e.currentTarget.dataset.uid;
          const nome = e.currentTarget.dataset.nome;
          if (!uid) {
            showAlert("Este pedido não tem um UID de utilizador válido.");
            return;
          }
          window.abrirHistoricoUsuario(uid, nome);
        });

      card
        .querySelector(".btn-ver-historico-chat")
        .addEventListener("click", () => {
          const box = card.querySelector(`.hist-chat-${d.id}`);
          const visivel = box.style.display !== "none";
          if (visivel) {
            box.style.display = "none";
            return;
          }
          box.style.display = "block";
          box.innerHTML =
            historicoChat
              .map(
                (m) => `
            <div style="margin-bottom:8px;text-align:${m.isUser ? "right" : "left"};">
              <span style="display:inline-block;max-width:80%;padding:8px 12px;border-radius:10px;font-size:13px;
                background:${m.isUser ? "var(--color-quaternary)" : "#fff"};color:${m.isUser ? "#fff" : "var(--gray-700)"};
                border:${m.isUser ? "none" : "1px solid var(--gray-200)"};">
                ${escapeHtml(m.texto || "")}
              </span>
            </div>`,
              )
              .join("") || `<p class="hist-empty">Sem mensagens.</p>`;
        });

      const btnManter = card.querySelector(".btn-suporte-manter");
      if (btnManter)
        btnManter.addEventListener("click", () =>
          _resolverSuporte(d.id, "suspensao_mantida"),
        );

      const btnReactivar = card.querySelector(".btn-suporte-reactivar");
      if (btnReactivar)
        btnReactivar.addEventListener("click", () =>
          _reativarPeloSuporte(
            d.id,
            btnReactivar.dataset.uid,
            btnReactivar.dataset.nome,
          ),
        );
    });
  } catch (err) {
    listEl.innerHTML = `<p class="tc" style="color:#e74c3c;padding:20px 0;">Erro: ${escapeHtml(err.message)}</p>`;
  }
}

async function _resolverSuporte(pedidoId, accao) {
  try {
    await updateDoc(doc(db, "suporte_suspensao", pedidoId), {
      status: "resolvido",
      resolvidoPor: auth.currentUser?.uid,
      resolvidoEm: serverTimestamp(),
      accao,
    });
    carregarSuporte();
  } catch (err) {
    showAlert("Erro: " + err.message);
  }
}

async function _reativarPeloSuporte(pedidoId, uid, nome) {
  if (!uid) {
    showAlert("Este pedido não tem um UID de utilizador válido.");
    return;
  }
  if (!confirm(`Reactivar a conta de "${nome}" com 60 pontos de Trust Score?`))
    return;
  try {
    await reporNivel(uid, auth.currentUser?.uid);
    await _resolverSuporte(pedidoId, "reativacao");
    showAlert(`✅ Conta de ${nome} reactivada.`, { onOk: carregarSuporte });
  } catch (err) {
    showAlert("Erro: " + err.message);
  }
}

// ── Wiring (executado uma única vez a partir de iniciarAdmin) ────────────
function configurarPainelTrustEComentarios() {
  document
    .getElementById("com-search")
    ?.addEventListener("input", (e) => {
      const q = e.target.value.toLowerCase();
      const filtrados = _todosComentariosAdmin.filter(
        (c) =>
          (c.texto || "").toLowerCase().includes(q) ||
          (c.autorNome || "").toLowerCase().includes(q) ||
          (c.casoNome || "").toLowerCase().includes(q),
      );
      renderizarComentariosAdmin(filtrados);
    });

  document.querySelectorAll("#trust-filtro-estado button").forEach((btn) => {
    btn.addEventListener("click", () => {
      _filtroEstadoTrust = btn.dataset.estado;
      document
        .querySelectorAll("#trust-filtro-estado button")
        .forEach((b) => b.classList.remove("filtro-ativo"));
      btn.classList.add("filtro-ativo");
      renderizarTrustScores(_todosUsuariosTrust);
    });
  });

  // NOVO: pesquisa por nome/email no painel Trust Scores.
  document.getElementById("trust-search")?.addEventListener("input", (e) => {
    _queryTrust = e.target.value.toLowerCase().trim();
    const clearBtn = document.getElementById("trust-search-clear");
    if (clearBtn) clearBtn.style.display = _queryTrust ? "flex" : "none";
    renderizarTrustScores(_todosUsuariosTrust);
  });
  document
    .getElementById("trust-search-clear")
    ?.addEventListener("click", () => {
      const input = document.getElementById("trust-search");
      if (input) input.value = "";
      _queryTrust = "";
      const clearBtn = document.getElementById("trust-search-clear");
      if (clearBtn) clearBtn.style.display = "none";
      renderizarTrustScores(_todosUsuariosTrust);
    });

  // NOVO: pré-visualização ao vivo enquanto se arrasta o slider.
  document
    .getElementById("ajustar-score-slider")
    ?.addEventListener("input", _atualizarPreviewAjusteScore);

  document
    .getElementById("btn-cancelar-ajustar-score")
    ?.addEventListener("click", () => {
      document.getElementById("modal-ajustar-score").classList.add("hidden");
    });

  document
    .getElementById("btn-confirmar-ajustar-score")
    ?.addEventListener("click", async () => {
      // CORRIGIDO: lê o valor do slider (ajustar-score-slider), não de
      // um campo de texto "ajustar-score-pontos" que já não existe.
      const delta = parseInt(
        document.getElementById("ajustar-score-slider").value,
        10,
      );
      const motivo =
        document.getElementById("ajustar-score-motivo").value.trim() ||
        "ajuste_manual";
      if (isNaN(delta) || delta === 0) {
        showAlert("Mova o slider para um valor diferente de 0.");
        return;
      }
      try {
        await ajustarScore(_ajustarScoreAlvo, delta, auth.currentUser?.uid, motivo);
        document.getElementById("modal-ajustar-score").classList.add("hidden");
        showAlert(`✅ Score ajustado em ${delta >= 0 ? "+" : ""}${delta}.`, {
          onOk: carregarTrustScores,
        });
      } catch (err) {
        showAlert("Erro: " + err.message);
      }
    });
}