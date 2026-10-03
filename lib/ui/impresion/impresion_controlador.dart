// Estado de la pantalla de impresión (fase 10, prioridad 3): configuración
// de la terminal Point que imprime, carpeta de PDFs, y la búsqueda mínima
// para reimprimir una venta pasada (adelantada de la fase 9 — Historial).

import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;

import '../../data/database.dart';
import '../../data/pdf_ticket.dart';
import '../../data/repositorio_ticket.dart';
import '../../domain/ticket.dart';
import '../../servicios/impresion_posnet_nube.dart';
import '../../servicios/marca_actual.dart';
import '../../servicios/nube.dart' show nubeApp;
import '../../servicios/preferencia_cobro_nube.dart';

class ImpresionControlador extends ChangeNotifier {
  ImpresionControlador(this.db, {this.httpClientDePrueba});

  final AppDatabase db;

  /// Solo para tests: evita que un test dispare una llamada de red real.
  final http.Client? httpClientDePrueba;

  String? mpAccessToken;
  String? mpTerminalId;
  String? mpTerminalCobroId;
  String? carpetaTickets;

  /// Interruptor de prueba (de este equipo): cobrar e imprimir por la integración Nodo Sur aunque haya un access token cargado.
  bool usarNodoSur = false;

  List<FilaVenta> resultados = [];
  String? mensaje;
  bool procesando = false;
  bool cargando = true;

  bool get posnetConfigurado => (mpAccessToken != null && mpTerminalId != null) || usarNodoSur;

  Future<void> cargarTodo() async {
    final config = await db.select(db.configuracionTabla).getSingle();
    mpAccessToken = config.mpAccessToken;
    mpTerminalId = config.mpTerminalId;
    mpTerminalCobroId = config.mpTerminalCobroId;
    carpetaTickets = config.rutaTicketsCarpeta;
    usarNodoSur = PreferenciaCobroNube.activo;
    resultados = await buscarVentasParaReimprimir(db);
    cargando = false;
    notifyListeners();
  }

  Future<void> cambiarUsarNodoSur(bool valor) async {
    await PreferenciaCobroNube.guardar(valor);
    usarNodoSur = valor;
    notifyListeners();
  }

  Future<void> guardarAccessToken(String valor) async {
    await configurarMpAccessToken(
      db,
      valor.trim().isEmpty ? null : valor.trim(),
    );
    await cargarTodo();
  }

  Future<void> guardarTerminalId(String valor) async {
    await configurarMpTerminalId(
      db,
      valor.trim().isEmpty ? null : valor.trim(),
    );
    await cargarTodo();
  }

  Future<void> guardarTerminalCobroId(String valor) async {
    await configurarMpTerminalCobroId(
      db,
      valor.trim().isEmpty ? null : valor.trim(),
    );
    await cargarTodo();
  }

  Future<void> guardarCarpetaTickets(String ruta) async {
    await configurarCarpetaTickets(db, ruta);
    await cargarTodo();
  }

  Future<void> buscar({DateTime? fecha, int? numero}) async {
    resultados = await buscarVentasParaReimprimir(
      db,
      fecha: fecha,
      numero: numero,
    );
    notifyListeners();
  }

  Future<void> ticketDePrueba() => _accion(() async {
    final ticket = construirTicket(
      fecha: DateTime.now(),
      vendedor: 'Prueba',
      lineas: const [
        LineaTicket(
          nombreProducto: 'Producto de prueba',
          cantidad: 1,
          subtotalCentavos: 100000,
        ),
      ],
      desglose: const DesgloseTicket(),
    );
    await _imprimir(ticket);
    return 'Ticket de prueba enviado a la terminal';
  });

  Future<void> reimprimirEnPosnet(int ventaId) => _accion(() async {
    final ticket = await ticketDeVenta(db, ventaId);
    await _imprimir(ticket);
    return 'Enviado a la terminal';
  });

  Future<void> guardarPdf(int ventaId) => _accion(() async {
    final carpeta = carpetaTickets;
    if (carpeta == null) {
      throw StateError('Falta configurar la carpeta de tickets');
    }
    final ruta = await guardarTicketPdf(
      db,
      ventaId: ventaId,
      carpetaDestino: carpeta,
      encabezadoNegocio: (await marcaDeBase(db)).encabezadoTicketEfectivo,
    );
    return 'Guardado en $ruta';
  });

  Future<void> _imprimir(Ticket ticket) async {
    if (!posnetConfigurado) {
      throw StateError('Falta configurar el access token o el terminal id');
    }
    await imprimirTicketPosnet(
      accessToken: mpAccessToken,
      terminalId: mpTerminalId,
      terminalCobroId: mpTerminalCobroId,
      forzarNube: usarNodoSur,
      almacen: nubeApp?.almacen,
      cliente: nubeApp?.cliente,
      ticket: ticket,
      encabezadoNegocio: (await marcaDeBase(db)).encabezadoTicketEfectivo,
      client: httpClientDePrueba,
    );
  }

  Future<void> _accion(Future<String> Function() cuerpo) async {
    procesando = true;
    mensaje = null;
    notifyListeners();
    try {
      mensaje = await cuerpo();
    } catch (e) {
      mensaje = 'Error: $e';
    }
    procesando = false;
    notifyListeners();
  }
}
