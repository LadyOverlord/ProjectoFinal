import { auth, db } from "./firebase.js";
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

// ─── Estado Global ────────────────────────────────────────────
let todosUsuarios = [];
let editandoId = null; // ID do anúncio em edição (null = novo)
let formularioConfigurado = false; // Guard: evita listeners duplicados

// ─── Auth + Segurança ─────────────────────────────────────────
onAuthStateChanged(auth, async (user) => {
    if (!user) {
    window.location.href = "login_cadastro.html";
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
  tbody.innerHTML = `<tr><td colspan="5" class="tc">Carregando...</td></tr>`;
  try {
    const snap = await getDocs(collection(db, "users"));
    todosUsuarios = [];
    snap.forEach((d) => todosUsuarios.push({ id: d.id, ...d.data() }));
    renderizarTabelaUsuarios(todosUsuarios);
  } catch (err) {
    tbody.innerHTML = `<tr><td colspan="5" class="tc">Erro ao carregar.</td></tr>`;
  }
}

function renderizarTabelaUsuarios(lista) {
  const tbody = document.getElementById("users-table-body");
  tbody.innerHTML = "";
  if (!lista.length) {
    tbody.innerHTML = `<tr><td colspan="5" class="tc">Nenhum utilizador encontrado.</td></tr>`;
    return;
  }
  lista.forEach((user) => {
    let rawDate = user.ultimoLogin || user.criadoEm;
    let dataTexto = "—";
    let labelTipo = "";
    if (rawDate) {
      const dt = rawDate.toDate ? rawDate.toDate() : new Date(rawDate);
      if (!isNaN(dt)) {
        dataTexto = `${String(dt.getHours()).padStart(2, "0")}:${String(dt.getMinutes()).padStart(2, "0")} · ${dt.getDate()}/${dt.getMonth() + 1}/${dt.getFullYear()}`;
        labelTipo = user.ultimoLogin
          ? `<span class="label-verde">Ativo</span>`
          : `<span class="label-laranja">Novo</span>`;
      }
    }
    tbody.innerHTML += `
      <tr style="border-bottom:1px solid #eee;">
        <td style="padding:12px 10px;">${user.nome || "—"}</td>
        <td style="padding:12px 10px;">${user.email}</td>
        <td style="padding:12px 10px;">
          <span class="role-badge ${user.role === "admin" ? "role-admin" : "role-user"}">
            ${user.role || "user"}
          </span>
        </td>
        <td style="padding:12px 10px;font-size:0.88em;color:#555;">${dataTexto} ${labelTipo}</td>
        <td style="padding:12px 10px;">
          <button onclick="window.excluirUsuario('${user.id}')" class="btn-danger-sm" title="Remover">
            <i class="fa-solid fa-trash"></i>
          </button>
        </td>
      </tr>`;
  });
}

function filtrarUsuarios(termo) {
  const painel = document.getElementById("users");
  if (!painel.classList.contains("active"))
    document.querySelector('[data-target="users"]').click();
  renderizarTabelaUsuarios(
    todosUsuarios.filter(
      (u) =>
        (u.nome || "").toLowerCase().includes(termo) ||
        (u.email || "").toLowerCase().includes(termo),
    ),
  );
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
    snap.forEach((docSnap) => {
      const data = docSnap.data();
      const id = docSnap.id;
      const dias = calcularDias(data.data_desaparecimento);
      const tempo = dias === 0 ? "hoje" : `há ${dias} dias`;

      const card = document.createElement("div");
      card.className = "card-aprovar";
      card.innerHTML = `
        <button class="top-menu-btn btn-rejeitar" data-id="${id}" title="Rejeitar">
          <i class="fa-solid fa-trash"></i>
        </button>
        <div class="card-header-admin">
          <img src="${data.imagem || "imgs/user.jpg"}" class="admin-avatar" onerror="this.src='imgs/user.jpg'" alt="">
          <div class="admin-user-info">
            <h3>${data.nome || "Nome Desconhecido"}</h3>
            <p>${data.idade || "?"} anos</p>
          </div>
        </div>
        <p class="card-desc">Desapareceu em <strong>${data.provincia || "local desconhecido"}</strong> ${tempo}.</p>
        <div class="admin-actions">
          <button class="btn-docs"
            onclick="window.showAlert('BI: ${data.bi || "N/A"}\\nRoupas: ${data.roupas || "N/A"}\\nRelato: ${data.informacoes_adicionais || "Sem detalhes"}')">
            Ver Documentos
          </button>
          <button class="btn-approve-pub" data-id="${id}">Aprovar Publicação</button>
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
            await setDoc(doc(db, "casos", id), {
              ...snap.data(),
              status: "aprovado",
            });
            await deleteDoc(ref);
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
