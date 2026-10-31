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

class TicketSummary {
  final String id;
  final String folio;
  final String titulo;
  final String estado;
  final DateTime? creadoEn;
  final DateTime? soporteHasta;

  const TicketSummary({
    required this.id,
    required this.folio,
    required this.titulo,
    required this.estado,
    this.creadoEn,
    this.soporteHasta,
  });

  factory TicketSummary.fromJson(Map<String, dynamic> j) => TicketSummary(
        id: j['id'] as String,
        folio: (j['folio'] ?? '') as String,
        titulo: (j['titulo'] ?? '') as String,
        estado: (j['estado'] ?? '') as String,
        creadoEn: _date(j['creado_en']),
        soporteHasta: _date(j['soporte_hasta']),
      );

  /// El permiso de conexión sin aceptar sigue vigente.
  bool soporteActivo(DateTime now) => soporteHasta != null && soporteHasta!.isAfter(now);
}

class TicketComment {
  final String autor;
  final String mensaje;
  final DateTime? creadoEn;
  const TicketComment({required this.autor, required this.mensaje, this.creadoEn});

  factory TicketComment.fromJson(Map<String, dynamic> j) => TicketComment(
        autor: (j['autor'] ?? '') as String,
        mensaje: (j['mensaje'] ?? '') as String,
        creadoEn: _date(j['creado_en']),
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
