import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geocoding/geocoding.dart';

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

  // Mapa
  GoogleMapController? _mapController;
  LatLng? _selectedPosition;
  String? _selectedAddress;

  final List<String> _sexos = ['Masculino', 'Feminino'];
  final List<String> _provincias = [
    'Bengo', 'Benguela', 'Bié', 'Cabinda', 'Cuando Cubango',
    'Cuanza Norte', 'Cuanza Sul', 'Cunene', 'Huambo', 'Huíla',
    'Luanda', 'Lunda Norte', 'Lunda Sul', 'Malanje', 'Moxico',
    'Namibe', 'Uíge', 'Zaire'
  ];

  // Coordenadas padrão (Luanda)
  static const CameraPosition _initialCamera = CameraPosition(
    target: LatLng(-8.8368, 13.2343),
    zoom: 12,
  );

  Future<void> _pickImage() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 800,
      maxHeight: 800,
      imageQuality: 75,
    );
    if (picked != null) {
      final bytes = await picked.readAsBytes();
      setState(() {
        base64Image = "data:image/jpeg;base64,${base64Encode(bytes)}";
      });
    }
  }

  Future<void> _selectDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? DateTime.now().subtract(const Duration(days: 1)),
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (picked != null) setState(() => _selectedDate = picked);
  }

  void _onMapCreated(GoogleMapController controller) {
    _mapController = controller;
  }

  void _onMapTapped(LatLng position) async {
    setState(() {
      _selectedPosition = position;
    });

    // Geocodificação reversa para pegar o endereço
    try {
      final placemarks = await placemarkFromCoordinates(position.latitude, position.longitude);
      if (placemarks.isNotEmpty) {
        final place = placemarks.first;
        setState(() {
          _selectedAddress = "${place.thoroughfare ?? ''}, ${place.subLocality ?? ''}, ${place.locality ?? ''}"
              .replaceAll(RegExp(r', ,'), ',')
              .trim();
          _ultimoLocalController.text = _selectedAddress ?? '';
        });
      }
    } catch (e) {
      debugPrint("Erro ao obter endereço: $e");
    }
  }

  Future<void> _saveCaso() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedProvincia == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Escolha a província")));
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    await FirebaseFirestore.instance.collection('casos_pendentes').add({
      "autorEmail": user.email,
      "userId": user.uid,
      "createdAt": Timestamp.now(),
      "nome": _nomeController.text.trim(),
      "idade": int.tryParse(_idadeController.text.trim()) ?? 0,
      "sexo": _selectedSexo,
      "ultimo_local": _ultimoLocalController.text.trim(),
      "municipio": _municipioController.text.trim(),
      "provincia": _selectedProvincia,
      "data_desaparecimento": _selectedDate != null
          ? DateFormat('yyyy-MM-dd').format(_selectedDate!)
          : '',
      "informacoes_adicionais": _informacoesController.text.trim(),
      "roupas": _roupasController.text.trim(),
      "deficiencia": _temDeficiencia ? 'Sim' : 'Não',
      "tipo_deficiencia": _temDeficiencia ? _tipoDeficienciaController.text.trim() : '',
      "imagem": base64Image,
      "status": "pendente",
      "lat": _selectedPosition?.latitude,
      "lng": _selectedPosition?.longitude,
    });

    if (mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Caso enviado para aprovação! ✅'), backgroundColor: Colors.green),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text("Relatar Desaparecimento", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              const SizedBox(height: 20),

              // Mapa
              const Text("Toque no mapa para marcar o último local visto", style: TextStyle(fontSize: 14, color: Colors.grey)),
              const SizedBox(height: 8),
              Container(
                height: 220,
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.grey.shade700)),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: GoogleMap(
                    onMapCreated: _onMapCreated,
                    initialCameraPosition: _initialCamera,
                    onTap: _onMapTapped,
                    markers: _selectedPosition != null
                        ? {
                            Marker(
                              markerId: const MarkerId('selected'),
                              position: _selectedPosition!,
                            )
                          }
                        : {},
                    myLocationButtonEnabled: false,
                    zoomControlsEnabled: true,
                  ),
                ),
              ),
              const SizedBox(height: 12),

              if (_selectedAddress != null)
                Text("Local selecionado: $_selectedAddress", style: const TextStyle(fontSize: 13, color: Colors.blueAccent)),

              const SizedBox(height: 20),

              // Foto
              Center(
                child: Column(
                  children: [
                    ElevatedButton.icon(
                      onPressed: _pickImage,
                      icon: const Icon(Icons.photo_library),
                      label: const Text("Escolher Foto"),
                    ),
                    if (base64Image != null) ...[
                      const SizedBox(height: 12),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.memory(
                          base64Decode(base64Image!.split(',').last),
                          height: 160,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 24),

              TextFormField(controller: _nomeController, decoration: const InputDecoration(labelText: "Nome completo *"), validator: (v) => v!.isEmpty ? "Obrigatório" : null),
              const SizedBox(height: 16),

              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _idadeController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: "Idade *"),
                      validator: (v) => v!.isEmpty ? "Obrigatório" : null,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: _selectedSexo,
                      decoration: const InputDecoration(labelText: "Sexo *"),
                      items: _sexos.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                      onChanged: (v) => setState(() => _selectedSexo = v),
                      validator: (v) => v == null ? "Escolha" : null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              DropdownButtonFormField<String>(
                value: _selectedProvincia,
                decoration: const InputDecoration(labelText: "Província *"),
                items: _provincias.map((p) => DropdownMenuItem(value: p, child: Text(p))).toList(),
                onChanged: (v) => setState(() => _selectedProvincia = v),
                validator: (v) => v == null ? "Escolha a província" : null,
              ),
              const SizedBox(height: 16),

              TextFormField(controller: _municipioController, decoration: const InputDecoration(labelText: "Município")),
              const SizedBox(height: 16),

              TextFormField(
                controller: _ultimoLocalController,
                decoration: const InputDecoration(labelText: "Último local visto"),
                readOnly: true, // preenchido automaticamente pelo mapa
              ),
              const SizedBox(height: 16),

              TextFormField(
                readOnly: true,
                controller: TextEditingController(text: _selectedDate != null ? DateFormat('dd/MM/yyyy').format(_selectedDate!) : ''),
                decoration: const InputDecoration(labelText: "Data do desaparecimento *", suffixIcon: Icon(Icons.calendar_today)),
                onTap: _selectDate,
                validator: (v) => _selectedDate == null ? "Escolha a data" : null,
              ),
              const SizedBox(height: 16),

              SwitchListTile(
                title: const Text("Possui deficiência?"),
                value: _temDeficiencia,
                onChanged: (val) => setState(() => _temDeficiencia = val),
                contentPadding: EdgeInsets.zero,
              ),
              if (_temDeficiencia)
                TextFormField(
                  controller: _tipoDeficienciaController,
                  decoration: const InputDecoration(labelText: "Tipo de deficiência"),
                ),
              const SizedBox(height: 16),

              TextFormField(
                controller: _informacoesController,
                maxLines: 3,
                decoration: const InputDecoration(labelText: "Informações adicionais"),
              ),
              const SizedBox(height: 16),

              TextFormField(
                controller: _roupasController,
                decoration: const InputDecoration(labelText: "Roupas que usava"),
              ),
              const SizedBox(height: 32),

              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _saveCaso,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blueAccent,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: const Text("Enviar para Aprovação", style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}