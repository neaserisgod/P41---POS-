// Acción puntual sobre una venta ya cobrada (botón manual, nunca automático
// — Regla de esta fase, confirmada por el dueño: nunca bloquea ni demora la
// venta si la impresora falla o no está conectada). Reusa exactamente las
// mismas funciones que la pantalla de Impresión, sin abrirla entera.

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../data/database.dart';
import '../../data/numero_venta.dart';
import '../../data/pdf_ticket.dart';
import '../../data/repositorio_ticket.dart';
import '../tema/tokens.dart';
import '../comun/botones.dart';
import '../comun/modal.dart';
import '../../servicios/impresion_posnet_nube.dart';
import '../../servicios/marca_actual.dart';
import '../../servicios/nube.dart' show nubeApp;
import '../../servicios/preferencia_cobro_nube.dart';

Future<void> mostrarDialogoImprimirTicket(
  BuildContext context, {
  required AppDatabase db,
  required int ventaId,
}) {
  return showDialog<void>(
    context: context,
    builder: (context) => _DialogoImprimirTicket(db: db, ventaId: ventaId),
  );
}

class _DialogoImprimirTicket extends StatefulWidget {
  const _DialogoImprimirTicket({required this.db, required this.ventaId});

  final AppDatabase db;
  final int ventaId;

  @override
  State<_DialogoImprimirTicket> createState() => _DialogoImprimirTicketState();
}

class _DialogoImprimirTicketState extends State<_DialogoImprimirTicket> {
  Configuracion? _config;
  bool _procesando = false;
  String? _mensaje;
  String? _numero;

  @override
  void initState() {
    super.initState();
    (widget.db.select(widget.db.ventas)..where((v) => v.id.equals(widget.ventaId))).getSingleOrNull().then((venta) {
      if (mounted && venta != null) setState(() => _numero = etiquetaDeVenta(id: venta.id, numero: venta.numero));
    });
    widget.db.select(widget.db.configuracionTabla).getSingle().then((config) {
      if (mounted) setState(() => _config = config);
    });
  }

  Future<void> _accion(Future<String> Function() cuerpo) async {
    setState(() {
      _procesando = true;
      _mensaje = null;
    });
    String resultado;
    try {
      resultado = await cuerpo();
    } catch (e) {
      resultado = 'Error: $e';
    }
    if (!mounted) return;
    setState(() {
      _procesando = false;
      _mensaje = resultado;
    });
  }

  Future<void> _enviarAPosnet() => _accion(() async {
        final config = _config!;
        final ticket = await ticketDeVenta(widget.db, widget.ventaId);
        await imprimirTicketPosnet(
          accessToken: config.mpAccessToken,
          terminalId: config.mpTerminalId,
          terminalCobroId: config.mpTerminalCobroId,
          forzarNube: PreferenciaCobroNube.activo,
          almacen: nubeApp?.almacen,
          cliente: nubeApp?.cliente,
          ticket: ticket,
          encabezadoNegocio: (await marcaDeBase(widget.db)).encabezadoTicketEfectivo,
        );
        return 'Enviado a la terminal';
      });

  Future<void> _guardarPdf() => _accion(() async {
        var carpeta = _config!.rutaTicketsCarpeta;
        if (carpeta == null) {
          // Antes esto solo avisaba que faltaba configurar la carpeta en
          // otra pantalla — bug real reportado por el dueño: "doy a imprimir y
          // no sale nada de seleccionar". La primera vez que hace falta, se
          // pregunta acá mismo, sin mandar a otro lado.
          carpeta = await getDirectoryPath();
          if (carpeta == null) return 'Cancelado: no se eligió carpeta';
          await configurarCarpetaTickets(widget.db, carpeta);
          _config = await widget.db.select(widget.db.configuracionTabla).getSingle();
        }
        final ruta = await guardarTicketPdf(
          widget.db,
          ventaId: widget.ventaId,
          carpetaDestino: carpeta,
          encabezadoNegocio: (await marcaDeBase(widget.db)).encabezadoTicketEfectivo,
        );
        return 'Guardado en $ruta';
      });

  @override
  Widget build(BuildContext context) {
    final listo = _config != null;
    return Modal(
      titulo: 'Imprimir ticket',
      subtitulo: 'Venta ${_numero ?? '#${widget.ventaId}'}',
      contenido: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          BotonPrimario(
            texto: 'Enviar a posnet',
            onPressed: listo && !_procesando ? _enviarAPosnet : null,
          ),
          const SizedBox(height: Espaciado.sm),
          BotonSecundario(
            texto: 'Guardar PDF',
            onPressed: listo && !_procesando ? _guardarPdf : null,
          ),
          if (_mensaje != null) ...[
            const SizedBox(height: Espaciado.md),
            Text(
              _mensaje!,
              style: TextStyle(
                color: _mensaje!.startsWith('Error') ? context.colores.error : context.colores.textoSecundario,
              ),
            ),
          ],
        ],
      ),
      botones: [BotonSecundario(texto: 'Cerrar', onPressed: () => Navigator.of(context).pop())],
    );
  }
}
