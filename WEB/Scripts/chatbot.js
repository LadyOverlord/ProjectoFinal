// === AVISO DE SEGURANÇA ===
// PARA A PRÉ-DEFESA: Coloque a sua chave aqui.
// APAGUE A CHAVE LÁ NO SITE DA OPENAI ASSIM QUE A APRESENTAÇÃO TERMINAR!
const OPENAI_API_KEY = "AIzaSyApuOtb3jfn0doaKPP3SEy7g-0NX2hWwe0"; 

document.addEventListener("DOMContentLoaded", () => {
    // Referências aos elementos do HTML
    const chatIcon = document.getElementById("chat_bot"); // O ID exato que você colocou no botão do header
    const chatbotDiv = document.getElementById("chatbotDiv");
    const closeChatbot = document.getElementById("closeChatbot");
    const inputField = document.getElementById("chatbotInput");
    const sendBtn = document.getElementById("sendChatbotMessage");
    const messagesContainer = document.getElementById("chatbotMessages");
    const suggestionBtns = document.querySelectorAll(".suggestion_btn");
    const suggestionsContainer = document.getElementById("chatbotSuggestions");

    // 1. Abrir e Fechar o Chatbot
    if (chatIcon) {
        chatIcon.addEventListener("click", () => {
            chatbotDiv.classList.add("active");
            // Adiciona mensagem de boas-vindas se for a primeira vez
            if (messagesContainer.children.length === 0) {
                addMessageToUI("Olá! Sou o Missing AI. Como posso ajudar você a usar a plataforma hoje?", "bot");
            }
        });
    }

    if (closeChatbot) {
        closeChatbot.addEventListener("click", () => {
            chatbotDiv.classList.remove("active");
        });
    }

    // 2. Função Principal de Enviar Mensagem para a OpenAI
    const sendMessage = async (text) => {
        if (!text || !text.trim()) return;

        // 2.1 Adiciona a mensagem do usuário na tela
        addMessageToUI(text, "user");
        inputField.value = ""; // Limpa o campo de texto
        
        // Esconde os botões de sugestão para limpar a tela
        if (suggestionsContainer) suggestionsContainer.classList.add("hidden");

        // 2.2 Mostra o indicador de "A processar..."
        const loadingId = addMessageToUI("A processar...", "bot", true);

        try {
            // Chamada à API da OpenAI
            const response = await fetch("https://api.openai.com/v1/chat/completions", {
                method: "POST",
                headers: {
                    "Content-Type": "application/json",
                    "Authorization": `Bearer ${OPENAI_API_KEY}`
                },
                body: JSON.stringify({
                    model: "gpt-3.5-turbo", // Versão rápida e barata
                    messages:[
                        { 
                            // Instruções para a IA agir como assistente da MissingAO
                            role: "system", 
                            content: `Você é o "Missing AI", assistente virtual da plataforma angolana "MissingAO". 
                            O objetivo do site é ajudar a relatar e encontrar pessoas desaparecidas em Angola. 
                            Responda de forma empática, curta e direta, usando português de Angola.
                            Se perguntarem como relatar, diga para clicar no botão "Relatar desaparecimento" no topo do site e preencher os dados.
                            Se perguntarem sobre aprovação, diga que o caso passa por um Administrador antes de aparecer no mapa.` 
                        },
                        { role: "user", content: text }
                    ],
                    temperature: 0.7
                })
            });

            const data = await response.json();
            
            // Remove o texto "A processar..."
            removeMessageFromUI(loadingId); 

            if (data.choices && data.choices[0]) {
                const botResponse = data.choices[0].message.content;
                addMessageToUI(botResponse, "bot");
            } else if (data.error) {
                console.error("Erro da OpenAI:", data.error);
                addMessageToUI("Desculpe, houve um erro ao conectar com o meu cérebro (Erro de API). Verifique a chave.", "bot");
            }
        } catch (error) {
            console.error("Erro de requisição:", error);
            removeMessageFromUI(loadingId);
            addMessageToUI("Sem conexão à internet ou a API falhou. Tente novamente mais tarde.", "bot");
        }
    };

    // 3. Eventos de Clique e Teclado
    sendBtn?.addEventListener("click", () => sendMessage(inputField.value));
    
    inputField?.addEventListener("keypress", (e) => {
        if (e.key === "Enter") sendMessage(inputField.value);
    });

    suggestionBtns.forEach(btn => {
        btn.addEventListener("click", () => {
            const pergunta = btn.getAttribute("data-suggestion");
            sendMessage(pergunta);
        });
    });

    // --- FUNÇÕES AUXILIARES DE INTERFACE ---
    function addMessageToUI(text, sender, isLoading = false) {
        const msgDiv = document.createElement("div");
        msgDiv.className = `chat_message message_${sender}`;
        
        const id = "msg-" + Date.now();
        msgDiv.id = id;
        
        // Pega a hora (Ex: 14:30)
        const time = new Date().toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });

        msgDiv.innerHTML = `
            <div class="message_text" ${isLoading ? 'style="color: #888; font-style: italic;"' : ''}>${text}</div>
            <div class="message_time">${time}</div>
        `;
        
        messagesContainer.appendChild(msgDiv);
        messagesContainer.scrollTop = messagesContainer.scrollHeight; // Desce a tela
        
        return id; // Retorna o ID para podermos apagar depois (usado no loading)
    }

    function removeMessageFromUI(id) {
        const el = document.getElementById(id);
        if (el) el.remove();
    }
});