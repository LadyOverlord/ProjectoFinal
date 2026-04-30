const parte1 = "AIzaSyDB3R7J66";
const parte2 = "7uy-pGvWWCE";
const parte3 = "WJ8EFJDSBw072c";

// Montar chave API
const GEMINI_API_KEY = parte1 + parte2 + parte3;

document.addEventListener("DOMContentLoaded", () => {
  // Elementos HTML
  // Abrir chat
  const chatOpenElements = Array.from(
    document.querySelectorAll("#chatbot, #chat_bot"),
  );
  const chatbotDiv = document.getElementById("chatbotDiv");
  const closeChatbot = document.getElementById("closeChatbot");
  const inputField = document.getElementById("chatbotInput");
  const sendBtn = document.getElementById("sendChatbotMessage");
  const messagesContainer = document.getElementById("chatbotMessages");
  const suggestionBtns = document.querySelectorAll(".suggestion_btn");
  const suggestionsContainer = document.getElementById("chatbotSuggestions");

  // Prompt do sistema
  const systemPrompt = `Você é o "Missing AI", um assistente virtual empático e direto da plataforma angolana "MissingAO". 
    O objetivo da plataforma é ajudar a relatar e encontrar pessoas desaparecidas em Angola. 
    Instruções do site: 
    - Para relatar um caso, o usuário deve clicar no botão 'Relatar desaparecimento' na barra superior, preencher a aba 'Pessoa', 'Local' e 'Detalhes'. O caso vai para aprovação de um Administrador.
    - Para ver os casos, o usuário pode olhar o feed principal ou usar os filtros do lado esquerdo.
    Mantenha as respostas curtas (máximo 2 parágrafos), em português de Angola, e mostre empatia.`;

  // Abrir/Fechar
  if (chatOpenElements.length > 0) {
    chatOpenElements.forEach((el) => {
      if (!el) return;
      el.addEventListener("click", () => {
        if (!chatbotDiv) return;
        chatbotDiv.classList.add("active");
        // Boas-vindas
        if (messagesContainer && messagesContainer.children.length === 0) {
          addMessageToUI(
            "Olá! Sou o Missing AI. Como posso ajudar você a usar a plataforma hoje?",
            "bot",
          );
        }
      });
    });
  }

  if (closeChatbot) {
    closeChatbot.addEventListener("click", () => {
      chatbotDiv.classList.remove("active");
    });
  }

  // Enviar via API
  const sendMessage = async (text) => {
    if (!text || !text.trim()) return;

    // Mensagem do usuário
    addMessageToUI(text, "user");
    inputField.value = ""; // Limpar

    // Ocultar sugestões
    if (suggestionsContainer) suggestionsContainer.classList.add("hidden");

    // Mostrar loading
    const loadingId = addMessageToUI("A processar...", "bot", true);

    try {
      // Modelo sugerido
      // Alternativa: gemini-pro
      const url = `https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=${GEMINI_API_KEY}`;

      const response = await fetch(url, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
        },
        // Payload combinado
        body: JSON.stringify({
          contents: [
            {
              role: "user",
              parts: [
                {
                  text:
                    systemPrompt +
                    "\n\n--- AGORA RESPONDA A ESTA PERGUNTA DO USUÁRIO ---\n\n" +
                    text,
                },
              ],
            },
          ],
          generationConfig: {
            temperature: 0.7,
          },
        }),
      });

      const data = await response.json();

      // Remover loading
      removeMessageFromUI(loadingId);

      if (
        data.candidates &&
        data.candidates.length > 0 &&
        data.candidates[0].content
      ) {
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
      addMessageToUI(
        "Sem conexão à internet ou a API falhou. Tente novamente mais tarde.",
        "bot",
      );
    }
  };
  // Eventos
  sendBtn?.addEventListener("click", () => sendMessage(inputField.value));

  inputField?.addEventListener("keypress", (e) => {
    if (e.key === "Enter") sendMessage(inputField.value);
  });

  suggestionBtns.forEach((btn) => {
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

    // Hora
    const time = new Date().toLocaleTimeString([], {
      hour: "2-digit",
      minute: "2-digit",
    });

    // Formatar quebras de linha
    const formattedText = text.replace(/\n/g, "<br>");

    msgDiv.innerHTML = `
            <div class="message_text" ${isLoading ? 'style="color: #888; font-style: italic;"' : ""}>${formattedText}</div>
            <div class="message_time">${time}</div>
        `;

    messagesContainer.appendChild(msgDiv);
    messagesContainer.scrollTop = messagesContainer.scrollHeight; // Rolagem

    return id; // ID da mensagem
  }

  function removeMessageFromUI(id) {
    const el = document.getElementById(id);
    if (el) el.remove();
  }
});
