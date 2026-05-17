// js/firebase.js
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

// Inicializa Firebase
const app = initializeApp(firebaseConfig);

console.log('Firebase inicializado para projeto:', firebaseConfig.projectId);

// Exporta Auth e Firestore
export const auth = getAuth(app);
export const db = getFirestore(app);
export const storage = getStorage(app);

// Retorna o caminho correto para a página de login/registro
export function getLoginPath() {
  try {
    const p = window.location.pathname || "";
    // Se a página actual já estiver dentro da pasta /WEB, use caminho relativo
    if (/\/WEB(\/|$)/.test(p)) return "login_cadastro.html";
    // Caso contrário, redirecionar para a página dentro da pasta WEB a partir da raiz
    return "WEB/login_cadastro.html";
  } catch (e) {
    return "WEB/login_cadastro.html";
  }
}

export async function navigateToLogin() {
  const origin = window.location.origin || '';
  const base = window.location.href;
  const candidates = [
    new URL('login_cadastro.html', base).href,
    new URL('WEB/login_cadastro.html', base).href,
    origin + '/login_cadastro.html',
    origin + '/WEB/login_cadastro.html',
  ].filter(Boolean);

  for (const url of candidates) {
    try {
      const res = await fetch(url, { method: 'HEAD' });
      if (res && res.ok) {
        console.log('navigateToLogin: redirecting to', url);
        window.location.href = url;
        return;
      }
    } catch (e) {
      // HEAD may be blocked; try GET as fallback
      try {
        const res2 = await fetch(url, { method: 'GET' });
        if (res2 && res2.ok) {
          console.log('navigateToLogin: redirecting to (GET)', url);
          window.location.href = url;
          return;
        }
      } catch (e2) {
        // ignore and try next
      }
    }
  }

  // Fallback: try relative path
  const fallback = 'WEB/login_cadastro.html';
  console.warn('navigateToLogin: no candidate found, using fallback', fallback);
  window.location.href = fallback;
}
