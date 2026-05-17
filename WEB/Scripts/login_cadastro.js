import { auth, db } from "./firebase.js";
import { signInWithEmailAndPassword, sendPasswordResetEmail, signOut, sendEmailVerification } from "https://www.gstatic.com/firebasejs/12.8.0/firebase-auth.js";
import {
  doc,
  getDoc,
  collection,
  getDocs,
  updateDoc,
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
    const user  = cred.user;

    // ── Verificação de email obrigatória (admins ficam isentos) ──────────
    if (!user.emailVerified) {
      let role = "user";
      try {
        const snap = await getDoc(doc(db, "users", user.uid));
        if (snap.exists()) role = snap.data().role || "user";
      } catch (_) {}

      if (role !== "admin") {
        await signOut(auth);          // não manter sessão não verificada
        mostrarModalVerificacao(email, user);
        return;
      }
    }

    // ── Utilizador verificado → buscar perfil e redirecionar ─────────────
    const snap = await getDoc(doc(db, "users", user.uid));
    if (!snap.exists()) {
      await signOut(auth);
      showAlert("Perfil não encontrado. Contacte o suporte.");
      return;
    }

    window.location.href =
      snap.data().role === "admin" ? "admin.html" : "index.html";
  } catch (err) {
    const msgs = {
      "auth/invalid-credential": "Email ou senha incorrectos.",
      "auth/user-not-found": "Utilizador não encontrado.",
      "auth/wrong-password": "Senha incorrecta.",
      "auth/too-many-requests": "Demasiadas tentativas. Aguarde um momento.",
      "auth/invalid-email": "Formato de email inválido.",
    };
    showAlert(msgs[err.code] || "Erro ao entrar: " + err.message);
  } finally {
    if (btn) {
      btn.disabled = false;
      btn.innerHTML =
        '<i class="fa-solid fa-arrow-right-to-bracket"></i> Entrar';
    }
  }
};

/* =========================================================================
   RECUPERAR SENHA
   ========================================================================= */
window.recuperarSenha = async function() {
    const email = document.getElementById("loginEmail").value;
    
    if (!email) {
        alert("Por favor, digite o seu e-mail no campo de E-mail acima para recuperar a senha.");
        return;
    }

    try {
        await sendPasswordResetEmail(auth, email);
        alert(`Um e-mail de recuperação foi enviado para: ${email}. Verifique a sua caixa de entrada (e a pasta Spam).`);
    } catch (error) {
        console.error("Erro ao recuperar senha:", error);
        if (error.code === 'auth/user-not-found') {
            alert("Não encontramos nenhuma conta com este e-mail.");
        } else if (error.code === 'auth/invalid-email') {
            alert("Por favor, digite um formato de e-mail válido.");
        } else {
            alert("Erro: " + error.message);
        }
    }
};


/* =========================================================================
   MODAL — EMAIL NÃO VERIFICADO
   Aparece quando o utilizador tenta entrar sem verificar o email.
   ========================================================================= */
function mostrarModalVerificacao(email, userObj) {
  document.getElementById("modal-verificacao")?.remove();

  const modal = document.createElement("div");
  modal.id = "modal-verificacao";
  modal.style.cssText =
    "position:fixed;inset:0;z-index:9999;display:flex;align-items:center;justify-content:center;";
  modal.innerHTML = `
    <div style="position:absolute;inset:0;background:rgba(0,0,0,0.5);backdrop-filter:blur(4px);" id="mv-bd"></div>
    <div style="position:relative;background:#fff;border-radius:16px;padding:36px 32px;max-width:400px;width:90%;text-align:center;box-shadow:0 20px 60px rgba(0,0,0,0.25);font-family:var(--font-base,'Quicksand',sans-serif);">
      <div style="width:64px;height:64px;background:#e3f2fd;border-radius:16px;display:flex;align-items:center;justify-content:center;font-size:28px;color:#0c7ab5;margin:0 auto 18px;">
        <i class="fa-solid fa-envelope-circle-check"></i>
      </div>
      <h2 style="margin:0 0 10px;font-size:20px;color:#111;">Verifique o seu email</h2>
      <p style="color:#555;font-size:14px;line-height:1.6;margin:0 0 6px;">
        Foi enviado um email de confirmação para<br>
        <strong style="color:#0c7ab5;">${email}</strong>
      </p>
      <p style="color:#999;font-size:12px;margin:0 0 24px;">
        Clique no link do email para activar a conta.<br>
        Depois volte aqui e faça login novamente.
      </p>
      <button id="mv-reenviar" style="width:100%;padding:12px;margin-bottom:10px;border:none;border-radius:8px;background:#0c7ab5;color:#fff;font-size:14px;font-weight:700;cursor:pointer;display:flex;align-items:center;justify-content:center;gap:8px;transition:background 0.2s;">
        <i class="fa-solid fa-paper-plane"></i> Reenviar email de verificação
      </button>
      <button id="mv-fechar" style="width:100%;padding:10px;border:1px solid #ddd;border-radius:8px;background:#f5f5f5;color:#666;font-size:14px;font-weight:600;cursor:pointer;">
        Fechar
      </button>
      <p style="margin:14px 0 0;font-size:11px;color:#aaa;">
        Não encontra? Verifique a pasta <strong>Spam</strong>.
      </p>
    </div>`;

  document.body.appendChild(modal);

  modal.querySelector("#mv-bd").addEventListener("click", () => modal.remove());
  modal.querySelector("#mv-fechar").addEventListener("click", () => modal.remove());

  modal.querySelector("#mv-reenviar").addEventListener("click", async () => {
    const btn = modal.querySelector("#mv-reenviar");
    btn.disabled = true;
    btn.innerHTML = '<i class="fa-solid fa-spinner fa-spin"></i> A enviar...';
    try {
      if (userObj) {
        await sendEmailVerification(userObj);
        btn.innerHTML = '<i class="fa-solid fa-check"></i> Enviado! Verifique a caixa de entrada.';
        setTimeout(() => {
          btn.innerHTML = '<i class="fa-solid fa-paper-plane"></i> Reenviar email de verificação';
          btn.disabled = false;
        }, 5000);
      } else {
        showAlert("Não foi possível reenviar. Tente fazer login novamente.");
        btn.disabled = false;
        btn.innerHTML = '<i class="fa-solid fa-paper-plane"></i> Reenviar email de verificação';
      }
    } catch (err) {
      const msgs = { "auth/too-many-requests": "Demasiadas tentativas. Aguarde alguns minutos." };
      showAlert(msgs[err.code] || "Erro: " + err.message);
      btn.disabled = false;
      btn.innerHTML = '<i class="fa-solid fa-paper-plane"></i> Reenviar email de verificação';
    }
  });
}

/* =========================================================================
   MUNICÍPIOS DINÂMICOS
   ========================================================================= */
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

const provinciaSelect = document.getElementById("provincia");
const municipioField = document.getElementById("municipio-field");
const municipioSelect = document.getElementById("municipio");

provinciaSelect?.addEventListener("change", function () {
  const lista = municipiosPorProvincia[this.value];
  municipioSelect.innerHTML =
    '<option value="" hidden>Selecione o município</option>';
  if (lista) {
    lista.forEach((m) => {
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
  if (!this.value) {
    hint.textContent = "";
    hint.className = "field-hint";
  } else if (this.value.length < 6) {
    hint.textContent = "Mínimo 6 caracteres";
    hint.className = "field-hint error";
  } else {
    hint.textContent = "✓ Senha válida";
    hint.className = "field-hint ok";
  }
});

document
  .getElementById("confirmarSenha")
  ?.addEventListener("input", function () {
    const hint = document.getElementById("confirSenha");
    const senha = document.getElementById("senha")?.value || "";
    if (!hint) return;
    if (!this.value) {
      hint.textContent = "";
      hint.className = "field-hint";
    } else if (this.value !== senha) {
      hint.textContent = "As senhas não coincidem";
      hint.className = "field-hint error";
    } else {
      hint.textContent = "✓ Senhas coincidem";
      hint.className = "field-hint ok";
    }
  });

/* =========================================================================
   MOSTRAR / OCULTAR SENHA
   ========================================================================= */
document.querySelectorAll(".btn-eye").forEach((btn) => {
  btn.addEventListener("click", () => {
    const input = document.getElementById(btn.dataset.target);
    if (!input) return;
    const isText = input.type === "text";
    input.type = isText ? "password" : "text";
    btn.querySelector("i").className = isText
      ? "fa-regular fa-eye"
      : "fa-regular fa-eye-slash";
  });
});

/* =========================================================================
   PARTÍCULAS — sem o bloco de debug stats.js
   ========================================================================= */
if (typeof particlesJS !== "undefined") {
  particlesJS("particles-js", {
    particles: {
      number: { value: 100, density: { enable: true, value_area: 900 } },
      color: { value: "#0c7ab5" },
      shape: { type: "circle" },
      opacity: { value: 0.4, random: true },
      size: { value: 3, random: true },
      line_linked: { enable: false },
      move: {
        enable: true,
        speed: 3,
        direction: "none",
        random: true,
        straight: false,
        out_mode: "out",
      },
    },
    interactivity: {
      detect_on: "canvas",
      events: {
        onhover: { enable: true, mode: "grab" },
        onclick: { enable: true, mode: "push" },
        resize: true,
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