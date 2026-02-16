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
