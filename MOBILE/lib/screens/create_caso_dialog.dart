// screens/create_caso_dialog.dart
// Pesquisa de endereço por texto (igual ao iFood/Uber) + mapa interactivo

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geocoding/geocoding.dart';
import '../config.dart';

class CreateCasoDialog extends StatefulWidget {
  const CreateCasoDialog({super.key});

  @override
  State<CreateCasoDialog> createState() => _CreateCasoDialogState();
}

class _CreateCasoDialogState extends State<CreateCasoDialog> {
  final _formKey = GlobalKey<FormState>();
  final _pageCtrl = PageController();
  int _currentPage = 0;

  // Controllers
  final _nomeController          = TextEditingController();
  final _idadeController         = TextEditingController();
  final _ultimoLocalController   = TextEditingController();
  final _municipioController     = TextEditingController();
  final _informacoesController   = TextEditingController();
  final _roupasController        = TextEditingController();
  final _tipoDeficienciaController = TextEditingController();
  final _enderecoSearchController  = TextEditingController(); // ← pesquisa de endereço

  String? _selectedSexo;
  String? _selectedProvincia;
  DateTime? _selectedDate;
  bool _temDeficiencia = false;
  String? base64Image;

  // Mapa
  GoogleMapController? _mapController;
  LatLng? _selectedPosition;
  String? _selectedAddress;

  // Pesquisa de endereço
  List<Location> _searchResults = [];
  List<Placemark> _searchPlacemarks = [];
  bool _searching = false;
  bool _showResults = false;

  final List<String> _sexos = ['Masculino', 'Feminino'];
  final List<String> _provincias = [
    'Bengo', 'Benguela', 'Bié', 'Cabinda', 'Cuando Cubango',
    'Cuanza Norte', 'Cuanza Sul', 'Cunene', 'Huambo', 'Huíla',
    'Luanda', 'Lunda Norte', 'Lunda Sul', 'Malanje', 'Moxico',
    'Namibe', 'Uíge', 'Zaire'
  ];

  // Coordenadas das províncias para centrar o mapa
  final Map<String, LatLng> _coordsProvincia = {
    'Luanda':         const LatLng(-8.8368,  13.2343),
    'Benguela':       const LatLng(-12.5763, 13.4055),
    'Huambo':         const LatLng(-12.776,  15.7388),
    'Bié':            const LatLng(-12.3764, 17.0557),
    'Cabinda':        const LatLng(-5.55,    12.2),
    'Cuando Cubango': const LatLng(-16.93,   19.8),
    'Cuanza Norte':   const LatLng(-9.2,     14.7),
    'Cuanza Sul':     const LatLng(-10.9,    14.3),
    'Cunene':         const LatLng(-16.9,    15.8),
    'Huíla':          const LatLng(-14.92,   13.5),
    'Lunda Norte':    const LatLng(-8.65,    20.4),
    'Lunda Sul':      const LatLng(-10.0,    21.0),
    'Malanje':        const LatLng(-9.54,    16.34),
    'Moxico':         const LatLng(-11.86,   19.92),
    'Namibe':         const LatLng(-15.1961, 12.1522),
    'Uíge':           const LatLng(-7.61,    15.06),
    'Zaire':          const LatLng(-6.1,     12.85),
    'Bengo':          const LatLng(-8.45,    13.75),
  };

  static const CameraPosition _initialCamera = CameraPosition(
    target: LatLng(-8.8368, 13.2343),
    zoom: 12,
  );

  @override
  void dispose() {
    _pageCtrl.dispose();
    _nomeController.dispose();
    _idadeController.dispose();
    _ultimoLocalController.dispose();
    _municipioController.dispose();
    _informacoesController.dispose();
    _roupasController.dispose();
    _tipoDeficienciaController.dispose();
    _enderecoSearchController.dispose();
    super.dispose();
  }

  // ── Pesquisa de endereço por texto (igual ao iFood) ──
  Future<void> _pesquisarEndereco(String query) async {
    if (query.trim().length < 3) {
      setState(() { _showResults = false; _searchResults = []; });
      return;
    }

    setState(() => _searching = true);

    try {
      // Adiciona Angola ao query para resultados mais precisos
      final locations = await locationFromAddress('$query, Angola');
      final placemarks = <Placemark>[];

      for (final loc in locations.take(5)) {
        final marks = await placemarkFromCoordinates(loc.latitude, loc.longitude);
        if (marks.isNotEmpty) placemarks.add(marks.first);
        else placemarks.add(const Placemark());
      }

      setState(() {
        _searchResults  = locations.take(5).toList();
        _searchPlacemarks = placemarks;
        _showResults    = locations.isNotEmpty;
        _searching      = false;
      });
    } catch (e) {
      setState(() { _searching = false; _showResults = false; });
    }
  }

  // ── Seleccionar resultado da pesquisa ──
  Future<void> _seleccionarEndereco(int index) async {
    final loc   = _searchResults[index];
    final place = _searchPlacemarks[index];
    final pos   = LatLng(loc.latitude, loc.longitude);

    final addr = [
      place.thoroughfare,
      place.subLocality,
      place.locality,
    ].where((s) => s != null && s.isNotEmpty).join(', ');

    setState(() {
      _selectedPosition = pos;
      _selectedAddress  = addr.isNotEmpty ? addr : '${loc.latitude.toStringAsFixed(4)}, ${loc.longitude.toStringAsFixed(4)}';
      _ultimoLocalController.text = _selectedAddress!;
      _enderecoSearchController.text = _selectedAddress!;
      _showResults = false;
    });

    // Mover câmara do mapa para o local seleccionado
    if (_mapController != null) {
      await _mapController!.animateCamera(CameraUpdate.newLatLngZoom(pos, 16));
    }
  }

  // ── Toque no mapa ──
  Future<void> _onMapTapped(LatLng position) async {
    setState(() => _selectedPosition = position);

    try {
      final placemarks = await placemarkFromCoordinates(position.latitude, position.longitude);
      if (placemarks.isNotEmpty) {
        final place = placemarks.first;
        final addr = [
          place.thoroughfare,
          place.subLocality,
          place.locality,
        ].where((s) => s != null && s.isNotEmpty).join(', ');

        setState(() {
          _selectedAddress = addr.isNotEmpty ? addr : 'Local marcado';
          _ultimoLocalController.text = _selectedAddress!;
          _enderecoSearchController.text = _selectedAddress!;
        });
      }
    } catch (e) {
      debugPrint('Erro geocoding: $e');
    }
  }

  void _onMapCreated(GoogleMapController controller) {
    _mapController = controller;
  }

  // ── Quando a província muda, centrar o mapa ──
  void _onProvinciaChanged(String? prov) {
    setState(() => _selectedProvincia = prov);
    if (prov != null && _coordsProvincia.containsKey(prov)) {
      _mapController?.animateCamera(
        CameraUpdate.newLatLngZoom(_coordsProvincia[prov]!, 11),
      );
    }
  }

  Future<void> _pickImage() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 800, maxHeight: 800, imageQuality: 75,
    );
    if (picked != null) {
      final bytes = await picked.readAsBytes();
      setState(() => base64Image = 'data:image/jpeg;base64,${base64Encode(bytes)}');
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

  void _nextPage() {
    if (_currentPage < 2) {
      _pageCtrl.nextPage(duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
      setState(() => _currentPage++);
    }
  }

  void _prevPage() {
    if (_currentPage > 0) {
      _pageCtrl.previousPage(duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
      setState(() => _currentPage--);
    }
  }

  Future<void> _saveCaso() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedProvincia == null) {
      _showSnack('Escolha a província', isError: true); return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      await FirebaseFirestore.instance.collection('casos_pendentes').add({
        'autorEmail':             user.email,
        'userId':                 user.uid,
        'createdAt':              Timestamp.now(),
        'nome':                   _nomeController.text.trim(),
        'idade':                  int.tryParse(_idadeController.text.trim()) ?? 0,
        'sexo':                   _selectedSexo,
        'ultimo_local':           _ultimoLocalController.text.trim(),
        'municipio':              _municipioController.text.trim(),
        'provincia':              _selectedProvincia,
        'data_desaparecimento':   _selectedDate != null ? DateFormat('yyyy-MM-dd').format(_selectedDate!) : '',
        'informacoes_adicionais': _informacoesController.text.trim(),
        'roupas':                 _roupasController.text.trim(),
        'deficiencia':            _temDeficiencia ? 'Sim' : 'Não',
        'tipo_deficiencia':       _temDeficiencia ? _tipoDeficienciaController.text.trim() : '',
        'imagem':                 base64Image,
        'status':                 'pendente',
        'lat':                    _selectedPosition?.latitude,
        'lng':                    _selectedPosition?.longitude,
        'apoios':                 0,
        'apoiadoPor':             [],
        'comentarios':            0,
      });

      if (mounted) {
        Navigator.pop(context);
        _showSnack('Caso enviado para aprovação! ✅');
      }
    } catch (e) {
      _showSnack('Erro ao enviar: $e', isError: true);
    }
  }

  void _showSnack(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? Colors.red : Colors.green,
    ));
  }

  // ── Indicador de páginas ──
  Widget _buildPageIndicator() {
    final labels = ['Pessoa', 'Local', 'Detalhes'];
    final icons  = [Icons.person_rounded, Icons.location_on_rounded, Icons.info_rounded];
    return Row(
      children: List.generate(3, (i) {
        final active = i == _currentPage;
        final done   = i < _currentPage;
        return Expanded(
          child: GestureDetector(
            onTap: () {
              _pageCtrl.animateToPage(i, duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
              setState(() => _currentPage = i);
            },
            child: Column(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  height: 3,
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  decoration: BoxDecoration(
                    color: active ? Colors.blueAccent : done ? Colors.green : Colors.grey.shade700,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 6),
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(icons[i], size: 13,
                    color: active ? Colors.blueAccent : done ? Colors.green : Colors.grey),
                  const SizedBox(width: 4),
                  Text(labels[i], style: TextStyle(
                    fontSize: 11,
                    fontWeight: active ? FontWeight.w700 : FontWeight.w400,
                    color: active ? Colors.blueAccent : done ? Colors.green : Colors.grey,
                  )),
                ]),
              ],
            ),
          ),
        );
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.all(12),
      child: Container(
        height: MediaQuery.of(context).size.height * 0.92,
        decoration: BoxDecoration(
          color: const Color(0xFF1C1C22),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              // ── Header ──
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 12, 12),
                child: Row(
                  children: [
                    const Icon(Icons.report_rounded, color: Colors.blueAccent, size: 22),
                    const SizedBox(width: 8),
                    const Text('Relatar Desaparecimento',
                      style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, color: Colors.grey),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),

              // ── Indicador de páginas ──
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _buildPageIndicator(),
              ),

              const SizedBox(height: 12),

              // ── Conteúdo paginado ──
              Expanded(
                child: PageView(
                  controller: _pageCtrl,
                  physics: const NeverScrollableScrollPhysics(),
                  children: [
                    _buildPaginaPessoa(),
                    _buildPaginaLocal(),
                    _buildPaginaDetalhes(),
                  ],
                ),
              ),

              // ── Botões de navegação ──
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                child: Row(
                  children: [
                    if (_currentPage > 0)
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _prevPage,
                          icon: const Icon(Icons.arrow_back_rounded, size: 16),
                          label: const Text('Anterior'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.grey,
                            side: const BorderSide(color: Color(0xFF2A2A33)),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                        ),
                      ),
                    if (_currentPage > 0) const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton.icon(
                        onPressed: _currentPage < 2 ? _nextPage : _saveCaso,
                        icon: Icon(_currentPage < 2 ? Icons.arrow_forward_rounded : Icons.send_rounded, size: 16),
                        label: Text(_currentPage < 2 ? 'Próximo' : 'Enviar para Aprovação'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _currentPage < 2 ? Colors.blueAccent : Colors.green,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          elevation: 0,
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
    );
  }

  // ── PÁGINA 1: Pessoa ──────────────────────────────────
  Widget _buildPaginaPessoa() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Foto
          Center(
            child: GestureDetector(
              onTap: _pickImage,
              child: Container(
                width: 110, height: 110,
                decoration: BoxDecoration(
                  color: const Color(0xFF141418),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.blueAccent, width: 2),
                ),
                child: base64Image != null
                    ? ClipOval(child: Image.memory(base64Decode(base64Image!.split(',').last), fit: BoxFit.cover))
                    : const Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Icon(Icons.camera_alt_rounded, color: Colors.blueAccent, size: 28),
                        SizedBox(height: 4),
                        Text('Foto', style: TextStyle(color: Colors.blueAccent, fontSize: 12)),
                      ]),
              ),
            ),
          ),
          const SizedBox(height: 20),

          _field(_nomeController, 'Nome completo *', validator: (v) => v!.isEmpty ? 'Obrigatório' : null),
          const SizedBox(height: 14),

          Row(children: [
            Expanded(child: _field(_idadeController, 'Idade *',
              keyboardType: TextInputType.number,
              validator: (v) => v!.isEmpty ? 'Obrigatório' : null)),
            const SizedBox(width: 12),
            Expanded(child: _dropdown('Sexo *', _sexos, _selectedSexo,
              (v) => setState(() => _selectedSexo = v),
              validator: (v) => v == null ? 'Escolha' : null)),
          ]),
          const SizedBox(height: 14),

          _dropdown('Província *', _provincias, _selectedProvincia,
            _onProvinciaChanged,
            validator: (v) => v == null ? 'Escolha a província' : null),
          const SizedBox(height: 14),

          _field(_municipioController, 'Município'),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  // ── PÁGINA 2: Local ───────────────────────────────────
  Widget _buildPaginaLocal() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── CAMPO DE PESQUISA (estilo iFood/Uber) ──
          const Text('Pesquisar endereço',
            style: TextStyle(color: Colors.grey, fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),

          // Campo de pesquisa
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFF141418),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF2A2A33)),
            ),
            child: TextField(
              controller: _enderecoSearchController,
              style: const TextStyle(color: Colors.white, fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Ex: Talatona, Rua da Samba...',
                hintStyle: const TextStyle(color: Colors.grey, fontSize: 14),
                prefixIcon: _searching
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(width: 16, height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.blueAccent)),
                      )
                    : const Icon(Icons.search_rounded, color: Colors.grey, size: 20),
                suffixIcon: _enderecoSearchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.close_rounded, color: Colors.grey, size: 18),
                        onPressed: () {
                          _enderecoSearchController.clear();
                          setState(() { _showResults = false; _searchResults = []; });
                        },
                      )
                    : null,
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              ),
              onChanged: (v) {
                if (v.length >= 3) {
                  Future.delayed(const Duration(milliseconds: 600), () {
                    if (_enderecoSearchController.text == v) _pesquisarEndereco(v);
                  });
                } else {
                  setState(() { _showResults = false; });
                }
              },
            ),
          ),

          // ── Lista de resultados (dropdown estilo iFood) ──
          if (_showResults && _searchResults.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(top: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF1C1C22),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF2A2A33)),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 10)],
              ),
              child: Column(
                children: List.generate(_searchResults.length, (i) {
                  final place = _searchPlacemarks[i];
                  final nome  = [place.thoroughfare, place.subLocality, place.locality]
                      .where((s) => s != null && s.isNotEmpty).join(', ');
                  final sub   = [place.administrativeArea, place.country]
                      .where((s) => s != null && s.isNotEmpty).join(', ');
                  return InkWell(
                    onTap: () => _seleccionarEndereco(i),
                    borderRadius: BorderRadius.circular(12),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      child: Row(
                        children: [
                          Container(
                            width: 36, height: 36,
                            decoration: BoxDecoration(
                              color: Colors.blueAccent.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(Icons.location_on_rounded, color: Colors.blueAccent, size: 18),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(nome.isNotEmpty ? nome : 'Local desconhecido',
                                  style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
                                if (sub.isNotEmpty)
                                  Text(sub, style: const TextStyle(color: Colors.grey, fontSize: 11)),
                              ],
                            ),
                          ),
                          const Icon(Icons.north_west_rounded, color: Colors.grey, size: 14),
                        ],
                      ),
                    ),
                  );
                }),
              ),
            ),

          const SizedBox(height: 16),

          // ── Instrução do mapa ──
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.blueAccent.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.blueAccent.withOpacity(0.3)),
            ),
            child: const Row(children: [
              Icon(Icons.touch_app_rounded, color: Colors.blueAccent, size: 16),
              SizedBox(width: 8),
              Expanded(child: Text('Ou toque no mapa para marcar o local exacto',
                style: TextStyle(color: Colors.blueAccent, fontSize: 12))),
            ]),
          ),

          const SizedBox(height: 12),

          // ── MAPA ──
          Container(
            height: 240,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFF2A2A33)),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: GoogleMap(
                onMapCreated: _onMapCreated,
                initialCameraPosition: _initialCamera,
                onTap: _onMapTapped,
                markers: _selectedPosition != null
                    ? { Marker(markerId: const MarkerId('selected'), position: _selectedPosition!) }
                    : {},
                myLocationButtonEnabled: false,
                zoomControlsEnabled: true,
              ),
            ),
          ),

          // ── Local seleccionado ──
          if (_selectedAddress != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.green.withOpacity(0.3)),
              ),
              child: Row(children: [
                const Icon(Icons.check_circle_rounded, color: Colors.green, size: 16),
                const SizedBox(width: 8),
                Expanded(child: Text(_selectedAddress!,
                  style: const TextStyle(color: Colors.green, fontSize: 12))),
                GestureDetector(
                  onTap: () => setState(() {
                    _selectedAddress  = null;
                    _selectedPosition = null;
                    _enderecoSearchController.clear();
                    _ultimoLocalController.clear();
                  }),
                  child: const Icon(Icons.close_rounded, color: Colors.green, size: 16),
                ),
              ]),
            ),
          ],

          const SizedBox(height: 14),

          // ── Data ──
          GestureDetector(
            onTap: _selectDate,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: const Color(0xFF141418),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF2A2A33)),
              ),
              child: Row(children: [
                const Icon(Icons.calendar_today_rounded, color: Colors.grey, size: 18),
                const SizedBox(width: 12),
                Text(
                  _selectedDate != null
                      ? DateFormat('dd/MM/yyyy').format(_selectedDate!)
                      : 'Data do desaparecimento *',
                  style: TextStyle(
                    color: _selectedDate != null ? Colors.white : Colors.grey,
                    fontSize: 14,
                  ),
                ),
              ]),
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  // ── PÁGINA 3: Detalhes ────────────────────────────────
  Widget _buildPaginaDetalhes() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _field(_roupasController, 'Roupas que usava', hint: 'Ex: Camisa azul e calça jeans'),
          const SizedBox(height: 14),

          // Deficiência
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFF141418),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF2A2A33)),
            ),
            child: SwitchListTile(
              title: const Text('Possui deficiência?', style: TextStyle(color: Colors.white, fontSize: 14)),
              value: _temDeficiencia,
              onChanged: (val) => setState(() => _temDeficiencia = val),
              activeColor: Colors.blueAccent,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
            ),
          ),

          if (_temDeficiencia) ...[
            const SizedBox(height: 10),
            _field(_tipoDeficienciaController, 'Tipo de deficiência', hint: 'Descreva a deficiência'),
          ],

          const SizedBox(height: 14),

          _field(_informacoesController, 'Informações adicionais',
            hint: 'Outras informações úteis...',
            maxLines: 4),

          const SizedBox(height: 20),

          // Resumo antes de enviar
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.blueAccent.withOpacity(0.08),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.blueAccent.withOpacity(0.2)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(children: [
                  Icon(Icons.summarize_rounded, color: Colors.blueAccent, size: 16),
                  SizedBox(width: 8),
                  Text('Resumo', style: TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.w700, fontSize: 13)),
                ]),
                const SizedBox(height: 10),
                _resumoItem(Icons.person_rounded,       _nomeController.text.isNotEmpty ? _nomeController.text : '—'),
                _resumoItem(Icons.location_on_rounded, _selectedAddress ?? (_ultimoLocalController.text.isNotEmpty ? _ultimoLocalController.text : '—')),
                _resumoItem(Icons.map_rounded,          _selectedProvincia ?? '—'),
                _resumoItem(Icons.calendar_today_rounded, _selectedDate != null ? DateFormat('dd/MM/yyyy').format(_selectedDate!) : '—'),
              ],
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _resumoItem(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(children: [
        Icon(icon, size: 13, color: Colors.grey),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: const TextStyle(color: Colors.grey, fontSize: 12), overflow: TextOverflow.ellipsis)),
      ]),
    );
  }

  // ── Helpers de UI ─────────────────────────────────────
  Widget _field(TextEditingController ctrl, String label, {
    String? hint,
    TextInputType? keyboardType,
    int maxLines = 1,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: ctrl,
      keyboardType: keyboardType,
      maxLines: maxLines,
      style: const TextStyle(color: Colors.white, fontSize: 14),
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: const TextStyle(color: Colors.grey, fontSize: 13),
        hintStyle: const TextStyle(color: Colors.grey, fontSize: 13),
        filled: true,
        fillColor: const Color(0xFF141418),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF2A2A33))),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF2A2A33))),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.blueAccent)),
        errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.red)),
      ),
    );
  }

  Widget _dropdown(String label, List<String> items, String? value, void Function(String?) onChanged, {String? Function(String?)? validator}) {
    return DropdownButtonFormField<String>(
      value: value,
      dropdownColor: const Color(0xFF1C1C22),
      style: const TextStyle(color: Colors.white, fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.grey, fontSize: 13),
        filled: true,
        fillColor: const Color(0xFF141418),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF2A2A33))),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF2A2A33))),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.blueAccent)),
      ),
      validator: validator,
      items: items.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
      onChanged: onChanged,
    );
  }
}