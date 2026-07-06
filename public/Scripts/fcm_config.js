// Scripts/fcm_config.js
//
// Credenciais da conta de serviço do Firebase, usadas para assinar os
// pedidos de envio de notificações push (FCM) directamente do browser.
//
// COMO OBTER OS VALORES:
//   1. Firebase Console → ⚙️ Definições do projeto → separador
//      "Contas de serviço"
//   2. Botão "Gerar nova chave privada" → confirma → descarrega um
//      ficheiro .json
//   3. Abre esse ficheiro. Tem esta forma:
//        {
//          "type": "service_account",
//          "project_id": "missingao-88704",
//          "private_key_id": "...",
//          "private_key": "-----BEGIN PRIVATE KEY-----\n...\n-----END PRIVATE KEY-----\n",
//          "client_email": "firebase-adminsdk-xxxxx@missingao-88704.iam.gserviceaccount.com",
//          ...
//        }
//   4. Copia "client_email" para FCM_CLIENT_EMAIL abaixo.
//   5. Copia o conteúdo de "private_key" para FCM_PRIVATE_KEY abaixo —
//      podes colar tal como está no JSON (com os "\n" literais) ou com
//      quebras de linha reais, o fcm_push.js trata das duas formas.
//
// LEMBRA-TE: este ficheiro fica visível para qualquer pessoa que abra o
// "Ver código-fonte" da página (foi a tua escolha manter assim por
// agora). Não o partilhes nem o publiques num repositório público sem
// teres a noção clara de que isso equivale a dar a qualquer pessoa
// acesso de administrador ao teu projecto Firebase inteiro.

export const FCM_CLIENT_EMAIL = "COLOCA_AQUI_O_client_email_DO_JSON";

export const FCM_PRIVATE_KEY = `-----BEGIN PRIVATE KEY-----
COLOCA_AQUI_O_CONTEUDO_COMPLETO_DO_private_key_DO_JSON
-----END PRIVATE KEY-----`;

// Já confirmado noutros ficheiros do projecto (firebase.js) — mantém
// assim a menos que o projectId do teu Firebase seja diferente.
export const FIREBASE_PROJECT_ID = "missingao-88704";