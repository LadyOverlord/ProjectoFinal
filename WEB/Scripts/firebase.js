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
// _webBase: devolve o URL absoluto da pasta /WEB/ independentemente de
// onde a página está a ser servida (raiz do repo, /WEB/, localhost, etc.)
//
// Exemplos:
//   https://missing-ao.github.io/ProjectoFinal/index.html
//     → https://missing-ao.github.io/ProjectoFinal/WEB/
//   https://missing-ao.github.io/ProjectoFinal/WEB/login_cadastro.html
//     → https://missing-ao.github.io/ProjectoFinal/WEB/
//   http://127.0.0.1:5500/WEB/index.html
//     → http://127.0.0.1:5500/WEB/
//   http://127.0.0.1:5500/index.html  (live server na raiz)
//     → http://127.0.0.1:5500/WEB/
// ---------------------------------------------------------------------------
function _webBase() {
  const loc  = window.location;
  const path = loc.pathname; // ex: /ProjectoFinal/WEB/login_cadastro.html

  // Se já estamos dentro de /WEB/, a base é o directório actual
  if (/\/WEB\//i.test(path)) {
    // "https://host/repo/WEB/pagina.html" → "https://host/repo/WEB/"
    return loc.origin + path.substring(0, path.toLowerCase().lastIndexOf("/web/") + 5);
  }

  // Estamos fora de /WEB/ (raiz do repo ou localhost raiz).
  // Construir base a partir do directório da página actual + "WEB/"
  const dir = path.substring(0, path.lastIndexOf("/") + 1); // ex: /ProjectoFinal/
  return loc.origin + dir + "WEB/";
}

// ---------------------------------------------------------------------------
// navigateToTarget(name)
// Navega para uma página dentro de /WEB/ (ex: "index.html", "admin.html").
// Funciona em localhost e GitHub Pages independentemente de onde a página
// actual está.
// ---------------------------------------------------------------------------
export async function navigateToTarget(name) {
  window.location.href = _webBase() + name;
}

// ---------------------------------------------------------------------------
// navigateToLogin
// ---------------------------------------------------------------------------
export async function navigateToLogin() {
  window.location.href = _webBase() + "login_cadastro.html";
}

// Mantida por compatibilidade
export function getLoginPath() {
  return _webBase() + "login_cadastro.html";
}