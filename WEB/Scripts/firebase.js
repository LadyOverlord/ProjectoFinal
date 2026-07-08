
























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

console.log('Firebase inicializado para projecto:', firebaseConfig.projectId);

export const auth = getAuth(app);
export const db = getFirestore(app);
export const storage = getStorage(app);

// ---------------------------------------------------------------------------
// _basePath: detecta o prefixo do repo no GitHub Pages (ex: "/missingao")
// Em localhost devolve "". Em GitHub Pages devolve "/REPO_NAME".
// Usado para construir URLs absolutas correctas em qualquer ambiente.
// ---------------------------------------------------------------------------
function _basePath() {
  try {
    const parts = window.location.pathname.split('/');
    // pathname em GitHub Pages: /REPO/WEB/pagina.html  → parts[1] = "REPO"
    // pathname em localhost:     /WEB/pagina.html       → parts[1] = "WEB"
    // Se parts[1] === "WEB" estamos em localhost sem subpasta de repo
    if (parts[1] && parts[1].toUpperCase() !== 'WEB') {
      return '/' + parts[1]; // ex: "/missingao"
    }
  } catch (_) {}
  return '';
}

// ---------------------------------------------------------------------------
// _inWEB: true se a página actual já está dentro da pasta /WEB/
// ---------------------------------------------------------------------------
function _inWEB() {
  return /\/WEB(\/|$)/i.test(window.location.pathname);
}

// ---------------------------------------------------------------------------
// navigateToLogin
// Sempre navega para WEB/login_cadastro.html relativo à raiz do repo.
// ---------------------------------------------------------------------------
export async function navigateToLogin() {
  const base  = _basePath();
  // Se já estamos em /WEB/ → relativo à pasta actual
  const url = _inWEB()
    ? new URL('login_cadastro.html', window.location.href).href
    : window.location.origin + base + '/WEB/login_cadastro.html';
  window.location.href = url;
}

// ---------------------------------------------------------------------------
// navigateToTarget(name)
// Navega para uma página dentro de /WEB/ (ex: "index.html", "admin.html").
// Funciona em localhost, localhost:PORT e GitHub Pages /REPO/WEB/*.
// ---------------------------------------------------------------------------
export async function navigateToTarget(name) {
  const base = _basePath();

  // Candidatos, do mais provável para o menos:
  const candidates = [
    // 1. Mesmo directório (estamos em /WEB/, o alvo também está em /WEB/)
    new URL(name, window.location.href).href,
    // 2. Absoluto com base do repo  (ex: /missingao/WEB/index.html)
    window.location.origin + base + '/WEB/' + name,
    // 3. Pai relativo (caso raro: chamado de fora de /WEB/)
    new URL('../WEB/' + name, window.location.href).href,
  ].filter(Boolean);

  // Remove duplicatas mantendo a ordem
  const seen = new Set();
  const unique = candidates.filter(u => {
    if (seen.has(u)) return false;
    seen.add(u);
    return true;
  });

  for (const url of unique) {
    try {
      console.debug('[nav] a testar', url);
      const res = await fetch(url, { method: 'HEAD' });
      if (res && res.ok) {
        console.debug('[nav] a redirigir para', url);
        window.location.href = url;
        return;
      }
    } catch (_) {
      // HEAD bloqueado (CORS) — tenta GET
      try {
        const res2 = await fetch(url, { method: 'GET' });
        if (res2 && res2.ok) {
          window.location.href = url;
          return;
        }
      } catch (_2) { /* ignorar */ }
    }
  }

  // Fallback garantido: mesmo directório
  const fallback = new URL(name, window.location.href).href;
  console.warn('[nav] fallback para', fallback);
  window.location.href = fallback;
}

// Mantida por compatibilidade com código legado que ainda a importe
export function getLoginPath() {
  return _inWEB() ? 'login_cadastro.html' : 'WEB/login_cadastro.html';
}
