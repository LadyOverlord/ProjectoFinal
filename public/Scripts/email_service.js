// email_service.js
// Notificações de estado da conta (suspensão / reactivação) via EmailJS.
//
// CORRIGIDO (2ª ronda) — o service ID estava certo, mas faltavam 2 coisas:
//
//  1. Public Key explícita: o admin.html faz emailjs.init("R5Femg5uCIC-Lh0RW"),
//     mas essa é a conta usada para os alertas de casos (service_8fq9usa).
//     O template de estado de conta (service_wn5nnwe / template_xgh395i)
//     pertence a outra conta EmailJS, com outra Public Key
//     (kIGZVu1cVW2kfPAfm — confirmada pelos valores já usados no mobile,
//     em config.dart). Sem passar esta key explicitamente, o envio usava
//     sempre a key errada (a global) e falhava.
//
//  2. Nomes dos parâmetros: o template "Contact Us" pré-construído do
//     EmailJS espera as variáveis email/name/title/message (é isso que
//     o "To Email" das Settings do template usa: {{email}}). O código
//     anterior enviava to_email/to_name/assunto/mensagem — nomes que
//     não batiam com nada dentro do template, por isso o {{email}}
//     ficava vazio e o EmailJS não tinha para onde enviar.

import { db } from "./firebase.js";
import {
  doc,
  getDoc,
} from "https://www.gstatic.com/firebasejs/12.8.0/firebase-firestore.js";

const TEMPLATE_TRUST_STATUS = "template_xgh395i";
const SERVICE_ID = "service_wn5nnwe";
// Confirmado a partir dos valores já usados no mobile (config.dart:
// emailJsPublicKeyContaStatus). Esta conta é diferente da usada para os
// alertas de caso aprovado (essa usa a key do emailjs.init() no admin.html).
const PUBLIC_KEY = "kIGZVu1cVW2kfPAfm";

export async function enviarEmailTrustStatus(uid, ativo, detalhe) {
  try {
    const userSnap = await getDoc(doc(db, "users", uid));
    if (!userSnap.exists()) return;

    const userData = userSnap.data();
    const nome = userData.nome ?? "Utilizador";
    const email = userData.email;
    if (!email) return;

    const assunto = ativo ? "✅ Conta Reactivada" : "🚫 Conta Suspensa";
    const mensagem = ativo
      ? `A sua conta foi reactivada com Trust Score de ${detalhe}. Já pode voltar a usar a plataforma normalmente.`
      : `A sua conta foi suspensa. Motivo: ${detalhe}. Contacte o suporte a partir da aplicação para pedir revisão.`;

    if (typeof emailjs === "undefined") {
      console.warn(
        "[email_service] objecto global 'emailjs' não encontrado. " +
          "Confirma que a página onde isto corre inclui o <script> do " +
          "EmailJS (https://cdn.jsdelivr.net/npm/@emailjs/browser@3/dist/email.min.js).",
      );
      return;
    }

    // NOVO — diagnóstico: confirma no console (F12) que o "email" aqui é
    // sempre o do utilizador certo, diferente a cada chamada. Se
    // aparecerem aqui emails diferentes mas na caixa de entrada chegar
    // sempre ao mesmo sítio, o problema está garantidamente no template
    // do EmailJS (campo "To Email"), não neste ficheiro.
    console.log(`[email_service] A enviar para: ${email} (uid: ${uid})`);

    // Envia as duas variantes de nomes de variável — o template tem uma
    // mistura de inglês (usado no Assunto/De Nome, herdados do "Contact
    // Us" original) e português (usado dentro do balão de mensagem,
    // {{nome}}/{{tempo}}/{{mensagem}}, da tua edição). Enviar ambas
    // evita teres de ir mexer no conteúdo do template outra vez.
    await emailjs.send(
      SERVICE_ID,
      TEMPLATE_TRUST_STATUS,
      {
        email,
        name: nome,
        nome: nome,
        title: assunto,
        message: mensagem,
        mensagem: mensagem,
        tempo: new Date().toLocaleString("pt-AO"),
        time: new Date().toISOString(),
      },
      PUBLIC_KEY,
    );
  } catch (err) {
    console.error("Erro ao enviar email de Trust Status:", err);
  }
}