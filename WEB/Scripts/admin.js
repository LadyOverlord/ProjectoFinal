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
  setDoc
} from "https://www.gstatic.com/firebasejs/12.8.0/firebase-firestore.js";

// === VARIÁVEIS GLOBAIS ===
let todosUsuarios = []; // Essencial para a pesquisa funcionar

// === 1. VERIFICAÇÃO DE SEGURANÇA (ADMIN) ===
onAuthStateChanged(auth, async (user) => {
if (user) {
try {
const docRef = doc(db, "users", user.uid);
const docSnap = await getDoc(docRef);

if (docSnap.exists() && docSnap.data().role === 'admin') {
            // É Admin: Mostra o painel e carrega os dados
            console.log("Admin logado:", user.email);
            iniciarAdmin();
        } else {
            // Não é admin: Expulsa
         
            window.location.href = "index.html";
        }
    } catch (error) {
        console.error("Erro ao verificar admin:", error);
        window.location.href = "index.html";
    }
} else {
    // Não está logado: Expulsa
    window.location.href = "login_cadastro.html";
}
});

// === 2. INICIALIZAÇÃO DO PAINEL ===
function iniciarAdmin() {
  configurarNavegacao();

  // Configura o botão de Sair
  document.getElementById("btn-logout").addEventListener("click", () => {
    signOut(auth).then(() => (window.location.href = "index.html"));
  });

  // === CONFIGURAR PESQUISA (Nav Superior) ===
  const searchInput = document.querySelector(".search input");
  if (searchInput) {
    searchInput.addEventListener("keyup", (e) => {
      filtrarUsuarios(e.target.value.toLowerCase());
    });
  }

  // Carrega a Dashboard inicial
  carregarDashboard();
}

// === 3. NAVEGAÇÃO ENTRE ABAS ===
function configurarNavegacao() {
  const links = document.querySelectorAll(".menu-link");
  const panels = document.querySelectorAll(".panel");

  links.forEach((link) => {
    link.addEventListener("click", (e) => {
      e.preventDefault();

      links.forEach((l) => l.classList.remove("active"));
      panels.forEach((p) => p.classList.remove("active"));

      link.classList.add("active");
      const targetId = link.getAttribute("data-target");
      document.getElementById(targetId).classList.add("active");

      if (targetId === "dashboard") carregarDashboard();
      if (targetId === "users") carregarUsuarios();
      if (targetId === "reports") carregarAprovacoes();
    });
  });
}

// === 4. DASHBOARD (VISÃO GERAL + GESTÃO DE ATIVOS) ===
async function carregarDashboard() {
  try {
    // A. Contadores
    const usersSnap = await getDocs(collection(db, "users"));
    document.getElementById("count-users").innerText = usersSnap.size;

    // ALTERAÇÃO: Conta os documentos diretamente da coleção casos_pendentes
    const reportsSnap = await getDocs(collection(db, "casos_pendentes"));
    document.getElementById("count-reports").innerText = reportsSnap.size;

    // B. Tabela de Casos Ativos (Para mudar status)
    const activeBody = document.getElementById("active-cases-body");
    if (activeBody) {
      activeBody.innerHTML = '<tr><td colspan="4" style="text-align:center;">Carregando casos ativos...</td></tr>';

      // Busca casos que estão visíveis no site (aprovado, encontrado, desmentido) na coleção oficial 'casos'
      const qAtivos = query(
        collection(db, "casos"),
        where("status", "in", ["aprovado", "encontrado", "desmentido"]),
      );
      const snapAtivos = await getDocs(qAtivos);

      activeBody.innerHTML = "";

      if (snapAtivos.empty) {
        activeBody.innerHTML = '<tr><td colspan="4" style="text-align:center;">Nenhum caso ativo.</td></tr>';
      } else {
        snapAtivos.forEach((doc) => {
          const data = doc.data();
          const tr = document.createElement("tr");
          tr.style.borderBottom = "1px solid #eee";

          const selectHtml = `
              <select class="status-select" style="padding: 5px; border-radius: 4px; border: 1px solid #ccc; font-family: var(--font-base);">
                  <option value="aprovado" ${data.status === "aprovado" ? "selected" : ""}>Ativo (Procurando)</option>
                  <option value="encontrado" ${data.status === "encontrado" ? "selected" : ""}>🟢 Encontrado</option>
                  <option value="desmentido" ${data.status === "desmentido" ? "selected" : ""}>⚫ Desmentido</option>
                  <option value="rejeitado" ${data.status === "rejeitado" ? "selected" : ""}>🔴 Arquivar/Remover</option>
              </select>
          `;

          tr.innerHTML = `
              <td style="padding: 10px;">${data.nome || "Desconhecido"}</td>
              <td style="padding: 10px;">${data.municipio || "-"}</td>
              <td style="padding: 10px;">${selectHtml}</td>
              <td style="padding: 10px;">
                  <button class="btn-save-status" data-id="${doc.id}" style="background: #0c7ab5; color: white; border: none; padding: 5px 10px; border-radius: 4px; cursor: pointer;">Salvar</button>
              </td>
          `;
          activeBody.appendChild(tr);
        });

        // Eventos dos botões Salvar
        document.querySelectorAll(".btn-save-status").forEach((btn) => {
          btn.addEventListener("click", async (e) => {
            const id = e.target.getAttribute("data-id");
            const row = e.target.closest("tr");
            const novoStatus = row.querySelector(".status-select").value;

            try {
              e.target.innerText = "...";
              await updateDoc(doc(db, "casos", id), { status: novoStatus });
              showAlert(`Status atualizado para: ${novoStatus}`, { onOk: carregarDashboard });
            } catch (err) {
              showAlert("Erro: " + err.message);
              e.target.innerText = "Salvar";
            }
          });
        });
      }
    }
  } catch (error) {
    console.error("Erro no dashboard:", error);
  }
}

// === 5. GESTÃO DE USUÁRIOS (COM DATA E PESQUISA) ===
async function carregarUsuarios() {
  const tbody = document.getElementById("users-table-body");
  tbody.innerHTML =
    '<tr><td colspan="5" style="text-align:center;">Carregando usuários...</td></tr>';

  try {
    const querySnapshot = await getDocs(collection(db, "users"));
    todosUsuarios = []; // Limpa a global

    querySnapshot.forEach((doc) => {
      let u = doc.data();
      u.id = doc.id;
      todosUsuarios.push(u);
    });

    renderizarTabelaUsuarios(todosUsuarios);
  } catch (error) {
    console.error("Erro usuarios:", error);
    tbody.innerHTML = '<tr><td colspan="5">Erro ao carregar.</td></tr>';
  }
}

function renderizarTabelaUsuarios(lista) {
  const tbody = document.getElementById("users-table-body");
  tbody.innerHTML = "";

  if (lista.length === 0) {
    tbody.innerHTML =
      '<tr><td colspan="5" style="text-align:center;">Nenhum usuário encontrado.</td></tr>';
    return;
  }

  lista.forEach((user) => {
    let rawDate = user.ultimoLogin || user.criadoEm;
    let dataTexto = "Desconhecido";
    let labelTipo = "";

    if (rawDate) {
      let dt;
      if (rawDate.toDate) {
        dt = rawDate.toDate();
      } else {
        dt = new Date(rawDate);
      }

      if (!isNaN(dt.getTime())) {
        const hora = String(dt.getHours()).padStart(2, "0");
        const min = String(dt.getMinutes()).padStart(2, "0");
        const dia = String(dt.getDate()).padStart(2, "0");
        const mes = String(dt.getMonth() + 1).padStart(2, "0");
        const ano = dt.getFullYear();

        dataTexto = `${hora}:${min} - ${dia}/${mes}/${ano}`;

        if (user.ultimoLogin) {
          labelTipo = `<span style="color:green; font-size:0.8em;">(Ativo)</span>`;
        } else {
          labelTipo = `<span style="color:orange; font-size:0.8em;">(Novo)</span>`;
        }
      }
    }

    const row = `
            <tr style="border-bottom: 1px solid #eee;">
                <td style="padding: 12px 10px;">${user.nome || "Sem nome"}</td>
                <td style="padding: 12px 10px;">${user.email}</td>
                <td style="padding: 12px 10px;">
                    <span style="background:${user.role === "admin" ? "#e3f2fd" : "#f5f5f5"}; 
                                color:${user.role === "admin" ? "#0c7ab5" : "#333"}; 
                                padding: 4px 8px; border-radius: 4px; font-size: 0.85em; font-weight: bold;">
                        ${user.role || "user"}
                    </span>
                </td>
                <td style="padding: 12px 10px; color: #555; font-size: 0.9em;">
                    ${dataTexto} ${labelTipo}
                </td>
                <td style="padding: 12px 10px;">
                    <button onclick="window.excluirUsuario('${user.id}')" title="Excluir Usuário" 
                            style="color: #dc3545; background: #fff0f1; border: none; width: 32px; height: 32px; border-radius: 4px; cursor: pointer; transition: 0.2s;">
                        <i class="fa-solid fa-trash"></i>
                    </button>
                </td>
            </tr>
        `;
    tbody.innerHTML += row;
  });
}

function filtrarUsuarios(termo) {
  // Muda para aba usuários se não estiver nela
  const usersPanel = document.getElementById("users");
  if (!usersPanel.classList.contains("active")) {
    document.querySelector('[data-target="users"]').click();
  }

  const filtrados = todosUsuarios.filter((u) => {
    const nome = (u.nome || "").toLowerCase();
    const email = (u.email || "").toLowerCase();
    return nome.includes(termo) || email.includes(termo);
  });

  renderizarTabelaUsuarios(filtrados);
}

// === 6. APROVAÇÕES PENDENTES (Lê da 'casos_pendentes' e move para 'casos') ===
async function carregarAprovacoes() {
  const container = document.getElementById("reports-list");
  container.innerHTML = '<p style="text-align:center;">Buscando casos pendentes...</p>';

  try {
    // BUSCA NA COLEÇÃO CRIADA PELA SUA COLEGA
    const querySnapshot = await getDocs(collection(db, "casos_pendentes"));

    container.innerHTML = "";

    if (querySnapshot.empty) {
      container.innerHTML = '<p style="text-align:center; color: #666; margin-top: 20px;">Nenhuma aprovação pendente.</p>';
      return;
    }

    querySnapshot.forEach((docSnap) => {
      const data = docSnap.data();
      const id = docSnap.id;

      const dias = calcularDias(data.data_desaparecimento);
      const textoTempo = dias === 0 ? "hoje" : `há ${dias} dias`;
      const imagemSrc = data.imagem || "imgs/user.jpg";

      const card = document.createElement("div");
      card.className = "card-aprovar";

      card.innerHTML = `
          <!-- Lixeira / Rejeitar -->
          <button class="top-menu-btn btn-rejeitar" data-id="${id}" title="Rejeitar caso">
              <i class="fa-solid fa-trash"></i>
          </button>

          <!-- Cabeçalho -->
          <div class="card-header-admin">
              <img src="${imagemSrc}" class="admin-avatar" alt="Foto">
              <div class="admin-user-info">
                  <h3>${data.nome || "Nome Desconhecido"}</h3>
                  <p>${data.idade || "?"} anos</p>
              </div>
          </div>

          <!-- Descrição -->
          <p class="card-desc">
              Desapareceu em ${data.provincia || "Local desconhecido"} ${textoTempo}.
          </p>

          <!-- Botões -->
          <div class="admin-actions">
              <button class="btn-docs" onclick="window.showAlert('Detalhes:\\nBI: ${data.bi || "N/A"}\\nRoupas: ${data.roupas || "N/A"}\\nRelato: ${data.informacoes_adicionais || "Sem detalhes"}')">
                  Ver Documentos
              </button>
              <button class="btn-approve-pub" data-id="${id}">
                  Aprovar Publicação
              </button>
          </div>
      `;
      container.appendChild(card);
    });

    // --- EVENTO APROVAR (Move o caso para a coleção oficial) ---
    document.querySelectorAll(".btn-approve-pub").forEach((btn) => {
      btn.addEventListener("click", async (e) => {
        const docId = e.target.getAttribute("data-id");
        e.target.innerText = "Aprovando...";
        e.target.disabled = true;

        try {
          // 1. Pega os dados do caso pendente
          const docRefPendente = doc(db, "casos_pendentes", docId);
          const docSnapUnico = await getDoc(docRefPendente);
          
          if (docSnapUnico.exists()) {
              const casoData = docSnapUnico.data();
              casoData.status = "aprovado"; // Aprova o status

              // 2. Salva na coleção oficial 'casos'
              await setDoc(doc(db, "casos", docId), casoData);

              // 3. Exclui da fila de pendentes
              await deleteDoc(docRefPendente);

              showAlert("Publicação Aprovada! O caso já está público.", { onOk: carregarAprovacoes });
          }
        } catch (err) {
          showAlert("Erro: " + err.message);
          e.target.disabled = false;
        }
      });
    });

    // --- EVENTO REJEITAR ---
    document.querySelectorAll(".btn-rejeitar").forEach((btn) => {
      btn.addEventListener("click", async (e) => {
        const btnEl = e.target.closest("button");
        const docId = btnEl.getAttribute("data-id");

        if (confirm("Tem certeza que deseja rejeitar este caso?")) {
          try {
            const docRefPendente = doc(db, "casos_pendentes", docId);
            await deleteDoc(docRefPendente); // Apenas apaga
            carregarAprovacoes();
          } catch (err) {
            showAlert("Erro ao rejeitar: " + err.message);
          }
        }
      });
    });

  } catch (error) {
    console.error("Erro admin:", error);
  }
}

// === UTILITÁRIOS ===

function calcularDias(dataString) {
  if (!dataString) return 0;
  const dataPassada = new Date(dataString);
  const hoje = new Date();
  if (isNaN(dataPassada.getTime())) return 0;

  const diferencaTempo = Math.abs(hoje - dataPassada);
  return Math.ceil(diferencaTempo / (1000 * 60 * 60 * 24));
}

// Tornar a função de excluir acessível ao HTML (window)
window.excluirUsuario = async function (id) {
  if (
    confirm("Tem certeza que deseja remover este usuário da base de dados?")
  ) {
    try {
      await deleteDoc(doc(db, "users", id));
      showAlert("Usuário removido.", { onOk: carregarUsuarios });
    } catch (e) {
      showAlert("Erro ao excluir: " + e.message);
    }
  }
};
