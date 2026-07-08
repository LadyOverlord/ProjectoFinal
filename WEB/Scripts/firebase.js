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



function _basePath() {
  const parts = window.location.pathname.split("/");

  if (parts[1] && parts[1].toUpperCase() !== "WEB") {
    return "/" + parts[1];
  }

  return "";
}


function _inWEB() {
  return /\/WEB(\/|$)/i.test(window.location.pathname);
}



export async function navigateToLogin() {

  const base = _basePath();

  window.location.href =
    window.location.origin +
    base +
    "/WEB/login_cadastro.html";
}



export async function navigateToTarget(name) {

  const base = _basePath();


  if (name === "index.html") {

    window.location.href =
      window.location.origin +
      base +
      "/index.html";

    return;
  }


  window.location.href =
    window.location.origin +
    base +
    "/WEB/" +
    name;
}



export function getLoginPath() {

  return _inWEB()
    ? "login_cadastro.html"
    : "WEB/login_cadastro.html";

}