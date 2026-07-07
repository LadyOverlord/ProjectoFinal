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

export const FCM_CLIENT_EMAIL = "firebase-adminsdk-fbsvc@missingao-88704.iam.gserviceaccount.com";

export const FCM_PRIVATE_KEY = `-----BEGIN PRIVATE KEY-----\nMIIEvQIBADANBgkqhkiG9w0BAQEFAASCBKcwggSjAgEAAoIBAQC1Q+KNetQyCc1I\n+aT8XkTtheB38Ysu9Km8021cFna52HRg1fBBvSoWSBd5KQCUPrF/BY61dhEjCgHr\n6gRCvZgU2mbqmFVANVuIVCL1qGJyStxQ8GgcMaQ27zWN6ElVIjuK2OdLkyLK5LGg\nX1Iqr4XYpbpujq2wYpkzt4GMHwoPqYptqD7LEvXlTDozdyFhYaYNKeqsX7EkaN0M\nMdPJdB7X6FmCy4+pSe+LJMi07lQxI6A8vqKLHnXcE1CbikAnBvks+2tHnahhBN2c\nEA+HcH9se4MnDh3ZkNRP5OBZKZyclNNf9IVWpvbV6u2erPKGopPUovqc78BnK9xI\nJ8aq80a/AgMBAAECggEAR3HNTuRV1K8mWZgEHnBtjI0S71Ol/0jxyfovhXdZLmER\nZcWNH+wWNZgOoHO3xbZ8MUuYdw9lK8FbBohDS6b81WNL4zVNjLQ7Mp2u9dJ7kv7M\nnZ5T+qDaT8iy/A7NMKAAhfZ+G7yPnxbKqCJJ+YcbI0wXElJsRTRnnAm9JuRpC8im\nQ+14n0mizUh6yaSiZOtugst02vgnQvHdmDQnn6bHiNSwrR/QmOPYHrUM5oMb6OE4\nrOmT45gh8t30+qpOsRTAiBjZ0hcO1ZxoJkVpyx7sH/n7oCoIZlq+NXInn3ci6h4L\nVMhDw2Bt1+3ZLpp6EPAWeND2SOVxiQbI+BLWQRjGaQKBgQDiB3tCF4n0foA2xoKj\ncMEg5hkjvfVHzBEVzTTQgQJ+pGOwTH3Psjt5Qz9mVqqwYnBORskgisoZoTZ4qeHp\nY5SivE3iMDfVsmq4hmDuVSYQXVTww1XIYAriXlbySarT+jqu88KmFc7RFByvm7FF\nQfPtXXgYmnNOezOc/WWzSmbofQKBgQDNTOV/KBS5TY1J5gItluX/tuNZuPU8jF9D\n7iZ4cBJ+CxnFOyzCpNL4ATjYVo2/OF2eMQsYUrnPNl/GDJoBM564lgbrdt4UH/T1\nMzO+DkI8P6lvWqzSdodgZSC+lS5sz2p4b6/1efJ3wOqvOb4OYLzO833IpmPNlHnb\nlUmcA84M6wKBgBF9QLVRevQ3IZabb5pT7C2ugD16wlLm4F+OfEqx4M6Jy8jlckqy\n4NU2Nd6mUBjL1SLJaWCiPJcVGVDm3Dsh4GtjJKee0YMwhf93LmLipcpYXm0uwCF8\nBPuVDyc6OgSi9Q16gRI218TnyHxyEJpqSwSP2e4VbVyiPdEk7kycMjBFAoGBALbl\nZ5sViQjgVxvbplsZEMP0GazoAsozP/eTpYAsT70shIPaSPEKx8wbwpmw2kzdmUGB\n7aF4qYI5ra8RsO2bIC7PsVB6MDR7l84OFG2f5FAqYvcKL+a7o7Uzwq0m2Bol2nN7\nBKZLQsB/BFSgu3mxouM3tvpXiZgvSzRdVhuApEOLAoGAPo0G+5KNlOJq+/BLcZJY\n7xmJwM4c5ccjat423d3ZN5It+jtPQ1Y3+cAMbVSUdYUkbXhGygBiGpj74G4oCQJo\nrI6KE8Y1bT8qONNMuJA6va9ea7Q9hRofPHiIEIN64ndDmZ6haze+BAEWL3myipCY\ntT9ZR2Qd/YUEPtfz/2b0LfI=\n-----END PRIVATE KEY-----\n`;

// Já confirmado noutros ficheiros do projecto (firebase.js) — mantém
// assim a menos que o projectId do teu Firebase seja diferente.
export const FIREBASE_PROJECT_ID = "missingao-88704";