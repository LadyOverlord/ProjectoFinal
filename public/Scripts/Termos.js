// Scripts/termos.js
// ─────────────────────────────────────────────────────────────────────────────
// Equivalente web do terms_acceptance_page.dart do mobile — mas em vez de
// uma página nova, é um modal bloqueante injectado na página actual,
// reaproveitando o mesmo padrão já usado em alerts.js / mostrarModalVerificacao
// (auth.js). Evita depender de navigateToTarget(), que já mostrou ter
// fragilidade real com a estrutura de pastas do alojamento.
//
// Uso:
//   import { versaoTermosActual, mostrarGateTermos } from "./termos.js";
//   if (userData.termosVersao !== versaoTermosActual) {
//     mostrarGateTermos(db, uid, () => { ...continuar normalmente... });
//   }
//
// IMPORTANTE — NÃO JURÍDICO: o texto abaixo é um rascunho estrutural,
// espelha o mesmo conteúdo já usado no mobile, mas TEM DE SER revisto por
// um advogado antes de publicar, dado o enquadramento da Lei n.º 22/11
// (Protecção de Dados Pessoais) em Angola.
// ─────────────────────────────────────────────────────────────────────────────

import {
  doc,
  setDoc,
} from "https://www.gstatic.com/firebasejs/12.8.0/firebase-firestore.js";

// Suba esta constante sempre que o texto mudar de forma substancial —
// todos os utilizadores, mesmo os que já tinham aceitado uma versão
// anterior, voltam automaticamente a ver o gate na próxima carga da página.
export const versaoTermosActual = "v1";

export const textoTermos = `
<h4 style="margin-bottom:10px;">TERMOS E CONDIÇÕES DE UTILIZAÇÃO — MISSING AO</h4>
<p style="color:#999;font-size:11px;margin-bottom:16px;">[RASCUNHO — por rever por um advogado antes de publicar]</p>

<p><strong>1. OBJECTO</strong><br>
A Missing AO é uma plataforma comunitária angolana que ajuda famílias a
localizar pessoas desaparecidas, permitindo a submissão, partilha e
comentário de casos de desaparecimento.</p>

<p><strong>2. RESPONSABILIDADE PELA INFORMAÇÃO SUBMETIDA</strong><br>
Ao relatar um caso de desaparecimento, o utilizador declara que a
informação submetida (nome, idade, fotografia, localização e demais dados
da pessoa desaparecida) é verdadeira, na medida do seu conhecimento, e que
tem motivo legítimo para a submeter. Informação comprovadamente falsa está
sujeita a remoção e penalização da conta, nos termos da secção 5.</p>

<p><strong>3. TRATAMENTO DE DADOS PESSOAIS</strong><br>
Os dados pessoais recolhidos — do utilizador e da pessoa reportada como
desaparecida — são tratados nos termos da Lei n.º 22/11, de 17 de Junho
(Lei da Protecção de Dados Pessoais). Isto inclui dados de conta (nome,
email, telefone, província e município), dados de localização (GPS,
quando autorizado) e dados de casos (informação sobre a pessoa
desaparecida, incluindo fotografia). Os dados de casos aprovados são
publicados no feed e mapa públicos da aplicação.</p>

<p><strong>4. NOTIFICAÇÕES</strong><br>
Ao registar-se, o utilizador consente em receber notificações por email
relacionadas com: alertas de casos na sua região, respostas a comentários,
e comunicações sobre o estado da sua conta.</p>

<p><strong>5. DIRECTRIZES DA COMUNIDADE E TRUST SCORE</strong><br>
A conta de cada utilizador tem associado um sistema de pontuação de
confiança ("Trust Score"), reduzido em caso de publicação de casos falsos
ou desmentidos, comentários ofensivos ou removidos, ou comportamento
abusivo. Caso o Trust Score chegue a zero, a conta é automaticamente
suspensa, com possibilidade de recurso junto do suporte.</p>

<p><strong>6. DIREITOS DO TITULAR DOS DADOS</strong><br>
Nos termos da Lei n.º 22/11, o utilizador tem direito a aceder, rectificar
ou solicitar a eliminação dos seus dados pessoais, através dos canais de
suporte disponíveis na aplicação.</p>

<p><strong>7. ALTERAÇÕES A ESTES TERMOS</strong><br>
Estes termos podem ser actualizados. Alterações substanciais requerem
nova aceitação explícita antes de continuar a usar a aplicação.</p>
`;

let _gateAberto = false;

// NOVO: versão só de leitura, sem checkbox nem gravação — para o link
// "Termos" no rodapé do index.html, acessível a qualquer pessoa (mesmo
// convidados), só para consulta.
export function mostrarTermosLeitura() {
  const overlay = document.createElement("div");
  overlay.id = "termos-leitura-overlay";
  overlay.style.cssText =
    "position:fixed;inset:0;z-index:20000;display:flex;align-items:center;justify-content:center;background:rgba(0,0,0,0.55);padding:16px;";

  overlay.innerHTML = `
    <div style="background:#fff;border-radius:16px;max-width:560px;width:100%;max-height:88vh;display:flex;flex-direction:column;box-shadow:0 20px 60px rgba(0,0,0,0.25);font-family:var(--font-base,'Quicksand',sans-serif);overflow:hidden;">
      <div style="padding:18px 22px;border-bottom:1px solid #eee;display:flex;align-items:center;justify-content:space-between;">
        <h3 style="margin:0;font-size:16px;color:#222;">Termos e Condições</h3>
        <button id="termos-leitura-fechar" style="background:none;border:none;font-size:20px;cursor:pointer;color:#888;line-height:1;">&times;</button>
      </div>
      <div style="padding:20px 22px;overflow-y:auto;flex:1;font-size:13px;line-height:1.6;color:#333;">
        ${textoTermos}
      </div>
    </div>
  `;

  document.body.appendChild(overlay);

  const fechar = () => overlay.remove();
  overlay.querySelector("#termos-leitura-fechar").addEventListener("click", fechar);
  // Fecha também ao clicar fora do cartão (no fundo escurecido)
  overlay.addEventListener("click", (e) => {
    if (e.target === overlay) fechar();
  });
}

/**
 * Mostra o modal bloqueante de aceitação de termos. Exige scroll até ao
 * fim do texto + checkbox marcada antes de activar o botão — mesma regra
 * usada no gate do mobile.
 *
 * @param {*} db instância do Firestore (já inicializada em firebase.js)
 * @param {string} uid utilizador autenticado
 * @param {() => void} onAceite chamado depois de gravar a aceitação com sucesso
 */
export function mostrarGateTermos(db, uid, onAceite) {
  if (_gateAberto) return; // evita duplicar o modal se o listener disparar várias vezes
  _gateAberto = true;

  const overlay = document.createElement("div");
  overlay.id = "termos-gate-overlay";
  overlay.style.cssText =
    "position:fixed;inset:0;z-index:20000;display:flex;align-items:center;justify-content:center;background:rgba(0,0,0,0.55);padding:16px;";

  overlay.innerHTML = `
    <div style="background:#fff;border-radius:16px;max-width:560px;width:100%;max-height:88vh;display:flex;flex-direction:column;box-shadow:0 20px 60px rgba(0,0,0,0.25);font-family:var(--font-base,'Quicksand',sans-serif);overflow:hidden;">
      <div style="padding:18px 22px;border-bottom:1px solid #eee;">
        <h3 style="margin:0;font-size:16px;color:#222;">Termos e Condições</h3>
      </div>
      <div id="termos-gate-scroll" style="padding:20px 22px;overflow-y:auto;flex:1;font-size:13px;line-height:1.6;color:#333;">
        ${textoTermos}
      </div>
      <div style="padding:16px 22px;border-top:1px solid #eee;background:#fafafa;">
        <p id="termos-gate-aviso" style="color:#d97706;font-size:12px;margin:0 0 10px;">
          Role até ao fim do texto para poder continuar.
        </p>
        <label style="display:flex;align-items:flex-start;gap:8px;font-size:12px;color:#555;margin-bottom:12px;cursor:pointer;">
          <input type="checkbox" id="termos-gate-checkbox" disabled style="margin-top:2px;" />
          Li e aceito os Termos e Condições e a Política de Privacidade.
        </label>
        <button id="termos-gate-btn" disabled
          style="width:100%;padding:12px;border:none;border-radius:8px;background:#9aa3ab;color:#fff;font-weight:700;font-size:14px;cursor:not-allowed;transition:background 0.15s;">
          Aceitar e continuar
        </button>
      </div>
    </div>
  `;

  document.body.appendChild(overlay);

  const scrollEl = overlay.querySelector("#termos-gate-scroll");
  const checkbox = overlay.querySelector("#termos-gate-checkbox");
  const aviso = overlay.querySelector("#termos-gate-aviso");
  const btn = overlay.querySelector("#termos-gate-btn");

  function atualizarBotao() {
    const pronto = !checkbox.disabled && checkbox.checked;
    btn.disabled = !pronto;
    btn.style.background = pronto ? "#0c7ab5" : "#9aa3ab";
    btn.style.cursor = pronto ? "pointer" : "not-allowed";
  }

  scrollEl.addEventListener("scroll", () => {
    const chegouAoFim =
      scrollEl.scrollTop + scrollEl.clientHeight >= scrollEl.scrollHeight - 24;
    if (chegouAoFim && checkbox.disabled) {
      checkbox.disabled = false;
      aviso.style.display = "none";
      atualizarBotao();
    }
  });

  // Caso o texto caiba todo sem precisar de scroll, liberta logo.
  if (scrollEl.scrollHeight <= scrollEl.clientHeight + 4) {
    checkbox.disabled = false;
    aviso.style.display = "none";
  }

  checkbox.addEventListener("change", atualizarBotao);

  btn.addEventListener("click", async () => {
    if (btn.disabled) return;
    btn.disabled = true;
    btn.textContent = "A guardar...";
    try {
      await setDoc(
        doc(db, "users", uid),
        {
          termosAceitos: true,
          termosAceitosEm: new Date(),
          termosVersao: versaoTermosActual,
        },
        { merge: true },
      );
      overlay.remove();
      _gateAberto = false;
      if (typeof onAceite === "function") onAceite();
    } catch (err) {
      btn.disabled = false;
      btn.textContent = "Aceitar e continuar";
      alert("Erro ao guardar: " + err.message);
    }
  });
}

// Expõe as funções globalmente para uso directo no HTML (onclick=)
// sem depender de resolução de módulos ES — resolve o problema do
// listener do footer-termos não disparar por questões de import.
window.mostrarTermosLeitura = mostrarTermosLeitura;
window.mostrarGateTermos    = mostrarGateTermos;