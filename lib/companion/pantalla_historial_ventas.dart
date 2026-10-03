// Historial de ventas, filtrable — "tipo Mercado Pago" (El dueño,
// 2026-09-07: "hagamos la sección de reportes para móvil con el
// historial de ventas... que sea filtrable... digamos que quiero que
// también sirva para un control manual en caso de desconfiar de los
// números"). Separar/retener/retirar sigue siendo pantalla exclusiva del
// escritorio ("Reportes").
//
// Eliminar una venta (El dueño, 2026-09-13) se agregó acá: solo mientras la
// sesión de caja de esa venta siga abierta (`v.sesionAbierta`, calculado
// del lado del servidor — anular una venta de un cierre ya arqueado
// descuadraría ese arqueo). Revierte stock y caja (misma lógica que editar
// en escritorio, `anularVenta`), pero nunca borra la venta — queda
// marcada, para no perder el rastro (Regla 6).

import 'dart:async';

import 'package:flutter/material.dart';

import '../domain/dinero.dart';
import '../ui/tema/tokens.dart';
import 'cambios_companion.dart';
import 'base_local.dart';
import 'cliente_companion.dart';
import 'emparejamiento.dart';
import 'mensaje_error.dart';
import 'navbar_companion.dart';
import 'puerto_local.dart';
import 'seleccion_servicio.dart';
import 'servicio_companion.dart';
import 'servicio_companion_offline.dart';
import 'tema/piezas_companion.dart';
import 'tema/tema_companion.dart';
import 'tema/hoja_vidrio.dart';
import 'tema/esqueleto_companion.dart';
import '../ui/comun/estado_error.dart';
import '../ui/comun/estado_vacio.dart';
import 'tema/chip_seleccionable.dart';
import 'tema/presionable.dart';
import '../ui/tema/iconos.dart';
import 'tema/error_en_linea.dart';

enum _Periodo { hoy, ayer, ultimaSemana, esteMes }

extension on _Periodo {
  String get etiqueta => switch (this) {
    _Periodo.hoy => 'Hoy',
    _Periodo.ayer => 'Ayer',
    _Periodo.ultimaSemana => 'Últimos 7 días',
    _Periodo.esteMes => 'Este mes',
  };

  ({DateTime desde, DateTime hasta}) rango() {
    final ahora = DateTime.now();
    final hoy = DateTime(ahora.year, ahora.month, ahora.day);
    return switch (this) {
      _Periodo.hoy => (desde: hoy, hasta: hoy.add(const Duration(days: 1))),
      _Periodo.ayer => (
        desde: hoy.subtract(const Duration(days: 1)),
        hasta: hoy,
      ),
      _Periodo.ultimaSemana => (
        desde: hoy.subtract(const Duration(days: 6)),
        hasta: hoy.add(const Duration(days: 1)),
      ),
      _Periodo.esteMes => (
        desde: DateTime(ahora.year, ahora.month, 1),
        hasta: hoy.add(const Duration(days: 1)),
      ),
    };
  }
}

extension on MedioVentaHistorialCompanion {
  String get etiqueta => switch (this) {
    MedioVentaHistorialCompanion.efectivo => 'Efectivo',
    MedioVentaHistorialCompanion.qr => 'QR',
    MedioVentaHistorialCompanion.debitCard => 'Débito',
    MedioVentaHistorialCompanion.mixto => 'Mixto',
  };
}

class PantallaHistorialVentas extends StatefulWidget {
  const PantallaHistorialVentas({super.key});

  @override
  State<PantallaHistorialVentas> createState() =>
      _PantallaHistorialVentasState();
}

class _PantallaHistorialVentasState extends State<PantallaHistorialVentas> {
  ServicioCompanion? _cliente;
  int? _usuarioId;
  _Periodo _periodo = _Periodo.hoy;
  MedioVentaHistorialCompanion? _filtroMedio;
  List<VentaDelHistorialCompanion> _ventas = [];
  bool _cargando = true;
  String? _error;

  /// La venta cuyo detalle está desplegado en la lista (una a la vez) y los
  /// detalles ya traídos: el resumen de cada fila viene sin líneas
  /// (`historialDeVentas`), así que se piden recién al abrirla (mismo `Ticket`
  /// que la impresión, Regla 3).
  int? _ventaAbierta;
  final Map<int, DetalleVentaCompanion> _detalles = {};
  String? _errorDetalle;

  /// El dueño, 2026-09-18: "no hay nada que actualice la app cuando se
  /// sincronizó" — repite la carga sola apenas la sync trae algo nuevo.
  /// El dueño, 2026-09-19: "las pantallas se refrescan en cada sync, cosa que
  /// me gustaría que se disimule más" — con el nudge de baja latencia de
  /// `sincronizacion_supabase.dart` esto pasa mucho más seguido, así que el
  /// refresco automático es [silencioso]: no tapa la lista ya visible con
  /// el spinner ni con una pantalla de error por un hiccup transitorio de
  /// wifi (se reintenta solo en la próxima sync). Un refresco explícito
  /// (pull-to-refresh, cambiar de período o de filtro) sigue mostrando
  /// ambos como siempre.
  StreamSubscription<void>? _subCambiosSync;

  @override
  void initState() {
    super.initState();
    leerUsuario().then((u) {
      if (mounted) setState(() => _usuarioId = u?.id);
    });
    _cargar();
    _subCambiosSync = avisosCambiosCompanion.listen(
      (_) => _cargar(silencioso: true),
    );
  }

  @override
  void dispose() {
    _subCambiosSync?.cancel();
    super.dispose();
  }

  Future<void> _cargar({bool silencioso = false}) async {
    if (!silencioso) {
      setState(() {
        _cargando = true;
        _error = null;
      });
    }
    try {
      final conexion = await leerConexion();
      final cliente =
          _cliente ??
          (conexion == null
              ? ServicioCompanionOffline(PuertoLocal(baseLocalCompanion()))
              : await resolverServicioCompanion(conexion));
      final rango = _periodo.rango();
      final ventas = await cliente.historialDeVentas(
        desde: rango.desde,
        hasta: rango.hasta,
        filtroMedio: _filtroMedio,
      );
      if (mounted) {
        setState(() {
          _cliente = cliente;
          _ventas = ventas;
        });
      }
    } catch (e) {
      if (mounted && !silencioso) setState(() => _error = mensajeDeError(e));
    } finally {
      if (mounted && !silencioso) setState(() => _cargando = false);
    }
  }

  Future<void> _alternarDetalle(VentaDelHistorialCompanion v) async {
    if (_ventaAbierta == v.ventaId) {
      setState(() => _ventaAbierta = null);
      return;
    }
    setState(() {
      _ventaAbierta = v.ventaId;
      _errorDetalle = null;
    });
    if (_detalles.containsKey(v.ventaId) || _cliente == null) return;
    try {
      final detalle = await _cliente!.detalleVenta(v.ventaId);
      if (mounted) setState(() => _detalles[v.ventaId] = detalle);
    } catch (e) {
      if (mounted) setState(() => _errorDetalle = mensajeDeError(e));
    }
  }

  void _elegirPeriodo(_Periodo p) {
    if (p == _periodo) return;
    setState(() => _periodo = p);
    _cargar();
  }

  void _elegirMedio(MedioVentaHistorialCompanion? m) {
    if (m == _filtroMedio) return;
    setState(() => _filtroMedio = m);
    _cargar();
  }

  Future<void> _confirmarYAnular(VentaDelHistorialCompanion v) async {
    final motivoCtrl = TextEditingController();
    final motivo = await mostrarHojaVidrio<String>(
      context,
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '¿Anular la venta de ${formatearARS(v.totalCentavos)}?',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: Espaciado.sm),
          Text(
            'Se repone el stock y se revierte la caja. La venta sigue viéndose acá, marcada como anulada.',
            style: TextStyle(color: context.colores.textoSecundario),
          ),
          const SizedBox(height: Espaciado.md),
          TextField(
            controller: motivoCtrl,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Motivo'),
          ),
          const SizedBox(height: Espaciado.lg),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancelar'),
                ),
              ),
              const SizedBox(width: Espaciado.sm),
              Expanded(
                child: FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: context.colores.error),
                  onPressed: () => Navigator.of(context).pop(motivoCtrl.text.trim()),
                  child: const Text('Anular'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
    motivoCtrl.dispose();
    if (motivo == null || motivo.isEmpty || _cliente == null || _usuarioId == null) {
      return;
    }
    try {
      await _cliente!.anularVenta(
        ventaId: v.ventaId,
        usuarioId: _usuarioId!,
        motivo: motivo,
      );
      _cargar();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(mensajeDeError(e))));
      }
    }
  }

  /// Antes eran dos filas rotuladas ("Período"/"Medio de pago") de chips
  /// horizontales — El dueño, 2026-09-13: "comen demasiado espacio y es muy
  /// confuso" (no quedaba claro que esas filas se podían deslizar). Un
  /// menú desplegable compacto por filtro dice el valor elegido Y da
  /// acceso a cambiarlo en el mismo lugar, sin ocupar una fila propia ni
  /// esconder opciones fuera de la pantalla.
  Widget _selectorPeriodo(BuildContext context) {
    return PopupMenuButton<_Periodo>(
      initialValue: _periodo,
      onSelected: _elegirPeriodo,
      itemBuilder: (context) => [
        for (final p in _Periodo.values)
          PopupMenuItem(value: p, child: Text(p.etiqueta)),
      ],
      child: _Pildora(icono: IconosPlazoleta.calendarTodayOutlined, texto: _periodo.etiqueta),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Una venta anulada no suma al total del período — su plata ya se
    // revirtió de la caja (`anularVenta`), contarla igual mostraría más de
    // lo que de verdad entró.
    final total = _ventas.where((v) => !v.anulada).fold<int>(0, (acc, v) => acc + v.totalCentavos);
    final resumen = _cargando || _error != null
        ? null
        : '${_ventas.length} ${_ventas.length == 1 ? 'venta' : 'ventas'} · ${formatearARS(total)}';
    // Los cierres ya no son una pestaña de acá: viven en Gestión → Cierres
    // anteriores, como en el mock completo del celular.
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            EncabezadoCompanion(
              titulo: 'Historial',
              bajada: resumen,
              padding: const EdgeInsets.fromLTRB(Espaciado.xl, Espaciado.xl, Espaciado.xl, Espaciado.md),
            ),
            _filaFiltrosVentas(context),
            const SizedBox(height: Espaciado.sm),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Espaciado.lg),
                child: ErrorEnLinea(_error!),
              ),
            Expanded(
              child: _cargando
                  ? const EsqueletoLista()
                  : _error != null
                  ? EstadoError(mensaje: _error!, onReintentar: _cargar)
                  : _ventas.isEmpty
                  ? RefreshIndicator(
                      onRefresh: _cargar,
                      child: ListView(
                        children: const [
                          SizedBox(
                            height: 300,
                            child: EstadoVacio(mensaje: 'Sin ventas en este período', icono: IconosPlazoleta.receiptLongOutlined),
                          ),
                        ],
                      ),
                    )
                  : RefreshIndicator(onRefresh: _cargar, child: _lista(context)),
            ),
          ],
        ),
      ),
    );
  }

  /// El período y, al lado, un chip por medio de pago (mock completo).
  Widget _filaFiltrosVentas(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: Espaciado.lg),
        children: [
          Center(child: _selectorPeriodo(context)),
          const SizedBox(width: Espaciado.sm),
          ChipSeleccionable(texto: 'Todos los medios', seleccionado: _filtroMedio == null, onTap: () => _elegirMedio(null)),
          for (final m in MedioVentaHistorialCompanion.values) ...[
            const SizedBox(width: Espaciado.sm),
            ChipSeleccionable(texto: m.etiqueta, seleccionado: _filtroMedio == m, onTap: () => _elegirMedio(m)),
          ],
        ],
      ),
    );
  }

  Widget _lista(BuildContext context) {
    // Agrupadas por día (El dueño: "tipo mercado pago") — sin `intl`, mismo
    // formateo manual que ya usa el resto de la companion.
    final grupos = <String, List<VentaDelHistorialCompanion>>{};
    for (final v in _ventas) {
      grupos.putIfAbsent(_tituloDia(v.fecha), () => []).add(v);
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(Espaciado.lg, 0, Espaciado.lg, Espaciado.lg + NavbarCompanion.espacioReservado),
      children: [
        for (final entrada in grupos.entries) ...[
          Padding(
            padding: const EdgeInsets.symmetric(vertical: Espaciado.sm),
            child: Text(entrada.key, style: Theme.of(context).textTheme.titleMedium),
          ),
          for (final v in entrada.value)
            Padding(padding: const EdgeInsets.only(bottom: Espaciado.sm), child: _FilaVenta(
              venta: v,
              abierta: _ventaAbierta == v.ventaId,
              detalle: _detalles[v.ventaId],
              errorDetalle: _ventaAbierta == v.ventaId ? _errorDetalle : null,
              onTap: () => _alternarDetalle(v),
              onEliminar: !v.anulada && v.sesionAbierta ? () => _confirmarYAnular(v) : null,
            )),
        ],
      ],
    );
  }
}

/// Una venta de la lista: hora, número y medio, y el total. Al tocarla se
/// despliega, sobre tinta, el detalle con sus líneas y "Eliminar venta".
class _FilaVenta extends StatelessWidget {
  const _FilaVenta({
    required this.venta,
    required this.abierta,
    required this.detalle,
    required this.errorDetalle,
    required this.onTap,
    required this.onEliminar,
  });

  final VentaDelHistorialCompanion venta;
  final bool abierta;
  final DetalleVentaCompanion? detalle;
  final String? errorDetalle;
  final VoidCallback onTap;
  final VoidCallback? onEliminar;

  @override
  Widget build(BuildContext context) {
    final colores = context.colores;
    final textTheme = Theme.of(context).textTheme;
    final v = venta;
    // Abierta, la fila pasa a tinta con letra clara (mismo giro del mock).
    final fondo = abierta ? colores.acento : colores.fondoBloque;
    final texto = abierta ? colores.acentoTexto : colores.textoPrimario;
    final apagado = abierta ? colores.acentoTexto.withValues(alpha: 0.7) : colores.textoSecundario;
    final tachado = v.anulada ? TextDecoration.lineThrough : null;
    return Container(
      decoration: BoxDecoration(color: fondo, borderRadius: BorderRadius.circular(radioSuperficieCompanion)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Presionable(
            radio: radioSuperficieCompanion,
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(Espaciado.lg),
              child: Row(
                children: [
                  Text(_hora(v.fecha), style: textTheme.headlineSmall?.copyWith(color: texto, decoration: tachado)),
                  const SizedBox(width: Espaciado.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(v.etiqueta, style: textTheme.titleMedium?.copyWith(color: texto, decoration: tachado)),
                        Text(
                          v.anulada ? 'Anulada · ${v.medio.etiqueta}' : v.medio.etiqueta,
                          style: textTheme.bodySmall?.copyWith(color: v.anulada && !abierta ? colores.error : apagado),
                        ),
                      ],
                    ),
                  ),
                  Text(formatearARS(v.totalCentavos), style: textTheme.titleMedium?.copyWith(color: texto, decoration: tachado)),
                ],
              ),
            ),
          ),
          if (abierta)
            Padding(
              padding: const EdgeInsets.fromLTRB(Espaciado.lg, 0, Espaciado.lg, Espaciado.lg),
              child: errorDetalle != null
                  ? Text(errorDetalle!, style: TextStyle(color: colores.acentoTexto))
                  : detalle == null
                  ? const Center(child: Padding(padding: EdgeInsets.all(Espaciado.md), child: CircularProgressIndicator(strokeWidth: 2)))
                  : _detalleLineas(context, detalle!, texto, apagado),
            ),
        ],
      ),
    );
  }

  Widget _detalleLineas(BuildContext context, DetalleVentaCompanion d, Color texto, Color apagado) {
    final colores = context.colores;
    Widget fila(String etiqueta, int centavos, {bool fuerte = false}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(etiqueta, style: TextStyle(color: fuerte ? texto : apagado, fontWeight: fuerte ? Pesos.fuerte : null)),
          Text(
            centavos < 0 ? '-${formatearARS(-centavos)}' : formatearARS(centavos),
            style: TextStyle(color: fuerte ? texto : apagado, fontWeight: fuerte ? Pesos.fuerte : null),
          ),
        ],
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('${_fechaHora(d.fecha)} · ${d.vendedor}', style: TextStyle(color: apagado)),
        const SizedBox(height: Espaciado.sm),
        for (final l in d.lineas)
          fila(
            l.gramos != null ? '${l.gramos} g × ${l.nombreProducto}' : '${l.cantidad} × ${l.nombreProducto}',
            l.subtotalCentavos,
          ),
        Divider(color: apagado.withValues(alpha: 0.3)),
        if (d.recargoCigarrillosCentavos > 0 || d.descuentoCentavos > 0 || d.redondeoCentavos > 0) ...[
          fila('Subtotal', d.subtotalCentavos),
          if (d.recargoCigarrillosCentavos > 0) fila('Recargo cigarrillos', d.recargoCigarrillosCentavos),
          if (d.descuentoCentavos > 0) fila('Descuento', -d.descuentoCentavos),
          if (d.redondeoCentavos > 0) fila('Redondeo', d.redondeoCentavos),
        ],
        fila('Total', d.totalCentavos, fuerte: true),
        if (onEliminar != null) ...[
          const SizedBox(height: Espaciado.md),
          TextButton(
            onPressed: onEliminar,
            style: TextButton.styleFrom(
              backgroundColor: texto.withValues(alpha: 0.14),
              foregroundColor: colores.error == colores.acentoTexto ? texto : const Color(0xFFFFB4AD),
              padding: const EdgeInsets.symmetric(vertical: Espaciado.md),
              shape: const StadiumBorder(),
            ),
            child: const Text('Anular venta'),
          ),
        ],
      ],
    );
  }
}

/// Botón compacto que muestra el filtro elegido y abre el menú para
/// cambiarlo (`PopupMenuButton` es quien maneja el toque; esto es solo su
/// apariencia) — mismo `Bloque`/radio de control que el resto del kit, sin
/// inventar un estilo de chip nuevo.
class _Pildora extends StatelessWidget {
  const _Pildora({required this.icono, required this.texto});

  final IconData icono;
  final String texto;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Espaciado.md,
        vertical: Espaciado.sm,
      ),
      decoration: BoxDecoration(
        color: context.colores.fondoBloque,
        borderRadius: BorderRadius.circular(Radios.control),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icono, size: 16, color: context.colores.textoSecundario),
          const SizedBox(width: Espaciado.xs),
          Text(texto, style: Theme.of(context).textTheme.bodyMedium),
          const Icon(IconosPlazoleta.arrowDropDown, size: 18),
        ],
      ),
    );
  }
}

String _fechaHora(DateTime f) {
  String dos(int n) => n.toString().padLeft(2, '0');
  return '${dos(f.day)}/${dos(f.month)}/${f.year} ${dos(f.hour)}:${dos(f.minute)}';
}

String _hora(DateTime f) =>
    '${f.hour.toString().padLeft(2, '0')}:${f.minute.toString().padLeft(2, '0')}';

String _tituloDia(DateTime f) {
  final ahora = DateTime.now();
  final hoy = DateTime(ahora.year, ahora.month, ahora.day);
  final dia = DateTime(f.year, f.month, f.day);
  if (dia == hoy) return 'Hoy';
  if (dia == hoy.subtract(const Duration(days: 1))) return 'Ayer';
  return '${f.day.toString().padLeft(2, '0')}/${f.month.toString().padLeft(2, '0')}/${f.year}';
}
