// Relatar modal / abas: lógica de exibição, navegação e envio
import { db } from "./firebase.js";
import {
  collection,
  addDoc,
} from "https://www.gstatic.com/firebasejs/12.8.0/firebase-firestore.js";

document.addEventListener("DOMContentLoaded", function () {
  const relatarSec = document.getElementById("relatarSec");
  const relatarBtn = document.getElementById("relatar");
  const closeBtn =
    relatarSec && relatarSec.querySelector(".relatar_caso header button");
  const pessoaLink = document.getElementById("pessoaActive");
  const localLink = document.getElementById("localActive");
  const detalhesLink = document.getElementById("detalhesActive");
  const pessoaDiv = document.getElementById("pessoaDiv");
  const localDiv = document.getElementById("localDiv");
  const detalhesDiv = document.getElementById("detalhesDiv");
  const enviarBtn = document.getElementById("enviarRelato");

  if (!pessoaDiv || !localDiv || !detalhesDiv) return;

  function hideAll() {
    pessoaDiv.style.display = "none";
    localDiv.style.display = "none";
    detalhesDiv.style.display = "none";
    pessoaLink && pessoaLink.classList.remove("active");
    localLink && localLink.classList.remove("active");
    detalhesLink && detalhesLink.classList.remove("active");
  }

  function showTab(tab) {
    hideAll();
    if (tab === "pessoa") {
      pessoaDiv.style.display = "flex";
      pessoaLink && pessoaLink.classList.add("active");
    }
    if (tab === "local") {
      localDiv.style.display = "flex";
      localLink && localLink.classList.add("active");
    }
    if (tab === "detalhes") {
      detalhesDiv.style.display = "flex";
      detalhesLink && detalhesLink.classList.add("active");
    }
  }

  // Iniciar com modal fechado
  if (relatarSec) relatarSec.style.display = "none";
  showTab("pessoa");

  pessoaLink &&
    pessoaLink.addEventListener("click", function (e) {
      e.preventDefault();
      showTab("pessoa");
    });
  localLink &&
    localLink.addEventListener("click", function (e) {
      e.preventDefault();
      showTab("local");
    });
  detalhesLink &&
    detalhesLink.addEventListener("click", function (e) {
      e.preventDefault();
      showTab("detalhes");
    });

  // Abrir modal a partir do botão Relatar (se estiver logado)
  relatarBtn &&
    relatarBtn.addEventListener("click", function (e) {
      // global click-interceptor já redireciona usuários não logados; garantir segurança extra aqui
      if (typeof window.isLoggedIn === "function" && !window.isLoggedIn()) {
        return; // deixe o listener global tratar o redirecionamento
      }
      if (relatarSec) relatarSec.style.display = "flex";
      showTab("pessoa");
    });

  closeBtn &&
    closeBtn.addEventListener("click", function () {
      if (relatarSec) relatarSec.style.display = "none";
    });

  // Enviar relato: validação simples e salvar em localStorage (array 'reports')
  enviarBtn &&
    enviarBtn.addEventListener("click", async function () {
      const pessoaInputs = pessoaDiv.querySelectorAll("input, select");
      const localInputs = localDiv.querySelectorAll("select, input");
      const detalhesInputs = detalhesDiv.querySelectorAll(
        "input, select, textarea",
      );

      function allFilled(list) {
        for (const el of list) {
          // ignore non-required checkboxes
          if (el.type === "checkbox") continue;
          if (
            (el.tagName === "INPUT" ||
              el.tagName === "SELECT" ||
              el.tagName === "TEXTAREA") &&
            String(el.value).trim() === ""
          ) {
            return false;
          }
        }
        return true;
      }

      if (
        !allFilled(pessoaInputs) ||
        !allFilled(localInputs) ||
        !allFilled(detalhesInputs)
      ) {
        alert("Por favor preencha todos os campos antes de relatar.");
        return;
      }

      const report = {
        pessoa: {},
        local: {},
        detalhes: {},
        createdAt: new Date().toISOString(),
      };

      pessoaInputs.forEach((el) => {
        const key =
          el.name || el.id || el.placeholder || "p_" + (el.type || "field");
        report.pessoa[key] = el.value;
      });
      localInputs.forEach((el) => {
        const key =
          el.name || el.id || el.placeholder || "l_" + (el.type || "field");
        report.local[key] = el.value;
      });
      detalhesInputs.forEach((el) => {
        const key =
          el.name || el.id || el.placeholder || "d_" + (el.type || "field");
        report.detalhes[key] = el.value;
      });

      try {
        await addDoc(collection(db, "casos"), report);
        alert("Relato enviado com sucesso.");
        if (relatarSec) relatarSec.style.display = "none";
      } catch (err) {
        console.error("Erro ao salvar relato:", err);
        alert("Erro ao enviar relato. Tente novamente mais tarde.");
      }
    });
});
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

function populateMunicipiosFor(provincia, selectEl, fieldEl) {
  if (!selectEl) return;
  selectEl.innerHTML = '<option value="" hidden>Selecione o município</option>';
  if (provincia && municipiosPorProvincia[provincia]) {
    municipiosPorProvincia[provincia].forEach(function (mun) {
      const opt = document.createElement("option");
      opt.value = mun.toLowerCase().replace(/ /g, "_");
      opt.textContent = mun;
      selectEl.appendChild(opt);
    });
    if (fieldEl) fieldEl.style.display = "block";
    selectEl.required = true;
  } else {
    if (fieldEl) fieldEl.style.display = "none";
    selectEl.required = false;
  }
}

const provinciaSelect = document.getElementById("provincia");
const municipioField = document.getElementById("municipio-field");
const municipioSelect = document.getElementById("municipio");
if (provinciaSelect) {
  provinciaSelect.addEventListener("change", function () {
    populateMunicipiosFor(this.value, municipioSelect, municipioField);
  });
}

// Modal-specific selects (relatar caso)
const provinciaRelatar = document.getElementById("provincia_relatar");
const municipioFieldRelatar = document.getElementById(
  "municipio-field-relatar",
);
const municipioRelatar = document.getElementById("municipio_relatar");
if (provinciaRelatar) {
  provinciaRelatar.addEventListener("change", function () {
    populateMunicipiosFor(this.value, municipioRelatar, municipioFieldRelatar);
  });
}

// Mostrar/ocultar campo 'Que tipo de deficiencia' no modal
const defSelect = document.getElementById('deficiencia');
const tipoDefField = document.getElementById('tipo_deficiencia_field');
if (defSelect && tipoDefField) {
  function toggleTipoDef() {
    if (defSelect.value === 'sim') {
      tipoDefField.style.display = 'block';
    } else {
      tipoDefField.style.display = 'none';
    }
  }
  defSelect.addEventListener('change', toggleTipoDef);
  // estado inicial
  toggleTipoDef();
}
