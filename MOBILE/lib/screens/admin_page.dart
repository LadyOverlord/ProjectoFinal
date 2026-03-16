import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart'; // pubspec.yaml → intl: ^0.19.0

class AdminPage extends StatefulWidget {
  const AdminPage({super.key});

  @override
  State<AdminPage> createState() => _AdminPageState();
}

class _AdminPageState extends State<AdminPage> {
  String _selectedSection = 'dashboard';
  final TextEditingController _searchController = TextEditingController();

  void _changeSection(String section) {
    setState(() => _selectedSection = section);
    if (MediaQuery.of(context).size.width <= 700) Navigator.pop(context);
  }

  Future<void> _logout() async {
    await FirebaseAuth.instance.signOut();
  }

  Future<void> _marcarComoEncontrado(DocumentSnapshot doc) async {
    await FirebaseFirestore.instance
        .collection('casos')
        .doc(doc.id)
        .update({'status': 'encontrado', 'encontradoEm': Timestamp.now()});

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('✅ Caso marcado como Encontrado!'), backgroundColor: Colors.green),
      );
    }
  }

  void _showCasoDetails(DocumentSnapshot doc, {bool isPending = false}) {
    final data = doc.data() as Map<String, dynamic>;
    final String? base64Img = data['imagem'];
    Uint8List? imageBytes;
    if (base64Img != null && base64Img.startsWith('data:image')) {
      imageBytes = base64Decode(base64Img.split(',').last);
    }

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Colors.grey[900],
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(data['nome'] ?? 'Sem nome', style: const TextStyle(color: Colors.white)),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (imageBytes != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Image.memory(imageBytes, height: 260, width: double.infinity, fit: BoxFit.cover),
                ),
              const SizedBox(height: 20),
              _detailRow('Idade', data['idade']?.toString() ?? '—'),
              _detailRow('Sexo', data['sexo'] ?? '—'),
              _detailRow('Província', data['provincia'] ?? '—'),
              _detailRow('Data', data['data_desaparecimento'] ?? '—'),
              const Divider(color: Colors.grey),
              Text(data['informacoes_adicionais'] ?? '', style: const TextStyle(color: Colors.white70)),
            ],
          ),
        ),
        actions: isPending
            ? [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('Fechar')),
                ElevatedButton.icon(onPressed: () { Navigator.pop(context); _aprovar(doc); }, icon: const Icon(Icons.check), label: const Text('Aprovar'), style: ElevatedButton.styleFrom(backgroundColor: Colors.green)),
                ElevatedButton.icon(onPressed: () { Navigator.pop(context); _rejeitar(doc); }, icon: const Icon(Icons.close), label: const Text('Rejeitar'), style: ElevatedButton.styleFrom(backgroundColor: Colors.red)),
              ]
            : [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Fechar'))],
      ),
    );
  }

  Widget _detailRow(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [Text('$label: ', style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.bold)), Expanded(child: Text(value, style: const TextStyle(color: Colors.white)))]),
      );

  Future<void> _aprovar(DocumentSnapshot doc) async {
    final data = doc.data() as Map<String, dynamic>;
    data['status'] = 'aprovado';
    data['aprovadoEm'] = Timestamp.now();
    await FirebaseFirestore.instance.collection('casos').add(data);
    await FirebaseFirestore.instance.collection('casos_pendentes').doc(doc.id).delete();
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('✅ Aprovado!')));
  }

  Future<void> _rejeitar(DocumentSnapshot doc) async {
    await FirebaseFirestore.instance.collection('casos_pendentes').doc(doc.id).delete();
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('❌ Rejeitado')));
  }

  Widget _buildContent() {
    switch (_selectedSection) {
      case 'dashboard':
        return _buildDashboard();
      case 'users':
        return _buildUsers();
      case 'reports':
        return _buildPendentes();
      case 'config':
        return const Center(child: Text('Configurações em breve...', style: TextStyle(color: Colors.white, fontSize: 22)));
      default:
        return const Center(child: Text('Seção não encontrada'));
    }
  }

  // ==================== DASHBOARD  ====================
  Widget _buildDashboard() {
    return Container(
      color: Colors.grey[900], 
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Visão Geral', style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold)),
            const SizedBox(height: 20),

            Row(
              children: [
                Expanded(child: _statCard('Total Usuários', 'users', Icons.people, Colors.blue)),
                const SizedBox(width: 12),
                Expanded(child: _statCard('Casos Pendentes', 'casos_pendentes', Icons.pending, Colors.orange)),
              ],
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _statCard(String title, String collection, IconData icon, Color color) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection(collection).snapshots(),
      builder: (context, snapshot) {
        final count = snapshot.hasData ? snapshot.data!.docs.length : 0;
        return Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(color: Colors.grey[850], borderRadius: BorderRadius.circular(16)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: color, size: 32),
              const SizedBox(height: 12),
              Text(count.toString(), style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.white)),
              Text(title, style: const TextStyle(color: Colors.white70)),
            ],
          ),
        );
      },
    );
  }

  Widget _buildUsers() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Gestão de Usuários', style: TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.bold)),
          const SizedBox(height: 20),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance.collection('users').snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                return ListView.builder(
                  itemCount: snapshot.data!.docs.length,
                  itemBuilder: (context, index) {
                    final u = snapshot.data!.docs[index].data() as Map<String, dynamic>;
                    return Card(
                      color: Colors.grey[800],
                      child: ListTile(
                        leading: CircleAvatar(backgroundColor: Colors.blueAccent, child: Text((u['email'] ?? '?')[0].toUpperCase())),
                        title: Text(u['nome'] ?? u['email'] ?? '', style: const TextStyle(color: Colors.white)),
                        subtitle: Text('${u['email']} • ${u['role']?.toUpperCase() ?? 'USER'}', style: const TextStyle(color: Colors.grey)),
                        trailing: const Icon(Icons.more_vert, color: Colors.grey),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPendentes() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('casos_pendentes').orderBy('createdAt', descending: true).snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const Center(child: Text('Nenhum caso pendente', style: TextStyle(color: Colors.white, fontSize: 20)));
        }
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: snapshot.data!.docs.length,
          itemBuilder: (context, index) {
            final doc = snapshot.data!.docs[index];
            final data = doc.data() as Map<String, dynamic>;
            Uint8List? img;
            if (data['imagem'] != null && data['imagem'].toString().startsWith('data:image')) {
              img = base64Decode(data['imagem'].split(',').last);
            }
            return Card(
              color: Colors.grey[850],
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Column(
                children: [
                  if (img != null)
                    ClipRRect(
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                      child: Image.memory(img, height: 180, width: double.infinity, fit: BoxFit.cover),
                    ),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(data['nome'] ?? '', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
                        Text('${data['idade']} anos • ${data['provincia']}', style: const TextStyle(color: Colors.white70)),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(child: ElevatedButton.icon(onPressed: () => _showCasoDetails(doc, isPending: true), icon: const Icon(Icons.visibility), label: const Text(''))),
                            const SizedBox(width: 8),
                            Expanded(child: ElevatedButton.icon(onPressed: () => _aprovar(doc), icon: const Icon(Icons.check), label: const Text(''), style: ElevatedButton.styleFrom(backgroundColor: Colors.green))),
                            const SizedBox(width: 8),
                            Expanded(child: ElevatedButton.icon(onPressed: () => _rejeitar(doc), icon: const Icon(Icons.close), label: const Text(''), style: ElevatedButton.styleFrom(backgroundColor: Colors.red))),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width > 700;

    return Scaffold(
      backgroundColor: Colors.grey[900], 
      appBar: AppBar(
        backgroundColor: Colors.grey[900],
        title: const Text('Painel de Controle', style: TextStyle(fontWeight: FontWeight.bold)),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: TextField(
              controller: _searchController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Procurar...',
                hintStyle: const TextStyle(color: Colors.grey),
                prefixIcon: const Icon(Icons.search, color: Colors.grey),
                filled: true,
                fillColor: Colors.grey[800],
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              ),
            ),
          ),
        ),
      ),
      drawer: isWide ? null : _buildDrawer(),
      body: Row(
        children: [
          if (isWide) _buildSideMenu(),
          Expanded(
            child: Container(color: Colors.grey[900], child: _buildContent()),
          ),
        ],
      ),
    );
  }

 
  Widget _buildSideMenu() {
    return Container(
      width: 260,
      color: Colors.grey[850],
      child: Column(
        children: [
          const Padding(
            padding: EdgeInsets.all(24),
            child: Column(
              children: [
                Icon(Icons.admin_panel_settings, size: 60, color: Colors.blueAccent),
                SizedBox(height: 12),
                Text('MissingAO', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
                Text('Admin Panel', style: TextStyle(color: Colors.grey)),
              ],
            ),
          ),
          _menuItem('dashboard', Icons.dashboard, 'Dashboard'),
          _menuItem('users', Icons.people, 'Utilizadores'),
          _menuItem('reports', Icons.assignment_turned_in, 'Aprovações'),
          _menuItem('config', Icons.settings, 'Configurações'),
          const Spacer(),
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.redAccent),
            title: const Text('Sair', style: TextStyle(color: Colors.redAccent)),
            onTap: _logout,
          ),
        ],
      ),
    );
  }

  Widget _buildDrawer() {
    return Drawer(
      backgroundColor: Colors.grey[850],
      child: Column(
        children: [
          const DrawerHeader(
            decoration: BoxDecoration(color: Color.fromARGB(255, 33, 33, 33)),
            child: Center(child: Text('MissingAO\nAdmin Panel', style: TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.bold))),
          ),
          _menuItem('dashboard', Icons.dashboard, 'Dashboard'),
          _menuItem('users', Icons.people, 'Utilizadores'),
          _menuItem('reports', Icons.assignment_turned_in, 'Aprovações'),
          _menuItem('config', Icons.settings, 'Configurações'),
          const Spacer(),
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.redAccent),
            title: const Text('Sair', style: TextStyle(color: Colors.redAccent)),
            onTap: _logout,
          ),
        ],
      ),
    );
  }

  Widget _menuItem(String section, IconData icon, String title) {
    final active = _selectedSection == section;
    return ListTile(
      leading: Icon(icon, color: active ? Colors.blueAccent : Colors.grey),
      title: Text(title, style: TextStyle(color: active ? Colors.blueAccent : Colors.grey, fontWeight: active ? FontWeight.bold : null)),
      onTap: () => _changeSection(section),
      tileColor: active ? Colors.grey[700] : null,
    );
  }
}