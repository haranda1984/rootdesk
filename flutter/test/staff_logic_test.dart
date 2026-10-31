import 'package:flutter_hbb/models/staff_logic.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> casoJson(String id, {String grupoClave = 'a1', String grupoNombre = 'Ana', Map<String, dynamic> extra = const {}}) => {
      'id': id,
      'folio': 'RD-$id',
      'titulo': 'Caso $id',
      'estado': 'en_proceso',
      'prioridad': 'alta',
      'creado_en': '2030-01-01T08:00:00Z',
      'ultima_actividad_en': '2030-01-01T09:00:00Z',
      'auxiliar': {'id': grupoClave, 'nombre': grupoNombre},
      'cliente_nombre': 'Cliente',
      'rustdesk_id': '123456789',
      'equipo_nombre': 'PC',
      'entrada_directa_hasta': null,
      'vencido': false,
      'mensajes': 3,
      'ultimo_cliente_en': null,
      'grupo': {'clave': grupoClave, 'nombre': grupoNombre},
      ...extra,
    };

void main() {
  test('StaffYo: permisos y supervisión', () {
    final yo = StaffYo.fromJson({'id': 'u', 'nombre': 'Ana', 'rol': 'auxiliar', 'permisos': ['conectar', 'invitar']});
    expect(yo.can('conectar'), isTrue);
    expect(yo.can('transferir'), isFalse);
    expect(yo.supervisa, isFalse);
    final jefe = StaffYo.fromJson({'id': 'a', 'nombre': 'Jefe', 'rol': 'admin', 'permisos': ['supervisar', 'conectar']});
    expect(jefe.supervisa, isTrue);
  });

  test('StaffCaso lee todos los campos', () {
    final c = StaffCaso.fromJson(casoJson('1', extra: {'entrada_directa_hasta': '2030-01-02T00:00:00Z', 'vencido': true}));
    expect(c.folio, 'RD-1');
    expect(c.responsable?.nombre, 'Ana');
    expect(c.vencido, isTrue);
    expect(c.mensajes, 3);
    expect(c.entradaDirectaVigente(DateTime.utc(2030, 1, 1, 12)), isTrue);
    expect(c.entradaDirectaVigente(DateTime.utc(2030, 1, 3)), isFalse);
  });

  test('un caso sin responsable queda sin auxiliar', () {
    final c = StaffCaso.fromJson(casoJson('2', grupoClave: 'sin-asignar', grupoNombre: 'Sin asignar', extra: {'auxiliar': null}));
    expect(c.responsable, isNull);
    expect(c.grupoNombre, 'Sin asignar');
  });

  test('seccionesDe parte la lista en bloques consecutivos por responsable', () {
    final casos = [
      StaffCaso.fromJson(casoJson('1', grupoClave: 'sin-asignar', grupoNombre: 'Sin asignar', extra: {'auxiliar': null})),
      StaffCaso.fromJson(casoJson('2')),
      StaffCaso.fromJson(casoJson('3', extra: {'vencido': true})),
      StaffCaso.fromJson(casoJson('4', grupoClave: 'a2', grupoNombre: 'Luis')),
    ];
    final s = seccionesDe(casos);
    expect(s.map((x) => '${x.titulo}:${x.casos.length}').toList(), ['Sin asignar:1', 'Ana:2', 'Luis:1']);
    expect(s[1].vencidos, 1);
    expect(seccionesDe([]), isEmpty);
  });

  test('mensaje del cliente sin leer', () {
    final c = StaffCaso.fromJson(casoJson('1', extra: {'ultimo_cliente_en': '2030-01-01T12:00:00Z'}));
    expect(clienteEscribioSinLeer(c, {}), isTrue);
    expect(clienteEscribioSinLeer(c, {'1': DateTime.utc(2030, 1, 1, 11)}), isTrue);
    expect(clienteEscribioSinLeer(c, {'1': DateTime.utc(2030, 1, 1, 12)}), isFalse);
    final sin = StaffCaso.fromJson(casoJson('2'));
    expect(clienteEscribioSinLeer(sin, {}), isFalse);
    expect(casosConMensajeNuevo([c, sin], {}), 1);
  });

  test('StaffDetalle: conversación con notas internas y botones permitidos', () {
    final d = StaffDetalle.fromJson({
      'id': '1',
      'folio': 'RD-1',
      'titulo': 'T',
      'descripcion': 'No abre',
      'estado': 'en_proceso',
      'prioridad': 'media',
      'creado_en': '2030-01-01T08:00:00Z',
      'categoria': 'Software',
      'cliente': {'nombre': 'Cli', 'email': 'cli@x.mx'},
      'responsable': {'id': 'a1', 'nombre': 'Ana'},
      'rustdesk_id': '123456789',
      'equipo_nombre': 'PC',
      'entrada_directa_hasta': null,
      'invitados': [
        {'id': 'a2', 'nombre': 'Luis'}
      ],
      'comentarios': [
        {'autor': 'Cli', 'rol': 'cliente', 'mensaje': 'hola', 'creado_en': '2030-01-01T10:00:00Z', 'interno': false, 'es_mio': false},
        {'autor': 'Ana', 'rol': 'auxiliar', 'mensaje': 'nota', 'creado_en': '2030-01-01T11:00:00Z', 'interno': true, 'es_mio': true},
        {'autor': 'Cli', 'rol': 'cliente', 'mensaje': 'sigue igual', 'creado_en': '2030-01-01T12:00:00Z', 'interno': false, 'es_mio': false},
      ],
      'puede': {'conectar': true, 'invitar': true, 'transferir': false},
    });
    expect(d.clienteNombre, 'Cli');
    expect(d.invitados.single.nombre, 'Luis');
    expect(d.comentarios[1].interno, isTrue);
    expect(d.puedeConectar, isTrue);
    expect(d.puedeTransferir, isFalse);
    expect(d.ultimoClienteEn, DateTime.parse('2030-01-01T12:00:00Z').toLocal());
  });

  test('EquipoFila acepta números enteros o decimales', () {
    final f = EquipoFila.fromJson({
      'nombre': 'Ana',
      'rol': 'auxiliar',
      'activo': true,
      'en_curso': 4,
      'esperan_cliente': 1.0,
      'vencidos_ahora': 2,
      'resueltos_7d': 9,
      'resueltos_30d': 30,
      'horas_promedio_respuesta': 1.5,
    });
    expect(f.enCurso, 4);
    expect(f.esperanCliente, 1);
    expect(f.horasRespuesta, 1.5);
  });

  test('prioridades en español', () {
    expect(prioridadLabel('critica'), 'Crítica');
    expect(prioridadLabel('x'), 'x');
  });
}
