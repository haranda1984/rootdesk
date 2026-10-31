import 'dart:async';

import 'package:bot_toast/bot_toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hbb/models/support_logic.dart';
import 'package:flutter_hbb/models/support_model.dart';

import '../../common.dart';

String _dateText(DateTime? d) => d == null ? '' : formatDateTime(d);

String _errorText(String code) {
  switch (code) {
    case 'session_expired':
      return translate('Your session expired, sign in again');
    case 'network_error':
      return translate('Could not reach support, check your connection');
    case 'datos_invalidos':
      return translate('Check the ticket data');
    case 'demasiadas_solicitudes':
      return translate('Too many requests, try again in a moment');
    case 'ticket_cerrado':
      return translate('This ticket is closed');
  }
  return '${translate('Support error')}: $code';
}

Color _stateColor(String estado) {
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

class _StateChip extends StatelessWidget {
  final String estado;
  const _StateChip(this.estado);

  @override
  Widget build(BuildContext context) {
    final c = _stateColor(estado);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: c.withOpacity(0.15), borderRadius: BorderRadius.circular(10)),
      child: Text(ticketStateLabel(estado), style: TextStyle(color: c, fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }
}

/// Pestaña "Soporte" de la pantalla principal: levantar tickets, ver su estado y conversar con soporte.
class SupportPage extends StatefulWidget {
  const SupportPage({Key? key}) : super(key: key);

  @override
  State<SupportPage> createState() => _SupportPageState();
}

class _SupportPageState extends State<SupportPage> {
  @override
  void initState() {
    super.initState();
    supportModel.startPolling();
    supportModel.refresh();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: supportModel,
      builder: (context, _) {
        switch (supportModel.status) {
          case SupportStatus.noLogin:
            return _message(translate('Sign in to use Support'));
          case SupportStatus.notConfigured:
            return _message(translate('Support is not available yet'));
          case SupportStatus.error:
            return Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text(_errorText(supportModel.errorMessage)),
              const SizedBox(height: 12),
              OutlinedButton(onPressed: supportModel.refresh, child: Text(translate('Retry'))),
            ]);
          case SupportStatus.idle:
          case SupportStatus.loading:
            if (supportModel.tickets.isEmpty) return const Center(child: CircularProgressIndicator());
            return _content(context);
          case SupportStatus.ready:
            return _content(context);
        }
      },
    );
  }

  Widget _message(String text) => Center(child: Text(text, textAlign: TextAlign.center));

  Widget _content(BuildContext context) {
    final tickets = supportModel.tickets;
    final open = tickets.where((t) => t.abierto).toList();
    final closed = tickets.where((t) => !t.abierto).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          ElevatedButton.icon(
            onPressed: () => _newTicket(context),
            icon: const Icon(Icons.add, size: 18),
            label: Text(translate('New ticket')),
          ),
          const SizedBox(width: 8),
          IconButton(
            tooltip: translate('Refresh'),
            onPressed: supportModel.refresh,
            icon: const Icon(Icons.refresh),
          ),
        ]),
        const SizedBox(height: 8),
        Expanded(
          child: tickets.isEmpty
              ? _message(translate('No tickets yet'))
              : ListView(
                  children: [
                    if (open.isNotEmpty) _header('${translate('Open tickets')} (${open.length})'),
                    for (final t in open) _ticketTile(context, t),
                    if (closed.isNotEmpty) _header('${translate('Finished tickets')} (${closed.length})'),
                    for (final t in closed) _ticketTile(context, t),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _header(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 10, 4, 4),
        child: Text(text, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 0.4)),
      );

  Widget _ticketTile(BuildContext context, TicketSummary t) {
    final now = DateTime.now();
    final unread = supportModel.unread(t);
    final active = t.soporteActivo(now);
    final primary = Theme.of(context).colorScheme.primary;
    final muted = Theme.of(context).hintColor;
    final when = t.actividadEn != null ? relativeTime(t.actividadEn!, now) : '';
    final count = t.mensajes == 0 ? translate('No messages yet') : '${t.mensajes} ${translate('messages')}';
    return Card(
      margin: const EdgeInsets.only(bottom: 6, right: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: unread ? primary : Theme.of(context).dividerColor),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => _openChat(context, t),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(children: [
            Badge(
              isLabelVisible: unread,
              smallSize: 10,
              child: Icon(Icons.chat_bubble_outline, color: primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Text(t.folio, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                  const SizedBox(width: 8),
                  _StateChip(t.estado),
                  if (active) ...[
                    const SizedBox(width: 8),
                    Tooltip(message: translate('Support can connect'), child: const Icon(Icons.verified_user, size: 16)),
                  ],
                ]),
                const SizedBox(height: 2),
                Text(t.titulo, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                Text('$when · $count', style: TextStyle(fontSize: 12, color: muted)),
                const SizedBox(height: 2),
                Text(
                  unread ? translate('Support replied, tap to read') : translate('Tap to open the conversation'),
                  style: TextStyle(fontSize: 12, color: primary, fontWeight: unread ? FontWeight.bold : FontWeight.normal),
                ),
              ]),
            ),
            Icon(Icons.chevron_right, color: muted),
          ]),
        ),
      ),
    );
  }

  Future<void> _newTicket(BuildContext context) async {
    final created = await showDialog<CreatedTicket>(context: context, builder: (_) => const _NewTicketDialog());
    if (created == null || !context.mounted) return;
    final String text;
    switch (created.soporte) {
      case 'activo':
        text = '${translate('Ticket created')} ${created.folio}. ${translate('Support can connect to your computer until')} ${_dateText(created.soporteHasta)}.';
        break;
      case 'no_vinculado':
        text = '${translate('Ticket created')} ${created.folio}. ${translate('Your computer is not linked to your account, support will ask you to accept the connection')}.';
        break;
      case 'error':
        text = '${translate('Ticket created')} ${created.folio}. ${translate('The direct connection could not be enabled, support will ask you to accept it')}.';
        break;
      default:
        text = '${translate('Ticket created')} ${created.folio}.';
    }
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: Text(text),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: Text(translate('OK')))],
      ),
    );
  }

  Future<void> _openChat(BuildContext context, TicketSummary t) async {
    await showDialog<void>(context: context, builder: (_) => _TicketChatDialog(ticket: t));
  }
}

class _NewTicketDialog extends StatefulWidget {
  const _NewTicketDialog();

  @override
  State<_NewTicketDialog> createState() => _NewTicketDialogState();
}

class _NewTicketDialogState extends State<_NewTicketDialog> {
  final _title = TextEditingController();
  final _description = TextEditingController();
  late final Future<List<TicketCategory>> _categories = supportModel.categories();
  late final Future<bool> _linked = supportModel.deviceLinked();
  String? _category;
  bool _consent = false;
  bool _sending = false;
  String _error = '';

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final title = _title.text.trim();
    final description = _description.text.trim();
    if (_category == null || title.length < 5 || description.length < 10) {
      setState(() => _error = translate('Choose a category, a title (5+ characters) and describe the problem (10+ characters)'));
      return;
    }
    setState(() {
      _sending = true;
      _error = '';
    });
    try {
      final created = await supportModel.create(
        titulo: title,
        descripcion: description,
        categoriaId: _category!,
        autorizaSoporte: _consent,
      );
      if (mounted) Navigator.pop(context, created);
    } on SupportException catch (e) {
      if (mounted) {
        setState(() {
          _sending = false;
          _error = e.detail.isNotEmpty ? e.detail : _errorText(e.unauthorized ? 'session_expired' : e.code);
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _sending = false;
          _error = _errorText('network_error');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(translate('New ticket')),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            FutureBuilder<List<TicketCategory>>(
              future: _categories,
              builder: (context, snap) {
                if (snap.hasError) return Text(_errorText('network_error'));
                final items = snap.data ?? const <TicketCategory>[];
                return DropdownButtonFormField<String>(
                  value: _category,
                  isExpanded: true,
                  decoration: InputDecoration(labelText: translate('Category')),
                  items: items.map((c) => DropdownMenuItem(value: c.id, child: Text(c.nombre))).toList(),
                  onChanged: _sending ? null : (v) => setState(() => _category = v),
                );
              },
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _title,
              enabled: !_sending,
              maxLength: 140,
              decoration: InputDecoration(labelText: translate('Title')),
            ),
            TextField(
              controller: _description,
              enabled: !_sending,
              minLines: 4,
              maxLines: 6,
              maxLength: 5000,
              decoration: InputDecoration(labelText: translate('Describe the problem')),
            ),
            FutureBuilder<bool>(
              future: _linked,
              builder: (context, snap) {
                final linked = snap.data == true;
                return CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: linked && _consent,
                  onChanged: (_sending || !linked) ? null : (v) => setState(() => _consent = v ?? false),
                  title: Text(translate('I allow support to connect to my computer')),
                  subtitle: Text(snap.connectionState != ConnectionState.done
                      ? ''
                      : linked
                          ? translate('Only for this ticket, up to 24 hours. You can revoke it at any time.')
                          : translate('Your computer is not linked to your account, support will ask you to accept the connection')),
                );
              },
            ),
            if (_error.isNotEmpty) Text(_error, style: const TextStyle(color: Colors.red)),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: _sending ? null : () => Navigator.pop(context), child: Text(translate('Cancel'))),
        ElevatedButton(
          onPressed: _sending ? null : _submit,
          child: _sending
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : Text(translate('Create ticket')),
        ),
      ],
    );
  }
}

/// Conversación de UN ticket: cada ticket abre su propia caja de chat, identificada por su folio,
/// y solo muestra los mensajes de ese ticket.
class _TicketChatDialog extends StatefulWidget {
  final TicketSummary ticket;
  const _TicketChatDialog({required this.ticket});

  @override
  State<_TicketChatDialog> createState() => _TicketChatDialogState();
}

class _TicketChatDialogState extends State<_TicketChatDialog> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  TicketDetail? _detail;
  String _error = '';
  bool _sending = false;
  int _lastCount = -1;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _load();
    // Mientras la conversación está abierta se revisa cada pocos segundos si soporte contestó.
    _timer = Timer.periodic(const Duration(seconds: 15), (_) => _load(quiet: true));
  }

  @override
  void dispose() {
    _timer?.cancel();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load({bool quiet = false}) async {
    try {
      final d = await supportModel.detail(widget.ticket.id);
      if (!mounted) return;
      final grew = d.comentarios.length != _lastCount;
      setState(() {
        _detail = d;
        _error = '';
      });
      _lastCount = d.comentarios.length;
      if (grew) _scrollToEnd();
    } on SupportException catch (e) {
      if (mounted && (!quiet || _detail == null)) {
        setState(() => _error = _errorText(e.unauthorized ? 'session_expired' : e.code));
      }
    } catch (_) {
      if (mounted && (!quiet || _detail == null)) setState(() => _error = _errorText('network_error'));
    }
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
      }
    });
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await supportModel.sendMessage(widget.ticket.id, text);
      _input.clear();
      await _load();
    } on SupportException catch (e) {
      BotToast.showText(text: e.detail.isNotEmpty ? e.detail : _errorText(e.unauthorized ? 'session_expired' : e.code));
    } catch (_) {
      BotToast.showText(text: _errorText('network_error'));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _revoke() async {
    try {
      await supportModel.revoke(widget.ticket.id);
      BotToast.showText(text: translate('Support access revoked'));
      await _load();
    } catch (_) {
      BotToast.showText(text: translate('Could not revoke, try again'));
    }
  }

  Widget _bubble(BuildContext context, {required String author, required String text, DateTime? at, required bool mine}) {
    final scheme = Theme.of(context).colorScheme;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: mine ? scheme.primary.withOpacity(0.14) : scheme.surfaceVariant.withOpacity(0.6),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('$author · ${_dateText(at)}', style: TextStyle(fontSize: 11, color: Theme.of(context).hintColor)),
            const SizedBox(height: 2),
            SelectableText(text),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.ticket;
    final d = _detail;
    final estado = d?.resumen.estado ?? t.estado;
    final canWrite = d != null && d.resumen.estado != 'cerrado' && d.resumen.estado != 'cancelado';
    final active = d?.resumen.soporteActivo(DateTime.now()) ?? false;
    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      child: SizedBox(
        width: 560,
        height: 620,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Text(t.folio, style: const TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(width: 8),
                    _StateChip(estado),
                  ]),
                  Text(t.titulo, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                ]),
              ),
              IconButton(tooltip: translate('Close'), onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
            ]),
          ),
          if (active)
            Container(
              color: Colors.amber.withOpacity(0.18),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(children: [
                const Icon(Icons.verified_user, size: 18),
                const SizedBox(width: 8),
                Expanded(child: Text('${translate('Support can connect to your computer until')} ${_dateText(d!.resumen.soporteHasta)}')),
                TextButton(onPressed: _revoke, child: Text(translate('Revoke'))),
              ]),
            ),
          const Divider(height: 1),
          Expanded(
            child: d == null
                ? Center(child: _error.isEmpty ? const CircularProgressIndicator() : Text(_error))
                : ListView(
                    controller: _scroll,
                    padding: const EdgeInsets.all(16),
                    children: [
                      _bubble(context, author: translate('Your request'), text: d.descripcion, at: d.resumen.creadoEn, mine: true),
                      for (final c in d.comentarios)
                        _bubble(context, author: c.esMio ? translate('You') : c.autor, text: c.mensaje, at: c.creadoEn, mine: c.esMio),
                    ],
                  ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(12),
            child: d != null && !canWrite
                ? Text(translate('This ticket is closed, open a new one if you need anything else'),
                    style: TextStyle(color: Theme.of(context).hintColor))
                : Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Expanded(
                      child: TextField(
                        controller: _input,
                        enabled: d != null && !_sending,
                        minLines: 1,
                        maxLines: 4,
                        decoration: InputDecoration(
                          hintText: translate('Write a message to support'),
                          border: const OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filled(
                      tooltip: translate('Send'),
                      onPressed: (d == null || _sending) ? null : _send,
                      icon: _sending
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.send),
                    ),
                  ]),
          ),
        ]),
      ),
    );
  }
}

/// Aviso permanente (sobre la lista de equipos) mientras haya un permiso de soporte vigente.
class SupportBanner extends StatefulWidget {
  const SupportBanner({Key? key}) : super(key: key);

  @override
  State<SupportBanner> createState() => _SupportBannerState();
}

class _SupportBannerState extends State<SupportBanner> {
  @override
  void initState() {
    super.initState();
    supportModel.startPolling();
  }

  Future<void> _revoke(TicketSummary t) async {
    try {
      await supportModel.revoke(t.id);
      BotToast.showText(text: translate('Support access revoked'));
    } catch (_) {
      BotToast.showText(text: translate('Could not revoke, try again'));
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: supportModel,
      builder: (context, _) {
        final t = supportModel.activeTicket;
        if (t == null) return const SizedBox.shrink();
        return Container(
          margin: const EdgeInsets.only(right: 12, bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.amber.withOpacity(0.18),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: Colors.amber.shade700),
          ),
          child: Row(children: [
            const Icon(Icons.verified_user, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text('${translate('Support can connect to your computer until')} ${_dateText(t.soporteHasta)} · ${t.folio}'),
            ),
            TextButton(onPressed: () => _revoke(t), child: Text(translate('Revoke'))),
          ]),
        );
      },
    );
  }
}
