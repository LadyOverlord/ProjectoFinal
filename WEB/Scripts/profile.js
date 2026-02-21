import { auth, db } from "./firebase.js";
import { onAuthStateChanged, signOut } from "https://www.gstatic.com/firebasejs/12.8.0/firebase-auth.js";
import { doc, getDoc, collection, query, where, getDocs } from "https://www.gstatic.com/firebasejs/12.8.0/firebase-firestore.js";

onAuthStateChanged(auth, async (user) => {
    if (user) {
        // 1. Carregar Dados do Usuário
        const docRef = doc(db, "users", user.uid);
        const docSnap = await getDoc(docRef);
        
        if (docSnap.exists()) {
            const data = docSnap.data();
            document.getElementById('p-nome').innerText = data.nome || "Usuário";
            document.getElementById('p-email').innerText = data.email;
            document.getElementById('p-local').innerText = `${data.municipio || ''}, ${data.provincia || ''}`;
        }

        // 2. Carregar Casos do Usuário
        carregarMeusCasos(user.uid);

    } else {
        // Se não estiver logado, volta pro login
        window.location.href = "login_cadastro.html";
    }
});

async function carregarMeusCasos(uid) {
    const listDiv = document.getElementById('cases-list');
    
    try {
        // Busca na coleção "casos" onde userId == uid
        const q = query(collection(db, "casos"), where("userId", "==", uid));
        const querySnapshot = await getDocs(q);

        listDiv.innerHTML = "";

        if (querySnapshot.empty) {
            listDiv.innerHTML = "<p>Você ainda não relatou nenhum caso.</p>";
            return;
        }

        querySnapshot.forEach((doc) => {
            const caso = doc.data();
            const statusClass = caso.status || 'pendente'; // pendente, aprovado, rejeitado
            
            const item = `
                <div class="case-item">
                    <div>
                        <strong>${caso.nome}</strong><br>
                        <small>Local: ${caso.ultimo_local || 'N/A'}</small>
                    </div>
                    <div>
                        <span class="status ${statusClass}">${caso.status || 'Pendente'}</span>
                    </div>
                </div>
            `;
            listDiv.innerHTML += item;
        });

    } catch (error) {
        console.error(error);
        listDiv.innerHTML = "<p>Erro ao carregar casos.</p>";
    }
}

// Logout
document.getElementById('btn-logout').addEventListener('click', () => {
    signOut(auth).then(() => window.location.href = "login_cadastro.html");
});