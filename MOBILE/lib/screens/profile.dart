import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'login_page.dart';
import '../models/user_mode.dart';
import 'home_page.dart';
import 'chatbot_page.dart';
import 'map_page.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({Key? key}) : super(key: key);

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  User? user = FirebaseAuth.instance.currentUser;
  Map<String, dynamic>? userData;
  File? _imageFile;

  @override
  void initState() {
    super.initState();
    if (user != null) {
      _loadUserData();
    }
  }

  Future<void> _loadUserData() async {
    final doc = await FirebaseFirestore.instance.collection('users').doc(user!.uid).get();
    if (doc.exists) {
      setState(() {
        userData = doc.data();
      });
    }
  }

  Future<void> _pickImage() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked != null) {
      setState(() {
        _imageFile = File(picked.path);
      });
    }
  }

  void _onBottomNavTap(int index) {
    switch (index) {
      case 0:
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => HomePage(mode: user == null ? UserMode.guest : UserMode.authenticated)),
        );
        break;
      case 1:
        
        break;
      case 2:
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const ChatbotPage()),
        );
        break;
      case 3:
        break; // Já está no perfil
    }
  }

  @override
  Widget build(BuildContext context) {
    final isGuest = user == null;

    return Scaffold(
      backgroundColor: Colors.grey[900],
      appBar: AppBar(
        backgroundColor: Colors.grey[900],
        title: const Text("Perfil", style: TextStyle(color: Colors.white)),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            GestureDetector(
              onTap: isGuest ? null : _pickImage,
              child: CircleAvatar(
                radius: 60,
                backgroundColor: Colors.grey[800],
                backgroundImage: _imageFile != null
                    ? FileImage(_imageFile!)
                    : (userData != null && userData!['p_file'] != null
                        ? NetworkImage(userData!['p_file'])
                        : null) as ImageProvider<Object>?,
                child: _imageFile == null && (userData == null || userData!['p_file'] == null)
                    ? const Icon(Icons.person, size: 60, color: Colors.white)
                    : null,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              isGuest ? "Convidado" : (userData?['nome'] ?? 'Usuário'),
              style: const TextStyle(
                  fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            const SizedBox(height: 6),
            Text(
              isGuest ? "Email não disponível" : (user?.email ?? ''),
              style: const TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 20),
            _infoCard("Município", isGuest ? "Não informado" : (userData?['municipio'] ?? 'Não informado')),
            _infoCard("Província", isGuest ? "Não informado" : (userData?['provincia'] ?? 'Não informado')),
            _infoCard("Idade", isGuest ? "Não informado" : (userData?['idade'] ?? 'Não informado')),
            const SizedBox(height: 30),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 15),
                backgroundColor: Colors.blueAccent,
              ),
              onPressed: () {
                if (isGuest) {
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(builder: (_) => const LoginPage()),
                  );
                } else {
                  FirebaseAuth.instance.signOut().then((_) {
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(builder: (_) => const LoginPage()),
                    );
                  });
                }
              },
              child: Text(
                isGuest ? "Entrar / Registrar" : "Sair",
                style: const TextStyle(fontSize: 18, color: Colors.white),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        backgroundColor: Colors.grey[900],
        selectedItemColor: Colors.blueAccent,
        unselectedItemColor: Colors.grey,
        type: BottomNavigationBarType.fixed,
        currentIndex: 3,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home_filled), label: 'Home'),
          BottomNavigationBarItem(icon: Icon(Icons.location_on_outlined), label: 'Mapa'),
          BottomNavigationBarItem(icon: Icon(Icons.auto_awesome), label: 'Chatbot'),
          BottomNavigationBarItem(icon: Icon(Icons.person_outline), label: 'Perfil'),
        ],
        onTap: _onBottomNavTap,
      ),
    );
  }

  Widget _infoCard(String title, String subtitle) {
    return Card(
      color: Colors.grey[850],
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: ListTile(
        title: Text(title, style: const TextStyle(color: Colors.white)),
        subtitle: Text(subtitle, style: const TextStyle(color: Colors.grey)),
      ),
    );
  }
}