import 'package:flutter_hbb/models/staff_aviso_logic.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SseParser', () {
    test('entrega un evento completo con id, nombre y datos', () {
      final p = SseParser();
      final r = p.add('id: 5-1\nevent: aviso\ndata: {"a":1}\n\n');
      expect(r, hasLength(1));
      expect(r.first.id, '5-1');
      expect(r.first.evento, 'aviso');
      expect(r.first.datos, '{"a":1}');
      expect(p.ultimoId, '5-1');
    });

    test('un evento partido en varios trozos se arma al llegar el final', () {
      final p = SseParser();
      expect(p.add('id: 7-2\nevent: av'), isEmpty);
      expect(p.add('iso\ndata: {"x"'), isEmpty);
      final r = p.add(':2}\n\n');
      expect(r, hasLength(1));
      expect(r.first.datos, '{"x":2}');
    });

    test('dos eventos en el mismo trozo salen en orden', () {
      final r = SseParser().add('event: aviso\ndata: uno\n\nevent: aviso\ndata: dos\n\n');
      expect(r.map((e) => e.datos), ['uno', 'dos']);
    });

    test('ignora latidos y comentarios', () {
      final p = SseParser();
      expect(p.add(': latido\n\n'), isEmpty);
      expect(p.add('retry: 5000\n: conectado\n\n'), isEmpty);
    });

    test('acepta saltos de línea de Windows', () {
      final r = SseParser().add('event: aviso\r\ndata: hola\r\n\r\n');
      expect(r.single.datos, 'hola');
    });

    test('varias líneas data se unen con salto de línea', () {
      final r = SseParser().add('data: a\ndata: b\n\n');
      expect(r.single.datos, 'a\nb');
      expect(r.single.evento, 'message');
    });
  });

  group('avisoDeEvento', () {
    SseEvento ev(String datos, {String evento = 'aviso'}) => SseEvento(evento: evento, datos: datos);
    const base = '{"id":"1-1","tipo":"mensaje_cliente","ticketId":"t1","folio":"TCK-1","titulo":"Correo","de":"Ana","mensaje":"Sigue igual"}';

    test('convierte un aviso válido', () {
      final a = avisoDeEvento(ev(base))!;
      expect(a.tipo, TipoAviso.mensajeCliente);
      expect(a.ticketId, 't1');
      expect(a.de, 'Ana');
    });

    test('un tipo desconocido se ignora', () {
      expect(avisoDeEvento(ev(base.replaceFirst('mensaje_cliente', 'algo_nuevo'))), isNull);
    });

    test('sin ticketId o con JSON roto se ignora', () {
      expect(avisoDeEvento(ev('{"tipo":"caso_nuevo"}')), isNull);
      expect(avisoDeEvento(ev('no es json')), isNull);
    });

    test('otro nombre de evento no es un aviso', () {
      expect(avisoDeEvento(ev(base, evento: 'message')), isNull);
    });
  });

  group('esperaReconexion', () {
    test('crece y se detiene en un minuto', () {
      expect(esperaReconexion(1), const Duration(seconds: 2));
      expect(esperaReconexion(2), const Duration(seconds: 4));
      expect(esperaReconexion(3), const Duration(seconds: 8));
      expect(esperaReconexion(5), const Duration(seconds: 32));
      expect(esperaReconexion(6), const Duration(seconds: 60));
      expect(esperaReconexion(40), const Duration(seconds: 60));
    });
    test('un número inválido cuenta como el primer intento', () {
      expect(esperaReconexion(0), const Duration(seconds: 2));
    });
  });

  group('textoAviso', () {
    String t(String k) => k;
    StaffAviso a(TipoAviso tipo) => StaffAviso(id: '1', tipo: tipo, ticketId: 't', folio: 'TCK-9', titulo: 'No imprime', de: 'Luis', mensaje: 'Pasó a ti');

    test('mensaje del cliente: título con quién y folio, cuerpo con el mensaje', () {
      final r = textoAviso(a(TipoAviso.mensajeCliente), t);
      expect(r.titulo, 'Luis · TCK-9');
      expect(r.cuerpo, 'Pasó a ti');
    });
    test('caso nuevo', () {
      final r = textoAviso(a(TipoAviso.casoNuevo), t);
      expect(r.titulo, 'New case · TCK-9');
      expect(r.cuerpo, 'Luis: No imprime');
    });
    test('asignado e invitado', () {
      expect(textoAviso(a(TipoAviso.casoAsignado), t).titulo, 'A case was assigned to you · TCK-9');
      expect(textoAviso(a(TipoAviso.casoInvitado), t).cuerpo, 'Luis · No imprime');
    });
  });

  test('tituloConInsignia solo antepone el número cuando hay casos', () {
    expect(tituloConInsignia('RootDesk', 0), 'RootDesk');
    expect(tituloConInsignia('RootDesk', 3), '(3) RootDesk');
  });
}
