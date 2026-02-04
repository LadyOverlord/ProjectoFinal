import { auth, db, storage } from "./firebase.js";
import {
  createUserWithEmailAndPassword
} from "https://www.gstatic.com/firebasejs/12.8.0/firebase-auth.js";

import {
  doc,
  setDoc
} from "https://www.gstatic.com/firebasejs/12.8.0/firebase-firestore.js";

import {
  ref,
  uploadBytes,
  getDownloadURL
} from "https://www.gstatic.com/firebasejs/12.8.0/firebase-storage.js";

window.cadastrar = async function () {
  const nome = document.getElementById("nome").value;
  const email = document.getElementById("email").value;
  const senha = document.getElementById("senha").value;
  const dataNascimento = document.getElementById("dataNascimento").value;
  const provincia = document.getElementById("provincia").value;
  const municipio = document.getElementById("municipio").value;
  const foto = document.getElementById("foto").files[0];

  if (!foto) {
    alert("Selecione uma foto");
    return;
  }

  // 1. Criar usuário no Auth
  const cred = await createUserWithEmailAndPassword(auth, email, senha);
  const uid = cred.user.uid;

  // 2. Upload da foto
  const fotoRef = ref(storage, `fotosUsuarios/${uid}`);
  await uploadBytes(fotoRef, foto);
  const fotoURL = await getDownloadURL(fotoRef);

  // 3. Criar documento no Firestore
  await setDoc(doc(db, "users", uid), {
    nome,
    email,
    dataNascimento,
    provincia,
    municipio,
    fotoURL,
    criadoEm: new Date()
  });

  alert("Cadastro realizado com sucesso!");
};
