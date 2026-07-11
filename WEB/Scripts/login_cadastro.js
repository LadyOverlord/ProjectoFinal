// Scripts/login_cadastro.js
// ─────────────────────────────────────────────────────────────────────────────
// FICHEIRO ÚNICO para a página de login/cadastro — contém login, recuperar
// senha, cadastro (com o gate de Termos e Condições), municípios
// dinâmicos, validação de senha, mostrar/ocultar senha, partículas de
// fundo e as estatísticas decorativas do slider.
//
// CORRIGIDO: antes isto estava dividido em dois ficheiros
// (login_cadastro.js + auth.js), carregados por duas tags <script>
// separadas em login_cadastro.html. Numa troca de ficheiros o conteúdo
// acabou por ir parar ao ficheiro errado — o resultado foi window.login
// deixar de existir (login parou de funcionar) enquanto o cadastro
// continuava a correr a versão antiga sem verificar os termos. Para
// eliminar de vez essa fonte de erro, ficou tudo num único ficheiro:
// só há um sítio para substituir.
// ─────────────────────────────────────────────────────────────────────────────

import { auth, db, navigateToTarget } from "./firebase.js";
import {
  signInWithEmailAndPassword,
  sendPasswordResetEmail,
  signOut,
  sendEmailVerification,
  createUserWithEmailAndPassword,
} from "https://www.gstatic.com/firebasejs/12.8.0/firebase-auth.js";
import {
  doc,
  getDoc,
  setDoc,
  collection,
  getDocs,
  query,
  where,
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
    const user = cred.user;

    // ── Verificação de email obrigatória (admins ficam isentos) ──────────
    if (!user.emailVerified) {
      let role = "user";
      try {
        const snap = await getDoc(doc(db, "users", user.uid));
        if (snap.exists()) role = snap.data().role || "user";
      } catch (_) {}

      if (role !== "admin") {
        await signOut(auth);
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

    if (snap.data().role === "admin") {
      await navigateToTarget("admin.html");
    } else {
      await navigateToTarget("index.html");
    }
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
window.recuperarSenha = async function () {
  const email = document.getElementById("loginEmail").value;

  if (!email) {
    alert(
      "Por favor, digite o seu e-mail no campo de E-mail acima para recuperar a senha.",
    );
    return;
  }

  try {
    await sendPasswordResetEmail(auth, email);
    alert(
      `Um e-mail de recuperação foi enviado para: ${email}. Verifique a sua caixa de entrada (e a pasta Spam).`,
    );
  } catch (error) {
    console.error("Erro ao recuperar senha:", error);
    if (error.code === "auth/user-not-found") {
      alert("Não encontramos nenhuma conta com este e-mail.");
    } else if (error.code === "auth/invalid-email") {
      alert("Por favor, digite um formato de e-mail válido.");
    } else {
      alert("Erro: " + error.message);
    }
  }
};

/* =========================================================================
   MODAL — EMAIL NÃO VERIFICADO
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
  modal
    .querySelector("#mv-fechar")
    .addEventListener("click", () => modal.remove());

  modal.querySelector("#mv-reenviar").addEventListener("click", async () => {
    const btn = modal.querySelector("#mv-reenviar");
    btn.disabled = true;
    btn.innerHTML = '<i class="fa-solid fa-spinner fa-spin"></i> A enviar...';
    try {
      if (userObj) {
        await sendEmailVerification(userObj);
        btn.innerHTML =
          '<i class="fa-solid fa-check"></i> Enviado! Verifique a caixa de entrada.';
        setTimeout(() => {
          btn.innerHTML =
            '<i class="fa-solid fa-paper-plane"></i> Reenviar email de verificação';
          btn.disabled = false;
        }, 5000);
      } else {
        showAlert("Não foi possível reenviar. Tente fazer login novamente.");
        btn.disabled = false;
        btn.innerHTML =
          '<i class="fa-solid fa-paper-plane"></i> Reenviar email de verificação';
      }
    } catch (err) {
      const msgs = {
        "auth/too-many-requests":
          "Demasiadas tentativas. Aguarde alguns minutos.",
      };
      showAlert(msgs[err.code] || "Erro: " + err.message);
      btn.disabled = false;
      btn.innerHTML =
        '<i class="fa-solid fa-paper-plane"></i> Reenviar email de verificação';
    }
  });
}

/* =========================================================================
   MUNICÍPIOS DINÂMICOS (formulário de cadastro)
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
   PARTÍCULAS
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

/* =========================================================================
   TERMOS E CONDIÇÕES — modal com scroll obrigatório antes de aceitar
   ========================================================================= */
const VERSAO_TERMOS = "v1";

const TEXTO_TERMOS = `
<h4 style="margin-bottom:10px;">TERMOS E CONDIÇÕES DE UTILIZAÇÃO — MISSING AO</h4>
<p style="color:#999;font-size:11px;margin-bottom:16px;">[RASCUNHO — por rever por um advogado antes de publicar]</p>

<p><strong>1. OBJECTO</strong><br>
A Missing AO é uma plataforma comunitária angolana que ajuda famílias a
localizar pessoas desaparecidas, permitindo a submissão, partilha e
comentário de casos de desaparecimento.</p>

<p><strong>2. RESPONSABILIDADE PELA INFORMAÇÃO SUBMETIDA</strong><br>
Ao relatar um caso de desaparecimento, o utilizador declara que a
informação submetida (nome, idade, fotografia, localização e demais dados
da pessoa desaparecida) é verdadeira, na medida do seu conhecimento, e que
tem motivo legítimo para a submeter. Informação comprovadamente falsa está
sujeita a remoção e penalização da conta, nos termos da secção 5.</p>

<p><strong>3. TRATAMENTO DE DADOS PESSOAIS</strong><br>
Os dados pessoais recolhidos — do utilizador e da pessoa reportada como
desaparecida — são tratados nos termos da Lei n.º 22/11, de 17 de Junho
(Lei da Protecção de Dados Pessoais). Isto inclui dados de conta (nome,
email, telefone, província e município), dados de localização (GPS,
quando autorizado) e dados de casos (informação sobre a pessoa
desaparecida, incluindo fotografia). Os dados de casos aprovados são
publicados no feed e mapa públicos da aplicação.</p>

<p><strong>4. NOTIFICAÇÕES</strong><br>
Ao registar-se, o utilizador consente em receber notificações por email
relacionadas com: alertas de casos na sua região, respostas a comentários,
e comunicações sobre o estado da sua conta.</p>

<p><strong>5. DIRECTRIZES DA COMUNIDADE E TRUST SCORE</strong><br>
A conta de cada utilizador tem associado um sistema de pontuação de
confiança ("Trust Score"), reduzido em caso de publicação de casos falsos
ou desmentidos, comentários ofensivos ou removidos, ou comportamento
abusivo. Caso o Trust Score chegue a zero, a conta é automaticamente
suspensa, com possibilidade de recurso junto do suporte.</p>

<p><strong>6. DIREITOS DO TITULAR DOS DADOS</strong><br>
Nos termos da Lei n.º 22/11, o utilizador tem direito a aceder, rectificar
ou solicitar a eliminação dos seus dados pessoais, através dos canais de
suporte disponíveis na aplicação.</p>

<p><strong>7. ALTERAÇÕES A ESTES TERMOS</strong><br>
Estes termos podem ser actualizados. Alterações substanciais requerem
nova aceitação explícita antes de continuar a usar a aplicação.</p>
`;

let _termosAceitos = false;
let _modalTermosAberto = false;

function _mostrarModalTermos(onAceitar) {
  if (_modalTermosAberto) return;
  _modalTermosAberto = true;

  const overlay = document.createElement("div");
  overlay.id = "termos-cadastro-overlay";
  overlay.style.cssText =
    "position:fixed;inset:0;z-index:20000;display:flex;align-items:center;justify-content:center;background:rgba(0,0,0,0.55);padding:16px;";

  overlay.innerHTML =
    '<div style="background:#fff;border-radius:16px;max-width:560px;width:100%;max-height:88vh;display:flex;flex-direction:column;box-shadow:0 20px 60px rgba(0,0,0,0.25);font-family:var(--font-base,\'Quicksand\',sans-serif);overflow:hidden;">' +
      '<div style="padding:18px 22px;border-bottom:1px solid #eee;display:flex;align-items:center;justify-content:space-between;">' +
        '<h3 style="margin:0;font-size:16px;color:#222;">Termos e Condições</h3>' +
        '<button id="termos-cadastro-fechar" type="button" style="background:none;border:none;font-size:20px;cursor:pointer;color:#888;line-height:1;">&times;</button>' +
      '</div>' +
      '<div id="termos-cadastro-scroll" style="padding:20px 22px;overflow-y:auto;flex:1;font-size:13px;line-height:1.6;color:#333;">' +
        TEXTO_TERMOS +
      '</div>' +
      '<div style="padding:16px 22px;border-top:1px solid #eee;background:#fafafa;">' +
        '<p id="termos-cadastro-aviso" style="color:#d97706;font-size:12px;margin:0 0 10px;">Role até ao fim do texto para poder continuar.</p>' +
        '<button id="termos-cadastro-btn" type="button" disabled style="width:100%;padding:12px;border:none;border-radius:8px;background:#9aa3ab;color:#fff;font-weight:700;font-size:14px;cursor:not-allowed;transition:background 0.15s;">Li e aceito — continuar</button>' +
      '</div>' +
    '</div>';

  document.body.appendChild(overlay);

  const scrollEl = overlay.querySelector("#termos-cadastro-scroll");
  const aviso = overlay.querySelector("#termos-cadastro-aviso");
  const btn = overlay.querySelector("#termos-cadastro-btn");
  const fecharBtn = overlay.querySelector("#termos-cadastro-fechar");

  function liberar() {
    btn.disabled = false;
    btn.style.background = "#0c7ab5";
    btn.style.cursor = "pointer";
    aviso.style.display = "none";
  }

  scrollEl.addEventListener("scroll", function () {
    const chegouAoFim =
      scrollEl.scrollTop + scrollEl.clientHeight >= scrollEl.scrollHeight - 24;
    if (chegouAoFim && btn.disabled) liberar();
  });

  if (scrollEl.scrollHeight <= scrollEl.clientHeight + 4) liberar();

  function fecharModal() {
    overlay.remove();
    _modalTermosAberto = false;
  }

  fecharBtn.addEventListener("click", fecharModal);
  overlay.addEventListener("click", function (e) {
    if (e.target === overlay) fecharModal();
  });

  btn.addEventListener("click", function () {
    if (btn.disabled) return;
    fecharModal();
    if (typeof onAceitar === "function") onAceitar();
  });
}

function _configurarBotaoTermos() {
  const btn = document.getElementById("btn-ler-termos");
  if (!btn) return;

  btn.addEventListener("click", function () {
    _mostrarModalTermos(function () {
      _termosAceitos = true;
      btn.innerHTML = '<i class="fa-solid fa-circle-check"></i> Termos e Condições aceites';
      btn.classList.add("termos-aceitos");
    });
  });
}

if (document.readyState === "loading") {
  document.addEventListener("DOMContentLoaded", _configurarBotaoTermos);
} else {
  _configurarBotaoTermos();
}

/* =========================================================================
   CADASTRO
   ========================================================================= */
window.cadastrar = async function () {
  const nome = document.getElementById("nome").value;
  const email = document.getElementById("email").value;
  const senha = document.getElementById("senha").value;
  const confirmarSenha = document.getElementById("confirmarSenha").value;
  const dataNascimento = document.getElementById("dataNascimento").value;
  const provincia = document.getElementById("provincia").value;
  const municipio = document.getElementById("municipio").value;
  const telefone = document.getElementById("telefone")
    ? document.getElementById("telefone").value.trim()
    : "";

  console.log("Iniciando cadastro", {
    nome,
    email,
    dataNascimento,
    provincia,
    municipio,
  });

  const nomeTrim = nome.trim();

  if (senha !== confirmarSenha) {
    showAlert("As senhas não coincidem. Verifique e tente novamente.");
    return;
  }

  if (senha.length < 6) {
    showAlert("A senha deve ter pelo menos 6 caracteres.");
    return;
  }

  if (!dataNascimento) {
    showAlert("Preencha a data de nascimento.");
    return;
  }
  const dt = new Date(dataNascimento);
  const year = dt.getFullYear();
  if (isNaN(dt.getTime()) || year < 1900 || year > 2009) {
    showAlert("A data de nascimento deve estar entre 1900 e 2009.");
    return;
  }

  // NOVO: sem ler e aceitar os termos, o cadastro não avança.
  if (!_termosAceitos) {
    showAlert(
      'Tem de ler e aceitar os Termos e Condições para se cadastrar. Toque em "Ler e aceitar os Termos e Condições" acima do botão de criar conta.',
    );
    return;
  }

  try {
    const usuariosRef = collection(db, "users");
    const q = query(usuariosRef, where("nome", "==", nomeTrim));
    const snap = await getDocs(q);
    if (!snap.empty) {
      showAlert("Já existe um usuário cadastrado com este nome completo.");
      return;
    }
  } catch (err) {
    console.error("Erro ao verificar nomes duplicados:", err);
  }

  if (!telefone) {
    showAlert("Preencha o número de telefone.");
    return;
  }
  const telClean = telefone.replace(/[^0-9]/g, "");
  if (telClean.length < 6) {
    showAlert("Número de telefone inválido.");
    return;
  }

  try {
    const cred = await createUserWithEmailAndPassword(auth, email, senha);
    const user = cred.user;
    const uid = user.uid;
    console.log("Usuário criado no Auth:", uid);

    await sendEmailVerification(user);
    console.log("E-mail de verificação enviado.");

    await setDoc(doc(db, "users", uid), {
      nome: nomeTrim,
      nome_normalized: nomeTrim.toLowerCase(),
      email: email,
      telefone: telefone,
      dataNascimento: dataNascimento,
      provincia: provincia,
      municipio: municipio,
      role: "user",
      criadoEm: new Date(),
      emailVerificado: false,
      termosAceitos: true,
      termosAceitosEm: new Date(),
      termosVersao: VERSAO_TERMOS,
    });

    console.log("Documento criado no Firestore para:", uid);

    showAlert(
      "✅ Conta criada com sucesso! Enviámos um email de verificação para " + email + ". " +
      "Clique no link do email e depois faça login.",
      { onOk: () => {} }
    );

    await signOut(auth);

    document.getElementById("logup").classList.remove("cadastro_move");
    document.getElementById("login").classList.remove("login_move");
  } catch (error) {
    console.error("Erro no cadastro:", error);

    if (error.code === "auth/email-already-in-use") {
      showAlert("Este e-mail já está sendo usado por outra conta.");
    } else if (error.code === "auth/invalid-email") {
      showAlert("O formato do e-mail é inválido.");
    } else if (error.code === "auth/weak-password") {
      showAlert("A senha é muito fraca.");
    } else {
      showAlert("Erro ao cadastrar: " + error.message);
    }
  }
};