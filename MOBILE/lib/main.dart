import 'package:flutter/material.dart';

void main() {
  runApp(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: Colors.grey[900],
        

        appBar: AppBar(
          backgroundColor: Colors.grey[900],
          elevation: 0,  
          title: const Text(
            "Desaparecidos", 
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 22),
          ),
          actions: [
            // BOTÃO DE NOTIFICAÇÕES
            IconButton(
              icon: const Icon(Icons.notifications_none_rounded, color: Colors.white, size: 28),
              onPressed: () => print("Abrir Notificações"),
            ),
          ],
        ),

        body: Column(
          children: [
            // BARRA DE PESQUISA 
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Container(
                height: 45,
                decoration: BoxDecoration(
                  color: Colors.grey[800],
                  borderRadius: BorderRadius.circular(15),
                ),
                child: const TextField(
                  style: TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: "Procurar...",
                    hintStyle: TextStyle(color: Colors.grey),
                    prefixIcon: Icon(Icons.search, color: Colors.grey),
                    border: InputBorder.none,
                  ),
                ),
              ),
            ),
            
            // LISTA DE CARDS
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  meuCardDesaparecido(
                    nomePessoa: "MIGUEL ANTÓNIO",
                    idade: "12 anos",
                    local: "Bairro Operário, Luanda",
                    descricao: "Visto pela última vez trajando t-shirt branca.",
                    fotoPost: "https://f.i.uol.com.br/fotografia/2020/11/18/16057002115fb50a73d8e69_1605700211_1x1_md.jpg",
                    familiaNome: "Família António",
                  ),
                  const SizedBox(height: 20),
                  meuCardDesaparecido(
                    nomePessoa: "ANA BELA",
                    idade: "15 anos",
                    local: "Viana, Luanda",
                    descricao: "Saiu para a escola e não regressou.",
                    fotoPost: "https://images.unsplash.com/photo-1531123897727-8f129e1688ce?auto=format&fit=crop&q=80&w=400",
                    familiaNome: "Família Bela",
                  ),
                ],
              ),
            ),
          ],
        ),

        // Ele fica flutuando por cima do conteúdo
        floatingActionButton: FloatingActionButton.extended(
          backgroundColor: Colors.blueAccent,
          icon: const Icon(Icons.add, color: Colors.white),
          label: const Text("", style: TextStyle(fontWeight: FontWeight.bold)),
          onPressed: () => print("Abrir tela de cadastro"),
        ),

        bottomNavigationBar: BottomNavigationBar(
          type: BottomNavigationBarType.fixed,
          backgroundColor: Colors.grey[900],
          selectedItemColor: Colors.blueAccent,
          unselectedItemColor: Colors.grey,
          showSelectedLabels: false, // Esconde labels para parecer mais moderno
          showUnselectedLabels: false,
          items: const [
            BottomNavigationBarItem(icon: Icon(Icons.home_filled, size: 28), label: 'Home'),
            BottomNavigationBarItem(icon: Icon(Icons.location_on_outlined), label: 'Mapa'),
            BottomNavigationBarItem(icon: Icon(Icons.smart_toy_outlined), label: 'Chatbot'),
            BottomNavigationBarItem(icon: Icon(Icons.person_outline), label: 'Perfil'),
          ],
        ),
      ),
    ),
  );
}

// --- OS TEUS WIDGETS AUXILIARES (A FÁBRICA DE CARDS E BOTÕES) ---

Widget meuCardDesaparecido({
  required String nomePessoa,
  required String idade,
  required String local,
  required String descricao,
  required String fotoPost,
  required String familiaNome,
}) {
  return Card(
    clipBehavior: Clip.antiAlias,
    color: Colors.grey[850],
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          leading: const CircleAvatar(
            backgroundColor: Colors.blueAccent,
            child: Icon(Icons.person, color: Colors.white),
          ),
          title: Text(familiaNome, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
          subtitle: const Text("Luanda, Angola", style: TextStyle(color: Colors.grey, fontSize: 11)),
          trailing: const Icon(Icons.more_horiz, color: Colors.grey), // 3 pontinhos horizontais 
        ),
        Image.network(fotoPost, height: 300, width: double.infinity, fit: BoxFit.cover),
        Padding(
          padding: const EdgeInsets.all(15),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("$nomePessoa, $idade", style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 5),
              Text(local, style: const TextStyle(color: Colors.redAccent, fontSize: 13, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(descricao, style: const TextStyle(color: Colors.grey, fontSize: 13)),
              const SizedBox(height: 15),
              Row(
                children: [
                  botaoInteracao(Icons.favorite_border, "Apoiar"),
                  const SizedBox(width: 10),
                  botaoInteracao(Icons.chat_bubble_outline, "Comentar"),
                  const Spacer(), // Empurra o próximo ícone para o fim
                  botaoInteracao(Icons.share_outlined, "Compartilhar"),
                ],
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

Widget botaoInteracao(IconData icon, String label) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    decoration: BoxDecoration(
      color: Colors.white.withOpacity(0.05),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      children: [
        Icon(icon, color: Colors.white, size: 18),
        if (label.isNotEmpty) const SizedBox(width: 6),
        if (label.isNotEmpty) Text(label, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500)),
      ],
    ),
  );
}