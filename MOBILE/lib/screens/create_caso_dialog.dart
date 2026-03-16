import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart'; // adicione no pubspec.yaml: intl: ^0.19.0

class CreateCasoDialog extends StatefulWidget {
  const CreateCasoDialog({super.key});

  @override
  State<CreateCasoDialog> createState() => _CreateCasoDialogState();
}

class _CreateCasoDialogState extends State<CreateCasoDialog> {
  final _formKey = GlobalKey<FormState>();

  final _nomeController = TextEditingController();
  final _idadeController = TextEditingController();
  final _ultimoLocalController = TextEditingController();
  final _municipioController = TextEditingController();
  final _informacoesController = TextEditingController();
  final _roupasController = TextEditingController();
  final _tipoDeficienciaController = TextEditingController();

  String? _selectedSexo;
  String? _selectedProvincia;
  DateTime? _selectedDate;
  bool _temDeficiencia = false;
  String? base64Image;

  final List<String> _sexos = ['Masculino', 'Feminino'];
  final List<String> _provincias = [
    'Bengo', 'Benguela', 'Bié', 'Cabinda', 'Cuando Cubango',
    'Cuanza Norte', 'Cuanza Sul', 'Cunene', 'Huambo', 'Huíla',
    'Luanda', 'Lunda Norte', 'Lunda Sul', 'Malanje', 'Moxico',
    'Namibe', 'Uíge', 'Zaire'
  ];

  Future<void> _pickImage() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked != null) {
      final bytes = await picked.readAsBytes();
      setState(() {
        base64Image = "data:image/jpeg;base64,${base64Encode(bytes)}";
      });
    }
  }

  Future<void> _selectDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? DateTime.now().subtract(const Duration(days: 1)),
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.dark(primary: Colors.blueAccent),
        ),
        child: child!,
      ),
    );

    if (picked != null) {
      setState(() => _selectedDate = picked);
    }
  }

  Future<void> _saveCaso() async {
    if (!_formKey.currentState!.validate()) return;

    final user = FirebaseAuth.instance.currentUser;

    await FirebaseFirestore.instance.collection('casos_pendentes').add({
      "autorEmail": user?.email,
      "userId": user?.uid,
      "createdAt": Timestamp.now(),
      "nome": _nomeController.text.trim(),
      "idade": int.tryParse(_idadeController.text.trim()) ?? 0,
      "sexo": _selectedSexo,
      "ultimo_local": _ultimoLocalController.text.trim(),
      "municipio": _municipioController.text.trim(),
      "provincia": _selectedProvincia,
      "data_desaparecimento": _selectedDate != null
          ? DateFormat('dd/MM/yyyy').format(_selectedDate!)
          : '',
      "informacoes_adicionais": _informacoesController.text.trim(),
      "roupas": _roupasController.text.trim(),
      "deficiencia": _temDeficiencia ? 'Sim' : 'Não',
      "tipo_deficiencia": _temDeficiencia ? _tipoDeficienciaController.text.trim() : '',
      "imagem": base64Image,
      "status": "pendente",
    });

    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Caso enviado para aprovação! ✅')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "Relatar desaparecimento",
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 24),

              // Imagem
              Center(
                child: Column(
                  children: [
                    ElevatedButton.icon(
                      onPressed: _pickImage,
                      icon: const Icon(Icons.photo_library),
                      label: const Text("Escolher foto"),
                    ),
                    if (base64Image != null) ...[
                      const SizedBox(height: 12),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.memory(
                          base64Decode(base64Image!.split(',').last),
                          height: 180,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Nome
              TextFormField(
                controller: _nomeController,
                decoration: const InputDecoration(labelText: "Nome completo *"),
                validator: (v) => v!.trim().isEmpty ? "Campo obrigatório" : null,
              ),
              const SizedBox(height: 16),

              // Idade + Sexo
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _idadeController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: "Idade *"),
                      validator: (v) => v!.trim().isEmpty ? "Obrigatório" : null,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: _selectedSexo,
                      decoration: const InputDecoration(labelText: "Sexo *"),
                      items: _sexos
                          .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                          .toList(),
                      onChanged: (v) => setState(() => _selectedSexo = v),
                      validator: (v) => v == null ? "Escolha o sexo" : null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Província + Município
              DropdownButtonFormField<String>(
                value: _selectedProvincia,
                decoration: const InputDecoration(labelText: "Província *"),
                items: _provincias
                    .map((p) => DropdownMenuItem(value: p, child: Text(p)))
                    .toList(),
                onChanged: (v) => setState(() => _selectedProvincia = v),
                validator: (v) => v == null ? "Escolha a província" : null,
              ),
              const SizedBox(height: 16),

              TextFormField(
                controller: _municipioController,
                decoration: const InputDecoration(labelText: "Município"),
              ),
              const SizedBox(height: 16),

              // Último local
              TextFormField(
                controller: _ultimoLocalController,
                decoration: const InputDecoration(labelText: "Último local visto"),
              ),
              const SizedBox(height: 16),

              // Data de desaparecimento
              TextFormField(
                readOnly: true,
                controller: TextEditingController(
                  text: _selectedDate != null
                      ? DateFormat('dd/MM/yyyy').format(_selectedDate!)
                      : '',
                ),
                decoration: const InputDecoration(
                  labelText: "Data do desaparecimento *",
                  suffixIcon: Icon(Icons.calendar_today),
                ),
                onTap: _selectDate,
                validator: (v) => _selectedDate == null ? "Escolha a data" : null,
              ),
              const SizedBox(height: 16),

              // Deficiência
              SwitchListTile(
                title: const Text("Possui deficiência?"),
                value: _temDeficiencia,
                onChanged: (val) => setState(() => _temDeficiencia = val),
                contentPadding: EdgeInsets.zero,
              ),
              if (_temDeficiencia) ...[
                const SizedBox(height: 8),
                TextFormField(
                  controller: _tipoDeficienciaController,
                  decoration: const InputDecoration(labelText: "Tipo de deficiência"),
                ),
              ],
              const SizedBox(height: 16),

              // Informações adicionais
              TextFormField(
                controller: _informacoesController,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: "Informações adicionais",
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 16),

              // Roupas
              TextFormField(
                controller: _roupasController,
                decoration: const InputDecoration(labelText: "Roupas que usava"),
              ),
              const SizedBox(height: 32),

              // Botão Relatar
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _saveCaso,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blueAccent,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    "Relatar caso",
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}