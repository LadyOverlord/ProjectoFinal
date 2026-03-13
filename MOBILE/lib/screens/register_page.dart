import 'package:flutter/material.dart'; 
import 'package:firebase_auth/firebase_auth.dart'; 
import 'package:cloud_firestore/cloud_firestore.dart'; 
import 'home_page.dart'; 
import '../models/user_mode.dart'; 

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _nameController = TextEditingController(); 
  final _emailController = TextEditingController(); 
  final _passwordController = TextEditingController(); 
  final _confirmPasswordController = TextEditingController(); 

  
  DateTime? _selectedDate; 
  String? _selectedProvince; 
  String? _selectedMunicipio; 

 
  final List<String> _provinces = [
    'Luanda', 'Benguela', 'Huambo', 'Huíla', 'Cunene', 'Namibe', 'Moxico',
    'Cuando Cubango', 'Lunda Norte', 'Lunda Sul', 'Malanje', 'Uíge',
    'Zaire', 'Cabinda', 'Bié', 'Cuanza Norte', 'Cuanza Sul',
  ];

  
 
  final Map<String, List<String>> _municipiosPorProvincia = {
    'Luanda': ['Luanda', 'Belas', 'Cacuaco', 'Viana'],
    
  };

  
  Future<void> _selectDate(BuildContext context) async {
    
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now().subtract(const Duration(days: 365 * 18)), 
      firstDate: DateTime(1900), 
      lastDate: DateTime.now(), 
    );
    
    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked; 
      });
    }
  }

  Future<void> _register() async {
    if (_passwordController.text != _confirmPasswordController.text) {
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("As senhas não coincidem")),
      );
      return; 
    }

    try {
      
      UserCredential userCredential = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: _emailController.text.trim(), 
        password: _passwordController.text.trim(),
      );

      await FirebaseFirestore.instance.collection('users').doc(userCredential.user!.uid).set({
        'nome': _nameController.text.trim(), 
        'nome_normalized': _nameController.text.trim().toLowerCase(), 
        'email': _emailController.text.trim(), 
        'emailVerificado': userCredential.user!.emailVerified, 
        'dataNascimento': _selectedDate?.toIso8601String(),
        'provincia': _selectedProvince, 
        'municipio': _selectedMunicipio,
        'role': 'user', 
        'criadoEm': Timestamp.now(), 
      });

      if (!mounted) return; 
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => const HomePage(mode: UserMode.authenticated),
        ),
      );
    } on FirebaseAuthException catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message ?? "Erro ao criar conta")),
      );
    } catch (e) {
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Erro ao salvar dados")),
      );
    }
  }


  @override
  Widget build(BuildContext context) {
   
    final screenHeight = MediaQuery.of(context).size.height;

    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack( 
        children: [
          
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
                      "Crie sua conta!",
                      style: TextStyle(color: Colors.grey, fontSize: 16),
                    ),
                    const SizedBox(height: 30), 

                    _buildTextField("Nome Completo:", "seu nome completo", controller: _nameController),
                    const SizedBox(height: 12),

                    
                    _buildTextField("Email:", "seu e-mail", controller: _emailController),
                    const SizedBox(height: 12),

                    
                    const Text("Data de Nascimento:", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    const SizedBox(height: 6),
                    
                    GestureDetector(
                      onTap: () => _selectDate(context), 
                      child: AbsorbPointer( 
                        child: TextField(
                          decoration: InputDecoration(
                            hintText: _selectedDate == null
                                ? "Selecione a data" 
                                : "${_selectedDate!.day}/${_selectedDate!.month}/${_selectedDate!.year}", 
                            filled: true,
                            fillColor: const Color(0xFFF8F9FA), 
                            contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 14),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
                            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
                            suffixIcon: const Icon(Icons.calendar_today), 
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    const Text("Província:", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    const SizedBox(height: 6),
                  
                    DropdownButtonFormField<String>(
                      value: _selectedProvince, 
                      hint: const Text("Selecione sua província"), 
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
                        filled: true,
                        fillColor: const Color(0xFFF8F9FA),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 14),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
                      ),
                    ),
                    const SizedBox(height: 12),

                    
                    const Text("Município:", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    const SizedBox(height: 6),
                    
                    DropdownButtonFormField<String>(
                      value: _selectedMunicipio,
                      hint: const Text("Selecione seu município"),
                      items: _selectedProvince != null && _municipiosPorProvincia.containsKey(_selectedProvince!)
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
                        filled: true,
                        fillColor: const Color(0xFFF8F9FA),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 14),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
                      ),
                    ),
                    const SizedBox(height: 12),

                    
                    _buildTextField("Senha:", "sua senha", controller: _passwordController, obscureText: true),
                    const SizedBox(height: 12),
                    
                    _buildTextField("Confirmar Senha:", "confirme sua senha", controller: _confirmPasswordController, obscureText: true),
                    const SizedBox(height: 20),

                    
                    SizedBox(
                      width: double.infinity, 
                      height: 52,
                      child: ElevatedButton(
                        onPressed: _register,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF90E0EF), 
                          foregroundColor: Colors.black87, 
                          elevation: 0, 
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)), 
                        ),
                        child: const Text("Cadastrar", 
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
                      ),
                    ),

                    
                    Align(
                      alignment: Alignment.centerLeft, 
                      child: TextButton(
                        onPressed: () {
                          Navigator.pop(context); 
                        },
                        style: TextButton.styleFrom(padding: EdgeInsets.zero), // Remove padding extra
                        child: const Text(
                          "Já tem conta? Entre aqui",
                          style: TextStyle(color: Colors.black54, fontSize: 14),
                        ),
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

 
  Widget _buildTextField(String label, String hint, {TextEditingController? controller, bool obscureText = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start, 
      children: [
        
        Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
        const SizedBox(height: 6), 
       
        TextField(
          controller: controller, 
          obscureText: obscureText, 
          decoration: InputDecoration(
            hintText: hint,
            filled: true,
            fillColor: const Color(0xFFF8F9FA), 
            contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 14),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)), // Borda
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)), 
          ),
        ),
      ],
    );
  }
}