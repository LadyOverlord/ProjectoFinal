// screens/register_page.dart
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart'; // ← NOVO: TapGestureRecognizer
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'home_page.dart';
import 'terms_acceptance_page.dart'; // ← NOVO
import '../models/user_mode.dart';

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  DateTime? _selectedDate;
  String? _selectedProvince;
  String? _selectedMunicipio;

  bool _isLoading = false;
  bool _aceitouTermos = false; // ← NOVO

  // ── Províncias de Angola ──────────────────────────────
  final List<String> _provinces = [
    'Luanda', 'Benguela', 'Huambo', 'Huíla', 'Cunene', 'Namibe', 'Moxico',
    'Cuando Cubango', 'Lunda Norte', 'Lunda Sul', 'Malanje', 'Uíge',
    'Zaire', 'Cabinda', 'Bié', 'Cuanza Norte', 'Cuanza Sul',
  ];

  // ── Municípios por província ──────────────────────────
  final Map<String, List<String>> _municipiosPorProvincia = {
    'Luanda': ['Belas', 'Cacuaco', 'Cazenga', 'Ícolo e Bengo', 'Luanda', 'Quilamba Quiaxi', 'Talatona', 'Viana'],
    'Benguela': ['Baía Farta', 'Balombo', 'Benguela', 'Bocoio', 'Caimbambo', 'Catumbela', 'Chongoroi', 'Cubal', 'Ganda', 'Lobito'],
    'Huambo': ['Bailundo', 'Catchiungo', 'Caála', 'Ecunha', 'Huambo', 'Londuimbali', 'Longonjo', 'Mungo', 'Tchicala-Tcholoanga', 'Tchindjenje', 'Ucuma'],
    'Huíla': ['Caconda', 'Caluquembe', 'Chibia', 'Chicomba', 'Chipindo', 'Cuvango', 'Humpata', 'Jamba', 'Lubango', 'Matala', 'Quilengues', 'Quipungo'],
    'Cunene': ['Cahama', 'Cuanhama', 'Curoca', 'Cuvelai', 'Namacunde', 'Ombadja'],
    'Namibe': ['Bibala', 'Camacuio', 'Moçâmedes', 'Tômbua', 'Virei'],
    'Moxico': ['Alto Zambeze', 'Bundas', 'Camanongue', 'Cameia', 'Léua', 'Luau', 'Luacano', 'Luchazes', 'Lumbala Nguimbo', 'Moxico'],
    'Cabinda': ['Belize', 'Buco-Zau', 'Cabinda', 'Cacongo'],
    'Bié': ['Andulo', 'Camacupa', 'Catabola', 'Chinguar', 'Chitembo', 'Cuemba', 'Cunhinga', 'Cuíto', 'Nharea'],
    'Cuanza Norte': ['Ambaca', 'Banga', 'Bolongongo', 'Cambambe', 'Cazengo', 'Golungo Alto', 'Gonguembo', 'Lucala', 'Quiculungo', 'Samba Cajú'],
    'Cuanza Sul': ['Amboim', 'Cassongue', 'Cela', 'Conda', 'Ebo', 'Libolo', 'Mussende', 'Porto Amboim', 'Quibala', 'Quilenda', 'Seles', 'Sumbe', 'Waku-Kungo'],
    'Cuando Cubango': ['Calai', 'Cuangar', 'Cuchi', 'Cuito Cuanavale', 'Dirico', 'Mavinga', 'Menongue', 'Nancova', 'Rivungo'],
    'Lunda Norte': ['Cambulo', 'Capenda-Camulemba', 'Caungula', 'Chitato', 'Cuango', 'Cuílo', 'Lubalo', 'Lucapa', 'Xá-Muteba'],
    'Lunda Sul': ['Cacolo', 'Dala', 'Muconda', 'Saurimo'],
    'Malanje': ['Cacuso', 'Calandula', 'Cambundi-Catembo', 'Cangandala', 'Caombo', 'Cuaba Nzoji', 'Cunda-Dia-Baze', 'Luquembo', 'Malanje', 'Marimba', 'Massango', 'Mucari', 'Quela', 'Quirima'],
    'Uíge': ['Alto Cauale', 'Ambuíla', 'Bembe', 'Buengas', 'Bungo', 'Damba', 'Maquela do Zombo', 'Mucaba', 'Negage', 'Puri', 'Quimbele', 'Quitexe', 'Sanza Pombo', 'Songo', 'Uíge'],
    'Zaire': ['Cuimba', 'Mabanza Congo', 'Nóqui', 'Nezeto', 'Soyo', 'Tomboco'],
  };

  // ── Selecionar data de nascimento ─────────────────────
  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now().subtract(const Duration(days: 365 * 18)),
      firstDate: DateTime(1900),
      lastDate: DateTime.now().subtract(const Duration(days: 365 * 16)), // mínimo 16 anos
      helpText: 'Selecione a data de nascimento',
      cancelText: 'Cancelar',
      confirmText: 'Confirmar',
    );

    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
      });
    }
  }

  // ── Cadastrar ─────────────────────────────────────────
  Future<void> _register() async {
    // Validações
    final nome = _nameController.text.trim();
    final email = _emailController.text.trim();
    final telefone = _phoneController.text.trim();
    final senha = _passwordController.text;
    final confirmarSenha = _confirmPasswordController.text;

    if (nome.isEmpty || email.isEmpty || telefone.isEmpty || senha.isEmpty || confirmarSenha.isEmpty) {
      _showError('Por favor, preencha todos os campos obrigatórios.');
      return;
    }

    if (!email.contains('@') || !email.contains('.')) {
      _showError('Por favor, digite um email válido.');
      return;
    }

    if (_selectedDate == null) {
      _showError('Por favor, selecione a data de nascimento.');
      return;
    }

    if (_selectedProvince == null) {
      _showError('Por favor, selecione a província.');
      return;
    }

    if (_selectedMunicipio == null) {
      _showError('Por favor, selecione o município.');
      return;
    }

    // Verificar idade mínima (16 anos)
    final idade = DateTime.now().difference(_selectedDate!).inDays ~/ 365;
    if (idade < 16) {
      _showError('É necessário ter pelo menos 16 anos para se cadastrar.');
      return;
    }

    if (senha.length < 6) {
      _showError('A senha deve ter pelo menos 6 caracteres.');
      return;
    }

    if (senha != confirmarSenha) {
      _showError('As senhas não coincidem.');
      return;
    }

    if (!_aceitouTermos) {
      _showError('Tem de ler e aceitar os Termos e Condições para se cadastrar.');
      return;
    }

    setState(() => _isLoading = true);

    try {
      // Criar usuário no Auth
      UserCredential userCredential = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: email,
        password: senha,
      );

      final uid = userCredential.user!.uid;

      // Salvar dados no Firestore (igual à versão web)
      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        'nome': nome,
        'nome_normalized': nome.toLowerCase(),
        'email': email,
        'emailVerificado': false,
        'dataNascimento': _selectedDate!.toIso8601String(),
        'provincia': _selectedProvince,
        'municipio': _selectedMunicipio,
        'telefone': telefone,
        'role': 'user',
        'criadoEm': Timestamp.now(),
        'visitasCount': 0,
        'photoBase64': '',
        'stats': {
          'apoios': 0,
          'comentarios': 0,
          'partilhas': 0,
        },
        // NOVO: regista a aceitação dos termos no momento do registo —
        // não é preciso passar pelo gate do AuthCheck logo a seguir,
        // já fica com a versão actual desde o início.
        'termosAceitos':   true,
        'termosAceitosEm': Timestamp.now(),
        'termosVersao':    kTermosVersaoActual,
      });

      // Enviar email de verificação
      await userCredential.user!.sendEmailVerification();

      // Fazer logout para forçar verificação antes de usar
      await FirebaseAuth.instance.signOut();

      if (!mounted) return;

      // Mostrar diálogo de sucesso
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          icon: const Icon(Icons.mark_email_read_rounded, color: Color(0xFF22C55E), size: 48),
          title: const Text('Conta criada com sucesso!'),
          content: Text(
            'Enviamos um email de verificação para:\n$email\n\n'
            'Verifique a sua caixa de entrada (e a pasta Spam) '
            'e clique no link para activar a sua conta.\n\n'
            'Depois, faça login para começar a usar o MissingAO.',
            style: const TextStyle(fontSize: 14, height: 1.5),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                Navigator.pop(context); // Voltar para o login
              },
              child: const Text('Ir para o Login'),
            ),
          ],
        ),
      );
    } on FirebaseAuthException catch (e) {
      String message;
      switch (e.code) {
        case 'email-already-in-use':
          message = 'Este email já está registado.';
          break;
        case 'invalid-email':
          message = 'Formato de email inválido.';
          break;
        case 'weak-password':
          message = 'A senha é muito fraca. Escolha uma senha mais forte.';
          break;
        case 'too-many-requests':
          message = 'Demasiadas tentativas. Aguarde um momento.';
          break;
        default:
          message = 'Erro ao criar conta: ${e.message}';
      }
      _showError(message);
    } catch (e) {
      _showError('Erro inesperado. Tente novamente.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: const Color(0xFFEF4444),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;

    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          // Rodapé azul fixo
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              height: screenHeight * 0.15,
              color: const Color.fromARGB(255, 240, 241, 241),
            ),
          ),

          SingleChildScrollView(
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 28.0, vertical: 20.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "Cadastre-se",
                      style: TextStyle(
                        fontSize: 34,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF333333),
                      ),
                    ),
                    const Text(
                      "Crie sua conta para ajudar!",
                      style: TextStyle(color: Colors.grey, fontSize: 16),
                    ),
                    const SizedBox(height: 30),

                    // ── Nome Completo ──
                    _buildTextField("Nome Completo:", "seu nome completo",
                        controller: _nameController, icon: Icons.person_rounded),
                    const SizedBox(height: 12),

                    // ── Email ──
                    _buildTextField("Email:", "seu e-mail",
                        controller: _emailController,
                        icon: Icons.email_rounded,
                        keyboardType: TextInputType.emailAddress),
                    const SizedBox(height: 12),

                    // ── Telefone ──
                    _buildTextField("Telefone:", "+244 9XX XXX XXX",
                        controller: _phoneController,
                        icon: Icons.phone_rounded,
                        keyboardType: TextInputType.phone),
                    const SizedBox(height: 12),

                    // ── Data de Nascimento ──
                    const Text("Data de Nascimento:",
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    const SizedBox(height: 6),
                    GestureDetector(
                      onTap: () => _selectDate(context),
                      child: AbsorbPointer(
                        child: TextField(
                          decoration: InputDecoration(
                            hintText: _selectedDate == null
                                ? "Selecione a data"
                                : "${_selectedDate!.day.toString().padLeft(2, '0')}/${_selectedDate!.month.toString().padLeft(2, '0')}/${_selectedDate!.year}",
                            prefixIcon: const Icon(Icons.calendar_today_rounded,
                                color: Color(0xFF0077B6), size: 20),
                            filled: true,
                            fillColor: const Color(0xFFF8F9FA),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 14),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide(color: Colors.grey.shade300),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide(color: Colors.grey.shade300),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // ── Província ──
                    const Text("Província:",
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<String>(
                      value: _selectedProvince,
                      hint: const Text("Selecione sua província"),
                      isExpanded: true,
                      icon: const Icon(Icons.arrow_drop_down_rounded, color: Color(0xFF0077B6)),
                      items: _provinces.map((province) {
                        return DropdownMenuItem<String>(
                          value: province,
                          child: Text(province),
                        );
                      }).toList(),
                      onChanged: (value) {
                        setState(() {
                          _selectedProvince = value;
                          _selectedMunicipio = null;
                        });
                      },
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.location_on_rounded,
                            color: Color(0xFF0077B6), size: 20),
                        filled: true,
                        fillColor: const Color(0xFFF8F9FA),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 14),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(color: Colors.grey.shade300),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(color: Colors.grey.shade300),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // ── Município ──
                    const Text("Município:",
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<String>(
                      value: _selectedMunicipio,
                      hint: const Text("Selecione seu município"),
                      isExpanded: true,
                      icon: const Icon(Icons.arrow_drop_down_rounded, color: Color(0xFF0077B6)),
                      items: _selectedProvince != null &&
                              _municipiosPorProvincia.containsKey(_selectedProvince!)
                          ? _municipiosPorProvincia[_selectedProvince!]!.map((municipio) {
                              return DropdownMenuItem<String>(
                                value: municipio,
                                child: Text(municipio),
                              );
                            }).toList()
                          : [],
                      onChanged: (value) {
                        setState(() {
                          _selectedMunicipio = value;
                        });
                      },
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.map_rounded,
                            color: Color(0xFF0077B6), size: 20),
                        filled: true,
                        fillColor: const Color(0xFFF8F9FA),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 14),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(color: Colors.grey.shade300),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(color: Colors.grey.shade300),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // ── Senha ──
                    _buildTextField("Senha:", "mínimo 6 caracteres",
                        controller: _passwordController,
                        icon: Icons.lock_rounded,
                        obscureText: true),
                    const SizedBox(height: 12),

                    // ── Confirmar Senha ──
                    _buildTextField("Confirmar Senha:", "repita a senha",
                        controller: _confirmPasswordController,
                        icon: Icons.lock_rounded,
                        obscureText: true),
                    const SizedBox(height: 16),

                    // NOVO: checkbox de aceitação dos Termos e Condições —
                    // obrigatório para avançar (validado em _register()).
                    // O texto "Termos e Condições" é tocável e abre o
                    // mesmo ecrã usado como gate, mas em modo leitura
                    // (somenteLeitura: true), sem exigir scroll nem
                    // escrever nada no Firestore — a conta ainda nem existe.
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Checkbox(
                          value: _aceitouTermos,
                          onChanged: (v) => setState(() => _aceitouTermos = v ?? false),
                          activeColor: const Color(0xFF0077B6),
                        ),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: RichText(
                              text: TextSpan(
                                style: const TextStyle(color: Colors.black87, fontSize: 13),
                                children: [
                                  const TextSpan(text: 'Li e aceito os '),
                                  TextSpan(
                                    text: 'Termos e Condições',
                                    style: const TextStyle(
                                      color: Color(0xFF0077B6),
                                      fontWeight: FontWeight.w700,
                                      decoration: TextDecoration.underline,
                                    ),
                                    recognizer: TapGestureRecognizer()
                                      ..onTap = () => Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (_) => const TermsAcceptancePage(somenteLeitura: true),
                                            ),
                                          ),
                                  ),
                                  const TextSpan(text: '.'),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity, height: 52,
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _register,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF90E0EF),
                          foregroundColor: Colors.black87,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        child: _isLoading
                            ? const SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black87),
                              )
                            : const Text("Cadastrar", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Center(
                      child: TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Já tem conta? Entre aqui'),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // ── Imagem ──
                    Container(
                      height: screenHeight * 0.35,
                      width: double.infinity,
                      alignment: Alignment.center,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Image.asset(
                            'assets/images/desaparecidosimg3.jpeg',
                            fit: BoxFit.cover,
                            width: double.infinity,
                            height: double.infinity,
                            alignment: Alignment.center,
                          ),
                          Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter, end: Alignment.bottomCenter,
                                colors: [Colors.transparent, const Color(0xFF0077B6).withOpacity(0.7)],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextField(String label, String hint,
      {TextEditingController? controller, bool obscureText = false, IconData? icon, TextInputType keyboardType = TextInputType.text}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          obscureText: obscureText,
          keyboardType: keyboardType,
          decoration: InputDecoration(
            hintText: hint,
            prefixIcon: icon != null
                ? Icon(icon, color: const Color(0xFF0077B6), size: 20)
                : null,
            filled: true,
            fillColor: const Color(0xFFF8F9FA),
            contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 14),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: Colors.grey.shade300),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: Colors.grey.shade300),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: Color(0xFF0077B6), width: 2),
            ),
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }
}