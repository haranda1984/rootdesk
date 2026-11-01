import 'dart:async';

import 'package:bot_toast/bot_toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hbb/models/staff_logic.dart';
import 'package:flutter_hbb/models/staff_model.dart';
import 'package:flutter_hbb/models/support_logic.dart';

import '../../common.dart';

String _fecha(DateTime? d) => d == null ? '' : formatDateTime(d);

String _textoError(SupportException e) {
  if (e.detail.isNotEmpty) return e.detail;
  switch (e.code) {
    case 'no_autorizado':
      return translate('Your session expired, sign in again');
    case 'sin_permiso':
      return translate('You do not have permission for this');
    case 'demasiadas_solicitudes':
      return translate('Too many requests, try again in a moment');
  }
  return '${translate('Support error')}: ${e.code}';
}

Color _colorEstado(String estado) {
  switch (estado) {
    case 'nuevo':
    case 'asignado':
      return Colors.blueGrey;
    case 'en_proceso':
      return Colors.amber.shade800;
    case 'en_espera_cliente':
      return Colors.deepOrange;
    case 'resuelto':
      return Colors.green.shade700;
  }
  return Colors.grey;
}

Color _colorPrioridad(String p) {
  switch (p) {
    case 'critica':
      return Colors.red.shade700;
    case 'alta':
      return Colors.deepOrange;
  }
  return Colors.blueGrey;
}

class _StaffEtiqueta extends StatelessWidget {
  final String texto;
  final Color color;
  const _StaffEtiqueta(this.texto, this.color);

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(color: color.withOpacity(0.15), borderRadius: BorderRadius.circular(10)),
        child: Text(texto, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
      );
}

/// Pestaña "Casos" de la edición Soporte: mis casos, los sin asignar, el tablero de todos y el equipo.
class StaffPage extends StatefulWidget {
  const StaffPage({Key? key}) : super(key: key);

  @override
  State<StaffPage> createState() => _StaffPageState();
}

class _StaffPageState extends State<StaffPage> {
  @override
  void initState() {
    super.initState();
    staffModel.start();
    staffModel.load(quiet: true);
    staffModel.addListener(_abrirPendiente);
    WidgetsBinding.instance.addPostFrameCallback((_) => _abrirPendiente());
  }

  @override
  void dispose() {
    staffModel.removeListener(_abrirPendiente);
    super.dispose();
  }

  /// Si la persona llegó desde una notificación, abre directo la conversación de ese caso.
  void _abrirPendiente() {
    final id = staffModel.casoPendiente;
    if (id == null || !mounted) return;
    staffModel.casoPendiente = null;
    final todos = staffModel.casos.values.expand((l) => l);
    final caso = todos.cast<StaffCaso?>().firstWhere((c) => c!.id == id, orElse: () => null) ??
        StaffCaso(id: id, folio: '', titulo: '', estado: '', prioridad: '', clienteNombre: '');
    showDialog<void>(context: context, builder: (_) => _StaffCasoDialog(caso: caso));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: staffModel,
      builder: (context, _) {
        switch (staffModel.status) {
          case StaffStatus.noLogin:
            return _mensaje(translate('Sign in to use Support'));
          case StaffStatus.noStaff:
            return _mensaje(translate('This app is only for the support staff'));
          case StaffStatus.notConfigured:
            return _mensaje(translate('Support is not available yet'));
          case StaffStatus.error:
            return Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text(staffModel.errorMessage == 'session_expired'
                  ? translate('Your session expired, sign in again')
                  : translate('Could not reach support, check your connection')),
              const SizedBox(height: 12),
              OutlinedButton(onPressed: staffModel.load, child: Text(translate('Retry'))),
            ]);
          case StaffStatus.idle:
          case StaffStatus.loading:
            if (staffModel.yo == null) return const Center(child: CircularProgressIndicator());
            return _cuerpo(context);
          case StaffStatus.ready:
            return _cuerpo(context);
        }
      },
    );
  }

  Widget _mensaje(String t) => Center(child: Text(t, textAlign: TextAlign.center));

  Widget _chip(StaffVista v, String etiqueta) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ChoiceChip(
        label: Text(etiqueta),
        selected: staffModel.vista == v,
        onSelected: (_) => staffModel.setVista(v),
      ),
    );
  }

  Widget _cuerpo(BuildContext context) {
    final yo = staffModel.yo!;
    final mios = staffModel.casosDe(StaffVista.mios);
    final sin = staffModel.casosDe(StaffVista.sinAsignar);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              _chip(StaffVista.mios, '${translate('My cases')} (${mios.length})'),
              _chip(StaffVista.sinAsignar, '${translate('Unassigned')} (${sin.length})'),
              if (yo.supervisa) _chip(StaffVista.enCurso, translate('In progress')),
              if (yo.supervisa) _chip(StaffVista.equipo, translate('Team')),
            ]),
          ),
        ),
        IconButton(tooltip: translate('Refresh'), onPressed: staffModel.load, icon: const Icon(Icons.refresh)),
      ]),
      if (staffModel.vista != StaffVista.equipo) _filtroEmpresa(context),
      const SizedBox(height: 4),
      Expanded(child: staffModel.vista == StaffVista.equipo ? _equipo(context) : _lista(context)),
    ]);
  }

  /// Selector de empresa; solo aparece si hay casos de alguna empresa.
  Widget _filtroEmpresa(BuildContext context) {
    final todos = staffModel.todosLosCasos;
    final opciones = empresasDe(todos);
    final sin = hayCasosSinEmpresa(todos);
    if (opciones.isEmpty) return const SizedBox.shrink();
    final actual = staffModel.filtroEmpresa;
    final existe = actual == null || actual == kSinEmpresa || opciones.any((o) => o.id == actual);
    return Padding(
      padding: const EdgeInsets.only(top: 2, bottom: 2),
      child: Row(children: [
        Icon(Icons.business, size: 16, color: Theme.of(context).hintColor),
        const SizedBox(width: 6),
        DropdownButton<String?>(
          value: existe ? actual : null,
          isDense: true,
          underline: const SizedBox.shrink(),
          items: [
            DropdownMenuItem<String?>(value: null, child: Text(translate('All companies'))),
            for (final o in opciones) DropdownMenuItem<String?>(value: o.id, child: Text(o.nombre)),
            if (sin) DropdownMenuItem<String?>(value: kSinEmpresa, child: Text(translate('No company'))),
          ],
          onChanged: staffModel.setFiltroEmpresa,
        ),
      ]),
    );
  }

  Widget _lista(BuildContext context) {
    final casos = staffModel.casosDe(staffModel.vista);
    if (casos.isEmpty) return _mensaje(translate('No cases here'));
    if (staffModel.vista != StaffVista.enCurso) {
      return ListView(children: [for (final c in casos) _tarjeta(context, c)]);
    }
    return ListView(children: [
      for (final s in seccionesDe(casos)) ...[
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 10, 4, 4),
          child: Text(
            '${s.titulo} · ${s.casos.length}${s.vencidos > 0 ? ' · ${s.vencidos} ${translate('Overdue').toLowerCase()}' : ''}',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 0.4),
          ),
        ),
        for (final c in s.casos) _tarjeta(context, c),
      ]
    ]);
  }

  Widget _tarjeta(BuildContext context, StaffCaso c) {
    final now = DateTime.now();
    final nuevo = staffModel.sinLeer(c);
    final primary = Theme.of(context).colorScheme.primary;
    final muted = Theme.of(context).hintColor;
    final cuando = c.actividadEn != null ? relativeTime(c.actividadEn!, now) : '';
    final equipo = c.equipoNombre?.isNotEmpty == true ? c.equipoNombre! : (c.rustdeskId ?? '');
    return Card(
      margin: const EdgeInsets.only(bottom: 6, right: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: nuevo ? primary : Theme.of(context).dividerColor),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => showDialog<void>(context: context, builder: (_) => _StaffCasoDialog(caso: c)),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(children: [
            Badge(isLabelVisible: nuevo, smallSize: 10, child: Icon(Icons.chat_bubble_outline, color: primary)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Wrap(spacing: 8, runSpacing: 2, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  if (c.empresaNombre.isNotEmpty) _StaffEtiqueta(c.empresaNombre, Colors.indigo.shade700),
                  Text(c.folio, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                  _StaffEtiqueta(ticketStateLabel(c.estado), _colorEstado(c.estado)),
                  _StaffEtiqueta(prioridadLabel(c.prioridad), _colorPrioridad(c.prioridad)),
                  if (c.vencido) _StaffEtiqueta(translate('Overdue'), Colors.red.shade700),
                  if (c.entradaDirectaVigente(now))
                    Tooltip(message: translate('Direct entry authorized'), child: const Icon(Icons.verified_user, size: 16)),
                ]),
                const SizedBox(height: 2),
                Text(c.titulo, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                Text(
                  '${c.clienteNombre}${equipo.isNotEmpty ? ' · $equipo' : ''} · $cuando · ${c.mensajes} ${translate('messages')}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: muted),
                ),
                const SizedBox(height: 2),
                Text(
                  nuevo ? translate('The customer replied, tap to read') : translate('Tap to open the case'),
                  style: TextStyle(fontSize: 12, color: primary, fontWeight: nuevo ? FontWeight.bold : FontWeight.normal),
                ),
              ]),
            ),
            Icon(Icons.chevron_right, color: muted),
          ]),
        ),
      ),
    );
  }

  Widget _equipo(BuildContext context) {
    final filas = staffModel.equipo;
    if (filas.isEmpty) return _mensaje(translate('No cases here'));
    return SingleChildScrollView(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columns: [
            DataColumn(label: Text(translate('Person'))),
            DataColumn(label: Text(translate('In progress')), numeric: true),
            DataColumn(label: Text(translate('Overdue')), numeric: true),
            DataColumn(label: Text(translate('Waiting for the customer')), numeric: true),
            DataColumn(label: Text(translate('Resolved in 7 days')), numeric: true),
            DataColumn(label: Text(translate('Resolved in 30 days')), numeric: true),
            DataColumn(label: Text(translate('Average first response (h)')), numeric: true),
          ],
          rows: [
            for (final f in filas.where((f) => f.activo))
              DataRow(cells: [
                DataCell(Text(f.nombre)),
                DataCell(Text('${f.enCurso}')),
                DataCell(Text('${f.vencidos}', style: TextStyle(color: f.vencidos > 0 ? Colors.red.shade700 : null))),
                DataCell(Text('${f.esperanCliente}')),
                DataCell(Text('${f.resueltos7d}')),
                DataCell(Text('${f.resueltos30d}')),
                DataCell(Text(f.horasRespuesta == null ? '—' : f.horasRespuesta!.toStringAsFixed(1))),
              ]),
          ],
        ),
      ),
    );
  }
}

/// Un caso: sus datos, los botones del personal (conectar, invitar, transferir) y la conversación con notas internas.
class _StaffCasoDialog extends StatefulWidget {
  final StaffCaso caso;
  const _StaffCasoDialog({required this.caso});

  @override
  State<_StaffCasoDialog> createState() => _StaffCasoDialogState();
}

class _StaffCasoDialogState extends State<_StaffCasoDialog> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  StaffDetalle? _d;
  String _error = '';
  bool _interno = false;
  bool _enviando = false;
  int _ultimaCantidad = -1;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    staffModel.casoAbierto = widget.caso.id;
    staffModel.casoActualizado.addListener(_alLlegarMensaje);
    _cargar();
    _timer = Timer.periodic(const Duration(seconds: 15), (_) => _cargar(quiet: true));
  }

  /// Llegó un mensaje de este caso por el canal de avisos: se muestra sin esperar al refresco periódico.
  void _alLlegarMensaje() {
    if (staffModel.casoActualizado.value.startsWith('${widget.caso.id}|')) _cargar(quiet: true);
  }

  @override
  void dispose() {
    staffModel.casoActualizado.removeListener(_alLlegarMensaje);
    if (staffModel.casoAbierto == widget.caso.id) staffModel.casoAbierto = null;
    _timer?.cancel();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _cargar({bool quiet = false}) async {
    try {
      final d = await staffModel.detalle(widget.caso.id);
      if (!mounted) return;
      final crecio = d.comentarios.length != _ultimaCantidad;
      setState(() {
        _d = d;
        _error = '';
      });
      _ultimaCantidad = d.comentarios.length;
      if (crecio) _alFinal();
    } on SupportException catch (e) {
      if (mounted && (!quiet || _d == null)) setState(() => _error = _textoError(e));
    } catch (_) {
      if (mounted && (!quiet || _d == null)) setState(() => _error = translate('Could not reach support, check your connection'));
    }
  }

  void _alFinal() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
      }
    });
  }

  Future<void> _enviar() async {
    final texto = _input.text.trim();
    if (texto.isEmpty || _enviando) return;
    setState(() => _enviando = true);
    try {
      await staffModel.comentar(widget.caso.id, texto, interno: _interno);
      _input.clear();
      await _cargar();
    } on SupportException catch (e) {
      BotToast.showText(text: _textoError(e));
    } catch (_) {
      BotToast.showText(text: translate('Could not reach support, check your connection'));
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  Future<void> _conectar(StaffDetalle d) async {
    try {
      final cred = await staffModel.conectar(d.id);
      if (!mounted) return;
      await connect(context, cred.id, password: cred.password);
    } on SupportException catch (e) {
      BotToast.showText(text: _textoError(e));
    } catch (_) {
      BotToast.showText(text: translate('Could not reach support, check your connection'));
    }
  }

  Future<void> _solicitar(StaffDetalle d) async {
    if (d.rustdeskId == null) return;
    await connect(context, d.rustdeskId!);
  }

  Future<void> _invitar(StaffDetalle d) async {
    final r = await showDialog<_Elegido>(
      context: context,
      builder: (_) => _ElegirPersonaDialog(titulo: translate('Invite a colleague'), conNota: false, excluir: {d.responsable?.id, ...d.invitados.map((e) => e.id)}),
    );
    if (r == null) return;
    try {
      BotToast.showText(text: await staffModel.invitar(d.id, r.id));
      await _cargar();
    } on SupportException catch (e) {
      BotToast.showText(text: _textoError(e));
    }
  }

  Future<void> _transferir(StaffDetalle d) async {
    final r = await showDialog<_Elegido>(
      context: context,
      builder: (_) => _ElegirPersonaDialog(titulo: translate('Transfer the case'), conNota: true, excluir: {d.responsable?.id}),
    );
    if (r == null) return;
    try {
      BotToast.showText(text: await staffModel.transferir(d.id, r.id, r.nota));
      await _cargar();
    } on SupportException catch (e) {
      BotToast.showText(text: _textoError(e));
    }
  }

  Widget _burbuja(BuildContext context, {required String autor, required String texto, DateTime? cuando, required bool mia, bool interno = false, bool cliente = false}) {
    final scheme = Theme.of(context).colorScheme;
    final Color fondo = interno
        ? Colors.amber.withOpacity(0.22)
        : mia
            ? scheme.primary.withOpacity(0.14)
            : scheme.surfaceVariant.withOpacity(0.6);
    return Align(
      alignment: mia ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: fondo, borderRadius: BorderRadius.circular(10)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              '${interno ? '${translate('Internal note')} · ' : ''}$autor · ${_fecha(cuando)}',
              style: TextStyle(fontSize: 11, color: Theme.of(context).hintColor),
            ),
            const SizedBox(height: 2),
            SelectableText(texto),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.caso;
    final d = _d;
    final estado = d?.estado ?? c.estado;
    // AlertDialog and not Dialog: common.dart defines its own Dialog class.
    return AlertDialog(
      insetPadding: const EdgeInsets.all(24),
      contentPadding: EdgeInsets.zero,
      content: SizedBox(
        width: 700,
        height: 680,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                    Text(c.folio, style: const TextStyle(fontWeight: FontWeight.bold)),
                    _StaffEtiqueta(ticketStateLabel(estado), _colorEstado(estado)),
                    _StaffEtiqueta(prioridadLabel(d?.prioridad ?? c.prioridad), _colorPrioridad(d?.prioridad ?? c.prioridad)),
                  ]),
                  Text(c.titulo, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                ]),
              ),
              IconButton(tooltip: translate('Close'), onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
            ]),
          ),
          if (d != null) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '${d.empresa.isNotEmpty ? '${translate('Company')}: ${d.empresa} · ' : ''}${translate('Customer')}: ${d.clienteNombre}'
                  '${d.rustdeskId != null ? ' · ${d.equipoNombre ?? ''} (ID ${d.rustdeskId})' : ''}'
                  ' · ${translate('Responsible')}: ${d.responsable?.nombre ?? translate('Unassigned')}'
                  '${d.invitados.isNotEmpty ? ' · ${translate('Invited')}: ${d.invitados.map((e) => e.nombre).join(', ')}' : ''}',
                  style: TextStyle(fontSize: 12, color: Theme.of(context).hintColor),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Wrap(spacing: 8, runSpacing: 6, children: [
                  if (d.puedeConectar)
                    FilledButton.icon(onPressed: () => _conectar(d), icon: const Icon(Icons.bolt, size: 18), label: Text(translate('Connect'))),
                  if (d.rustdeskId != null)
                    OutlinedButton.icon(onPressed: () => _solicitar(d), icon: const Icon(Icons.desktop_windows_outlined, size: 18), label: Text(translate('Request connection'))),
                  if (d.puedeInvitar)
                    OutlinedButton.icon(onPressed: () => _invitar(d), icon: const Icon(Icons.group_add_outlined, size: 18), label: Text(translate('Invite'))),
                  if (d.puedeTransferir)
                    OutlinedButton.icon(onPressed: () => _transferir(d), icon: const Icon(Icons.swap_horiz, size: 18), label: Text(translate('Transfer'))),
                ]),
              ),
            ),
          ],
          const SizedBox(height: 6),
          const Divider(height: 1),
          Expanded(
            child: d == null
                ? Center(child: _error.isEmpty ? const CircularProgressIndicator() : Text(_error))
                : ListView(
                    controller: _scroll,
                    padding: const EdgeInsets.all(16),
                    children: [
                      _burbuja(context, autor: d.clienteNombre, texto: d.descripcion, cuando: d.creadoEn, mia: false, cliente: true),
                      for (final m in d.comentarios)
                        _burbuja(context, autor: m.esMio ? translate('You') : m.autor, texto: m.mensaje, cuando: m.creadoEn, mia: m.esMio, interno: m.interno),
                    ],
                  ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: Column(children: [
              Row(children: [
                Checkbox(value: _interno, onChanged: _enviando ? null : (v) => setState(() => _interno = v ?? false)),
                Expanded(child: Text(translate('Internal note (the customer does not see it)'), style: const TextStyle(fontSize: 12))),
              ]),
              Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Expanded(
                  child: TextField(
                    controller: _input,
                    enabled: d != null && !_enviando,
                    minLines: 1,
                    maxLines: 4,
                    decoration: InputDecoration(
                      hintText: _interno ? translate('Write an internal note') : translate('Write a message to the customer'),
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  tooltip: translate('Send'),
                  onPressed: (d == null || _enviando) ? null : _enviar,
                  icon: _enviando
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.send),
                ),
              ]),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _Elegido {
  final String id;
  final String nota;
  const _Elegido(this.id, this.nota);
}

/// Elegir a un compañero (y, al transferir, escribir la nota de traspaso).
class _ElegirPersonaDialog extends StatefulWidget {
  final String titulo;
  final bool conNota;
  final Set<String?> excluir;
  const _ElegirPersonaDialog({required this.titulo, required this.conNota, required this.excluir});

  @override
  State<_ElegirPersonaDialog> createState() => _ElegirPersonaDialogState();
}

class _ElegirPersonaDialogState extends State<_ElegirPersonaDialog> {
  late final Future<List<StaffPersona>> _personal = staffModel.personal();
  final _nota = TextEditingController();
  String? _id;

  @override
  void dispose() {
    _nota.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.titulo),
      content: SizedBox(
        width: 420,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          FutureBuilder<List<StaffPersona>>(
            future: _personal,
            builder: (context, snap) {
              if (snap.hasError) return Text(translate('Could not reach support, check your connection'));
              final items = (snap.data ?? const <StaffPersona>[]).where((p) => !widget.excluir.contains(p.id)).toList();
              return DropdownButtonFormField<String>(
                value: _id,
                isExpanded: true,
                decoration: InputDecoration(labelText: translate('Choose a person')),
                items: items.map((p) => DropdownMenuItem(value: p.id, child: Text(p.nombre))).toList(),
                onChanged: (v) => setState(() => _id = v),
              );
            },
          ),
          if (widget.conNota) ...[
            const SizedBox(height: 8),
            TextField(
              controller: _nota,
              minLines: 2,
              maxLines: 4,
              decoration: InputDecoration(labelText: translate('Handoff note (optional)'), border: const OutlineInputBorder()),
            ),
          ],
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(translate('Cancel'))),
        FilledButton(
          onPressed: _id == null ? null : () => Navigator.pop(context, _Elegido(_id!, _nota.text.trim())),
          child: Text(translate('Accept')),
        ),
      ],
    );
  }
}
