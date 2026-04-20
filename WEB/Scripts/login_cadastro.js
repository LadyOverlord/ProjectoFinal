import { auth, db } from "./firebase.js";
import { signInWithEmailAndPassword } from "https://www.gstatic.com/firebasejs/12.8.0/firebase-auth.js";
import {
  doc,
  getDoc,
} from "https://www.gstatic.com/firebasejs/12.8.0/firebase-firestore.js";

window.login = async function () {
  const email = document.getElementById("loginEmail").value; // Ajuste o ID conforme seu HTML
  const senha = document.getElementById("loginSenha").value; // Ajuste o ID conforme seu HTML

  if (!email || !senha) {
    showAlert("Por favor, preencha todos os campos.");
    return;
  }

  try {
    // 1. Autentica no Firebase Auth
    const userCredential = await signInWithEmailAndPassword(auth, email, senha);
    const user = userCredential.user;

    // (Opcional) Bloquear se o e-mail não foi verificado ainda
    if (!user.emailVerified) {
      showAlert(
        "Por favor, verifique o seu e-mail antes de entrar. Verifique sua caixa de entrada ou spam.",
      );
      // return; // Remova o comentário se quiser impedir o login de quem não verificou
    }

    console.log("Login autenticado. Buscando perfil no Firestore...");

    // 2. Busca o documento do usuário no Firestore usando o UID
    const docRef = doc(db, "users", user.uid);
    const docSnap = await getDoc(docRef);

    if (docSnap.exists()) {
      const dados = docSnap.data();
      const role = dados.role; // Aqui pegamos 'admin' ou 'user'

      console.log("Papel do usuário:", role);

      // 3. Redirecionamento baseado no Role
      if (role === "admin") {
  window.location.href = "admin.html";
} 
else if (role === "policia") {
  window.location.href = "police.html";
}
else {
  window.location.href = "index.html";
}
    } else {
      // O usuário existe no Auth, mas não tem documento no Firestore (erro de cadastro)
      console.error("Documento de usuário não encontrado!");
      showAlert("Erro: Perfil de usuário não encontrado.");
    }
  } catch (error) {
    console.error("Erro ao fazer login:", error);

    // Tratamento de erros
    if (error.code === "auth/invalid-credential") {
      showAlert("E-mail ou senha incorretos.");
    } else if (error.code === "auth/user-not-found") {
      showAlert("Usuário não cadastrado.");
    } else if (error.code === "auth/wrong-password") {
      showAlert("Senha incorreta.");
    } else {
      showAlert("Erro ao entrar: " + error.message);
    }
  }
};

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

provinciaSelect.addEventListener("change", function () {
  const provincia = this.value;
  municipioSelect.innerHTML =
    '<option value="" hidden>Selecione o município</option>';
  if (municipiosPorProvincia[provincia]) {
    municipiosPorProvincia[provincia].forEach(function (mun) {
      const opt = document.createElement("option");
      opt.value = mun.toLowerCase().replace(/ /g, "_");
      opt.textContent = mun;
      municipioSelect.appendChild(opt);
    });
    municipioField.style.display = "block";
    municipioSelect.required = true;
  } else {
    municipioField.style.display = "none";
    municipioSelect.required = false;
  }
});

particlesJS("particles-js", {
  particles: {
    number: {
      value: 80,
      density: { enable: true, value_area: 1025.8919341219544 },
    },
    color: { value: "#0c7ab5" },
    shape: {
      type: "circle",
      stroke: { width: 0, color: "#000000" },
      polygon: { nb_sides: 4 },
      image: { src: "img/github.svg", width: 100, height: 100 },
    },
    opacity: {
      value: 0.5,
      random: false,
      anim: { enable: false, speed: 1, opacity_min: 0.1, sync: false },
    },
    size: {
      value: 3,
      random: true,
      anim: { enable: false, speed: 40, size_min: 0.1, sync: false },
    },
    line_linked: {
      enable: false,
      distance: 128.27296486924183,
      color: "#ffffff",
      opacity: 0.2244776885211732,
      width: 1,
    },
    move: {
      enable: true,
      speed: 6,
      direction: "none",
      random: false,
      straight: false,
      out_mode: "out",
      bounce: false,
      attract: { enable: false, rotateX: 600, rotateY: 1200 },
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
      grab: { distance: 400, line_linked: { opacity: 1 } },
      bubble: { distance: 400, size: 40, duration: 2, opacity: 8, speed: 3 },
      repulse: { distance: 200, duration: 0.4 },
      push: { particles_nb: 4 },
      remove: { particles_nb: 2 },
    },
  },
  retina_detect: true,
});
var count_particles, stats, update;
stats = new Stats();
stats.setMode(0);
stats.domElement.style.position = "absolute";
stats.domElement.style.left = "0px";
stats.domElement.style.top = "0px";
document.body.appendChild(stats.domElement);
count_particles = document.querySelector(".js-count-particles");
update = function () {
  stats.begin();
  stats.end();
  if (window.pJSDom[0].pJS.particles && window.pJSDom[0].pJS.particles.array) {
    count_particles.innerText = window.pJSDom[0].pJS.particles.array.length;
  }
  requestAnimationFrame(update);
};
requestAnimationFrame(update);
