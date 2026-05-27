// screens/create_caso_dialog.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geocoding/geocoding.dart';

// ─── DADOS DE MUNICÍPIOS POR PROVÍNCIA ──────────────────
const Map<String, List<String>> _municipiosPorProvincia = {
  'Luanda': ['Belas', 'Cacuaco', 'Cazenga', 'Icolo e Bengo', 'Kilamba Kiaxi', 'Luanda', 'Maianga', 'Musseques', 'Quiçama', 'Rangel', 'Talatona', 'Viana'],
  'Benguela': ['Balombo', 'Baía Farta', 'Benguela', 'Bocoio', 'Caimbambo', 'Catumbela', 'Chongoroi', 'Cubal', 'Ganda', 'Lobito'],
  'Huambo': ['Bailundo', 'Caála', 'Catchiungo', 'Chicala-Cholohanga', 'Chinjenje', 'Ecunha', 'Huambo', 'Londuimbali', 'Longonjo', 'Mungo', 'Tchindjenje', 'Ukuma'],
  'Bié': ['Andulo', 'Camacupa', 'Catabola', 'Chitembo', 'Cuito', 'Cunhinga', 'Nharea'],
  'Cabinda': ['Belize', 'Buco-Zau', 'Cabinda', 'Cacongo'],
  'Cuando Cubango': ['Calai', 'Cuangar', 'Cuchi', 'Cuito Cuanavale', 'Dirico', 'Mavinga', 'Menongue', 'Nancova', 'Rivungo'],
  'Cuanza Norte': ['Ambaca', 'Bolongongo', 'Cagonzo', 'Cazengo', 'Golungo Alto', 'Gonguembo', 'Lucala', 'Quiculungo', 'Samba Caju'],
  'Cuanza Sul': ['Amboim', 'Cela', 'Conda', 'Ebo', 'Libolo', 'Mussende', 'Porto Amboim', 'Quibala', 'Quilenda', 'Seles', 'Sumbe'],
  'Cunene': ['Cahama', 'Cuanhama', 'Curoca', 'Namacunde', 'Ombadja'],
  'Huíla': ['Caconda', 'Cacula', 'Caluquembe', 'Chibia', 'Chicomba', 'Chipindo', 'Cuvango', 'Gambos', 'Humpata', 'Jamba', 'Lubango', 'Matala', 'Quilengues', 'Quipungo'],
  'Lunda Norte': ['Cambulo', 'Capenda-Camulemba', 'Caungula', 'Chitato', 'Cuango', 'Cuílo', 'Lubalo', 'Lucapa', 'Xá-Muteba'],
  'Lunda Sul': ['Cacolo', 'Dala', 'Muconda', 'Saurimo'],
  'Malanje': ['Cacuso', 'Calandula', 'Cambundi-Catembo', 'Cangandala', 'Caombo', 'Cuaba Nzoji', 'Cunda-Dia-Baze', 'Luquembo', 'Malanje', 'Marimba', 'Massango', 'Mucari', 'Quela', 'Quirima'],
  'Moxico': ['Alto Zambeze', 'Bundas', 'Camanongue', 'Léua', 'Luau', 'Luchazes', 'Luena', 'Lumeje'],
  'Namibe': ['Bibala', 'Camucuio', 'Moçâmedes', 'Tômbwa', 'Virei'],
  'Uíge': ['Alto Cauale', 'Ambuila', 'Bembe', 'Buengas', 'Bungo', 'Damba', 'Milunga', 'Mucaba', 'Negage', 'Puri', 'Quimbele', 'Quitexe', 'Sanza Pombo', 'Songo', 'Uíge', 'Zombo'],
  'Zaire': ['Cuimba', 'Mbanza Congo', 'Noqui', 'Nzeto', 'Soyo', 'Tomboco'],
  'Bengo': ['Ambriz', 'Bula Atumba', 'Dande', 'Dembos', 'Nambuangongo', 'Pango Aluquém'],
};

class CreateCasoDialog extends StatefulWidget {
  const CreateCasoDialog({super.key});

  @override
  State<CreateCasoDialog> createState() => _CreateCasoDialogState();
}

class _CreateCasoDialogState extends State<CreateCasoDialog> {
  final _formKey = GlobalKey<FormState>();
  final _pageCtrl = PageController();
  int _currentPage = 0;

  final _nomeController              = TextEditingController();
  final _idadeController             = TextEditingController();
  final _ultimoLocalController       = TextEditingController();
  final _informacoesController       = TextEditingController();
  final _roupasController            = TextEditingController();
  final _tipoDeficienciaController   = TextEditingController();
  final _enderecoSearchController    = TextEditingController();

  String? _selectedSexo;
  String? _selectedProvincia;
  String? _selectedMunicipio;
  DateTime? _selectedDate;
  bool _temDeficiencia = false;
  String? base64Image;

  GoogleMapController? _mapController;
  LatLng? _selectedPosition;
  String? _selectedAddress;

  List<Location> _searchResults       = [];
  List<Placemark> _searchPlacemarks   = [];
  bool _searching   = false;
  bool _showResults = false;

  final List<String> _sexos     = ['Masculino', 'Feminino'];
  final List<String> _provincias = _municipiosPorProvincia.keys.toList()..sort();

  List<String> get _municipios => _selectedProvincia != null
      ? (_municipiosPorProvincia[_selectedProvincia] ?? [])
      : [];

  // Coordenadas das províncias
  final Map<String, LatLng> _coordsProvincia = const {
    'Luanda':         LatLng(-8.8368,  13.2343),
    'Benguela':       LatLng(-12.5763, 13.4055),
    'Huambo':         LatLng(-12.776,  15.7388),
    'Bié':            LatLng(-12.3764, 17.0557),
    'Cabinda':        LatLng(-5.55,    12.2),
    'Cuando Cubango': LatLng(-16.93,   19.8),
    'Cuanza Norte':   LatLng(-9.2,     14.7),
    'Cuanza Sul':     LatLng(-10.9,    14.3),
    'Cunene':         LatLng(-16.9,    15.8),
    'Huíla':          LatLng(-14.92,   13.5),
    'Lunda Norte':    LatLng(-8.65,    20.4),
    'Lunda Sul':      LatLng(-10.0,    21.0),
    'Malanje':        LatLng(-9.54,    16.34),
    'Moxico':         LatLng(-11.86,   19.92),
    'Namibe':         LatLng(-15.1961, 12.1522),
    'Uíge':           LatLng(-7.61,    15.06),
    'Zaire':          LatLng(-6.1,     12.85),
    'Bengo':          LatLng(-8.45,    13.75),
  };

  static const CameraPosition _initialCamera = CameraPosition(
    target: LatLng(-8.8368, 13.2343),
    zoom: 12,
  );

  // ── MÉTODO SIMPLES PARA FORMATAR DATA SEM INTL ────────
  String _formatarData(DateTime data) {
    final meses = [
      'Janeiro', 'Fevereiro', 'Março', 'Abril', 'Maio', 'Junho',
      'Julho', 'Agosto', 'Setembro', 'Outubro', 'Novembro', 'Dezembro'
    ];
    return '${data.day} de ${meses[data.month - 1]} de ${data.year}';
  }

  String _formatarDataCurta(DateTime data) {
    final dia = data.day.toString().padLeft(2, '0');
    final mes = data.month.toString().padLeft(2, '0');
    return '$dia/$mes/${data.year}';
  }

  String _formatarDataParaFirestore(DateTime data) {
    final dia = data.day.toString().padLeft(2, '0');
    final mes = data.month.toString().padLeft(2, '0');
    return '${data.year}-$mes-$dia';
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    _nomeController.dispose();
    _idadeController.dispose();
    _ultimoLocalController.dispose();
    _informacoesController.dispose();
    _roupasController.dispose();
    _tipoDeficienciaController.dispose();
    _enderecoSearchController.dispose();
    super.dispose();
  }

  // ── Pesquisa de endereço melhorada para Angola ────────
  Future<void> _pesquisarEndereco(String query) async {
    if (query.trim().length < 3) {
      setState(() { _showResults = false; _searchResults = []; });
      return;
    }
    setState(() => _searching = true);

    try {
      final queries = [
        '$query, ${_selectedProvincia ?? 'Luanda'}, Angola',
        '$query, Angola',
        query,
      ];

      List<Location> locations = [];
      for (final q in queries) {
        try {
          locations = await locationFromAddress(q);
          if (locations.isNotEmpty) break;
        } catch (_) {}
      }

      final placemarks = <Placemark>[];
      for (final loc in locations.take(5)) {
        try {
          final marks = await placemarkFromCoordinates(loc.latitude, loc.longitude);
          placemarks.add(marks.isNotEmpty ? marks.first : const Placemark());
        } catch (_) {
          placemarks.add(const Placemark());
        }
      }

      setState(() {
        _searchResults    = locations.take(5).toList();
        _searchPlacemarks = placemarks;
        _showResults      = locations.isNotEmpty;
        _searching        = false;
      });
    } catch (e) {
      setState(() { _searching = false; _showResults = false; });
    }
  }

  Future<void> _seleccionarEndereco(int index) async {
    final loc   = _searchResults[index];
    final place = _searchPlacemarks[index];
    final pos   = LatLng(loc.latitude, loc.longitude);

    final parts = [place.thoroughfare, place.subLocality, place.locality, place.subAdministrativeArea]
        .where((s) => s != null && s.isNotEmpty).toSet().toList();
    final addr = parts.isNotEmpty
        ? parts.join(', ')
        : '${loc.latitude.toStringAsFixed(4)}, ${loc.longitude.toStringAsFixed(4)}';

    setState(() {
      _selectedPosition = pos;
      _selectedAddress  = addr;
      _ultimoLocalController.text    = addr;
      _enderecoSearchController.text = addr;
      _showResults = false;
    });

    await _mapController?.animateCamera(CameraUpdate.newLatLngZoom(pos, 16));
  }

  Future<void> _onMapTapped(LatLng position) async {
    setState(() => _selectedPosition = position);
    try {
      final placemarks = await placemarkFromCoordinates(position.latitude, position.longitude);
      if (placemarks.isNotEmpty) {
        final place = placemarks.first;
        final parts = [place.thoroughfare, place.subLocality, place.locality]
            .where((s) => s != null && s.isNotEmpty).toList();
        final addr = parts.isNotEmpty ? parts.join(', ') : 'Local marcado no mapa';
        setState(() {
          _selectedAddress = addr;
          _ultimoLocalController.text    = addr;
          _enderecoSearchController.text = addr;
        });
      }
    } catch (_) {}
  }

  void _onMapCreated(GoogleMapController controller) => _mapController = controller;

  void _onProvinciaChanged(String? prov) {
    setState(() {
      _selectedProvincia = prov;
      _selectedMunicipio = null;
    });
    if (prov != null && _coordsProvincia.containsKey(prov)) {
      _mapController?.animateCamera(CameraUpdate.newLatLngZoom(_coordsProvincia[prov]!, 10));
    }
  }

  Future<void> _pickImage() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 800, maxHeight: 800, imageQuality: 75);
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
      builder: (context, child) => Theme(
        data: ThemeData.dark().copyWith(
          colorScheme: const ColorScheme.dark(primary: Colors.blueAccent, surface: Color(0xFF1C1C22)),
        ),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _selectedDate = picked);
  }

  void _nextPage() {
    if (_currentPage == 0) {
      if (!_formKey.currentState!.validate()) return;
      if (_selectedProvincia == null) { _showSnack('Escolha a província', isError: true); return; }
      if (_selectedMunicipio == null) { _showSnack('Escolha o município', isError: true); return; }
    }
    if (_currentPage == 1) {
      if (_selectedDate == null) { 
        _showSnack('Escolha a data do desaparecimento', isError: true); 
        return; 
      }
      if (_selectedPosition == null && _ultimoLocalController.text.trim().isEmpty) {
        _showSnack('Indique o último local visto', isError: true);
        return;
      }
    }
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
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    if (_selectedDate == null) {
      _showSnack('Escolha a data do desaparecimento', isError: true);
      return;
    }

    try {
      await FirebaseFirestore.instance.collection('casos_pendentes').add({
        'autorEmail':             user.email,
        'userId':                 user.uid,
        'createdAt':              Timestamp.now(),
        'nome':                   _nomeController.text.trim(),
        'idade':                  int.tryParse(_idadeController.text.trim()) ?? 0,
        'sexo':                   _selectedSexo,
        'ultimo_local':           _ultimoLocalController.text.trim(),
        'municipio':              _selectedMunicipio ?? '',
        'provincia':              _selectedProvincia ?? '',
        'data_desaparecimento':   Timestamp.fromDate(_selectedDate!), // Correção: usar Timestamp
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
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

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
                  Icon(icons[i], size: 13, color: active ? Colors.blueAccent : done ? Colors.green : Colors.grey),
                  const SizedBox(width: 4),
                  Text(labels[i], style: TextStyle(fontSize: 11, fontWeight: active ? FontWeight.w700 : FontWeight.w400, color: active ? Colors.blueAccent : done ? Colors.green : Colors.grey)),
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
        decoration: BoxDecoration(color: const Color(0xFF1C1C22), borderRadius: BorderRadius.circular(20)),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 12, 12),
                child: Row(
                  children: [
                    const Icon(Icons.report_rounded, color: Colors.blueAccent, size: 22),
                    const SizedBox(width: 8),
                    const Text('Relatar Desaparecimento', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
                    const Spacer(),
                    IconButton(icon: const Icon(Icons.close_rounded, color: Colors.grey), onPressed: () => Navigator.pop(context)),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _buildPageIndicator(),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: PageView(
                  controller: _pageCtrl,
                  physics: const NeverScrollableScrollPhysics(),
                  children: [_buildPaginaPessoa(), _buildPaginaLocal(), _buildPaginaDetalhes()],
                ),
              ),
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
                          style: OutlinedButton.styleFrom(foregroundColor: Colors.grey, side: const BorderSide(color: Color(0xFF2A2A33)), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), padding: const EdgeInsets.symmetric(vertical: 14)),
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
          Center(
            child: GestureDetector(
              onTap: _pickImage,
              child: Stack(
                children: [
                  Container(
                    width: 110, height: 110,
                    decoration: BoxDecoration(color: const Color(0xFF141418), shape: BoxShape.circle, border: Border.all(color: Colors.blueAccent, width: 2)),
                    child: base64Image != null
                        ? ClipOval(child: Image.memory(base64Decode(base64Image!.split(',').last), fit: BoxFit.cover))
                        : const Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                            Icon(Icons.camera_alt_rounded, color: Colors.blueAccent, size: 28),
                            SizedBox(height: 4),
                            Text('Foto', style: TextStyle(color: Colors.blueAccent, fontSize: 12)),
                          ]),
                  ),
                  if (base64Image != null)
                    Positioned(
                      bottom: 0, right: 0,
                      child: Container(
                        width: 28, height: 28,
                        decoration: const BoxDecoration(color: Colors.blueAccent, shape: BoxShape.circle),
                        child: const Icon(Icons.edit_rounded, color: Colors.white, size: 14),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          const Center(child: Text('Toque para adicionar foto', style: TextStyle(color: Colors.grey, fontSize: 12))),
          const SizedBox(height: 20),

          _field(_nomeController, 'Nome completo *',
            validator: (v) {
              if (v == null || v.trim().isEmpty) return 'Nome é obrigatório';
              if (v.trim().length < 3) return 'Nome deve ter pelo menos 3 letras';
              return null;
            }),
          const SizedBox(height: 14),

          Row(children: [
            Expanded(
              child: TextFormField(
                controller: _idadeController,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                style: const TextStyle(color: Colors.white, fontSize: 14),
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Obrigatório';
                  final idade = int.tryParse(v);
                  if (idade == null) return 'Inválido';
                  if (idade <= 0) return 'Idade inválida';
                  if (idade > 120) return 'Idade inválida';
                  return null;
                },
                decoration: _inputDec('Idade *'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(child: _dropdown('Sexo *', _sexos, _selectedSexo, (v) => setState(() => _selectedSexo = v), validator: (v) => v == null ? 'Escolha' : null)),
          ]),
          const SizedBox(height: 14),

          _dropdown('Província *', _provincias, _selectedProvincia, _onProvinciaChanged,
            validator: (v) => v == null ? 'Escolha a província' : null),
          const SizedBox(height: 14),

          if (_selectedProvincia != null) ...[
            DropdownButtonFormField<String>(
              value: _selectedMunicipio,
              dropdownColor: const Color(0xFF1C1C22),
              style: const TextStyle(color: Colors.white, fontSize: 14),
              decoration: _inputDec('Município *'),
              validator: (v) => v == null ? 'Escolha o município' : null,
              items: _municipios.map((m) => DropdownMenuItem(value: m, child: Text(m))).toList(),
              onChanged: (v) => setState(() => _selectedMunicipio = v),
            ),
            const SizedBox(height: 14),
          ] else ...[
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF141418),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF2A2A33)),
              ),
              child: const Row(children: [
                Icon(Icons.info_outline_rounded, color: Colors.grey, size: 16),
                SizedBox(width: 8),
                Text('Escolha a província primeiro', style: TextStyle(color: Colors.grey, fontSize: 13)),
              ]),
            ),
            const SizedBox(height: 14),
          ],
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
          // Data - usando formato simples sem intl
          GestureDetector(
            onTap: _selectDate,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _selectedDate != null ? Colors.blueAccent.withOpacity(0.1) : const Color(0xFF141418),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _selectedDate != null ? Colors.blueAccent.withOpacity(0.5) : const Color(0xFF2A2A33)),
              ),
              child: Row(children: [
                Icon(Icons.calendar_today_rounded, color: _selectedDate != null ? Colors.blueAccent : Colors.grey, size: 20),
                const SizedBox(width: 12),
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Data do desaparecimento *', style: TextStyle(color: Colors.grey, fontSize: 11)),
                  const SizedBox(height: 2),
                  Text(
                    _selectedDate != null ? _formatarData(_selectedDate!) : 'Toque para seleccionar',
                    style: TextStyle(color: _selectedDate != null ? Colors.white : Colors.grey, fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                ]),
                const Spacer(),
                Icon(Icons.chevron_right_rounded, color: Colors.grey, size: 20),
              ]),
            ),
          ),
          const SizedBox(height: 16),

          const Text('Último local visto', style: TextStyle(color: Colors.grey, fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(color: const Color(0xFF141418), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFF2A2A33))),
            child: TextField(
              controller: _enderecoSearchController,
              style: const TextStyle(color: Colors.white, fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Ex: Talatona, Rua Principal...',
                hintStyle: const TextStyle(color: Colors.grey, fontSize: 14),
                prefixIcon: _searching
                    ? const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.blueAccent)))
                    : const Icon(Icons.search_rounded, color: Colors.grey, size: 20),
                suffixIcon: _enderecoSearchController.text.isNotEmpty
                    ? IconButton(icon: const Icon(Icons.close_rounded, color: Colors.grey, size: 18), onPressed: () { _enderecoSearchController.clear(); setState(() { _showResults = false; _searchResults = []; }); })
                    : null,
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              ),
              onChanged: (v) {
                if (v.length >= 3) {
                  Future.delayed(const Duration(milliseconds: 700), () {
                    if (_enderecoSearchController.text == v) _pesquisarEndereco(v);
                  });
                } else {
                  setState(() { _showResults = false; });
                }
              },
            ),
          ),

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
                  final nome = [place.thoroughfare, place.subLocality, place.locality]
                      .where((s) => s != null && s.isNotEmpty).toSet().join(', ');
                  final sub = [place.subAdministrativeArea, place.administrativeArea]
                      .where((s) => s != null && s.isNotEmpty).toSet().join(', ');
                  return InkWell(
                    onTap: () => _seleccionarEndereco(i),
                    borderRadius: BorderRadius.circular(12),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      child: Row(
                        children: [
                          Container(width: 36, height: 36, decoration: BoxDecoration(color: Colors.blueAccent.withOpacity(0.15), borderRadius: BorderRadius.circular(10)), child: const Icon(Icons.location_on_rounded, color: Colors.blueAccent, size: 18)),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(nome.isNotEmpty ? nome : 'Local', style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
                              if (sub.isNotEmpty) Text(sub, style: const TextStyle(color: Colors.grey, fontSize: 11)),
                            ]),
                          ),
                          const Icon(Icons.north_west_rounded, color: Colors.grey, size: 14),
                        ],
                      ),
                    ),
                  );
                }),
              ),
            ),

          const SizedBox(height: 12),

          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(color: Colors.blueAccent.withOpacity(0.1), borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.blueAccent.withOpacity(0.3))),
            child: const Row(children: [
              Icon(Icons.touch_app_rounded, color: Colors.blueAccent, size: 16),
              SizedBox(width: 8),
              Expanded(child: Text('Ou toque no mapa para marcar o local exacto', style: TextStyle(color: Colors.blueAccent, fontSize: 12))),
            ]),
          ),
          const SizedBox(height: 12),

          Container(
            height: 220,
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFF2A2A33))),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: GoogleMap(
                onMapCreated: _onMapCreated,
                initialCameraPosition: _initialCamera,
                onTap: _onMapTapped,
                markers: _selectedPosition != null
                    ? {Marker(markerId: const MarkerId('selected'), position: _selectedPosition!)}
                    : {},
                myLocationButtonEnabled: false,
                zoomControlsEnabled: true,
              ),
            ),
          ),

          if (_selectedAddress != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(color: Colors.green.withOpacity(0.1), borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.green.withOpacity(0.3))),
              child: Row(children: [
                const Icon(Icons.check_circle_rounded, color: Colors.green, size: 16),
                const SizedBox(width: 8),
                Expanded(child: Text(_selectedAddress!, style: const TextStyle(color: Colors.green, fontSize: 12))),
                GestureDetector(
                  onTap: () => setState(() { _selectedAddress = null; _selectedPosition = null; _enderecoSearchController.clear(); _ultimoLocalController.clear(); }),
                  child: const Icon(Icons.close_rounded, color: Colors.green, size: 16),
                ),
              ]),
            ),
          ],
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
          _field(_roupasController, 'Roupas que usava', hint: 'Ex: Camisa azul, calça jeans preta'),
          const SizedBox(height: 14),

          Container(
            decoration: BoxDecoration(color: const Color(0xFF141418), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFF2A2A33))),
            child: SwitchListTile(
              title: const Text('Possui deficiência?', style: TextStyle(color: Colors.white, fontSize: 14)),
              subtitle: const Text('Física, mental ou sensorial', style: TextStyle(color: Colors.grey, fontSize: 12)),
              value: _temDeficiencia,
              onChanged: (val) => setState(() => _temDeficiencia = val),
              activeColor: Colors.blueAccent,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
            ),
          ),

          if (_temDeficiencia) ...[
            const SizedBox(height: 10),
            _field(_tipoDeficienciaController, 'Descreva a deficiência', hint: 'Ex: Deficiência mental, não fala'),
          ],

          const SizedBox(height: 14),

          _field(_informacoesController, 'Informações adicionais',
            hint: 'Sinais físicos, cicatrizes, tatuagens, comportamento habitual...',
            maxLines: 4),

          const SizedBox(height: 20),

          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: Colors.blueAccent.withOpacity(0.08), borderRadius: BorderRadius.circular(14), border: Border.all(color: Colors.blueAccent.withOpacity(0.2))),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(children: [
                  Icon(Icons.summarize_rounded, color: Colors.blueAccent, size: 16),
                  SizedBox(width: 8),
                  Text('Resumo do relato', style: TextStyle(color: Colors.blueAccent, fontWeight: FontWeight.w700, fontSize: 13)),
                ]),
                const SizedBox(height: 12),
                _resumoItem(Icons.person_rounded,         _nomeController.text.isNotEmpty ? '${_nomeController.text}, ${_idadeController.text} anos' : '—'),
                _resumoItem(Icons.wc_rounded,             _selectedSexo ?? '—'),
                _resumoItem(Icons.map_rounded,            _selectedMunicipio != null && _selectedProvincia != null ? '$_selectedMunicipio, $_selectedProvincia' : '—'),
                _resumoItem(Icons.location_on_rounded,    _selectedAddress ?? (_ultimoLocalController.text.isNotEmpty ? _ultimoLocalController.text : '—')),
                _resumoItem(Icons.calendar_today_rounded, _selectedDate != null ? _formatarDataCurta(_selectedDate!) : '—'),
              ],
            ),
          ),

          const SizedBox(height: 12),

          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.orange.withOpacity(0.1), borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.orange.withOpacity(0.3))),
            child: const Row(children: [
              Icon(Icons.info_outline_rounded, color: Colors.orange, size: 16),
              SizedBox(width: 8),
              Expanded(child: Text('O caso será revisto pelo administrador antes de ser publicado.', style: TextStyle(color: Colors.orange, fontSize: 12))),
            ]),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _resumoItem(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(children: [
        Icon(icon, size: 14, color: Colors.blueAccent.withOpacity(0.7)),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: const TextStyle(color: Colors.grey, fontSize: 12), overflow: TextOverflow.ellipsis)),
      ]),
    );
  }

  InputDecoration _inputDec(String label, {String? hint}) {
    return InputDecoration(
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
    );
  }

  Widget _field(TextEditingController ctrl, String label, {String? hint, TextInputType? keyboardType, int maxLines = 1, String? Function(String?)? validator}) {
    return TextFormField(
      controller: ctrl,
      keyboardType: keyboardType,
      maxLines: maxLines,
      style: const TextStyle(color: Colors.white, fontSize: 14),
      validator: validator,
      decoration: _inputDec(label, hint: hint),
    );
  }

  Widget _dropdown(String label, List<String> items, String? value, void Function(String?) onChanged, {String? Function(String?)? validator}) {
    return DropdownButtonFormField<String>(
      value: value,
      dropdownColor: const Color(0xFF1C1C22),
      style: const TextStyle(color: Colors.white, fontSize: 14),
      decoration: _inputDec(label),
      validator: validator,
      items: items.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
      onChanged: onChanged,
    );
  }
}