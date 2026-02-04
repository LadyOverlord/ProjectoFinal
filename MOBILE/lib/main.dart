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
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 22,
            ),
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.notifications_none_rounded, color: Colors.white),
              onPressed: () {},
            ),
          ],
        ),
        body: Column(
          children: [
            // BARRA DE PESQUISA
            Padding(
              padding: const EdgeInsets.all(16),
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
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  
                  // CARD 1 - MIGUEL ANTÓNIO
                  Card(
                    clipBehavior: Clip.antiAlias,
                    color: Colors.grey[850],
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const ListTile(
                          leading: CircleAvatar(backgroundColor: Colors.blueAccent, child: Icon(Icons.person, color: Colors.white)),
                          title: Text("Família António", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                          subtitle: Text("Luanda, Angola", style: TextStyle(color: Colors.grey, fontSize: 12)),
                          trailing: Icon(Icons.more_horiz, color: Colors.grey),
                        ),
                        Image.network(
                          "https://images.unsplash.com/photo-1531123897727-8f129e16fd3c?w=500",
                          height: 250, width: double.infinity, fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) => Container(height: 250, color: Colors.grey[800], child: const Icon(Icons.broken_image, color: Colors.grey)),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(15),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text("Miguel António, 12 anos", style: TextStyle(color: Colors.white, fontSize: 18)),
                              const SizedBox(height: 5),
                              const Text("Nova-vida, Luanda", style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
                              const SizedBox(height: 12),
                              const Text("Visto pela última vez trajando t-shirt branca e calças azuis. Por favor, ajudem.", style: TextStyle(color: Colors.grey, fontSize: 13)),
                              const SizedBox(height: 15),
                              Row(
                                children: [
                                  Expanded(child: TextButton.icon(onPressed: () {}, icon: const Icon(Icons.favorite_border, color: Colors.grey, size: 16), label: const Text("Apoiar", style: TextStyle(color: Colors.grey, fontSize: 10)), style: TextButton.styleFrom(backgroundColor: Colors.white.withOpacity(0.05), padding: EdgeInsets.zero))),
                                  const SizedBox(width: 4),
                                  Expanded(child: TextButton.icon(onPressed: () {}, icon: const Icon(Icons.mode_comment_outlined, color: Colors.grey, size: 16), label: const Text("Comentar", style: TextStyle(color: Colors.grey, fontSize: 10)), style: TextButton.styleFrom(backgroundColor: Colors.white.withOpacity(0.05), padding: EdgeInsets.zero))),
                                  const SizedBox(width: 4),
                                  Expanded(child: TextButton.icon(onPressed: () {}, icon: const Icon(Icons.send_outlined, color: Colors.grey, size: 16), label: const Text("Partilhar", style: TextStyle(color: Colors.grey, fontSize: 10)), style: TextButton.styleFrom(backgroundColor: Colors.white.withOpacity(0.05), padding: EdgeInsets.zero))),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // CARD 2 - ANA SILVA
                  Card(
                    clipBehavior: Clip.antiAlias,
                    color: Colors.grey[850],
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const ListTile(
                          leading: CircleAvatar(backgroundColor: Colors.blueAccent, child: Icon(Icons.person, color: Colors.white)),
                          title: Text("Família Silva", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                          subtitle: Text("Benguela, Angola", style: TextStyle(color: Colors.grey, fontSize: 12)),
                          trailing: Icon(Icons.more_horiz, color: Colors.grey),
                        ),
                        Image.network(
                          "https://images.unsplash.com/photo-1529139574466-a3090c302d1a?w=500",
                          height: 250, width: double.infinity, fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) => Container(height: 250, color: Colors.grey[800], child: const Icon(Icons.broken_image, color: Colors.grey)),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(15),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text("Ana Silva, 8 anos", style: TextStyle(color: Colors.white, fontSize: 18)),
                              const SizedBox(height: 5),
                              const Text("Zona Comercial, Benguela", style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
                              const SizedBox(height: 12),
                              const Text("Desaparecida desde ontem. Estava com um vestido cor-de-rosa. Ajudem a partilhar.", style: TextStyle(color: Colors.grey, fontSize: 13)),
                              const SizedBox(height: 15),
                              Row(
                                children: [
                                  Expanded(child: TextButton.icon(onPressed: () {}, icon: const Icon(Icons.favorite_border, color: Colors.grey, size: 16), label: const Text("Apoiar", style: TextStyle(color: Colors.grey, fontSize: 10)), style: TextButton.styleFrom(backgroundColor: Colors.white.withOpacity(0.05), padding: EdgeInsets.zero))),
                                  const SizedBox(width: 4),
                                  Expanded(child: TextButton.icon(onPressed: () {}, icon: const Icon(Icons.mode_comment_outlined, color: Colors.grey, size: 16), label: const Text("Comentar", style: TextStyle(color: Colors.grey, fontSize: 10)), style: TextButton.styleFrom(backgroundColor: Colors.white.withOpacity(0.05), padding: EdgeInsets.zero))),
                                  const SizedBox(width: 4),
                                  Expanded(child: TextButton.icon(onPressed: () {}, icon: const Icon(Icons.send_outlined, color: Colors.grey, size: 16), label: const Text("Partilhar", style: TextStyle(color: Colors.grey, fontSize: 10)), style: TextButton.styleFrom(backgroundColor: Colors.white.withOpacity(0.05), padding: EdgeInsets.zero))),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // CARD 3 - PEDRO SANTOS
                  Card(
                    clipBehavior: Clip.antiAlias,
                    color: Colors.grey[850],
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const ListTile(
                          leading: CircleAvatar(backgroundColor: Colors.blueAccent, child: Icon(Icons.person, color: Colors.white)),
                          title: Text("Família Santos", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                          subtitle: Text("Huambo, Angola", style: TextStyle(color: Colors.grey, fontSize: 12)),
                          trailing: Icon(Icons.more_horiz, color: Colors.grey),
                        ),
                        Image.network(
                          "https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?w=500",
                          height: 250, width: double.infinity, fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) => Container(height: 250, color: Colors.grey[800], child: const Icon(Icons.broken_image, color: Colors.grey)),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(15),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text("Pedro Santos, 25 anos", style: TextStyle(color: Colors.white, fontSize: 18)),
                              const SizedBox(height: 5),
                              const Text("Bairro Operário, Huambo", style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
                              const SizedBox(height: 12),
                              const Text("Saiu de casa para o trabalho e não regressou. Qualquer info é importante.", style: TextStyle(color: Colors.grey, fontSize: 13)),
                              const SizedBox(height: 15),
                              Row(
                                children: [
                                  Expanded(child: TextButton.icon(onPressed: () {}, icon: const Icon(Icons.favorite_border, color: Colors.grey, size: 16), label: const Text("Apoiar", style: TextStyle(color: Colors.grey, fontSize: 10)), style: TextButton.styleFrom(backgroundColor: Colors.white.withOpacity(0.05), padding: EdgeInsets.zero))),
                                  const SizedBox(width: 4),
                                  Expanded(child: TextButton.icon(onPressed: () {}, icon: const Icon(Icons.mode_comment_outlined, color: Colors.grey, size: 16), label: const Text("Comentar", style: TextStyle(color: Colors.grey, fontSize: 10)), style: TextButton.styleFrom(backgroundColor: Colors.white.withOpacity(0.05), padding: EdgeInsets.zero))),
                                  const SizedBox(width: 4),
                                  Expanded(child: TextButton.icon(onPressed: () {}, icon: const Icon(Icons.send_outlined, color: Colors.grey, size: 16), label: const Text("Partilhar", style: TextStyle(color: Colors.grey, fontSize: 10)), style: TextButton.styleFrom(backgroundColor: Colors.white.withOpacity(0.05), padding: EdgeInsets.zero))),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        bottomNavigationBar: BottomNavigationBar(
          backgroundColor: Colors.grey[900],
          selectedItemColor: Colors.blueAccent,
          unselectedItemColor: Colors.grey,
          type: BottomNavigationBarType.fixed,
          items: const [
            BottomNavigationBarItem(icon: Icon(Icons.home_filled), label: 'Home'),
            BottomNavigationBarItem(icon: Icon(Icons.location_on_outlined), label: 'Mapa'),
            BottomNavigationBarItem(icon: Icon(Icons.auto_awesome), label: 'Chatbot'),
            BottomNavigationBarItem(icon: Icon(Icons.person_outline), label: 'Perfil'),
          ],
        ),
      ),
    ),
  );
}