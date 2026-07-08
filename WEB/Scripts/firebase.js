import { initializeApp } from "https://www.gstatic.com/firebasejs/12.8.0/firebase-app.js";
import { getAuth } from "https://www.gstatic.com/firebasejs/12.8.0/firebase-auth.js";
import { getFirestore } from "https://www.gstatic.com/firebasejs/12.8.0/firebase-firestore.js";
import { getStorage } from "https://www.gstatic.com/firebasejs/12.8.0/firebase-storage.js";

const firebaseConfig = {
  apiKey: "AIzaSyAWnSkF8rxzonTK7oqrFGUC-2yLfTc2_jk",
  authDomain: "missingao-88704.firebaseapp.com",
  projectId: "missingao-88704",
  storageBucket: "missingao-88704.firebasestorage.app",
  messagingSenderId: "489576604551",
  appId: "1:489576604551:web:2625dd76489772a2662922"
};

const app = initializeApp(firebaseConfig);
console.log("Firebase inicializado para projecto:", firebaseConfig.projectId);

export const auth = getAuth(app);
export const db   = getFirestore(app);
export const storage = getStorage(app);

// ---------------------------------------------------------------------------
// _origin: devolve "https://host/repo" (sem barra no fim)
// Exemplos:
//   https://missing-ao.github.io/ProjectoFinal/WEB/login.html
//     → https://missing-ao.github.io/ProjectoFinal
//   http://127.0.0.1:5500/WEB/login.html
//     → http://127.0.0.1:5500
// ---------------------------------------------------------------------------
function _repoRoot() {
  const loc  = window.location;
  const path = loc.pathname;

  // Em GitHub Pages o pathname é /REPO/... — o repo root é /REPO
  // Em localhost o pathname é /... — o repo root é ""
  // Detectar: se o primeiro segmento NÃO é "WEB", é o nome do repo
  const parts = path.split("/").filter(Boolean); // ["ProjectoFinal","WEB","login.html"]
  
  if (parts.length > 0 && parts[0].toUpperCase() !== "WEB") {
    // GitHub Pages: origin + /REPO
    return loc.origin + "/" + parts[0];
  }
  // Localhost: apenas origin
  return loc.origin;
}

// ---------------------------------------------------------------------------
// Estrutura do projecto:
//   /index.html          ← home (app principal)
//   /WEB/login_cadastro.html
//   /WEB/admin.html
//   /WEB/profile.html
//
// "index.html" → raiz do repo
// tudo o resto → /WEB/
// ---------------------------------------------------------------------------
export async function navigateToTarget(name) {
  const root = _repoRoot();
  if (name === "index.html") {
    window.location.href = root + "/index.html";
  } else {
    window.location.href = root + "/WEB/" + name;
  }
}

export async function navigateToLogin() {
  const root = _repoRoot();
  window.location.href = root + "/WEB/login_cadastro.html";
}

export function getLoginPath() {
  return _repoRoot() + "/WEB/login_cadastro.html";
}