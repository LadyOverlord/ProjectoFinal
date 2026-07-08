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

console.log(
  "Firebase inicializado para projecto:",
  firebaseConfig.projectId
);


export const auth = getAuth(app);
export const db = getFirestore(app);
export const storage = getStorage(app);


// Detecta se está no GitHub Pages ou localhost
function _basePath() {
  try {
    const parts = window.location.pathname.split("/");

    // GitHub Pages:
    // /nome-repositorio/WEB/admin.html
    //
    // localhost:
    // /WEB/admin.html

    if (parts[1] && parts[1].toUpperCase() !== "WEB") {
      return "/" + parts[1];
    }

  } catch (_) {}

  return "";
}


// Verifica se a página atual está dentro da pasta WEB
function _inWEB() {
  return /\/WEB(\/|$)/i.test(window.location.pathname);
}



// Ir para login
export async function navigateToLogin() {

  const base = _basePath();

  window.location.href =
    window.location.origin +
    base +
    "/WEB/login_cadastro.html";
}



// Navegação geral
export async function navigateToTarget(name) {

  const base = _basePath();


  // index.html está fora da WEB
  if (name === "index.html") {

    window.location.href =
      window.location.origin +
      base +
      "/index.html";

    return;
  }


  // Outras páginas ficam dentro da WEB
  window.location.href =
    window.location.origin +
    base +
    "/WEB/" +
    name;
}



// Compatibilidade com código antigo
export function getLoginPath() {

  return _inWEB()
    ? "login_cadastro.html"
    : "WEB/login_cadastro.html";

}