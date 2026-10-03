// Panel de cobro — remake de disposición (2026-09-19, el dueño: "ahora
// remakea venta" → "Cambiar también la disposición"). Antes era una
// columna angosta (340px) apilando total/descuento/medios/cobrar en
// vertical, compartiendo ancho con el carrito; ahora es un panel FIJO al
// pie de la zona derecha, ancho completo — el carrito (`ColumnaCarrito`)
// pasó a ser `Expanded` con scroll propio arriba de este panel
// (`pantalla_venta.dart`).
//
// El total sigue siendo la pieza "hero" (rediseño de composición: ahora un
// bisel doble, marco de vidrio + núcleo con el degradé de
// `acentos.gradienteDinero`, ver `_TotalHero`) pero ahora ocupa el ancho
// completo del panel, con el control de descuento como un ícono chico
// adentro (mismo criterio que la tarjeta del total de la companion,
// `pantalla_carrito_venta.dart::_tarjetaCobrar`/`_botonDescuento`) en vez
// de un bloque propio siempre visible con el toggle $/% y el campo de
// texto ocupando toda una fila — se abre en un `Modal` (vidrio, mismo
// mecanismo que el resto de la app) solo cuando hace falta.
//
// Lo que NO se porta de la companion, a propósito (ver el plan del
// remake): los cuatro medios de pago siguen siendo CUATRO CONTROLES
// SIEMPRE VISIBLES con su propio atajo Alt+, no una tarjeta que al
// tocarla abre un menú para elegir el medio — CLAUDE.md documenta que
// El dueño revirtió ese patrón de un solo toque en el paso a la terminal
// Point (fase 12: "necesito cobro manual... no hay más modal para
// seleccionarlo"), así que no corresponde reintroducirlo acá.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../domain/descuento.dart';
import '../../domain/dinero.dart';
import '../../domain/medio_pago.dart';
import '../../domain/ticket.dart';
import '../comun/botones.dart';
import '../comun/modal.dart';
import '../tema/acentos.dart';
import '../tema/resplandor.dart';
import '../tema/tema.dart';
import '../tema/tokens.dart';
import 'acciones_venta.dart';
import 'color_categoria.dart';
import 'tacto_venta.dart';
import 'venta_controlador.dart';
import '../tema/iconos.dart';
import '../tema/movimiento.dart';

class PanelCobro extends StatelessWidget {
  const PanelCobro({super.key, required this.usuarioId});

  final int usuarioId;

  @override
  Widget build(BuildContext context) {
    final c = context.watch<VentaControlador>();
    final colores = context.colores;
    final habilitado = c.carrito.isNotEmpty && c.medioElegido != null && !c.cobrando;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (c.avisoCobro != null) ...[
          Text(
            c.avisoCobro!,
            textAlign: TextAlign.center,
            style: TextStyle(color: colores.error, fontWeight: Pesos.medium),
          ),
          const SizedBox(height: Espaciado.sm),
        ],
        _TotalHero(controlador: c),
        const SizedBox(height: Espaciado.md),
        // Grilla 2×2, no una sola fila de 4 (El dueño, panel angosto de
        // 560px: "los botones de cobro... no se ven bien" — con el
        // `Flexible`+ellipsis que ya tenía `_BotonMedio` la etiqueta
        // truncaba igual, "Efectivo (Alt+E)" no entraba en ~126px). El
        // doble de ancho por botón alcanza para la etiqueta completa;
        // mismo orden de lectura de siempre (Efectivo, QR, Débito, Mixto).
        Row(
          children: [
            Expanded(
              child: _BotonMedio(
                icono: IconosPlazoleta.paymentsOutlined,
                etiqueta: 'Efectivo (Alt+E)',
                seleccionado: c.medioElegido == ComposicionPago.efectivo,
                colorSeleccionado: ColorMedioPago.efectivo(context),
                onPressed: () => _elegir(context, ComposicionPago.efectivo),
              ),
            ),
            const SizedBox(width: Espaciado.sm),
            Expanded(
              child: _BotonMedio(
                icono: IconosPlazoleta.qrCode2Outlined,
                etiqueta: 'QR (Alt+Q)',
                seleccionado:
                    c.medioElegido == ComposicionPago.virtual &&
                    c.canalElegido == 'qr',
                colorSeleccionado: ColorMedioPago.qr(context),
                onPressed: () => _elegirCanal(context, 'qr'),
              ),
            ),
          ],
        ),
        const SizedBox(height: Espaciado.sm),
        Row(
          children: [
            Expanded(
              child: _BotonMedio(
                icono: IconosPlazoleta.creditCardOutlined,
                etiqueta: 'Débito (Alt+D)',
                seleccionado:
                    c.medioElegido == ComposicionPago.virtual &&
                    c.canalElegido == 'debit_card',
                colorSeleccionado: ColorMedioPago.debito(context),
                onPressed: () => _elegirCanal(context, 'debit_card'),
              ),
            ),
            const SizedBox(width: Espaciado.sm),
            Expanded(
              child: _BotonMedio(
                icono: IconosPlazoleta.callSplitOutlined,
                etiqueta: 'Mixto (Alt+X)',
                seleccionado: c.medioElegido == ComposicionPago.mixto,
                colorSeleccionado: ColorMedioPago.mixto(context),
                onPressed: () => abrirMixto(context, c),
              ),
            ),
          ],
        ),
        const SizedBox(height: Espaciado.md),
        Row(
          children: [
            Expanded(
              child: SuperficieTactil(
                // Fondo explícito, no solo el color del ícono/texto
                // (corrección post-revisión heredada: "Cobrar se ve
                // apagado" — acá el botón entero es la superficie, así que
                // el color deshabilitado tiene que notarse en el fondo, no
                // solo en el texto). `onPressed` es `null` solo con el
                // carrito vacío o sin medio elegido, a propósito.
                color: habilitado ? colores.acento : colores.fondo,
                // Píldora completa, no `TactoVenta.radio` — es la única
                // acción PRIMARIA del panel (rediseño de composición): se
                // distingue en forma de los cuatro selectores de medio de
                // pago y de "A mano", que se quedan con el radio de
                // control de siempre. Un radio para selectores, píldora
                // solo para el CTA único — regla documentada acá, no una
                // mezcla sin criterio.
                borderRadius: BorderRadius.circular(TactoVenta.alturaControl / 2),
                onTap: habilitado ? () => _cobrar(context) : null,
                child: SizedBox(
                  height: TactoVenta.alturaControl,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        IconosPlazoleta.shoppingCartCheckout,
                        size: TactoVenta.icono,
                        color: habilitado ? colores.acentoTexto : colores.textoTenue,
                      ),
                      const SizedBox(width: Espaciado.sm),
                      Text(
                        'Cobrar',
                        style: TextStyle(
                          color: habilitado ? colores.acentoTexto : colores.textoTenue,
                          fontSize: TamanioTexto.subtitulo,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            // "Cobrar a mano (sin terminal)" (El dueño, 2026-09-08: "necesito
            // cobro manual... no hay más modal para seleccionarlo") — solo
            // con QR/Débito ya elegido (`canalElegido` puesto por
            // `elegirCanalDirecto`/`confirmarMixto`), nunca con Efectivo
            // puro (eso no pasa por Point). Mismo destino que "Cobrar a
            // mano" del diálogo de Point cuando falla (`cobrarActual()`),
            // pero elegible de entrada.
            if (c.canalElegido != null) ...[
              const SizedBox(width: Espaciado.sm),
              Tooltip(
                message: 'Cobrar a mano, sin pasar por la terminal — Alt+M',
                child: SizedBox(
                  height: TactoVenta.alturaControl,
                  child: SuperficieTactil(
                    // `fondoBloque`, no `fondo` (bug real, visto en
                    // captura): este botón vive directo sobre el canvas de
                    // la pantalla, no adentro de una `Superficie` como los
                    // medios de pago — con `colores.fondo` quedaba
                    // invisible, mismo color que lo que tiene atrás.
                    color: colores.fondoBloque,
                    borderRadius: BorderRadius.circular(TactoVenta.radio),
                    onTap: () => cobrarAMano(context, c),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: Espaciado.lg),
                      child: Center(
                        child: Text(
                          'A mano',
                          style: TextStyle(color: colores.textoPrimario, fontSize: TamanioTexto.cuerpo),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }

  void _elegir(BuildContext context, ComposicionPago medio) {
    final c = context.read<VentaControlador>();
    c.elegirMedio(medio);
    c.focoCampoPrincipal.requestFocus();
  }

  // QR y Débito eligen el canal nada más (El dueño, 2026-09-08: volvió a ser
  // de dos pasos) — mismo criterio que el atajo de teclado
  // (`pantalla_venta.dart`): "Cobrar" (o Alt+M para cobro manual) es quien
  // dispara algo de verdad.
  void _elegirCanal(BuildContext context, String canal) {
    final c = context.read<VentaControlador>();
    c.elegirCanalDirecto(canal);
    c.focoCampoPrincipal.requestFocus();
  }

  Future<void> _cobrar(BuildContext context) async {
    final c = context.read<VentaControlador>();
    if (c.medioElegido == ComposicionPago.mixto &&
        c.montoEfectivoMixtoCentavos == null) {
      await abrirMixto(context, c);
      if (!context.mounted) return;
      // `confirmarMixto` reclasifica el medio según cómo terminó pagando el
      // cliente (`domain/medio_pago.dart::clasificarComposicion`): si dio
      // puro efectivo o puro virtual, `medioElegido` ya NO es mixto acá,
      // aunque `montoEfectivoMixtoCentavos` siga en null (correcto, no hay
      // parte mixta que llevar). Bug real: chequear solo
      // `montoEfectivoMixtoCentavos == null` cortaba también ese caso y
      // cobraba nada, en vez de solo cuando el diálogo se cerró sin
      // confirmar (que es el único caso donde sigue en mixto sin monto).
      if (c.medioElegido == ComposicionPago.mixto &&
          c.montoEfectivoMixtoCentavos == null) {
        return;
      }
    }
    await cobrarOAbrirPosnet(context, c);
    c.focoCampoPrincipal.requestFocus();
  }
}

/// El total, ancho completo — pieza "hero" de la pantalla. Rediseño de
/// composición (El dueño: "rediseño completo, no un remake que mantenga las
/// bases"): antes era una `Superficie` con degradé de borde a borde; ahora
/// es un bisel doble — un marco exterior de vidrio (borde + sombra
/// ambiente) con un hueco chico, y adentro el núcleo de color de verdad
/// (el degradé + el glow), con su propio radio más chico y concéntrico —
/// la misma sensación de "pieza montada en su marco" que ya describe
/// `DISENO.md` para piezas premium, no un rectángulo pintado liso. El
/// control de descuento sigue viviendo adentro del núcleo, como un ícono
/// chico a la derecha — mismo lugar que `_botonDescuento` de la companion.
class _TotalHero extends StatelessWidget {
  const _TotalHero({required this.controlador});

  final VentaControlador controlador;

  @override
  Widget build(BuildContext context) {
    final c = controlador;
    final resultado = c.resultado;
    final totalAMostrar = resultado?.totalCentavos ?? c.subtotalCentavos;
    final textoSobre = context.acentosPlazoleta.textoSobreColor;

    final desglose = resultado == null
        ? const DesgloseTicket()
        : DesgloseTicket(
            recargoCigarrillosCentavos: resultado.recargoCigarrillosCentavos,
            descuentoCentavos: resultado.descuentoCentavos,
            redondeoCentavos: resultado.redondeoCentavos,
          );

    final radioNucleo = radioSuperficieEscritorio;

    // Sin el marco de vidrio con sombra de antes: la tarjeta oscura del
    // total ya destaca sola ("Lenguaje de diseño", 2026-09-26).
    return SizedBox(
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radioNucleo),
          gradient: LinearGradient(
            colors: context.acentosPlazoleta.gradienteDinero,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: resplandorNeon(context.acentosPlazoleta.gradienteDinero.first),
        ),
        padding: const EdgeInsets.all(Espaciado.lg),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // FittedBox, no `overflow: ellipsis` (mismo criterio que
                  // `Metrica`): el total partido en dos líneas es un bug
                  // real, no solo estético — una cifra de plata cortada se
                  // puede leer como un monto distinto.
                  // Late cuando cambia (2026-10-03): el número nuevo ya está desde el primer cuadro.
                  Pulso(
                    valor: totalAMostrar,
                    alineacion: Alignment.centerLeft,
                    child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      formatearARS(totalAMostrar),
                      maxLines: 1,
                      style: Theme.of(context).textTheme.displayLarge!.copyWith(color: textoSobre).tabular,
                    ),
                  ),
                  ),
                  // El desglose aparece y se va suave en vez de empujar la tarjeta de golpe.
                  AnimatedSize(
                    duration: Animaciones.corta,
                    curve: Animaciones.curva,
                    alignment: Alignment.topLeft,
                    child: !desglose.tieneAlgoQueMostrar
                        ? const SizedBox(width: double.infinity)
                        : Entrada(
                    key: const ValueKey('desglose'),
                    desplazamiento: 4,
                    child: Text(
                      [
                        if (desglose.recargoCigarrillosCentavos > 0)
                          'Recargo QR ${formatearARS(desglose.recargoCigarrillosCentavos)}',
                        if (desglose.descuentoCentavos > 0)
                          'Descuento -${formatearARS(desglose.descuentoCentavos)}',
                        if (desglose.redondeoCentavos > 0)
                          'Redondeo ${formatearARS(desglose.redondeoCentavos)}',
                      ].join(' · '),
                      style: Theme.of(context).textTheme.bodySmall!.copyWith(color: textoSobre.withValues(alpha: 0.8)).tabular,
                    ),
                        ),
                  ),
                ],
              ),
            ),
            _BotonDescuento(controlador: c, colorIcono: textoSobre),
          ],
        ),
      ),
    );
  }
}

class _BotonDescuento extends StatelessWidget {
  const _BotonDescuento({required this.controlador, required this.colorIcono});

  final VentaControlador controlador;
  final Color colorIcono;

  bool get _hayDescuento => controlador.campoDescuentoCtrl.text.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'Descuento',
      onPressed: () => _abrirModalDescuento(context),
      icon: Icon(
        _hayDescuento ? IconosPlazoleta.sellActivo : IconosPlazoleta.sellOutlined,
        color: colorIcono,
      ),
    );
  }

  Future<void> _abrirModalDescuento(BuildContext context) {
    return mostrarModal<void>(
      context,
      builder: (_) => _ModalDescuento(controlador: controlador),
    );
  }
}

class _ModalDescuento extends StatelessWidget {
  const _ModalDescuento({required this.controlador});

  final VentaControlador controlador;

  @override
  Widget build(BuildContext context) {
    final c = controlador;
    return Modal(
      titulo: 'Descuento',
      contenido: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: _BotonMedio(
                  etiqueta: r'$',
                  seleccionado: c.tipoDescuento == TipoDescuento.monto,
                  onPressed: () => c.elegirTipoDescuento(TipoDescuento.monto),
                ),
              ),
              const SizedBox(width: Espaciado.sm),
              Expanded(
                child: _BotonMedio(
                  etiqueta: '%',
                  seleccionado: c.tipoDescuento == TipoDescuento.porcentaje,
                  onPressed: () => c.elegirTipoDescuento(TipoDescuento.porcentaje),
                ),
              ),
            ],
          ),
          const SizedBox(height: Espaciado.sm),
          TextField(
            key: const Key('campo_descuento'),
            controller: c.campoDescuentoCtrl,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              hintText: c.tipoDescuento == TipoDescuento.monto ? 'Monto del descuento' : 'Porcentaje de descuento',
            ),
          ),
        ],
      ),
      // `BotonPrimario`, no `FilledButton` crudo (bug real, encontrado
      // corriendo los tests): `FilledButtonThemeData.minimumSize` es
      // `Size.fromHeight(...)` (ancho infinito, pensado para un botón que
      // ocupa todo el ancho de su contenedor, ej. `EstadoError`) — un
      // `FilledButton` suelto en el `Row` de `Modal.botones` (sin
      // `Expanded`/ancho fijo alrededor) hereda ese ancho infinito y
      // `BoxConstraints forces an infinite width` revienta el layout.
      // `BotonPrimario` ya trae su propio `SizedBox` de ancho acotado — es
      // el botón que usa el resto de los modales de la app.
      botones: [
        BotonPrimario(
          texto: 'Listo',
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}

/// Los cuatro medios de pago comparten altura (`TactoVenta.alturaControl`)
/// y ancho entre ellos (remake 2026-09-19: ya no comparten columna
/// vertical, van los cuatro en una sola fila) — cada uno con su ícono e
/// identificado por su propio color (`ColorMedioPago`, reconciliado con
/// `AcentosPlazoleta`).
class _BotonMedio extends StatelessWidget {
  const _BotonMedio({
    required this.etiqueta,
    required this.seleccionado,
    required this.onPressed,
    this.icono,
    this.colorSeleccionado,
  });

  final String etiqueta;
  final bool seleccionado;
  final VoidCallback onPressed;

  /// Null para los dos botones de un solo carácter (\$/%, descuento) — un
  /// glifo tan corto ya se distingue solo, un ícono al lado sería ruido.
  final IconData? icono;

  /// Color del botón cuando está seleccionado — nulo usa `colores.acento`
  /// (el descuento \$/%, que sigue siendo neutro). Los cuatro medios de
  /// pago pasan su propio color (`ColorMedioPago`) en vez de compartir el
  /// acento — texto blanco encima, mismo criterio que `colores.errorTexto`
  /// sobre una superficie sólida.
  final Color? colorSeleccionado;

  @override
  Widget build(BuildContext context) {
    final colores = context.colores;
    // Sin elegir, cada medio ya se reconoce por su color (fondo suave y
    // texto en su tono, como las filas Efectivo/MP del "Lenguaje de
    // diseño", 2026-09-26); elegido, el color lleno.
    final colorMedio = colorSeleccionado;
    final colorFondo = seleccionado
        ? (colorMedio ?? colores.acento)
        : (colorMedio == null ? colores.fondoBloque : colorMedio.withValues(alpha: 0.11));
    final colorContenido = seleccionado
        ? (colorMedio == null ? colores.acentoTexto : context.acentosPlazoleta.textoSobreColor)
        : (colorMedio == null ? colores.textoPrimario : Color.lerp(colorMedio, colores.textoPrimario, 0.35)!);
    // Elegido, el color llena el botón con una transición corta y el botón late una vez (2026-10-03).
    return Pulso(
      valor: seleccionado,
      escala: 1.03,
      child: TweenAnimationBuilder<Color?>(
      tween: ColorTween(end: colorFondo),
      duration: Animaciones.corta,
      curve: Animaciones.curva,
      builder: (context, fondoAnimado, _) => SizedBox(
      height: TactoVenta.alturaControl,
      child: SuperficieTactil(
        color: fondoAnimado ?? colorFondo,
        borderRadius: BorderRadius.circular(TactoVenta.radio),
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Espaciado.sm),
          // `mainAxisAlignment.center`, no `Center` + `mainAxisSize.min`:
          // con el ícono, "Débito (Alt+D)"/"Mixto (Alt+X)" a veces no
          // entran en el ancho del botón — un `Row` de ancho mínimo
          // desborda en vez de acotarse (bug real, encontrado en los
          // tests). `Flexible` en el texto deja que trunque con "…" en vez
          // de romper el layout, sin afectar el caso normal.
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icono != null) ...[
                // Ícono en su propio chip circular (rediseño de
                // composición, mismo patrón que `ChipIcono` de la
                // companion) en vez de suelto en la fila — cabe sin sumar
                // alto: el botón sigue en `TactoVenta.alturaControl` (48),
                // fijo porque el panel de cobro ya está al límite vertical
                // en el piso mínimo (1366×768, ver `tacto_venta.dart`).
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: colorContenido.withValues(alpha: 0.18),
                  ),
                  child: Icon(icono, size: 14, color: colorContenido),
                ),
                const SizedBox(width: Espaciado.sm),
              ],
              Flexible(
                child: Text(
                  etiqueta,
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                  style: Theme.of(context).textTheme.titleMedium!.copyWith(color: colorContenido),
                ),
              ),
            ],
          ),
        ),
      ),
      ),
      ),
    );
  }
}
