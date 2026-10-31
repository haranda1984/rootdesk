import 'dart:async';
import 'dart:convert';

import 'package:bot_toast/bot_toast.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_hbb/models/staff_logic.dart';
import 'package:flutter_hbb/models/support_logic.dart';
import 'package:flutter_hbb/models/support_model.dart';

import '../common.dart';

enum StaffVista { mios, sinAsignar, enCurso, equipo }

enum StaffStatus { idle, loading, ready, noLogin, noStaff, notConfigured, error }

/// Edición "Soporte": habla con el API del personal del portal (/api/staff) con la sesión del panel.
class StaffModel with ChangeNotifier {
  static const _pollInterval = Duration(seconds: 45);
  static const _seenKey = 'staff-seen';
  static const _vistaApi = {
    StaffVista.mios: 'mios',
    StaffVista.sinAsignar: 'sin_asignar',
    StaffVista.enCurso: 'en_curso',
  };

  StaffStatus status = StaffStatus.idle;
  String errorMessage = '';
  StaffYo? yo;
  StaffVista vista = StaffVista.mios;
  final Map<StaffVista, List<StaffCaso>> casos = {};
  List<EquipoFila> equipo = const [];
  Timer? _timer;
  Map<String, DateTime> _seen = {};
  bool _seenLoaded = false;
  int _alertasPrevias = -1;
  int _sinAsignarPrevios = -1;

  // ---- mensajes de clientes sin leer (se recuerdan entre sesiones) ----

  void _loadSeen() {
    if (_seenLoaded) return;
    _seenLoaded = true;
    try {
      final raw = bind.mainGetLocalOption(key: _seenKey);
      if (raw.isNotEmpty) {
        final m = jsonDecode(raw) as Map<String, dynamic>;
        _seen = m.map((k, v) => MapEntry(k, DateTime.parse(v as String)));
      }
    } catch (e) {
      debugPrint('staff: could not read seen messages: $e');
    }
  }

  bool sinLeer(StaffCaso c) {
    _loadSeen();
    return clienteEscribioSinLeer(c, _seen);
  }

  List<StaffCaso> get _mios => casos[StaffVista.mios] ?? const [];
  List<StaffCaso> get _sinAsignar => casos[StaffVista.sinAsignar] ?? const [];

  /// Casos que piden atención: con mensaje del cliente sin leer entre los míos, y los que nadie ha tomado.
  int get alertas {
    _loadSeen();
    return casosConMensajeNuevo(_mios, _seen) + _sinAsignar.length;
  }

  void markSeen(String id, DateTime? ultimoCliente) {
    _loadSeen();
    if (ultimoCliente == null) return;
    final cur = _seen[id];
    if (cur != null && !ultimoCliente.isAfter(cur)) return;
    _seen[id] = ultimoCliente;
    bind.mainSetLocalOption(
        key: _seenKey, value: jsonEncode(_seen.map((k, v) => MapEntry(k, v.toUtc().toIso8601String()))));
    notifyListeners();
  }

  // ---- red ----

  Future<dynamic> _get(String path) async => supportModel.apiJson(await supportModel.apiCall('GET', path));

  Future<void> start() async {
    _timer ??= Timer.periodic(_pollInterval, (_) {
      if (supportModel.loggedIn) load(quiet: true);
    });
    if (status == StaffStatus.idle) await load();
  }

  void setVista(StaffVista v) {
    vista = v;
    notifyListeners();
    load(quiet: true);
  }

  /// Carga lo que el personal ve: quién es, sus casos, los sin asignar y, si supervisa, la vista activa.
  Future<void> load({bool quiet = false}) async {
    if (!supportModel.loggedIn) {
      status = StaffStatus.noLogin;
      notifyListeners();
      return;
    }
    if (!quiet) {
      status = StaffStatus.loading;
      notifyListeners();
    }
    try {
      yo ??= StaffYo.fromJson(await _get('/api/staff/yo') as Map<String, dynamic>);
      await _cargarCasos(StaffVista.mios);
      await _cargarCasos(StaffVista.sinAsignar);
      if (yo!.supervisa && vista == StaffVista.enCurso) await _cargarCasos(StaffVista.enCurso);
      if (yo!.supervisa && vista == StaffVista.equipo) await cargarEquipo();
      status = StaffStatus.ready;
      _avisarNovedades(quiet);
    } on SupportException catch (e) {
      if (e.status == 403) {
        status = StaffStatus.noStaff;
      } else if (e.code == 'sin_portal') {
        status = StaffStatus.notConfigured;
      } else if (!quiet || status != StaffStatus.ready) {
        status = StaffStatus.error;
        errorMessage = e.unauthorized ? 'session_expired' : (e.code.isEmpty ? 'unknown_error' : e.code);
      }
    } catch (e) {
      debugPrint('staff load failed: $e');
      if (!quiet || status != StaffStatus.ready) {
        status = StaffStatus.error;
        errorMessage = 'network_error';
      }
    }
    notifyListeners();
  }

  void _avisarNovedades(bool quiet) {
    final nuevos = _sinAsignar.length;
    final alertasAhora = alertas;
    if (quiet && _sinAsignarPrevios >= 0 && nuevos > _sinAsignarPrevios) {
      BotToast.showText(text: translate('There is a new unassigned case'));
    } else if (quiet && _alertasPrevias >= 0 && alertasAhora > _alertasPrevias && nuevos <= _sinAsignarPrevios) {
      BotToast.showText(text: translate('A customer replied on your case'));
    }
    _sinAsignarPrevios = nuevos;
    _alertasPrevias = alertasAhora;
  }

  Future<void> _cargarCasos(StaffVista v) async {
    final list = await _get('/api/staff/casos?vista=${_vistaApi[v]}') as List;
    casos[v] = list.map((e) => StaffCaso.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<void> cargarEquipo() async {
    final list = await _get('/api/staff/equipo') as List;
    equipo = list.map((e) => EquipoFila.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<StaffDetalle> detalle(String id) async {
    final d = StaffDetalle.fromJson(await _get('/api/staff/casos/$id') as Map<String, dynamic>);
    markSeen(id, d.ultimoClienteEn);
    return d;
  }

  Future<void> comentar(String id, String texto, {required bool interno}) async {
    supportModel.apiJson(
        await supportModel.apiCall('POST', '/api/staff/casos/$id/comentarios',
            body: {'mensaje': texto, 'visible_cliente': !interno}),
        ok: 201);
    await load(quiet: true);
  }

  /// ID y contraseña de la ventana de soporte para entrar directo al equipo.
  Future<({String id, String password})> conectar(String id) async {
    final j = supportModel.apiJson(await supportModel.apiCall('POST', '/api/staff/casos/$id/conectar')) as Map<String, dynamic>;
    return (id: j['rustdesk_id'] as String, password: j['password'] as String);
  }

  Future<List<StaffPersona>> personal() async {
    final list = await _get('/api/staff/personal') as List;
    return list.map((e) => StaffPersona.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<String> invitar(String id, String usuarioId) async {
    final j = supportModel.apiJson(await supportModel.apiCall('POST', '/api/staff/casos/$id/invitar', body: {'usuario_id': usuarioId})) as Map<String, dynamic>;
    await load(quiet: true);
    return (j['mensaje'] ?? '') as String;
  }

  Future<String> transferir(String id, String usuarioId, String nota) async {
    final j = supportModel.apiJson(await supportModel.apiCall('POST', '/api/staff/casos/$id/transferir', body: {'usuario_id': usuarioId, 'nota': nota})) as Map<String, dynamic>;
    await load(quiet: true);
    return (j['mensaje'] ?? '') as String;
  }
}

final StaffModel staffModel = StaffModel();
