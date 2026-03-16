import { auth, db } from "./firebase.js";
import {
  collection,
  addDoc,
  getDocs,
  query,
  where,
} from "https://www.gstatic.com/firebasejs/12.8.0/firebase-firestore.js";

// Variável global para guardar os casos (evita recarregar o banco ao filtrar)
let todosOsCasos = [];

document.addEventListener("DOMContentLoaded", async function () {
  // 1. Configurar Navegação do Modal (Abas Pessoa/Local/Detalhes) - RESTAURADO
  configurarNavegacaoModal();

  // 2. Configurar Lógica de Municípios e Deficiência - RESTAURADO
  configurarLogicaMunicipios();
  configurarLogicaDeficiencia();

  // 3. Carregar dados do banco
  await carregarCasos();

  // 4. Configurar Botões de Ação
  document
    .getElementById("enviarRelato")
    ?.addEventListener("click", enviarRelato);
  document
    .querySelector(".caracter button")
    ?.addEventListener("click", aplicarFiltros);
});

/* =========================================================================
   1. EXIBIÇÃO ESTILO "FEED" (Igual ao seu design da imagem)
   ========================================================================= */

async function carregarCasos() {
  const container = document.querySelector(".casos_main");

  // Limpa cards antigos
  document.querySelectorAll(".desaparecido").forEach((c) => c.remove());
  document.querySelectorAll(".feed-card").forEach((c) => c.remove());

  try {
    const q = query(collection(db, "casos"));
    const querySnapshot = await getDocs(q);

    todosOsCasos = [];

    querySnapshot.forEach((doc) => {
      let data = doc.data();
      data.id = doc.id;

      // FILTRO DE SEGURANÇA: Só mostra aprovados, encontrados, etc.
      if (
        data.status &&
        data.status !== "pendente" &&
        data.status !== "rejeitado"
      ) {
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
  container.innerHTML = ""; // Limpa container

  if (lista.length === 0) {
    container.innerHTML =
      "<p style='padding:20px; text-align:center;'>Nenhum caso encontrado.</p>";
    return;
  }

  lista.forEach((caso) => {
    // Lógica de tempo "Há X dias"
    const dias = calcularDias(caso.data_desaparecimento);
    const textoTempo = dias === 0 ? "Hoje" : `Há ${dias} dias`;

    // Lógica de Status (Cor da bolinha ou texto)
    let statusTexto = caso.status === "aprovado" ? "Ativo" : caso.status;

    const div = document.createElement("div");
    div.className = "feed-card"; // CSS que passei anteriormente

    // HTML Estruturado igual ao seu Design
    div.innerHTML = `
            <!-- HEADER DO CARD -->
            <div class="card-header">
                <img src="${caso.imagem || "imgs/user.jpg"}" class="avatar-small" alt="Avatar"> <!-- Avatar genérico do sistema -->
                <div class="header-info">
                    <h4>${caso.nome || "Nome Desconhecido"}</h4>
                    <span>${caso.idade || "?"} anos • ${caso.municipio || "Angola"}</span>
                </div>
                <div style="margin-left: auto; text-align: right;">
                    <span class="status-badge status-${caso.status}">${statusTexto}</span>
                </div>
            </div>

            <!-- IMAGEM PRINCIPAL (A que o usuário subiu) -->
            <img src="${caso.imagem || "imgs/user.jpg"}" class="card-main-image" alt="Foto Desaparecido">

            <!-- CORPO DO CARD -->
            <div class="card-body">
                <h3 class="card-title">${caso.nome}</h3>
                
                <div class="card-details">
                    <strong>Último local visto:</strong> ${caso.ultimo_local || "Não informado"}<br>
                    <span class="time-badge"><i class="fa-regular fa-clock"></i> ${textoTempo}</span>
                </div>
                
                <p class="card-details" style="margin-top: 10px;">
                    Desapareceu em ${caso.provincia || "Local incerto"}. 
                    ${caso.roupas ? `Vestia: ${caso.roupas}.` : ""}
                    ${caso.informacoes_adicionais || ""}
                </p>

                <p style="font-size: 0.9rem; color: #666; margin-top: 15px; border-top: 1px solid #eee; padding-top: 10px;">
                    <strong><i class="fa-solid fa-users"></i> Várias pessoas</strong> estão a ajudar na busca.
                </p>

                <!-- BOTÕES DE AÇÃO -->
                <div class="card-actions">
                    <button class="btn-action"><i class="fa-solid fa-heart"></i> Apoiar</button>
                    <button class="btn-action"><i class="fa-solid fa-comment"></i> Comentar</button>
                    <button class="btn-action"><i class="fa-solid fa-share"></i> Partilhar</button>
                </div>
            </div>
        `;

    container.appendChild(div);
  });
}

function calcularDias(dataString) {
  if (!dataString) return 0;
  const dataPassada = new Date(dataString);
  const hoje = new Date();
  if (isNaN(dataPassada)) return 0;

  const diferencaTempo = Math.abs(hoje - dataPassada);
  return Math.ceil(diferencaTempo / (1000 * 60 * 60 * 24));
}

/* =========================================================================
   2. RELATAR CASO (COM FUNCIONALIDADES RESTAURADAS + IMAGEM)
   ========================================================================= */

async function enviarRelato() {
  const user = auth.currentUser;
  if (!user) {
    showAlert("Você precisa estar logado para relatar um caso.");
    return;
  }

  const btn = document.getElementById("enviarRelato");
  btn.innerText = "Processando...";
  btn.disabled = true;

  try {
    // Coleta de Inputs Básicos
    const nome = document.querySelector('input[name="nome"]').value;
    const idade = document.querySelector('input[name="idade"]').value;
    const sexo = document.querySelector('select[name="sexo"]').value;
    const provincia = document.getElementById("provincia_relatar").value;
    const municipio = document.getElementById("municipio_relatar").value;
    const ultimo_local = document.querySelector(
      'input[name="ultimo_local"]',
    ).value;
    const roupas = document.querySelector('input[name="roupas"]').value;
    const data_desaparecimento = document.querySelector(
      'input[name="data_desaparecimento"]',
    ).value;
    const info = document.getElementById("informacoes_adicionais").value;

    // Coleta de Inputs Específicos (Deficiência)
    const deficiencia = document.getElementById("deficiencia").value;
    const tipoDeficiencia = document.getElementById(
      "tipo_deficiencia_input",
    ).value;

    // Validação básica
    if (!nome || !provincia || !municipio) {
      showAlert("Preencha pelo menos Nome, Província e Município.");
      throw new Error("Campos obrigatórios vazios.");
    }

    // --- TRATAMENTO DA IMAGEM (BASE64) ---
    const fileInput = document.querySelector('input[name="imagem"]');
    let imagemBase64 = null;

    if (fileInput.files.length > 0) {
      const file = fileInput.files[0];
      // Limite de segurança para o Firestore (aprox 1000KB)
      if (file.size > 1000 * 1024) {
        showAlert(
          "A imagem é muito grande para o sistema atual. Por favor escolha uma imagem menor (abaixo de 1000KB).",
        );
        btn.innerText = "Relatar";
        btn.disabled = false;
        return;
      }
      imagemBase64 = await lerArquivoComoBase64(file);
    }

    // Montar Objeto
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
      imagem: imagemBase64, // Salva a foto aqui
    };

    // Salvar no Firestore

await addDoc(collection(db, "casos_pendentes"), dados);

    showAlert("Caso relatado com sucesso! Aguarde aprovação do administrador.");
    document.getElementById("relatarSec").style.display = "none";

    // Limpar todos os inputs
    document
      .querySelectorAll("#relatarSec input, #relatarSec textarea")
      .forEach((i) => (i.value = ""));
    document
      .querySelectorAll("#relatarSec select")
      .forEach((s) => (s.selectedIndex = 0));
  } catch (err) {
    if (err.message !== "Campos obrigatórios vazios.") {
      console.error(err);
      showAlert("Erro ao enviar: " + err.message);
    }
  } finally {
    btn.innerText = "Relatar";
    btn.disabled = false;
  }
}

function lerArquivoComoBase64(file) {
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onload = () => resolve(reader.result);
    reader.onerror = (error) => reject(error);
    reader.readAsDataURL(file);
  });
}

/* =========================================================================
   3. NAVEGAÇÃO DO MODAL (Abas) - RESTAURADA
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

  function showTab(nomeAba) {
    // Esconde tudo
    Object.values(abas).forEach((item) => {
      if (item.div) item.div.style.display = "none";
      if (item.link) item.link.classList.remove("active");
    });

    // Mostra a selecionada
    if (abas[nomeAba]) {
      abas[nomeAba].div.style.display = "flex";
      abas[nomeAba].link.classList.add("active");
    }
  }

  // Adiciona cliques nas abas
  Object.keys(abas).forEach((key) => {
    abas[key].link?.addEventListener("click", (e) => {
      e.preventDefault();
      showTab(key);
    });
  });

  // Abrir Modal
  relatarBtn?.addEventListener("click", () => {
    if (!auth.currentUser) {
      showAlert("Faça login para relatar.");
      return;
    }
    relatarSec.style.display = "flex";
    showTab("pessoa"); // Começa sempre na aba Pessoa
  });

  // Fechar Modal
  closeBtn?.addEventListener("click", () => {
    relatarSec.style.display = "none";
  });
}

/* =========================================================================
   4. UTILITÁRIOS (Municípios e Deficiência) - RESTAURADOS
   ========================================================================= */

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

  function atualizarSelect(provinciaVal, selectMun, divMun) {
    if (!selectMun) return;
    selectMun.innerHTML =
      '<option value="" hidden>Selecione o município</option>';

    if (provinciaVal && municipiosPorProvincia[provinciaVal]) {
      municipiosPorProvincia[provinciaVal].forEach((mun) => {
        const opt = document.createElement("option");
        opt.value = mun.toLowerCase().replace(/ /g, "_");
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

  // Filtro Lateral (Esquerda)
  const provFiltro = document.getElementById("provincia");
  provFiltro?.addEventListener("change", function () {
    atualizarSelect(
      this.value,
      document.getElementById("municipio"),
      document.getElementById("municipio-field"),
    );
  });

  // Modal Relatar (Pop-up)
  const provRelatar = document.getElementById("provincia_relatar");
  provRelatar?.addEventListener("change", function () {
    atualizarSelect(
      this.value,
      document.getElementById("municipio_relatar"),
      document.getElementById("municipio-field-relatar"),
    );
  });
}

function configurarLogicaDeficiencia() {
  const defSelect = document.getElementById("deficiencia");
  const tipoDefField = document.getElementById("tipo_deficiencia_field");

  if (defSelect && tipoDefField) {
    defSelect.addEventListener("change", () => {
      if (defSelect.value === "sim") {
        tipoDefField.style.display = "block";
      } else {
        tipoDefField.style.display = "none";
        document.getElementById("tipo_deficiencia_input").value = ""; // Limpa se selecionar Não
      }
    });
  }
}

// Filtro Simples (Sidebar)
function aplicarFiltros() {
  const provincia = document.getElementById("provincia").value;
  const sexo = document.getElementById("sexo").value;

  const filtrados = todosOsCasos.filter((caso) => {
    let passou = true;
    if (provincia && caso.provincia !== provincia) passou = false;
    if (sexo && caso.sexo !== sexo) passou = false;
    return passou;
  });

  renderizarCasos(filtrados);
}
