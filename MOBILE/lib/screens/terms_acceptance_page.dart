// lib/screens/terms_acceptance_page.dart
// ─────────────────────────────────────────────────────────────────────────────
// Ecrã de aceitação de Termos e Condições / Política de Privacidade.
//
// Aparece em dois contextos:
//   1. Gate bloqueante, mostrado pelo AuthCheck sempre que
//      users/{uid}.termosVersao != kTermosVersaoActual (cobre tanto
//      utilizadores novos como já existentes, e qualquer subida futura
//      de versão dos termos).
//   2. Chamado directamente a partir do RegisterPage, em modo leitura,
//      para quem quer ler antes de marcar a checkbox no registo (nesse
//      caso não escreve nada no Firestore — a conta ainda não existe).
//
// IMPORTANTE — NÃO JURÍDICO: o texto abaixo é um placeholder estrutural,
// cobre os pontos que foram discutidos (consentimento de dados, dados de
// terceiros submetidos pelo relator, diretrizes da comunidade, uso de
// dados) mas TEM DE SER revisto por um advogado antes de publicar,
// especialmente dado o enquadramento da Lei n.º 22/11 (Protecção de
// Dados Pessoais) em Angola.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

// Suba esta constante sempre que o texto dos termos mudar de forma
// substancial — todos os utilizadores, mesmo os que já tinham aceitado
// uma versão anterior, voltam automaticamente a ver o gate.
const String kTermosVersaoActual = 'v1';

const String kTermosTexto = '''
TERMOS E CONDIÇÕES DE UTILIZAÇÃO — MISSING AO

1. OBJECTO
A Missing AO é uma plataforma comunitária angolana que ajuda famílias a
localizar pessoas desaparecidas, permitindo a submissão, partilha e
comentário de casos de desaparecimento.

2. RESPONSABILIDADE PELA INFORMAÇÃO SUBMETIDA
Ao relatar um caso de desaparecimento, o utilizador declara que a
informação submetida (nome, idade, fotografia, localização e demais
dados da pessoa desaparecida) é verdadeira, na medida do seu
conhecimento, e que tem motivo legítimo para a submeter. Informação
comprovadamente falsa está sujeita a remoção e penalização da conta,
nos termos da secção 5.

3. TRATAMENTO DE DADOS PESSOAIS
Os dados pessoais recolhidos — do utilizador e da pessoa reportada como
desaparecida — são tratados nos termos da Lei n.º 22/11, de 17 de
Junho (Lei da Protecção de Dados Pessoais). Isto inclui:
  • Dados de conta: nome, email, telefone, província e município.
  • Dados de localização: GPS, quando autorizado pelo dispositivo.
  • Dados de casos: informação sobre a pessoa desaparecida, incluindo
    fotografia, submetida pelo utilizador que relata.
Os dados de casos aprovados são publicados no feed e mapa públicos da
aplicação, visíveis a todos os utilizadores.

4. NOTIFICAÇÕES
Ao registar-se, o utilizador consente em receber notificações push e/ou
por email relacionadas com: alertas de casos na sua região, respostas a
comentários, e comunicações sobre o estado da sua conta.

5. DIRECTRIZES DA COMUNIDADE E TRUST SCORE
A conta de cada utilizador tem associado um sistema de pontuação de
confiança ("Trust Score"), que pode ser reduzido em caso de:
  • Publicação de casos falsos ou comprovadamente desmentidos;
  • Comentários ofensivos, discriminatórios ou removidos por um
    administrador;
  • Comportamento abusivo para com outros utilizadores.
Caso o Trust Score chegue a zero, a conta é automaticamente suspensa,
com possibilidade de recurso junto do suporte através da própria
aplicação.

6. DIREITOS DO TITULAR DOS DADOS
Nos termos da Lei n.º 22/11, o utilizador tem direito a aceder,
rectificar ou solicitar a eliminação dos seus dados pessoais, através
dos canais de suporte disponíveis na aplicação.

7. ALTERAÇÕES A ESTES TERMOS
Estes termos podem ser actualizados. Alterações substanciais requerem
nova aceitação explícita antes de continuar a usar a aplicação.
''';

class TermsAcceptancePage extends StatefulWidget {
  /// Se null, o widget assume que está a correr como gate bloqueante
  /// (chamado pelo AuthCheck) e escreve directamente no Firestore ao
  /// aceitar. Se fornecido, chama este callback em vez de escrever —
  /// usado pelo RegisterPage, onde a conta ainda não existe.
  final VoidCallback? onAceitar;
  final bool somenteLeitura;

  const TermsAcceptancePage({super.key, this.onAceitar, this.somenteLeitura = false});

  @override
  State<TermsAcceptancePage> createState() => _TermsAcceptancePageState();
}

class _TermsAcceptancePageState extends State<TermsAcceptancePage> {
  final _scrollCtrl = ScrollController();
  bool _chegouAoFim = false;
  bool _marcouCheckbox = false;
  bool _salvando = false;

  @override
  void initState() {
    super.initState();
    // Em modo leitura (chamado a partir do registo) não exige scroll
    // nem checkbox — é só consulta.
    if (widget.somenteLeitura) {
      _chegouAoFim = true;
      _marcouCheckbox = true;
    } else {
      _scrollCtrl.addListener(_onScroll);
    }
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_chegouAoFim) return;
    final max = _scrollCtrl.position.maxScrollExtent;
    // Uma pequena margem (32px) evita que fique impossível de accionar
    // em ecrãs onde o conteúdo termina exactamente no limite visível.
    if (_scrollCtrl.position.pixels >= max - 32) {
      setState(() => _chegouAoFim = true);
    }
  }

  bool get _podeAceitar => _chegouAoFim && _marcouCheckbox && !_salvando;

  Future<void> _aceitar() async {
    if (!_podeAceitar) return;

    if (widget.onAceitar != null) {
      widget.onAceitar!();
      return;
    }

    setState(() => _salvando = true);
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      setState(() => _salvando = false);
      return;
    }
    try {
      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        'termosAceitos':   true,
        'termosAceitosEm': Timestamp.now(),
        'termosVersao':    kTermosVersaoActual,
      }, SetOptions(merge: true));
      // Não navega manualmente — o AuthCheck escuta este documento via
      // StreamBuilder e, assim que termosVersao corresponder à versão
      // actual, substitui automaticamente este ecrã pelo destino certo
      // (Home, Admin, ou SuspendedPage, conforme aplicável).
    } catch (e) {
      if (mounted) {
        setState(() => _salvando = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Erro ao guardar: $e'),
          backgroundColor: Colors.red,
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0F),
      appBar: AppBar(
        backgroundColor: const Color(0xFF141418),
        elevation: 0,
        title: const Text('Termos e Condições', style: TextStyle(color: Colors.white, fontSize: 16)),
        leading: widget.somenteLeitura
            ? IconButton(icon: const Icon(Icons.close_rounded, color: Colors.white), onPressed: () => Navigator.pop(context))
            : null,
        automaticallyImplyLeading: widget.somenteLeitura,
      ),
      body: Column(
        children: [
          Expanded(
            child: Scrollbar(
              controller: _scrollCtrl,
              thumbVisibility: true,
              child: SingleChildScrollView(
                controller: _scrollCtrl,
                padding: const EdgeInsets.all(20),
                child: Text(
                  kTermosTexto,
                  style: const TextStyle(color: Color(0xFFE4E4E7), fontSize: 13, height: 1.6),
                ),
              ),
            ),
          ),
          if (!widget.somenteLeitura)
            SafeArea(
              top: false,
              child: Container(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
                decoration: const BoxDecoration(
                  color: Color(0xFF141418),
                  border: Border(top: BorderSide(color: Color(0xFF2A2A33))),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (!_chegouAoFim)
                      const Padding(
                        padding: EdgeInsets.only(bottom: 8),
                        child: Text('Role até ao fim do texto para poder continuar.',
                          style: TextStyle(color: Color(0xFFF59E0B), fontSize: 12)),
                      ),
                    Row(
                      children: [
                        Checkbox(
                          value: _marcouCheckbox,
                          onChanged: _chegouAoFim ? (v) => setState(() => _marcouCheckbox = v ?? false) : null,
                          activeColor: const Color(0xFF4F7EFF),
                        ),
                        const Expanded(
                          child: Text('Li e aceito os Termos e Condições e a Política de Privacidade.',
                            style: TextStyle(color: Color(0xFFA1A1AA), fontSize: 12)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _podeAceitar ? _aceitar : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF4F7EFF),
                          disabledBackgroundColor: const Color(0xFF3F3F46),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: _salvando
                            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Text('Aceitar e continuar', style: TextStyle(fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}