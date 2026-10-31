// Lógica pura de la sección Soporte (tickets de RootDesk). Sin dependencias de Flutter
// para poder probarla con `flutter test` sin construir la aplicación.

/// Error de la API de tickets: [status] HTTP y [code] (`no_autorizado`, `datos_invalidos`, ...).
class SupportException implements Exception {
  final int status;
  final String code;
  final String detail;
  SupportException(this.status, this.code, [this.detail = '']);

  bool get unauthorized => status == 401;

  @override
  String toString() => 'SupportException($status, $code, $detail)';
}

DateTime? _date(dynamic v) => v is String ? DateTime.tryParse(v)?.toLocal() : null;

const List<String> _closedStates = ['resuelto', 'cerrado', 'cancelado'];

class TicketSummary {
  final String id;
  final String folio;
  final String titulo;
  final String estado;
  final DateTime? creadoEn;
  final DateTime? soporteHasta;

  /// Lo más reciente entre el último cambio del ticket y el último mensaje.
  final DateTime? actividadEn;

  /// Mensajes visibles en la conversación (de la persona y de soporte).
  final int mensajes;

  /// Cuándo escribió soporte por última vez; null si nunca.
  final DateTime? ultimoSoporteEn;

  const TicketSummary({
    required this.id,
    required this.folio,
    required this.titulo,
    required this.estado,
    this.creadoEn,
    this.soporteHasta,
    this.actividadEn,
    this.mensajes = 0,
    this.ultimoSoporteEn,
  });

  factory TicketSummary.fromJson(Map<String, dynamic> j) => TicketSummary(
        id: j['id'] as String,
        folio: (j['folio'] ?? '') as String,
        titulo: (j['titulo'] ?? '') as String,
        estado: (j['estado'] ?? '') as String,
        creadoEn: _date(j['creado_en']),
        soporteHasta: _date(j['soporte_hasta']),
        actividadEn: _date(j['ultima_actividad_en']) ?? _date(j['actualizado_en']) ?? _date(j['creado_en']),
        mensajes: (j['mensajes'] is int) ? j['mensajes'] as int : 0,
        ultimoSoporteEn: _date(j['ultimo_soporte_en']),
      );

  /// El permiso de conexión sin aceptar sigue vigente.
  bool soporteActivo(DateTime now) => soporteHasta != null && soporteHasta!.isAfter(now);

  /// Sigue en atención (no resuelto, cerrado ni cancelado).
  bool get abierto => !_closedStates.contains(estado);
}

class TicketComment {
  final String autor;
  final String mensaje;
  final DateTime? creadoEn;

  /// Lo escribió la propia persona (y no soporte).
  final bool esMio;
  const TicketComment({required this.autor, required this.mensaje, this.creadoEn, this.esMio = false});

  factory TicketComment.fromJson(Map<String, dynamic> j) => TicketComment(
        autor: (j['autor'] ?? '') as String,
        mensaje: (j['mensaje'] ?? '') as String,
        creadoEn: _date(j['creado_en']),
        esMio: j['es_mio'] == true,
      );
}

class TicketDetail {
  final TicketSummary resumen;
  final String descripcion;
  final List<TicketComment> comentarios;
  const TicketDetail({required this.resumen, required this.descripcion, required this.comentarios});

  factory TicketDetail.fromJson(Map<String, dynamic> j) => TicketDetail(
        resumen: TicketSummary.fromJson(j),
        descripcion: (j['descripcion'] ?? '') as String,
        comentarios: ((j['comentarios'] ?? []) as List)
            .map((c) => TicketComment.fromJson(c as Map<String, dynamic>))
            .toList(),
      );

  /// Cuándo escribió soporte por última vez en esta conversación.
  DateTime? get ultimoSoporteEn {
    DateTime? best;
    for (final c in comentarios) {
      if (c.esMio || c.creadoEn == null) continue;
      if (best == null || c.creadoEn!.isAfter(best)) best = c.creadoEn;
    }
    return best;
  }
}

class TicketCategory {
  final String id;
  final String nombre;
  const TicketCategory(this.id, this.nombre);

  factory TicketCategory.fromJson(Map<String, dynamic> j) =>
      TicketCategory(j['id'] as String, (j['nombre'] ?? '') as String);
}

/// Resultado de crear un ticket. [soporte]: activo | no_autorizado | no_vinculado | error.
class CreatedTicket {
  final String id;
  final String folio;
  final String soporte;
  final DateTime? soporteHasta;
  const CreatedTicket({required this.id, required this.folio, required this.soporte, this.soporteHasta});

  factory CreatedTicket.fromJson(Map<String, dynamic> j) => CreatedTicket(
        id: j['id'] as String,
        folio: (j['folio'] ?? '') as String,
        soporte: (j['soporte'] ?? 'error') as String,
        soporteHasta: _date(j['soporte_hasta']),
      );
}

/// El ticket con el permiso de soporte que vence más tarde, o null si ninguno sigue vigente.
TicketSummary? activeSupportTicket(List<TicketSummary> tickets, DateTime now) {
  TicketSummary? best;
  for (final t in tickets) {
    if (!t.soporteActivo(now)) continue;
    if (best == null || t.soporteHasta!.isAfter(best.soporteHasta!)) best = t;
  }
  return best;
}

/// Orden de la lista: primero los que siguen en atención y después los terminados; dentro de cada
/// grupo, el de actividad más reciente arriba. Cada ticket conserva su propia conversación (por id).
List<TicketSummary> sortTickets(List<TicketSummary> tickets) {
  final out = List<TicketSummary>.from(tickets);
  int ms(TicketSummary t) => (t.actividadEn ?? t.creadoEn)?.millisecondsSinceEpoch ?? 0;
  out.sort((a, b) {
    if (a.abierto != b.abierto) return a.abierto ? -1 : 1;
    return ms(b).compareTo(ms(a));
  });
  return out;
}

/// Hay un mensaje de soporte que la persona todavía no ha leído. [seen] guarda, por ticket, el
/// último mensaje de soporte que ya vio.
bool hasUnread(TicketSummary t, Map<String, DateTime> seen) {
  final last = t.ultimoSoporteEn;
  if (last == null) return false;
  final s = seen[t.id];
  return s == null || last.isAfter(s);
}

/// "hace 5 min", "hace 3 h", "ayer" o la fecha, en español.
String relativeTime(DateTime d, DateTime now) {
  final diff = now.difference(d);
  if (diff.isNegative || diff.inSeconds < 60) return 'hace un momento';
  if (diff.inMinutes < 60) return 'hace ${diff.inMinutes} min';
  if (diff.inHours < 24) return 'hace ${diff.inHours} h';
  if (diff.inHours < 48) return 'ayer';
  return formatDate(d);
}

String _two(int n) => n.toString().padLeft(2, '0');

String formatDate(DateTime d) => '${_two(d.day)}/${_two(d.month)}/${d.year}';

/// Fecha y hora de 24 horas en la zona del equipo, por ejemplo "31/10/2026 13:37".
String formatDateTime(DateTime d) => '${formatDate(d)} ${_two(d.hour)}:${_two(d.minute)}';

/// Estado del ticket en español para mostrarlo.
String ticketStateLabel(String estado) {
  switch (estado) {
    case 'nuevo':
      return 'Nuevo';
    case 'asignado':
      return 'Asignado';
    case 'en_proceso':
      return 'En atención';
    case 'en_espera_cliente':
      return 'Esperando tu respuesta';
    case 'resuelto':
      return 'Resuelto';
    case 'cerrado':
      return 'Cerrado';
    case 'cancelado':
      return 'Cancelado';
  }
  return estado;
}

/// Une la base del servicio con una ruta sin duplicar ni perder barras.
String joinUrl(String base, String path) {
  final b = base.replaceAll(RegExp(r'/+$'), '');
  final p = path.startsWith('/') ? path : '/$path';
  return '$b$p';
}

/// Lee `tickets_url` de la respuesta de `/api/support/config`; null si falta o está vacía.
String? parseTicketsUrl(Map<String, dynamic> body) {
  final v = body['tickets_url'];
  if (v is! String) return null;
  final t = v.trim();
  return t.isEmpty ? null : t;
}

/// Traduce el cuerpo de error de la API en una [SupportException].
SupportException supportErrorFrom(int status, Map<String, dynamic>? body) {
  final code = body == null ? '' : ((body['error'] ?? '') as Object).toString();
  final detail = body == null ? '' : ((body['detalle'] ?? '') as Object).toString();
  return SupportException(status, code, detail);
}
