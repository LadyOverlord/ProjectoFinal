import { auth, db } from "./firebase.js";
import {
    onAuthStateChanged,
    signOut
} from "https://www.gstatic.com/firebasejs/12.8.0/firebase-auth.js";
import {
    doc,
    getDoc,
    updateDoc,
    collection,
    query,
    where,
    getDocs
} from "https://www.gstatic.com/firebasejs/12.8.0/firebase-firestore.js";

// ─── Estado global ──────────────────────────────────────────────
let currentUID = null;
let allCasos   = [];

// ─── Autenticação ────────────────────────────────────────────────
onAuthStateChanged(auth, async (user) => {
    if (user) {
        currentUID = user.uid;
        await carregarPerfil(user);
        await carregarMeusCasos(user.uid);
    } else {
        window.location.href = "login_cadastro.html";
    }
});

// ─── Carregar dados do perfil ────────────────────────────────────
async function carregarPerfil(user) {
    try {
        const docRef  = doc(db, "users", user.uid);
        const docSnap = await getDoc(docRef);

        if (docSnap.exists()) {
            const data = docSnap.data();

            document.getElementById("p-nome").innerText    = data.nome  || "Utilizador";
            document.querySelector("#p-email span").innerText = data.email || user.email || "—";
            document.querySelector("#p-local span").innerText =
                [data.municipio, data.provincia].filter(Boolean).join(", ") || "Localização não definida";

            // Mostrar foto guardada (base64)
            if (data.photoBase64) {
                mostrarFoto(data.photoBase64);
            }
        }
    } catch (err) {
        console.error("Erro ao carregar perfil:", err);
    }
}

// ─── Exibir foto no avatar ───────────────────────────────────────
function mostrarFoto(base64) {
    const img         = document.getElementById("profile-photo");
    const placeholder = document.getElementById("avatar-placeholder");

    img.src = base64;
    img.classList.remove("hidden");
    placeholder.style.display = "none";
}

// ─── Upload e compressão de foto ─────────────────────────────────
/**
 * Comprime a imagem selecionada para um canvas e retorna base64.
 * maxDim: largura/altura máxima do resultado (default 300px)
 * quality: qualidade JPEG 0-1 (default 0.82)
 */
function comprimirImagem(file, maxDim = 300, quality = 0.82) {
    return new Promise((resolve, reject) => {
        const reader = new FileReader();
        reader.onerror = () => reject(new Error("Erro ao ler ficheiro."));
        reader.onload = (e) => {
            const img = new Image();
            img.onerror = () => reject(new Error("Imagem inválida."));
            img.onload = () => {
                // Calcular dimensões mantendo proporção
                let { width, height } = img;
                if (width > height) {
                    if (width > maxDim) { height = Math.round(height * maxDim / width); width = maxDim; }
                } else {
                    if (height > maxDim) { width = Math.round(width * maxDim / height); height = maxDim; }
                }

                const canvas = document.createElement("canvas");
                canvas.width  = width;
                canvas.height = height;
                canvas.getContext("2d").drawImage(img, 0, 0, width, height);

                resolve(canvas.toDataURL("image/jpeg", quality));
            };
            img.src = e.target.result;
        };
        reader.readAsDataURL(file);
    });
}

// ─── Guardar foto no Firestore ───────────────────────────────────
async function guardarFotoFirestore(base64) {
    if (!currentUID) return;

    const loader = document.getElementById("upload-loader");
    loader.classList.remove("hidden");

    try {
        const userRef = doc(db, "users", currentUID);
        await updateDoc(userRef, { photoBase64: base64 });
        mostrarFoto(base64);
        mostrarNotificacao("✅ Foto de perfil actualizada com sucesso!");
    } catch (err) {
        console.error("Erro ao guardar foto:", err);
        mostrarNotificacao("❌ Erro ao guardar foto. Tente novamente.");
    } finally {
        loader.classList.add("hidden");
    }
}

// ─── Evento: clique no avatar ou no menu "Alterar Foto" ─────────
function acionarUploadFoto() {
    document.getElementById("photo-input").click();
}

document.getElementById("avatar-trigger").addEventListener("click", acionarUploadFoto);

document.getElementById("photo-input").addEventListener("change", async (e) => {
    const file = e.target.files[0];
    if (!file) return;

    // Validações básicas
    const tiposPermitidos = ["image/jpeg", "image/png", "image/webp", "image/gif"];
    if (!tiposPermitidos.includes(file.type)) {
        mostrarNotificacao("⚠️ Formato não suportado. Use JPG, PNG ou WEBP.");
        e.target.value = "";
        return;
    }
    // Limite: 5 MB antes da compressão
    if (file.size > 5 * 1024 * 1024) {
        mostrarNotificacao("⚠️ Ficheiro demasiado grande (máximo 5 MB).");
        e.target.value = "";
        return;
    }

    try {
        const base64Comprimido = await comprimirImagem(file);
        await guardarFotoFirestore(base64Comprimido);
    } catch (err) {
        console.error(err);
        mostrarNotificacao("❌ Não foi possível processar a imagem.");
    }

    // Reset para permitir seleccionar o mesmo ficheiro novamente
    e.target.value = "";
});

// ─── Carregar casos do utilizador ───────────────────────────────
async function carregarMeusCasos(uid) {
    const listDiv = document.getElementById("cases-list");

    try {
        const q             = query(collection(db, "casos_pendentes"), where("userId", "==", uid));
        const querySnapshot = await getDocs(q);

        allCasos = [];
        if (querySnapshot.empty) {
            listDiv.innerHTML = `<p style="color:#999; font-size:14px; padding:16px 0; font-family:var(--font-base);">
                Ainda não relatou nenhum caso.
            </p>`;
            atualizarStats([]);
            return;
        }

        querySnapshot.forEach((document) => {
            allCasos.push({ id: document.id, ...document.data() });
        });

        atualizarStats(allCasos);
        renderizarCasos(allCasos);

    } catch (error) {
        console.error(error);
        listDiv.innerHTML = `<p style="color:#e74c3c; font-size:14px; padding:16px 0; font-family:var(--font-base);">
            Erro ao carregar casos. Tente novamente.
        </p>`;
    }
}

// ─── Renderizar lista de casos ───────────────────────────────────
function renderizarCasos(casos) {
    const listDiv = document.getElementById("cases-list");

    if (casos.length === 0) {
        listDiv.innerHTML = `<p style="color:#999; font-size:14px; padding:16px 0; font-family:var(--font-base);">
            Nenhum caso encontrado para este filtro.
        </p>`;
        return;
    }

    listDiv.innerHTML = casos.map((caso) => {
        const statusClass = caso.status || "pendente";
        const statusLabel = {
            pendente:  "Pendente",
            aprovado:  "Aprovado",
            rejeitado: "Rejeitado"
        }[statusClass] || statusClass;

        return `
            <div class="case-item">
                <div class="case-info">
                    <strong>${caso.nome || "Sem nome"}</strong>
                    <small><i class="fa-solid fa-location-dot" style="color:#e07a5f; margin-right:4px;"></i>${caso.ultimo_local || "Local não definido"}</small>
                </div>
                <span class="status ${statusClass}">${statusLabel}</span>
            </div>
        `;
    }).join("");
}

// ─── Actualizar estatísticas ─────────────────────────────────────
function atualizarStats(casos) {
    const aprovados = casos.filter(c => c.status === "aprovado").length;
    const pendentes = casos.filter(c => !c.status || c.status === "pendente").length;

    document.getElementById("stat-casos").innerText    = casos.length;
    document.getElementById("stat-aprovados").innerText = aprovados;
    document.getElementById("stat-pendentes").innerText  = pendentes;
}

// ─── Filtros de casos ────────────────────────────────────────────
document.querySelectorAll(".filter-btn").forEach((btn) => {
    btn.addEventListener("click", () => {
        document.querySelectorAll(".filter-btn").forEach(b => b.classList.remove("active"));
        btn.classList.add("active");

        const filtro = btn.dataset.filter;
        if (filtro === "all") {
            renderizarCasos(allCasos);
        } else {
            const filtrados = allCasos.filter(c => (c.status || "pendente") === filtro);
            renderizarCasos(filtrados);
        }
    });
});

// ─── Menu de opções ──────────────────────────────────────────────
const editMenu    = document.getElementById("edit-menu");
const backdrop    = document.getElementById("menu-backdrop");

function abrirMenu() {
    editMenu.classList.add("open_section");
    backdrop.classList.remove("hidden");
}

function fecharMenu() {
    editMenu.classList.remove("open_section");
    backdrop.classList.add("hidden");
}

document.getElementById("btn-edit-profile").addEventListener("click", abrirMenu);
document.getElementById("btn-cancel-edit").addEventListener("click", fecharMenu);
backdrop.addEventListener("click", fecharMenu);

document.getElementById("btn-change-photo").addEventListener("click", () => {
    fecharMenu();
    setTimeout(acionarUploadFoto, 200);
});

// ─── Logout ──────────────────────────────────────────────────────
document.getElementById("btn-logout").addEventListener("click", () => {
    signOut(auth).then(() => {
        window.location.href = "login_cadastro.html";
    }).catch((err) => {
        console.error("Erro ao sair:", err);
        mostrarNotificacao("❌ Erro ao sair da conta.");
    });
});

// ─── Notificação simples (fallback se alerts.js não existir) ─────
function mostrarNotificacao(msg) {
    if (typeof window.showAlert === "function") {
        window.showAlert(msg);
        return;
    }
    // Fallback: toast simples
    const toast = document.createElement("div");
    toast.innerText = msg;
    Object.assign(toast.style, {
        position:     "fixed",
        bottom:       "24px",
        left:         "50%",
        transform:    "translateX(-50%)",
        background:   "#222",
        color:        "#fff",
        padding:      "12px 22px",
        borderRadius: "10px",
        fontSize:     "14px",
        fontFamily:   "var(--font-base)",
        zIndex:       "9999",
        boxShadow:    "0 4px 16px rgba(0,0,0,0.2)",
        transition:   "opacity 0.4s",
        maxWidth:     "90vw",
        textAlign:    "center"
    });
    document.body.appendChild(toast);
    setTimeout(() => {
        toast.style.opacity = "0";
        setTimeout(() => toast.remove(), 500);
    }, 3000);
}