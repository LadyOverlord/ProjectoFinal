import { auth, db } from "./firebase.js";
import { onAuthStateChanged } from "https://www.gstatic.com/firebasejs/12.8.0/firebase-auth.js";
import { doc, getDoc } from "https://www.gstatic.com/firebasejs/12.8.0/firebase-firestore.js";

// Monitora o estado da autenticação
onAuthStateChanged(auth, async (user) => {
  if (user) {
    // 1. Usuário está logado, vamos verificar se é admin
    try {
      const docRef = doc(db, "users", user.uid);
      const docSnap = await getDoc(docRef);

      if (docSnap.exists()) {
        const role = docSnap.data().role;
        
        if (role === 'admin') {
          // 2. É ADMIN! Pode mostrar a tela.
          document.body.style.display = "block"; 
          console.log("Acesso autorizado para admin.");
        } else {
          // 3. É user comum tentando entrar. Chuta para o index.
          window.location.href = "index.html";
        }
      } else {
        // Erro: Usuário sem cadastro no banco
        alert("Erro de permissão.");
        window.location.href = "index.html";
      }
    } catch (error) {
      console.error("Erro ao verificar admin:", error);
      window.location.href = "index.html";
    }
  } else {
    // 4. Não está logado. Chuta para o login.
    window.location.href = "index.html"; // ou login.html
  }
});

// Resto do seu código do admin.js abaixo...