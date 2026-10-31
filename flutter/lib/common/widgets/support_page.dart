import 'package:bot_toast/bot_toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hbb/models/support_logic.dart';
import 'package:flutter_hbb/models/support_model.dart';

import '../../common.dart';

String _dateText(BuildContext context, DateTime? d) {
  if (d == null) return '';
  final day = '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
  return '$day ${TimeOfDay.fromDateTime(d).format(context)}';
}

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
  }
  return '${translate('Support error')}: $code';
}

/// Pestaña "Soporte" de la pantalla principal: levantar tickets y ver su estado.
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
              : ListView.separated(
                  itemCount: tickets.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, i) => _ticketTile(context, tickets[i]),
                ),
        ),
      ],
    );
  }

  Widget _ticketTile(BuildContext context, TicketSummary t) {
    final active = t.soporteActivo(DateTime.now());
    return ListTile(
      dense: true,
      title: Text('${t.folio} · ${t.titulo}', maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text('${ticketStateLabel(t.estado)} · ${_dateText(context, t.creadoEn)}'),
      trailing: active ? Tooltip(message: translate('Support can connect'), child: const Icon(Icons.verified_user, size: 18)) : null,
      onTap: () => _showDetail(context, t),
    );
  }

  Future<void> _newTicket(BuildContext context) async {
    final created = await showDialog<CreatedTicket>(context: context, builder: (_) => const _NewTicketDialog());
    if (created == null || !context.mounted) return;
    final String text;
    switch (created.soporte) {
      case 'activo':
        text = '${translate('Ticket created')} ${created.folio}. ${translate('Support can connect to your computer until')} ${_dateText(context, created.soporteHasta)}.';
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

  Future<void> _showDetail(BuildContext context, TicketSummary t) async {
    await showDialog<void>(context: context, builder: (_) => _TicketDetailDialog(ticket: t));
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

class _TicketDetailDialog extends StatefulWidget {
  final TicketSummary ticket;
  const _TicketDetailDialog({required this.ticket});

  @override
  State<_TicketDetailDialog> createState() => _TicketDetailDialogState();
}

class _TicketDetailDialogState extends State<_TicketDetailDialog> {
  late Future<TicketDetail> _detail = supportModel.detail(widget.ticket.id);

  Future<void> _revoke() async {
    try {
      await supportModel.revoke(widget.ticket.id);
      BotToast.showText(text: translate('Support access revoked'));
      if (mounted) setState(() => _detail = supportModel.detail(widget.ticket.id));
    } catch (_) {
      BotToast.showText(text: translate('Could not revoke, try again'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.ticket;
    return AlertDialog(
      title: Text('${t.folio} · ${t.titulo}'),
      content: SizedBox(
        width: 480,
        child: FutureBuilder<TicketDetail>(
          future: _detail,
          builder: (context, snap) {
            if (snap.hasError) return Text(_errorText('network_error'));
            final d = snap.data;
            if (d == null) return const SizedBox(height: 80, child: Center(child: CircularProgressIndicator()));
            final active = d.resumen.soporteActivo(DateTime.now());
            return SingleChildScrollView(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text('${translate('Status')}: ${ticketStateLabel(d.resumen.estado)}'),
                const SizedBox(height: 8),
                Text(d.descripcion),
                if (active) ...[
                  const SizedBox(height: 12),
                  Row(children: [
                    const Icon(Icons.verified_user, size: 18),
                    const SizedBox(width: 6),
                    Expanded(child: Text('${translate('Support can connect to your computer until')} ${_dateText(context, d.resumen.soporteHasta)}')),
                    TextButton(onPressed: _revoke, child: Text(translate('Revoke'))),
                  ]),
                ],
                if (d.comentarios.isNotEmpty) ...[
                  const Divider(height: 24),
                  for (final c in d.comentarios)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('${c.autor} · ${_dateText(context, c.creadoEn)}', style: Theme.of(context).textTheme.bodySmall),
                        Text(c.mensaje),
                      ]),
                    ),
                ],
              ]),
            );
          },
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text(translate('Close')))],
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
              child: Text('${translate('Support can connect to your computer until')} ${_dateText(context, t.soporteHasta)} · ${t.folio}'),
            ),
            TextButton(onPressed: () => _revoke(t), child: Text(translate('Revoke'))),
          ]),
        );
      },
    );
  }
}
