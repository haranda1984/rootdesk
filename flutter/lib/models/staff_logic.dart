// Lógica pura de la edición "Soporte" (la app del personal). Sin dependencias de Flutter, para probarla
// con `flutter test` sin construir la aplicación.

DateTime? _d(dynamic v) => v is String ? DateTime.tryParse(v)?.toLocal() : null;
int _n(dynamic v) => v is num ? v.toInt() : 0;

/// Quién es la persona que usa la app y qué puede hacer (lo decide el portal según su rol y permisos).
class StaffYo {
  final String id;
  final String nombre;
  final String rol;
  final Set<String> permisos;
  const StaffYo({required this.id, required this.nombre, required this.rol, required this.permisos});

  factory StaffYo.fromJson(Map<String, dynamic> j) => StaffYo(
        id: j['id'] as String,
        nombre: (j['nombre'] ?? '') as String,
        rol: (j['rol'] ?? '') as String,
        permisos: ((j['permisos'] ?? []) as List).map((e) => e.toString()).toSet(),
      );

  bool can(String permiso) => permisos.contains(permiso);

  /// Puede ver el tablero de todos y las estadísticas del equipo.
  bool get supervisa => can('supervisar');
}

class StaffPersona {
  final String id;
  final String nombre;
  const StaffPersona(this.id, this.nombre);

  factory StaffPersona.fromJson(Map<String, dynamic> j) => StaffPersona(j['id'] as String, (j['nombre'] ?? '') as String);
}

class StaffCaso {
  final String id;
  final String folio;
  final String titulo;
  final String estado;
  final String prioridad;
  final DateTime? creadoEn;
  final DateTime? actividadEn;
  final StaffPersona? responsable;
  final String clienteNombre;
  final String? rustdeskId;
  final String? equipoNombre;
  final DateTime? entradaDirectaHasta;
  final bool vencido;
  final int mensajes;
  final DateTime? ultimoClienteEn;
  final String grupoClave;
  final String grupoNombre;

  const StaffCaso({
    required this.id,
    required this.folio,
    required this.titulo,
    required this.estado,
    required this.prioridad,
    this.creadoEn,
    this.actividadEn,
    this.responsable,
    required this.clienteNombre,
    this.rustdeskId,
    this.equipoNombre,
    this.entradaDirectaHasta,
    this.vencido = false,
    this.mensajes = 0,
    this.ultimoClienteEn,
    this.grupoClave = '',
    this.grupoNombre = '',
  });

  factory StaffCaso.fromJson(Map<String, dynamic> j) {
    final grupo = j['grupo'] is Map<String, dynamic> ? j['grupo'] as Map<String, dynamic> : const <String, dynamic>{};
    return StaffCaso(
      id: j['id'] as String,
      folio: (j['folio'] ?? '') as String,
      titulo: (j['titulo'] ?? '') as String,
      estado: (j['estado'] ?? '') as String,
      prioridad: (j['prioridad'] ?? '') as String,
      creadoEn: _d(j['creado_en']),
      actividadEn: _d(j['ultima_actividad_en']) ?? _d(j['creado_en']),
      responsable: j['auxiliar'] is Map<String, dynamic> ? StaffPersona.fromJson(j['auxiliar'] as Map<String, dynamic>) : null,
      clienteNombre: (j['cliente_nombre'] ?? '') as String,
      rustdeskId: j['rustdesk_id'] as String?,
      equipoNombre: j['equipo_nombre'] as String?,
      entradaDirectaHasta: _d(j['entrada_directa_hasta']),
      vencido: j['vencido'] == true,
      mensajes: _n(j['mensajes']),
      ultimoClienteEn: _d(j['ultimo_cliente_en']),
      grupoClave: (grupo['clave'] ?? '') as String,
      grupoNombre: (grupo['nombre'] ?? '') as String,
    );
  }

  /// La entrada directa autorizada por el cliente sigue vigente.
  bool entradaDirectaVigente(DateTime now) => entradaDirectaHasta != null && entradaDirectaHasta!.isAfter(now);
}

class StaffComentario {
  final String autor;
  final String? rol;
  final String mensaje;
  final DateTime? creadoEn;

  /// Nota interna: el cliente no la ve.
  final bool interno;
  final bool esMio;
  const StaffComentario({required this.autor, this.rol, required this.mensaje, this.creadoEn, this.interno = false, this.esMio = false});

  factory StaffComentario.fromJson(Map<String, dynamic> j) => StaffComentario(
        autor: (j['autor'] ?? '') as String,
        rol: j['rol'] as String?,
        mensaje: (j['mensaje'] ?? '') as String,
        creadoEn: _d(j['creado_en']),
        interno: j['interno'] == true,
        esMio: j['es_mio'] == true,
      );
}

class StaffDetalle {
  final String id;
  final String folio;
  final String titulo;
  final String descripcion;
  final String estado;
  final String prioridad;
  final DateTime? creadoEn;
  final String? categoria;
  final String clienteNombre;
  final String clienteEmail;
  final StaffPersona? responsable;
  final String? rustdeskId;
  final String? equipoNombre;
  final DateTime? entradaDirectaHasta;
  final List<StaffPersona> invitados;
  final List<StaffComentario> comentarios;
  final bool puedeConectar;
  final bool puedeInvitar;
  final bool puedeTransferir;

  const StaffDetalle({
    required this.id,
    required this.folio,
    required this.titulo,
    required this.descripcion,
    required this.estado,
    required this.prioridad,
    this.creadoEn,
    this.categoria,
    required this.clienteNombre,
    required this.clienteEmail,
    this.responsable,
    this.rustdeskId,
    this.equipoNombre,
    this.entradaDirectaHasta,
    this.invitados = const [],
    this.comentarios = const [],
    this.puedeConectar = false,
    this.puedeInvitar = false,
    this.puedeTransferir = false,
  });

  factory StaffDetalle.fromJson(Map<String, dynamic> j) {
    final cliente = j['cliente'] is Map<String, dynamic> ? j['cliente'] as Map<String, dynamic> : const <String, dynamic>{};
    final puede = j['puede'] is Map<String, dynamic> ? j['puede'] as Map<String, dynamic> : const <String, dynamic>{};
    return StaffDetalle(
      id: j['id'] as String,
      folio: (j['folio'] ?? '') as String,
      titulo: (j['titulo'] ?? '') as String,
      descripcion: (j['descripcion'] ?? '') as String,
      estado: (j['estado'] ?? '') as String,
      prioridad: (j['prioridad'] ?? '') as String,
      creadoEn: _d(j['creado_en']),
      categoria: j['categoria'] as String?,
      clienteNombre: (cliente['nombre'] ?? '') as String,
      clienteEmail: (cliente['email'] ?? '') as String,
      responsable: j['responsable'] is Map<String, dynamic> ? StaffPersona.fromJson(j['responsable'] as Map<String, dynamic>) : null,
      rustdeskId: j['rustdesk_id'] as String?,
      equipoNombre: j['equipo_nombre'] as String?,
      entradaDirectaHasta: _d(j['entrada_directa_hasta']),
      invitados: ((j['invitados'] ?? []) as List).map((e) => StaffPersona.fromJson(e as Map<String, dynamic>)).toList(),
      comentarios: ((j['comentarios'] ?? []) as List).map((e) => StaffComentario.fromJson(e as Map<String, dynamic>)).toList(),
      puedeConectar: puede['conectar'] == true,
      puedeInvitar: puede['invitar'] == true,
      puedeTransferir: puede['transferir'] == true,
    );
  }

  /// Último mensaje que escribió el propio cliente (rol "cliente").
  DateTime? get ultimoClienteEn {
    DateTime? best;
    for (final c in comentarios) {
      if (c.rol != 'cliente' || c.creadoEn == null) continue;
      if (best == null || c.creadoEn!.isAfter(best)) best = c.creadoEn;
    }
    return best;
  }
}

/// Una fila de las estadísticas del equipo.
class EquipoFila {
  final String nombre;
  final String rol;
  final bool activo;
  final int enCurso;
  final int esperanCliente;
  final int vencidos;
  final int resueltos7d;
  final int resueltos30d;
  final double? horasRespuesta;
  const EquipoFila({
    required this.nombre,
    required this.rol,
    required this.activo,
    required this.enCurso,
    required this.esperanCliente,
    required this.vencidos,
    required this.resueltos7d,
    required this.resueltos30d,
    this.horasRespuesta,
  });

  factory EquipoFila.fromJson(Map<String, dynamic> j) => EquipoFila(
        nombre: (j['nombre'] ?? '') as String,
        rol: (j['rol'] ?? '') as String,
        activo: j['activo'] != false,
        enCurso: _n(j['en_curso']),
        esperanCliente: _n(j['esperan_cliente']),
        vencidos: _n(j['vencidos_ahora']),
        resueltos7d: _n(j['resueltos_7d']),
        resueltos30d: _n(j['resueltos_30d']),
        horasRespuesta: j['horas_promedio_respuesta'] is num ? (j['horas_promedio_respuesta'] as num).toDouble() : null,
      );
}

/// Un bloque del tablero: el responsable (o "Sin asignar") y sus casos.
class CasoSeccion {
  final String clave;
  final String titulo;
  final List<StaffCaso> casos;
  const CasoSeccion(this.clave, this.titulo, this.casos);

  int get vencidos => casos.where((c) => c.vencido).length;
}

/// Parte la lista (que ya viene ordenada por responsable) en bloques consecutivos con el mismo grupo.
List<CasoSeccion> seccionesDe(List<StaffCaso> casos) {
  final out = <CasoSeccion>[];
  for (final c in casos) {
    if (out.isEmpty || out.last.clave != c.grupoClave) {
      out.add(CasoSeccion(c.grupoClave, c.grupoNombre, <StaffCaso>[]));
    }
    out.last.casos.add(c);
  }
  return out;
}

/// El cliente escribió algo que esta persona todavía no ha leído. [seen] guarda, por caso, el último mensaje del
/// cliente que ya vio.
bool clienteEscribioSinLeer(StaffCaso c, Map<String, DateTime> seen) {
  final last = c.ultimoClienteEn;
  if (last == null) return false;
  final s = seen[c.id];
  return s == null || last.isAfter(s);
}

/// Cuántos casos tienen un mensaje del cliente sin leer.
int casosConMensajeNuevo(List<StaffCaso> casos, Map<String, DateTime> seen) =>
    casos.where((c) => clienteEscribioSinLeer(c, seen)).length;

String prioridadLabel(String p) {
  switch (p) {
    case 'baja':
      return 'Baja';
    case 'media':
      return 'Media';
    case 'alta':
      return 'Alta';
    case 'critica':
      return 'Crítica';
  }
  return p;
}
