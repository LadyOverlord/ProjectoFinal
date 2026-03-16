// === AVISO DE SEGURANÇA ===
// PARA A PRÉ-DEFESA: Coloque a sua chave do Google Gemini aqui.
// APAGUE A CHAVE NO GOOGLE AI STUDIO ASSIM QUE A APRESENTAÇÃO TERMINAR!
const GEMINI_API_KEY = "AIzaSyApuOtb3jfn0doaKPP3SEy7g-0NX2hWwe0"; 

document.addEventListener("DOMContentLoaded", () => {
    // Referências aos elementos do HTML
    const chatIcon = document.getElementById("chat_bot"); 
    const chatbotDiv = document.getElementById("chatbotDiv");
    const closeChatbot = document.getElementById("closeChatbot");
    const inputField = document.getElementById("chatbotInput");
    const sendBtn = document.getElementById("sendChatbotMessage");
    const messagesContainer = document.getElementById("chatbotMessages");
    const suggestionBtns = document.querySelectorAll(".suggestion_btn");
    const suggestionsContainer = document.getElementById("chatbotSuggestions");

    // Instrução do Sistema (Personalidade do Bot)
    const systemPrompt = `Você é o "Missing AI", um assistente virtual empático e direto da plataforma angolana "MissingAO". 
    O objetivo da plataforma é ajudar a relatar e encontrar pessoas desaparecidas em Angola. 
    Instruções do site: 
    - Para relatar um caso, o usuário deve clicar no botão 'Relatar desaparecimento' na barra superior, preencher a aba 'Pessoa', 'Local' e 'Detalhes'. O caso vai para aprovação de um Administrador.
    - Para ver os casos, o usuário pode olhar o feed principal ou usar os filtros do lado esquerdo.
    Mantenha as respostas curtas (máximo 2 parágrafos), em português de Angola, e mostre empatia.`;

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

    // 2. Função Principal de Enviar Mensagem para o Gemini (ATUALIZADA)
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
            // MUDANÇA 1: O nome do modelo correto e mais estável é 'gemini-1.5-flash-latest'
            // Se mesmo assim der erro, mude a palavra 'gemini-1.5-flash-latest' para 'gemini-pro'
            const url = `https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=${GEMINI_API_KEY}`;
            
            const response = await fetch(url, {
                method: "POST",
                headers: {
                    "Content-Type": "application/json"
                },
                // MUDANÇA 2: Estrutura 100% à prova de falhas (juntamos a regra com a pergunta)
                body: JSON.stringify({
                    contents: [
                        {
                            role: "user",
                            parts:[
                                { text: systemPrompt + "\n\n--- AGORA RESPONDA A ESTA PERGUNTA DO USUÁRIO ---\n\n" + text }
                            ]
                        }
                    ],
                    generationConfig: {
                        temperature: 0.7
                    }
                })
            });

            const data = await response.json();
            
            // Remove o texto "A processar..."
            removeMessageFromUI(loadingId); 

            if (data.candidates && data.candidates.length > 0 && data.candidates[0].content) {
                const botResponse = data.candidates[0].content.parts[0].text;
                addMessageToUI(botResponse, "bot");
            } else if (data.error) {
                console.error("Erro da API Gemini:", data.error);
                addMessageToUI("ERRO DO GOOGLE: " + data.error.message, "bot");
            } else {
                addMessageToUI("Desculpe, não consegui processar a resposta.", "bot");
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

        // Se a mensagem contiver quebras de linha, vamos trocar \n por <br> para ficar bonito
        const formattedText = text.replace(/\n/g, "<br>");

        msgDiv.innerHTML = `
            <div class="message_text" ${isLoading ? 'style="color: #888; font-style: italic;"' : ''}>${formattedText}</div>
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