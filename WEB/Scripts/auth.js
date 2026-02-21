import { auth, db } from "./firebase.js";
import {
  createUserWithEmailAndPassword,
  sendEmailVerification,
  signOut,
} from "https://www.gstatic.com/firebasejs/12.8.0/firebase-auth.js";
import {
  doc,
  setDoc,
  collection,
  query,
  where,
  getDocs,
} from "https://www.gstatic.com/firebasejs/12.8.0/firebase-firestore.js";

window.cadastrar = async function () {
  const nome = document.getElementById("nome").value;
  const email = document.getElementById("email").value;
  const senha = document.getElementById("senha").value;
  const confirmarSenha = document.getElementById("confirmarSenha").value;
  const dataNascimento = document.getElementById("dataNascimento").value;
  const provincia = document.getElementById("provincia").value;
  const municipio = document.getElementById("municipio").value;
  const telefone = document.getElementById("telefone")
    ? document.getElementById("telefone").value.trim()
    : "";

  console.log("Iniciando cadastro", {
    nome,
    email,
    dataNascimento,
    provincia,
    municipio,
  });

  const nomeTrim = nome.trim();

  // 1. Validação de Senhas
  if (senha !== confirmarSenha) {
    showAlert("As senhas não coincidem. Verifique e tente novamente.");
    return;
  }

  if (senha.length < 6) {
    showAlert("A senha deve ter pelo menos 6 caracteres.");
    return;
  }

  // 2. Validação de Data
  if (!dataNascimento) {
    showAlert("Preencha a data de nascimento.");
    return;
  }
  const dt = new Date(dataNascimento);
  const year = dt.getFullYear();
  if (isNaN(dt.getTime()) || year < 1900 || year > 2009) {
    showAlert("A data de nascimento deve estar entre 1900 e 2009.");
    return;
  }

  // 3. Verificar nome duplicado no Firestore
  try {
    const usuariosRef = collection(db, "users");
    const q = query(usuariosRef, where("nome", "==", nomeTrim));
    const snap = await getDocs(q);
    if (!snap.empty) {
      showAlert("Já existe um usuário cadastrado com este nome completo.");
      return;
    }
  } catch (err) {
    console.error("Erro ao verificar nomes duplicados:", err);
    // Dica: Verifique se os índices do Firestore estão criados para esta consulta
  }

  // 4. Validação simples do telefone
  if (!telefone) {
    showAlert("Preencha o número de telefone.");
    return;
  }
  // Opcional: validar formato mínimo (apenas dígitos, sinais + e espaços aceitos)
  const telClean = telefone.replace(/[^0-9]/g, "");
  if (telClean.length < 6) {
    showAlert("Número de telefone inválido.");
    return;
  }

  try {
    // 4. Criar o usuário no Authentication (Aqui a senha é salva de forma segura automaticamente)
    const cred = await createUserWithEmailAndPassword(auth, email, senha);
    const user = cred.user;
    const uid = user.uid;
    console.log("Usuário criado no Auth:", uid);

    // 5. Enviar E-mail de Verificação (SOLUÇÃO DO PROBLEMA 1)
    await sendEmailVerification(user);
    console.log("E-mail de verificação enviado.");

    // 6. Salvar dados adicionais no Firestore (Sem senha!)
    await setDoc(doc(db, "users", uid), {
      nome: nomeTrim,
      nome_normalized: nomeTrim.toLowerCase(),
      email: email,
      telefone: telefone,
      dataNascimento: dataNascimento,
      provincia: provincia,
      municipio: municipio,
      role: "user",
      criadoEm: new Date(),
      emailVerificado: false, // Você pode usar user.emailVerified no futuro para checar
    });

    console.log("Documento criado no Firestore para:", uid);

    showAlert(
      "Cadastro realizado com sucesso! Verifique seu e-mail para confirmar a conta.",
    );

    // Opcional: Deslogar o usuário para obrigá-lo a logar apenas após verificar o e-mail
    // await signOut(auth);

    // Transição de tela
    document.getElementById("logup").classList.toggle("cadastro_move");
    document.getElementById("login").classList.toggle("login_move");
  } catch (error) {
    console.error("Erro no cadastro:", error);

    // Tratamento de erros comuns do Firebase
    if (error.code === "auth/email-already-in-use") {
      showAlert("Este e-mail já está sendo usado por outra conta.");
    } else if (error.code === "auth/invalid-email") {
      showAlert("O formato do e-mail é inválido.");
    } else if (error.code === "auth/weak-password") {
      showAlert("A senha é muito fraca.");
    } else {
      showAlert("Erro ao cadastrar: " + error.message);
    }
  }
};
