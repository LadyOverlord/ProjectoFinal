import { auth, db } from "./firebase.js";
import { signInWithEmailAndPassword } from "https://www.gstatic.com/firebasejs/12.8.0/firebase-auth.js";
import {
  doc, getDoc, collection, getDocs,
} from "https://www.gstatic.com/firebasejs/12.8.0/firebase-firestore.js";

/* =========================================================================
   LOGIN
   ========================================================================= */
window.login = async function () {
  const email = document.getElementById("loginEmail").value.trim();
  const senha = document.getElementById("loginSenha").value;

  if (!email || !senha) {
    showAlert("Por favor, preencha todos os campos.");
    return;
  }

  const btn = document.querySelector("#login .btn-submit");
  if (btn) {
    btn.disabled = true;
    btn.innerHTML = '<i class="fa-solid fa-spinner fa-spin"></i> A entrar...';
  }

  try {
    const cred = await signInWithEmailAndPassword(auth, email, senha);
    const snap = await getDoc(doc(db, "users", cred.user.uid));

    if (!snap.exists()) {
      showAlert("Perfil não encontrado. Contacte o suporte.");
      return;
    }

    window.location.href = snap.data().role === "admin" ? "admin.html" : "index.html";

  } catch (err) {
    const msgs = {
      "auth/invalid-credential": "Email ou senha incorrectos.",
      "auth/user-not-found":     "Utilizador não encontrado.",
      "auth/wrong-password":     "Senha incorrecta.",
      "auth/too-many-requests":  "Demasiadas tentativas. Aguarde um momento.",
      "auth/invalid-email":      "Formato de email inválido.",
    };
    showAlert(msgs[err.code] || "Erro ao entrar: " + err.message);
  } finally {
    if (btn) {
      btn.disabled = false;
      btn.innerHTML = '<i class="fa-solid fa-arrow-right-to-bracket"></i> Entrar';
    }
  }
};

/* =========================================================================
   MUNICÍPIOS DINÂMICOS
   ========================================================================= */
const municipiosPorProvincia = {
  luanda:   ["Belas","Cacuaco","Cazenga","Ícolo e Bengo","Luanda","Quilamba Quiaxi","Talatona","Viana"],
  benguela: ["Baía Farta","Balombo","Benguela","Bocoio","Caimbambo","Catumbela","Chongoroi","Cubal","Ganda","Lobito"],
  huambo:   ["Bailundo","Catchiungo","Caála","Ecunha","Huambo","Londuimbali","Longonjo","Mungo","Tchicala-Tcholoanga","Tchindjenje","Ucuma"],
};

const provinciaSelect = document.getElementById("provincia");
const municipioField  = document.getElementById("municipio-field");
const municipioSelect = document.getElementById("municipio");

provinciaSelect?.addEventListener("change", function () {
  const lista = municipiosPorProvincia[this.value];
  municipioSelect.innerHTML = '<option value="" hidden>Selecione o município</option>';
  if (lista) {
    lista.forEach(m => {
      const opt = document.createElement("option");
      opt.value = m.toLowerCase().replace(/ /g, "_");
      opt.textContent = m;
      municipioSelect.appendChild(opt);
    });
    municipioField.style.display = "block";
    municipioSelect.required = true;
  } else {
    municipioField.style.display = "none";
    municipioSelect.required = false;
  }
});

/* =========================================================================
   VALIDAÇÃO DE SENHA EM TEMPO REAL
   ========================================================================= */
document.getElementById("senha")?.addEventListener("input", function () {
  const hint = document.getElementById("verifSenha");
  if (!hint) return;
  if (!this.value)           { hint.textContent = "";                hint.className = "field-hint"; }
  else if (this.value.length < 6) { hint.textContent = "Mínimo 6 caracteres"; hint.className = "field-hint error"; }
  else                       { hint.textContent = "✓ Senha válida"; hint.className = "field-hint ok"; }
});

document.getElementById("confirmarSenha")?.addEventListener("input", function () {
  const hint  = document.getElementById("confirSenha");
  const senha = document.getElementById("senha")?.value || "";
  if (!hint) return;
  if (!this.value)              { hint.textContent = "";                     hint.className = "field-hint"; }
  else if (this.value !== senha){ hint.textContent = "As senhas não coincidem"; hint.className = "field-hint error"; }
  else                          { hint.textContent = "✓ Senhas coincidem";   hint.className = "field-hint ok"; }
});

/* =========================================================================
   MOSTRAR / OCULTAR SENHA
   ========================================================================= */
document.querySelectorAll(".btn-eye").forEach(btn => {
  btn.addEventListener("click", () => {
    const input = document.getElementById(btn.dataset.target);
    if (!input) return;
    const isText = input.type === "text";
    input.type = isText ? "password" : "text";
    btn.querySelector("i").className = isText ? "fa-regular fa-eye" : "fa-regular fa-eye-slash";
  });
});

/* =========================================================================
   PARTÍCULAS — sem o bloco de debug stats.js
   ========================================================================= */
if (typeof particlesJS !== "undefined") {
  particlesJS("particles-js", {
    particles: {
      number:      { value: 100, density: { enable: true, value_area: 900 } },
      color:       { value: "#0c7ab5" },
      shape:       { type: "circle" },
      opacity:     { value: 0.4, random: true },
      size:        { value: 3, random: true },
      line_linked: { enable: false },
      move: {
        enable: true, speed: 3, direction: "none",
        random: true, straight: false, out_mode: "out",
      },
    },
    interactivity: {
      detect_on: "canvas",
      events: {
        onhover: { enable: true,  mode: "grab" },
        onclick:  { enable: true,  mode: "push" },
        resize:   true,
      },
      modes: {
        grab: { distance: 300, line_linked: { opacity: 0.6 } },
        push: { particles_nb: 3 },
      },
    },
    retina_detect: true,
  });
}

/* =========================================================================
   STATS DECORATIVAS NO SLIDER (casos / encontrados)
   ========================================================================= */
(async () => {
  try {
    const snap = await getDocs(collection(db, "casos"));
    let total = 0, encontrados = 0;
    snap.forEach(d => {
      total++;
      if (d.data().status === "encontrado") encontrados++;
    });
    const elTotal = document.getElementById("s-casos");
    const elEnc   = document.getElementById("s-enc");
    if (elTotal) elTotal.textContent = total;
    if (elEnc)   elEnc.textContent   = encontrados;
  } catch (_) { /* silencioso — apenas decorativo */ }
})();