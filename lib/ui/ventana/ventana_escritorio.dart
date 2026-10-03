// Ventana propia de la app de escritorio ("ventana-la-plazoleta/", mocks de
// El dueño, 2026-09-29): se saca la barra de título nativa de Windows y se
// dibuja una propia de 40 px, con la marca, el estado de la caja y el
// respaldo, y los tres botones de siempre. Distribución y medidas del
// LEEME de esa carpeta; los colores salen de los tokens de la app (así el
// modo oscuro sigue andando) en vez de los hex sueltos del mock.
//
// Cerrar la ventana con la caja abierta no cierra: pregunta primero (el
// arqueo no se hace solo, y cerrar el sistema sin contar es justo lo que el
// cierre obligatorio quiere evitar).

import 'dart:async';

import 'package:drift/drift.dart' show OrderingTerm;
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../../data/database.dart';
import '../../data/repositorio_respaldo.dart';
import '../../servicios/actualizaciones.dart';
import '../cierre/pantalla_cierre.dart';
import '../comun/modal.dart';
import '../tema/acentos.dart';
import '../tema/tokens.dart';
import '../../domain/marca.dart';
import '../../servicios/marca_actual.dart';
import '../comun/marca_pos.dart';

const double _alturaBarra = 40;
const double _anchoBoton = 46;

/// Se llama una sola vez, antes de `runApp`: saca la barra nativa y deja
/// que el cierre lo decida la app (`setPreventClose`), no Windows.
Future<void> configurarVentanaEscritorio() async {
  await windowManager.ensureInitialized();
  const opciones = WindowOptions(
    titleBarStyle: TitleBarStyle.hidden,
    windowButtonVisibility: false,
    title: nombreProducto,
  );
  await windowManager.waitUntilReadyToShow(opciones, () async {
    await windowManager.show();
    await windowManager.focus();
  });
  await windowManager.setPreventClose(true);
}

/// Envuelve toda la app: la barra propia arriba y, debajo, el `Navigator`.
/// Va en el `builder` del `MaterialApp`, así los diálogos y las pantallas
/// nunca se dibujan encima de la barra.
class MarcoVentana extends StatefulWidget {
  const MarcoVentana({
    super.key,
    required this.db,
    required this.navigatorKey,
    required this.child,
  });

  final AppDatabase db;
  final GlobalKey<NavigatorState> navigatorKey;
  final Widget child;

  @override
  State<MarcoVentana> createState() => _MarcoVentanaState();
}

class _MarcoVentanaState extends State<MarcoVentana> with WindowListener {
  bool _enFoco = true;
  bool _maximizada = false;
  bool _preguntando = false;
  DateTime? _ultimoRespaldo;
  Timer? _tickRespaldo;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    marcaActual.addListener(_poneTituloDeVentana);
    _poneTituloDeVentana();
    windowManager.isMaximized().then((v) {
      if (mounted) setState(() => _maximizada = v);
    });
    _leerRespaldo();
    // Un minuto alcanza: es un dato de "hoy a tal hora", no de tiempo real.
    _tickRespaldo = Timer.periodic(
      const Duration(minutes: 1),
      (_) => _leerRespaldo(),
    );
  }

  // El título de la ventana (barra de tareas, Alt+Tab) acompaña al nombre del comercio.
  void _poneTituloDeVentana() {
    windowManager.setTitle(marcaActual.value.nombre).catchError((_) {});
  }

  @override
  void dispose() {
    marcaActual.removeListener(_poneTituloDeVentana);
    windowManager.removeListener(this);
    _tickRespaldo?.cancel();
    super.dispose();
  }

  Future<void> _leerRespaldo() async {
    try {
      final respaldos = await listarRespaldos(widget.db);
      final hoy = DateTime.now();
      final deHoy = respaldos.where(
        (r) =>
            r.fecha.year == hoy.year &&
            r.fecha.month == hoy.month &&
            r.fecha.day == hoy.day,
      );
      if (mounted) {
        setState(
          () => _ultimoRespaldo = deHoy.isEmpty ? null : deHoy.last.fecha,
        );
      }
    } catch (_) {
      // Sin carpeta configurada o ilegible: simplemente no hay chip.
    }
  }

  @override
  void onWindowFocus() => setState(() => _enFoco = true);

  @override
  void onWindowBlur() => setState(() => _enFoco = false);

  @override
  void onWindowMaximize() => setState(() => _maximizada = true);

  @override
  void onWindowUnmaximize() => setState(() => _maximizada = false);

  @override
  Future<void> onWindowClose() async {
    if (_preguntando) return;
    final sesion =
        await (widget.db.select(widget.db.sesionesDeCaja)
              ..where((s) => s.estado.equals('ABIERTA'))
              ..orderBy([(s) => OrderingTerm.desc(s.fechaApertura)])
              ..limit(1))
            .getSingleOrNull();
    if (sesion == null) {
      await windowManager.destroy();
      return;
    }
    final contexto = widget.navigatorKey.currentContext;
    if (contexto == null || !mounted || !contexto.mounted) {
      await windowManager.destroy();
      return;
    }
    _preguntando = true;
    try {
      final decision = await showDialog<_DecisionCierre>(
        context: contexto,
        barrierColor: const Color(0x6B1F1F1F),
        builder: (_) => const _DialogoCerrarConCajaAbierta(),
      );
      switch (decision) {
        case _DecisionCierre.cerrarIgual:
          await windowManager.destroy();
        case _DecisionCierre.irACerrar:
          final ctx = widget.navigatorKey.currentContext;
          if (ctx != null && ctx.mounted) {
            // Cerrar la caja desde acá era un callejón: el botón final decía
            // "Volver a la venta" y la ventana seguía abierta, sin dejar claro
            // si se había cerrado o no. Ahora, con la caja cerrada, el botón
            // cierra el sistema (El dueño, 2026-10-03).
            var cajaCerrada = false;
            await mostrarModal<void>(
              ctx,
              builder: (_) => PantallaCierre(
                db: widget.db,
                sesionId: sesion.id,
                usuarioId: sesion.usuarioAbrioId,
                textoBotonFinal: 'Cerrar el sistema',
                onFinalizado: () {
                  cajaCerrada = true;
                  Navigator.of(ctx).pop();
                },
              ),
            );
            if (cajaCerrada) await windowManager.destroy();
          }
        case _DecisionCierre.seguir || null:
          break;
      }
    } finally {
      _preguntando = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        StreamBuilder<SesionCaja?>(
          stream:
              (widget.db.select(widget.db.sesionesDeCaja)
                    ..where((s) => s.estado.equals('ABIERTA'))
                    ..orderBy([(s) => OrderingTerm.desc(s.fechaApertura)])
                    ..limit(1))
                  .watchSingleOrNull(),
          builder: (context, snapshot) {
            final sesion = snapshot.data;
            final ahora = DateTime.now();
            final deOtroDia =
                sesion != null &&
                (sesion.fechaApertura.year != ahora.year ||
                    sesion.fechaApertura.month != ahora.month ||
                    sesion.fechaApertura.day != ahora.day);
            return _BarraVentana(
              enFoco: _enFoco,
              maximizada: _maximizada,
              cajaAbierta: sesion != null && !deOtroDia,
              cajaDeAyerSinCerrar: deOtroDia,
              ultimoRespaldo: _ultimoRespaldo,
            );
          },
        ),
        Expanded(child: widget.child),
      ],
    );
  }
}

class _BarraVentana extends StatelessWidget {
  const _BarraVentana({
    required this.enFoco,
    required this.maximizada,
    required this.cajaAbierta,
    required this.cajaDeAyerSinCerrar,
    required this.ultimoRespaldo,
  });

  final bool enFoco;
  final bool maximizada;
  final bool cajaAbierta;
  final bool cajaDeAyerSinCerrar;
  final DateTime? ultimoRespaldo;

  @override
  Widget build(BuildContext context) {
    final colores = context.colores;
    final textTheme = Theme.of(context).textTheme;
    final acentos = context.acentosPlazoleta;
    final colorMarca = enFoco
        ? colores.acento
        : colores.acento.withValues(alpha: 0.45);
    final colorTitulo = enFoco ? colores.textoPrimario : colores.textoTenue;
    final colorIconos = enFoco ? colores.textoSecundario : colores.textoTenue;

    return Material(
      color: colores.fondo,
      child: Container(
        height: _alturaBarra,
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: colores.borde)),
        ),
        child: Row(
          children: [
            // Todo lo que no es un botón arrastra la ventana; doble clic
            // maximiza o restaura (comportamiento de cualquier ventana).
            Expanded(
              child: DragToMoveArea(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onDoubleTap: () async {
                    if (await windowManager.isMaximized()) {
                      await windowManager.unmaximize();
                    } else {
                      await windowManager.maximize();
                    }
                  },
                  child: Padding(
                    padding: const EdgeInsets.only(left: 12),
                    child: Row(
                      children: [
                        // El ícono de Nodo Sur POS ("pos" con un punto, 2026-10-03), el mismo de la barra de tareas;
                        // más tenue cuando la ventana no tiene el foco, como el título.
                        MarcaPos(fondo: colorMarca, tinta: colores.acentoTexto),
                        const SizedBox(width: 10),
                        ValueListenableBuilder<MarcaNegocio>(
                          valueListenable: marcaActual,
                          builder: (context, marca, _) => Text(
                            marca.nombre,
                            style: textTheme.bodyMedium?.copyWith(
                              fontSize: 14,
                              fontWeight: Pesos.medium,
                              color: colorTitulo,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        if (cajaDeAyerSinCerrar)
                          _Chip(
                            texto: 'Caja de ayer sin cerrar',
                            fondo: acentos.alertaSuave,
                            color: acentos.alerta,
                            enFoco: enFoco,
                          )
                        else if (cajaAbierta)
                          _Chip(
                            texto: 'Caja abierta',
                            fondo: acentos.gananciaSuave,
                            color: acentos.ganancia,
                            enFoco: enFoco,
                          ),
                        if (ultimoRespaldo != null) ...[
                          const SizedBox(width: 10),
                          Text(
                            'Respaldo hoy ${_hora(ultimoRespaldo!)}',
                            style: textTheme.bodySmall?.copyWith(
                              fontSize: 12,
                              fontWeight: Pesos.medium,
                              color: enFoco
                                  ? colores.textoSecundario
                                  : colores.textoTenue,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const _AvisoActualizacion(),
            _BotonVentana(
              tooltip: 'Minimizar',
              color: colorIconos,
              dibujo: _Dibujo.minimizar,
              onTap: windowManager.minimize,
            ),
            _BotonVentana(
              tooltip: maximizada ? 'Restaurar' : 'Maximizar',
              color: colorIconos,
              dibujo: maximizada ? _Dibujo.restaurar : _Dibujo.maximizar,
              onTap: () async {
                if (await windowManager.isMaximized()) {
                  await windowManager.unmaximize();
                } else {
                  await windowManager.maximize();
                }
              },
            ),
            _BotonVentana(
              tooltip: 'Cerrar',
              color: colorIconos,
              dibujo: _Dibujo.cerrar,
              esCerrar: true,
              onTap: windowManager.close,
            ),
          ],
        ),
      ),
    );
  }

  static String _hora(DateTime f) =>
      '${f.hour.toString().padLeft(2, '0')}:${f.minute.toString().padLeft(2, '0')}';
}

/// Aviso discreto de actualización (2026-09-30). Aparece solo cuando hay una
/// versión nueva Y no hay una venta abierta (`decidirAviso`); nunca instala
/// sola: "Instalar ahora" o "Más tarde".
class _AvisoActualizacion extends StatelessWidget {
  const _AvisoActualizacion();

  @override
  Widget build(BuildContext context) {
    final servicio = servicioActualizaciones;
    if (servicio == null) return const SizedBox.shrink();
    return ListenableBuilder(
      listenable: servicio,
      builder: (context, _) {
        if (!servicio.mostrarAviso) return const SizedBox.shrink();
        final colores = context.colores;
        final estilo = TextButton.styleFrom(
          minimumSize: const Size(0, 28),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        );
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Hay una actualización',
              style: TextStyle(fontSize: 12, color: colores.textoSecundario),
            ),
            const SizedBox(width: 4),
            TextButton(
              style: estilo.copyWith(
                foregroundColor: WidgetStatePropertyAll(colores.acento),
              ),
              onPressed: servicio.instalarAhora,
              child: const Text('Instalar ahora'),
            ),
            TextButton(
              style: estilo.copyWith(
                foregroundColor: WidgetStatePropertyAll(colores.textoTenue),
              ),
              onPressed: servicio.postergar,
              child: const Text('Más tarde'),
            ),
            const SizedBox(width: 8),
          ],
        );
      },
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.texto,
    required this.fondo,
    required this.color,
    required this.enFoco,
  });

  final String texto;
  final Color fondo;
  final Color color;
  final bool enFoco;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: enFoco ? fondo : context.colores.borde.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        texto,
        style: TextStyle(
          fontSize: 12,
          fontWeight: Pesos.fuerte,
          height: 1.1,
          color: enFoco ? color : context.colores.textoTenue,
        ),
      ),
    );
  }
}

enum _Dibujo { minimizar, maximizar, restaurar, cerrar }

/// 46 × 40 px, ícono de 10 px con trazo de 1 px. Al pasar el mouse se pinta
/// gris suave; solo "Cerrar" se pone rojo (con el ícono blanco).
class _BotonVentana extends StatefulWidget {
  const _BotonVentana({
    required this.tooltip,
    required this.color,
    required this.dibujo,
    required this.onTap,
    this.esCerrar = false,
  });

  final String tooltip;
  final Color color;
  final _Dibujo dibujo;
  final VoidCallback onTap;
  final bool esCerrar;

  @override
  State<_BotonVentana> createState() => _BotonVentanaState();
}

class _BotonVentanaState extends State<_BotonVentana> {
  bool _encima = false;

  @override
  Widget build(BuildContext context) {
    final colores = context.colores;
    final fondo = !_encima
        ? Colors.transparent
        : widget.esCerrar
        ? const Color(0xFFC42B1C)
        : colores.borde.withValues(alpha: 0.6);
    final colorIcono = _encima && widget.esCerrar ? Colors.white : widget.color;
    return MouseRegion(
      onEnter: (_) => setState(() => _encima = true),
      onExit: (_) => setState(() => _encima = false),
      child: Tooltip(
        message: widget.tooltip,
        waitDuration: const Duration(milliseconds: 800),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: Container(
            width: _anchoBoton,
            height: _alturaBarra,
            color: fondo,
            alignment: Alignment.center,
            child: CustomPaint(
              size: const Size(10, 10),
              painter: _PintorIcono(widget.dibujo, colorIcono),
            ),
          ),
        ),
      ),
    );
  }
}

class _PintorIcono extends CustomPainter {
  _PintorIcono(this.dibujo, this.color);

  final _Dibujo dibujo;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final trazo = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    switch (dibujo) {
      case _Dibujo.minimizar:
        canvas.drawLine(const Offset(0, 5.5), const Offset(10, 5.5), trazo);
      case _Dibujo.maximizar:
        canvas.drawRect(const Rect.fromLTWH(0.5, 0.5, 9, 9), trazo);
      case _Dibujo.restaurar:
        canvas.drawRect(const Rect.fromLTWH(0.5, 2.5, 7, 7), trazo);
        canvas.drawPath(
          Path()
            ..moveTo(2.5, 2.5)
            ..lineTo(2.5, 0.5)
            ..lineTo(9.5, 0.5)
            ..lineTo(9.5, 7.5)
            ..lineTo(7.5, 7.5),
          trazo,
        );
      case _Dibujo.cerrar:
        canvas.drawLine(Offset.zero, const Offset(10, 10), trazo);
        canvas.drawLine(const Offset(10, 0), const Offset(0, 10), trazo);
    }
  }

  @override
  bool shouldRepaint(_PintorIcono viejo) =>
      viejo.dibujo != dibujo || viejo.color != color;
}

enum _DecisionCierre { irACerrar, seguir, cerrarIgual }

/// "¿Cerrar La Plazoleta?" — mock `Cierre.dc.html`: tarjeta de 480 px,
/// radio 28, tres botones en píldora de 52 px.
class _DialogoCerrarConCajaAbierta extends StatelessWidget {
  const _DialogoCerrarConCajaAbierta();

  @override
  Widget build(BuildContext context) {
    final colores = context.colores;
    final acentos = context.acentosPlazoleta;
    final textTheme = Theme.of(context).textTheme;

    Widget boton(
      String texto,
      _DecisionCierre valor, {
      required Color fondo,
      required Color color,
    }) {
      return SizedBox(
        height: 52,
        child: Material(
          color: fondo,
          borderRadius: BorderRadius.circular(999),
          child: InkWell(
            borderRadius: BorderRadius.circular(999),
            onTap: () => Navigator.of(context).pop(valor),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Center(
                widthFactor: 1,
                child: Text(
                  texto,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: Pesos.fuerte,
                    color: color,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Dialog(
      backgroundColor: colores.fondoBloque,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: acentos.alertaSuave,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(Icons.lock_outline_rounded, color: acentos.alerta),
              ),
              const SizedBox(height: 16),
              Text(
                '¿Cerrar ${marcaActual.value.nombre}?',
                style: textTheme.headlineSmall?.copyWith(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'La caja de hoy sigue abierta. Si cerrás el sistema ahora, no se hace el arqueo.',
                style: textTheme.bodyLarge?.copyWith(fontSize: 16),
              ),
              const SizedBox(height: 24),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  boton(
                    'Ir a cerrar la caja',
                    _DecisionCierre.irACerrar,
                    fondo: colores.acento,
                    color: colores.acentoTexto,
                  ),
                  boton(
                    'Seguir trabajando',
                    _DecisionCierre.seguir,
                    fondo: colores.destacado,
                    color: colores.textoPrimario,
                  ),
                  boton(
                    'Cerrar igual',
                    _DecisionCierre.cerrarIgual,
                    fondo: Colors.transparent,
                    color: colores.error,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
