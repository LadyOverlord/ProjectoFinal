// screens/map_page.dart

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// ─── PALETA ─────────────────────────────────────────────
class _C {
  static const bg      = Color(0xFF0D0D0F);
  static const surface = Color(0xFF141418);
  static const card    = Color(0xFF1C1C22);
  static const border  = Color(0xFF2A2A33);
  static const accent  = Color(0xFF4F7EFF);
  static const green   = Color(0xFF22C55E);
  static const red     = Color(0xFFEF4444);
  static const grey2   = Color(0xFFA1A1AA);
  static const grey3   = Color(0xFF52525B);
  static const grey4   = Color(0xFF3F3F46);
  static const white   = Color(0xFFFFFFFF);
}

// ─── COORDENADAS POR PROVÍNCIA 
const _coordsProvincia = {
  'luanda':         LatLng(-8.8368,  13.2343),
  'benguela':       LatLng(-12.5763, 13.4055),
  'huambo':         LatLng(-12.776,  15.7388),
  'bié':            LatLng(-12.3764, 17.0557),
  'cabinda':        LatLng(-5.55,    12.2),
  'cuando cubango': LatLng(-16.93,   19.8),
  'cuanza norte':   LatLng(-9.2,     14.7),
  'cuanza sul':     LatLng(-10.9,    14.3),
  'cunene':         LatLng(-16.9,    15.8),
  'huíla':          LatLng(-14.92,   13.5),
  'lunda norte':    LatLng(-8.65,    20.4),
  'lunda sul':      LatLng(-10.0,    21.0),
  'malanje':        LatLng(-9.54,    16.34),
  'moxico':         LatLng(-11.86,   19.92),
  'namibe':         LatLng(-15.1961, 12.1522),
  'uíge':           LatLng(-7.61,    15.06),
  'zaire':          LatLng(-6.1,     12.85),
  'bengo':          LatLng(-8.45,    13.75),
};

class MapPage extends StatefulWidget {
  const MapPage({super.key, this.casoId});

  /// Se preenchido, o mapa centra-se neste caso ao abrir e mostra o seu InfoCard.
  final String? casoId;

  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  final Completer<GoogleMapController> _controller = Completer();

  List<Map<String, dynamic>> _todosOsCasos = [];
  List<Map<String, dynamic>> _casosFiltrados = [];
  Set<Marker> _markers = {};

  // Filtros activos
  String _filtroStatus    = '';
  String _filtroProvincia = '';

  bool _loading = true;
  Map<String, dynamic>? _selectedCaso; // caso com InfoWindow aberto

  // Camera inicial — Angola centrada
  static const CameraPosition _angola = CameraPosition(
    target: LatLng(-11.2027, 17.8739),
    zoom: 5.5,
  );

  @override
  void initState() {
    super.initState();
    _carregarCasos();
  }

  // ── Carregar casos do Firestore ───────────────────────
  Future<void> _carregarCasos() async {
    try {
      final snap = await FirebaseFirestore.instance.collection('casos').get();
      final lista = <Map<String, dynamic>>[];
      for (final d in snap.docs) {
        final data = {...d.data(), 'id': d.id};
        final status = data['status'] as String? ?? '';
        if (status != 'pendente' && status != 'rejeitado' && status.isNotEmpty) {
          lista.add(data);
        }
      }
      setState(() {
        _todosOsCasos    = lista;
        _casosFiltrados  = lista;
        _loading = false;
      });
      await _criarMarcadores(lista);

      // ── Se veio um casoId específico (ex: a partir do card), foca nele ──
      if (widget.casoId != null) {
        await _focarNoCaso(widget.casoId!);
      }
    } catch (e) {
      setState(() => _loading = false);
      debugPrint('Erro ao carregar casos para o mapa: $e');
    }
  }

  // ── Centra a câmara no caso indicado e abre o seu InfoCard ────────────
  Future<void> _focarNoCaso(String casoId) async {
    final caso = _todosOsCasos.firstWhere(
      (c) => c['id'] == casoId,
      orElse: () => {},
    );
    if (caso.isEmpty) return;

    final pos = _resolverCoordenadas(caso);
    if (pos == null) return;

    setState(() => _selectedCaso = caso);

    try {
      final ctrl = await _controller.future;
      await ctrl.animateCamera(CameraUpdate.newLatLngZoom(pos, 15));
    } catch (e) {
      debugPrint('Erro ao focar no caso: $e');
    }
  }

  // ── Criar marcadores ──────────────────────────────────
  Future<void> _criarMarcadores(List<Map<String, dynamic>> lista) async {
    final novosMarcadores = <Marker>{};

    for (final caso in lista) {
      final pos = _resolverCoordenadas(caso);
      if (pos == null) continue;

      final status = caso['status'] as String? ?? 'aprovado';
      final markerColor = _corMarker(status);

      // Criar ícone personalizado com cor por status
      final BitmapDescriptor icone = await _criarIconeCircular(markerColor);

      final marker = Marker(
        markerId: MarkerId(caso['id'] as String),
        position: pos,
        icon: icone,
        onTap: () => setState(() => _selectedCaso = caso),
      );

      novosMarcadores.add(marker);
    }

    setState(() => _markers = novosMarcadores);
  }

  // Resolve coordenadas do caso — usa lat/lng do documento ou fallback por província
  LatLng? _resolverCoordenadas(Map<String, dynamic> caso) {
    final latRaw = caso['lat'];
    final lngRaw = caso['lng'];

    if (latRaw != null && lngRaw != null) {
      final lat = double.tryParse(latRaw.toString());
      final lng = double.tryParse(lngRaw.toString());
      if (lat != null && lng != null) return LatLng(lat, lng);
    }

    // Fallback por província (com dispersão aleatória pequena)
    final prov = (caso['provincia'] as String? ?? '').toLowerCase();
    final coords = _coordsProvincia[prov];
    if (coords == null) return null;

    // Dispersão ±0.15 graus para não sobrepor marcadores
    final seed = (caso['id'] as String).hashCode;
    final offsetLat = ((seed % 30) - 15) * 0.01;
    final offsetLng = (((seed ~/ 30) % 30) - 15) * 0.01;
    return LatLng(coords.latitude + offsetLat, coords.longitude + offsetLng);
  }

  // Cor do marcador por status (equivalente ao corStatus do web)
  Color _corMarker(String status) {
    switch (status) {
      case 'encontrado': return _C.green;
      case 'desmentido': return _C.grey3;
      default:           return _C.accent; // aprovado / ativo
    }
  }

  // Cria um BitmapDescriptor com círculo colorido
  Future<BitmapDescriptor> _criarIconeCircular(Color color) async {
    final recorder = ui.PictureRecorder();
    final canvas   = Canvas(recorder);
    const size     = 28.0;
    final paint    = Paint()..color = color..style = PaintingStyle.fill;
    final paintBorder = Paint()..color = Colors.white..style = PaintingStyle.stroke..strokeWidth = 3;

    canvas.drawCircle(const Offset(size / 2, size / 2), size / 2 - 2, paint);
    canvas.drawCircle(const Offset(size / 2, size / 2), size / 2 - 2, paintBorder);

    final picture = recorder.endRecording();
    final img     = await picture.toImage(size.toInt(), size.toInt());
    final data    = await img.toByteData(format: ui.ImageByteFormat.png);
    return BitmapDescriptor.fromBytes(data!.buffer.asUint8List());
  }

  // ── Aplicar filtros ───────────────────────────────────
  void _aplicarFiltros() {
    final filtrados = _todosOsCasos.where((caso) {
      if (_filtroStatus.isNotEmpty) {
        final s = caso['status'] as String? ?? '';
        if (_filtroStatus == 'ativo' && s != 'aprovado') return false;
        if (_filtroStatus == 'encontrado' && s != 'encontrado') return false;
        if (_filtroStatus == 'desmentido' && s != 'desmentido') return false;
      }
      if (_filtroProvincia.isNotEmpty) {
        final p = (caso['provincia'] as String? ?? '').toLowerCase();
        if (p != _filtroProvincia.toLowerCase()) return false;
      }
      return true;
    }).toList();

    setState(() {
      _casosFiltrados = filtrados;
      _selectedCaso   = null;
    });
    _criarMarcadores(filtrados);
  }

  void _limparFiltros() {
    setState(() {
      _filtroStatus    = '';
      _filtroProvincia = '';
      _casosFiltrados  = _todosOsCasos;
      _selectedCaso    = null;
    });
    _criarMarcadores(_todosOsCasos);
  }

  // ── Calcular dias desaparecido ────────────────────────
  // CORRIGIDO: trata Timestamp (Firestore) E String (fallback) —
  // antes fazia `as String?` directo e crashava com
  // "type 'Timestamp' is not a subtype of type 'String?'"
  String _diasAgo(Map<String, dynamic> caso) {
    final raw = caso['data_desaparecimento'];
    if (raw == null) return '';

    DateTime? dt;
    if (raw is Timestamp) {
      dt = raw.toDate();
    } else if (raw is String) {
      dt = DateTime.tryParse(raw);
    }

    if (dt == null) return '';
    final diff = DateTime.now().difference(dt).inDays;
    return diff == 0 ? 'Hoje' : 'Há $diff dias';
  }

  // ─────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _C.bg,
      body: Stack(
        children: [
          // ── MAPA ──
          GoogleMap(
            initialCameraPosition: _angola,
            onMapCreated: (ctrl) => _controller.complete(ctrl),
            markers: _markers,
            onTap: (_) => setState(() => _selectedCaso = null),
            mapToolbarEnabled: false,
            zoomControlsEnabled: false,
            myLocationButtonEnabled: false,
            buildingsEnabled: false,
          ),

          // ── TOPBAR ──
          Positioned(
            top: 0, left: 0, right: 0,
            child: SafeArea(
              child: Container(
                margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: _C.surface.withOpacity(0.95),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: _C.border),
                ),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back_ios_rounded, color: _C.white, size: 18),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: () => Navigator.pop(context),
                    ),
                    const SizedBox(width: 8),
                    const Icon(Icons.location_on_rounded, color: _C.accent, size: 18),
                    const SizedBox(width: 8),
                    const Text('Mapa de Casos', style: TextStyle(color: _C.white, fontWeight: FontWeight.w700, fontSize: 15)),
                    const Spacer(),
                    // Contador
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: _C.accent.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: _C.accent.withOpacity(0.4)),
                      ),
                      child: Text(
                        '${_casosFiltrados.length} caso${_casosFiltrados.length != 1 ? 's' : ''}',
                        style: const TextStyle(color: _C.accent, fontSize: 11, fontWeight: FontWeight.w700),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Botão filtros
                    GestureDetector(
                      onTap: _mostrarPainelFiltros,
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: (_filtroStatus.isNotEmpty || _filtroProvincia.isNotEmpty) ? _C.accent : _C.card,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: _C.border),
                        ),
                        child: Icon(Icons.tune_rounded, color: _C.white, size: 16),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // ── LOADING ──
          if (_loading)
            Container(
              color: _C.bg.withOpacity(0.7),
              child: const Center(child: CircularProgressIndicator(color: _C.accent)),
            ),

          // ── INFO CARD (quando um marcador é tocado) ──
          if (_selectedCaso != null)
            Positioned(
              bottom: 20, left: 12, right: 12,
              child: _InfoCard(
                caso: _selectedCaso!,
                diasAgo: _diasAgo(_selectedCaso!),
                onClose: () => setState(() => _selectedCaso = null),
              ),
            ),

          // ── LEGENDA ──
          Positioned(
            bottom: _selectedCaso != null ? 170 : 20,
            right: 12,
            child: _buildLegenda(),
          ),
        ],
      ),
    );
  }

  Widget _buildLegenda() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: _C.surface.withOpacity(0.95),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _C.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _legendaItem(_C.accent, 'Ativo'),
          const SizedBox(height: 6),
          _legendaItem(_C.green,  'Encontrado'),
          const SizedBox(height: 6),
          _legendaItem(_C.grey3,  'Desmentido'),
        ],
      ),
    );
  }

  Widget _legendaItem(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(color: _C.grey2, fontSize: 11)),
      ],
    );
  }

  // ── Painel de filtros (bottom sheet) ─────────────────
  void _mostrarPainelFiltros() {
    String tmpStatus    = _filtroStatus;
    String tmpProvincia = _filtroProvincia;

    final provincias = [
      'Luanda', 'Benguela', 'Huambo', 'Bié', 'Cabinda',
      'Cuando Cubango', 'Cuanza Norte', 'Cuanza Sul', 'Cunene', 'Huíla',
      'Lunda Norte', 'Lunda Sul', 'Malanje', 'Moxico', 'Namibe', 'Uíge', 'Zaire', 'Bengo',
    ];

    showModalBottomSheet(
      context: context,
      backgroundColor: _C.card,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => Padding(
          padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(ctx).viewInsets.bottom + 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(width: 36, height: 4, decoration: BoxDecoration(color: _C.grey4, borderRadius: BorderRadius.circular(2))),
              ),
              const SizedBox(height: 16),
              const Text('Filtros', style: TextStyle(color: _C.white, fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 20),

              // Estado
              const Text('Estado', style: TextStyle(color: _C.grey2, fontSize: 13, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  _filterChip(ctx, 'Todos',       '',          tmpStatus, (v) => setLocal(() => tmpStatus = v)),
                  _filterChip(ctx, 'Ativo',       'ativo',     tmpStatus, (v) => setLocal(() => tmpStatus = v)),
                  _filterChip(ctx, 'Encontrado',  'encontrado',tmpStatus, (v) => setLocal(() => tmpStatus = v)),
                  _filterChip(ctx, 'Desmentido',  'desmentido',tmpStatus, (v) => setLocal(() => tmpStatus = v)),
                ],
              ),

              const SizedBox(height: 20),

              // Província
              const Text('Província', style: TextStyle(color: _C.grey2, fontSize: 13, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: tmpProvincia.isEmpty ? null : tmpProvincia,
                dropdownColor: _C.card,
                style: const TextStyle(color: _C.white, fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'Todas as províncias',
                  hintStyle: const TextStyle(color: _C.grey3, fontSize: 13),
                  filled: true, fillColor: _C.surface,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _C.border)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _C.border)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                ),
                items: [
                  const DropdownMenuItem(value: '', child: Text('Todas', style: TextStyle(color: _C.grey2))),
                  ...provincias.map((p) => DropdownMenuItem(value: p.toLowerCase(), child: Text(p, style: const TextStyle(color: _C.white)))),
                ],
                onChanged: (v) => setLocal(() => tmpProvincia = v ?? ''),
              ),

              const SizedBox(height: 24),

              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () { Navigator.pop(ctx); _limparFiltros(); },
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: _C.border),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: const Text('Limpar', style: TextStyle(color: _C.grey2)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.pop(ctx);
                        setState(() {
                          _filtroStatus    = tmpStatus;
                          _filtroProvincia = tmpProvincia;
                        });
                        _aplicarFiltros();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _C.accent,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: const Text('Aplicar', style: TextStyle(color: _C.white, fontWeight: FontWeight.w700)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _filterChip(BuildContext ctx, String label, String value, String current, Function(String) onTap) {
    final selected = current == value;
    return GestureDetector(
      onTap: () => onTap(value),
      child: Container(
        margin: const EdgeInsets.only(bottom: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? _C.accent : _C.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? _C.accent : _C.border),
        ),
        child: Text(label, style: TextStyle(color: selected ? _C.white : _C.grey2, fontSize: 12, fontWeight: selected ? FontWeight.w700 : FontWeight.w400)),
      ),
    );
  }
}

// ─── CARD DE INFO (ao tocar num marcador) ───────────────
class _InfoCard extends StatelessWidget {
  final Map<String, dynamic> caso;
  final String diasAgo;
  final VoidCallback onClose;

  const _InfoCard({required this.caso, required this.diasAgo, required this.onClose});

  @override
  Widget build(BuildContext context) {
    final nome      = caso['nome']       as String? ?? 'Sem nome';
    final idade     = caso['idade']?.toString() ?? '?';
    final provincia = caso['provincia']  as String? ?? 'Angola';
    final municipio = caso['municipio']  as String? ?? '';
    final local     = municipio.isNotEmpty ? '$municipio, $provincia' : provincia;
    final status    = caso['status']     as String? ?? 'aprovado';
    final apoios    = caso['apoios']     as int?    ?? 0;
    final imagem    = caso['imagem']     as String? ?? '';

    Uint8List? bytes;
    if (imagem.startsWith('data:image')) {
      try { bytes = base64Decode(imagem.split(',').last); } catch (_) {}
    }

    Color statusColor;
    switch (status) {
      case 'encontrado': statusColor = const Color(0xFF22C55E); break;
      case 'desmentido': statusColor = const Color(0xFF52525B); break;
      default:           statusColor = const Color(0xFF4F7EFF);
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _C.card.withOpacity(0.97),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _C.border),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.4), blurRadius: 20, offset: const Offset(0, 8))],
      ),
      child: Row(
        children: [
          // Foto ou placeholder
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: bytes != null
                ? Image.memory(bytes, width: 70, height: 70, fit: BoxFit.cover)
                : Container(width: 70, height: 70, color: _C.surface, child: const Icon(Icons.person_rounded, color: _C.grey4, size: 36)),
          ),

          const SizedBox(width: 14),

          // Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(children: [
                  Expanded(child: Text(nome, style: const TextStyle(color: _C.white, fontWeight: FontWeight.w700, fontSize: 15), overflow: TextOverflow.ellipsis)),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(color: statusColor.withOpacity(0.2), borderRadius: BorderRadius.circular(10)),
                    child: Text(status, style: TextStyle(color: statusColor, fontSize: 10, fontWeight: FontWeight.w700)),
                  ),
                ]),
                const SizedBox(height: 4),
                Text('$idade anos · $local', style: const TextStyle(color: _C.grey3, fontSize: 12)),
                if (diasAgo.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text('Desapareceu $diasAgo', style: const TextStyle(color: _C.grey3, fontSize: 11)),
                ],
                const SizedBox(height: 6),
                Row(children: [
                  const Icon(Icons.favorite_rounded, size: 12, color: _C.red),
                  const SizedBox(width: 4),
                  Text('$apoios apoios', style: const TextStyle(color: _C.grey2, fontSize: 11)),
                ]),
              ],
            ),
          ),

          // Fechar
          IconButton(
            icon: const Icon(Icons.close_rounded, color: _C.grey3, size: 18),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            onPressed: onClose,
          ),
        ],
      ),
    );
  }
}