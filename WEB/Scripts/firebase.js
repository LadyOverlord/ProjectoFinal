// Scripts/firebase.js
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
  appId: "1:489576604551:web:2625dd76489772a2662922",
};

const app = initializeApp(firebaseConfig);
console.log("Firebase inicializado para o projecto:", firebaseConfig.projectId);

export const auth = getAuth(app);
export const db = getFirestore(app);
export const storage = getStorage(app);

/* =========================================================================
   NAVEGAÇÃO ENTRE PÁGINAS
   ─────────────────────────────────────────────────────────────────────────
   Estrutura do projecto (confirmada):
     /index.html              ← app principal, na raiz
     /WEB/login_cadastro.html
     /WEB/admin.html
     /WEB/profile.html
     /WEB/Scripts/, /WEB/CSS/, /WEB/imgs/  ← tudo o resto vive aqui dentro

   CORRIGIDO: as versões anteriores desta função ora testavam vários
   caminhos candidatos com fetch HEAD/GET (lento e ainda assim falhava
   nalguns servidores que bloqueiam HEAD), ora assumiam uma estrutura
   fixa que não batia certo com todos os ambientes (Live Server local
   vs. GitHub Pages com subpasta de repositório) — foi isso que causou o
   404 ao navegar de index.html (modo convidado) para login_cadastro.html.

   Nova abordagem, mais simples: a "raiz do projecto" é sempre a parte do
   URL que vem ANTES de "/WEB/". Se a página actual ainda não estiver
   dentro de "/WEB/" (ou seja, estamos no próprio index.html), a raiz é
   simplesmente a pasta que contém o ficheiro actual. Isto funciona tanto
   em localhost/Live Server (http://127.0.0.1:5500/...) como em GitHub
   Pages com o nome do repositório no caminho (https://user.github.io/
   repo/...), sem precisar de nenhum pedido de rede extra para testar
   candidatos.
   ========================================================================= */
function _getRepoRoot() {
  const path = window.location.pathname; // ex: "/WEB/login_cadastro.html" ou "/index.html"
  const webIndex = path.toUpperCase().indexOf("/WEB/");

  if (webIndex !== -1) {
    // Já estamos dentro de /WEB/ — a raiz é tudo o que vem antes disso.
    return window.location.origin + path.substring(0, webIndex);
  }

  // Ainda não estamos em /WEB/ (ex: estamos no index.html da raiz) — a
  // raiz é a pasta que contém o ficheiro actual.
  const lastSlash = path.lastIndexOf("/");
  return window.location.origin + path.substring(0, lastSlash);
}

/**
 * Navega para uma página dentro do projecto.
 * @param {string} name "index.html" (raiz) ou o nome de um ficheiro dentro
 *                       de WEB/ (ex: "admin.html", "profile.html").
 */
export async function navigateToTarget(name) {
  const root = _getRepoRoot();
  if (name === "index.html") {
    window.location.href = root + "/index.html";
  } else {
    window.location.href = root + "/WEB/" + name;
  }
}

export async function navigateToLogin() {
  const root = _getRepoRoot();
  window.location.href = root + "/WEB/login_cadastro.html";
}

export function getLoginPath() {
  return _getRepoRoot() + "/WEB/login_cadastro.html";
}