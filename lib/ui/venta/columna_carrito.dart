// Columna central: el carrito, en un único bloque bento. Una línea por
// producto, la última agregada resaltada con el acento, el nombre en rojo
// si el stock quedó en 0 o negativo.
//
// Fase 13 (principio rector, `DISENO.md`): el padding ajustado y la fila
// angosta que tenía esta columna eran una regla escrita para 720px de alto
// (hardware 2008) — ya no queda una excepción documentada al padding
// estándar de `Bloque`. Con 1080px de sobra, cada fila usa el mismo aire
// que cualquier otra lista de la app, y su contenido (nombre → cantidad →
// plata) tiene un ancho máximo (`Medidas.anchoFilaCarrito`) en vez de
// estirarse hasta el borde de una columna que hoy sobra en ancho: apretar
// cuando no hace falta es exactamente lo que cansa la vista.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../domain/dinero.dart';
import '../../domain/venta.dart';
import '../comun/color_categoria.dart';
import '../tema/superficie.dart';
import '../tema/tema.dart';
import '../tema/tokens.dart';
import 'dialogo_editar_cantidad.dart';
import 'tacto_venta.dart';
import 'cancelar_venta_con_deshacer.dart';
import 'venta_controlador.dart';
import '../tema/iconos.dart';
import '../tema/acentos.dart';
import '../tema/movimiento.dart';

class ColumnaCarrito extends StatelessWidget {
  const ColumnaCarrito({
    super.key,
    this.ventaConfirmada,
    this.totalConfirmadoCentavos,
    required this.onImprimir,
  });

  /// Id y total de la última venta cobrada en esta pantalla (bug real:
  /// cobrar no daba ninguna señal de que la venta había entrado). Mientras
  /// el carrito siga vacío, ocupa el lugar de "El carrito está vacío" — deja
  /// de mostrarse solo, sin timer, en cuanto entra la primera línea de la
  /// venta siguiente.
  final int? ventaConfirmada;
  final int? totalConfirmadoCentavos;

  /// Imprimir ya no es una acción permanente de la barra lateral (fase 13,
  /// ítem 3): aparece acá, junto al acuse, mientras hay algo reciente para
  /// imprimir — se va con el resto del acuse en cuanto entra la primera
  /// línea de la venta siguiente.
  final VoidCallback onImprimir;

  @override
  Widget build(BuildContext context) {
    final c = context.watch<VentaControlador>();

    // Las pestañas van arriba, sobre el canvas, como las píldoras de
    // categoría de la grilla — no adentro del panel blanco del carrito.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _BarraVentasAbiertas(),
        const SizedBox(height: Espaciado.sm),
        Expanded(
          child: Superficie(
            child: c.carrito.isEmpty
                ? Center(
                    child: _EstadoVacio(
                      ventaId: ventaConfirmada,
                      totalCentavos: totalConfirmadoCentavos,
                      onImprimir: onImprimir,
                    ),
                  )
                : ListView.builder(
                    // ListView.builder, no Column+scroll: el carrito de una venta
                    // grande no puede redibujarse entero en cada línea agregada
                    // (hardware 2008).
                    itemCount: c.carrito.length,
                    // Con la clave por producto, sacar una línea del medio no hace re-entrar a las de abajo (sin esto
                    // la lista reusa las filas por posición y cada una volvería a animarse).
                    findChildIndexCallback: (clave) {
                      for (var i = 0; i < c.carrito.length; i++) {
                        if (_claveLinea(c.carrito[i], i) == clave) return i;
                      }
                      return null;
                    },
                    itemBuilder: (context, index) {
                      final linea = c.carrito[index];
                      final esUltima = index == c.indiceUltimaLinea;
                      final stockNegativo = _stockQuedaEnCeroONegativo(
                        context,
                        linea,
                      );
                      final textTheme = Theme.of(context).textTheme;
                      // "Bento con carácter" (El dueño, 2026-09-16): punto de color
                      // por rubro — null en "Varios" (sin categoría, Regla 5) o en
                      // cualquier producto sin categoría cargada, mismo criterio
                      // que `BarraCategoria` ya resuelve solo.
                      final colorCat = colorCategoria(
                        context,
                        c.productoPorId(linea.productoId)?.categoriaId,
                      );

                      // Precio unitario: solo por unidad (El dueño, 2026-09-06,
                      // "algo de detalle" — la fila era pobre con solo nombre,
                      // cantidad y subtotal). Un pesable no tiene un "precio
                      // unitario" en ese sentido (es tarifa por kilo, ya visible
                      // en la búsqueda antes de agregar) — se deja un espacio en
                      // blanco del mismo ancho para que el subtotal siga
                      // alineado entre líneas mixtas (`DISENO.md`, reglas de
                      // alineación), no se saca la columna entera.
                      final precioUnitarioTexto = linea is LineaVentaPorUnidad
                          ? formatearARS(
                              linea.precioUnitarioCentavos,
                              conSigno: false,
                            )
                          : null;

                      // Ancho máximo, no `Expanded` hasta el borde de la columna
                      // (regla 1, `DISENO.md`): a este ancho de columna, una fila
                      // que llegara hasta el final obligaría al ojo a recorrer
                      // mucho más de lo que hace falta para conectar el nombre con
                      // su plata. `anchoFilaCarrito` (no `anchoMaximoContenido`):
                      // más ancho que un formulario completo, pero con tope. El
                      // resaltado de la última línea agregada acompaña ese mismo
                      // ancho, no la columna entera.
                      // La línea nueva entra deslizándose; cuando cambia su cantidad, late (2026-10-03).
                      return Entrada(
                        key: _claveLinea(linea, index),
                        child: Pulso(
                          valor: _descripcionCantidad(linea),
                          escala: 1.02,
                          alineacion: Alignment.centerLeft,
                          child: Align(
                        alignment: Alignment.centerLeft,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(
                            maxWidth: Medidas.anchoFilaCarrito,
                          ),
                          child: Container(
                            decoration: BoxDecoration(
                              color: esUltima
                                  ? context.colores.destacado
                                  : null,
                              borderRadius: BorderRadius.circular(
                                radioControlEscritorio,
                              ),
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: Espaciado.md,
                              vertical: Espaciado.md,
                            ),
                            // LayoutBuilder, no un ancho fijo de columna: a
                            // 1920×1080 esto sobra de espacio, pero en el piso
                            // mínimo (1366×768, DISENO.md) con la barra lateral
                            // desplegada la columna del carrito queda en ~230px
                            // — ahí no entran todos los datos más los íconos sin
                            // desbordar (`RenderFlex overflowed`, encontrado por
                            // los tests, no a simple vista). El precio unitario y
                            // los botones "−"/"+" son lo que se saca cuando no
                            // hay lugar — el doble clic para editar la cantidad
                            // sigue andando igual (no ocupa ancho extra).
                            child: LayoutBuilder(
                              builder: (context, constraints) {
                                final hayLugarParaDetalle =
                                    constraints.maxWidth >= 380;
                                final esPorUnidad =
                                    linea is LineaVentaPorUnidad;
                                return Row(
                                  children: [
                                    if (colorCat != null) ...[
                                      BarraCategoria(color: colorCat),
                                      const SizedBox(width: Espaciado.xs),
                                    ],
                                    Expanded(
                                      child: Text(
                                        linea.nombreProducto,
                                        overflow: TextOverflow.ellipsis,
                                        // 2, no 1 (El dueño, panel angosto de 560px:
                                        // "los nombres largos no se ven bien") —
                                        // el `Row` centra al resto de la fila
                                        // solo, no hace falta tocar nada más.
                                        maxLines: 2,
                                        style: textTheme.titleMedium?.copyWith(
                                          color: stockNegativo
                                              ? context.colores.error
                                              : null,
                                        ),
                                      ),
                                    ),
                                    // Stepper en cápsula, solo por unidad y con
                                    // lugar (El dueño, 2026-09-06 + rediseño de
                                    // composición): restar gramos de a poco no
                                    // tiene sentido práctico, y a 1366×768 con la
                                    // barra desplegada no entra sin desbordar —
                                    // mismo umbral exacto que ya evitaba ese bug
                                    // (`TRAMPAS.md`), solo cambia el envoltorio de
                                    // los tres elementos, no cuándo aparecen. En
                                    // 1, restar saca la línea entera
                                    // (`ajustarCantidad`). Doble clic en el
                                    // número: tipear el valor exacto de un tirón.
                                    if (hayLugarParaDetalle && esPorUnidad)
                                      _EscalonCantidad(
                                        texto: _descripcionCantidad(linea),
                                        onMenos: () => context
                                            .read<VentaControlador>()
                                            .ajustarCantidad(index, -1),
                                        onMas: () => context
                                            .read<VentaControlador>()
                                            .ajustarCantidad(index, 1),
                                        onDobleTap: () => _editarCantidad(
                                          context,
                                          index,
                                          linea,
                                        ),
                                      )
                                    else
                                      GestureDetector(
                                        onDoubleTap: () =>
                                            linea is LineaVentaPorUnidad
                                            ? _editarCantidad(
                                                context,
                                                index,
                                                linea,
                                              )
                                            : _editarGramos(
                                                context,
                                                index,
                                                linea as LineaVentaPesable,
                                              ),
                                        child: Text(
                                          _descripcionCantidad(linea),
                                          style: textTheme.bodyMedium,
                                        ),
                                      ),
                                    const SizedBox(width: Espaciado.xs),
                                    if (hayLugarParaDetalle) ...[
                                      SizedBox(
                                        width: Medidas.anchoValorListaCompacto,
                                        child: precioUnitarioTexto == null
                                            ? null
                                            : Text(
                                                precioUnitarioTexto,
                                                textAlign: TextAlign.right,
                                                style: textTheme
                                                    .bodyMedium
                                                    ?.tabular,
                                              ),
                                      ),
                                      const SizedBox(width: Espaciado.sm),
                                    ],
                                    SizedBox(
                                      // Más angosto cuando falta lugar (mismo
                                      // caso que esconde precio unitario y
                                      // "−"/"+"): el margen real en el piso
                                      // mínimo con la barra desplegada resultó
                                      // más justo de lo que parecía a simple
                                      // vista — un desborde de unos pocos
                                      // píxeles apareció recién con ciertas
                                      // interacciones (doble clic), no en el
                                      // primer render. `anchoValorListaCompacto`
                                      // sigue alcanzando de sobra para cualquier
                                      // importe real de este negocio.
                                      width: hayLugarParaDetalle
                                          ? Medidas.anchoValorLista
                                          : Medidas.anchoValorListaCompacto,
                                      child: Text(
                                        formatearARS(
                                          linea.subtotalCentavos,
                                          conSigno: false,
                                        ),
                                        textAlign: TextAlign.right,
                                        style: textTheme.titleMedium?.tabular,
                                      ),
                                    ),
                                    // Ícono de tacho (El dueño, 2026-09-06: "con
                                    // mouse para seleccionar el producto a
                                    // eliminar") — sin confirmación, un tap saca
                                    // la línea. Reemplaza al `Backspace` de
                                    // antes, que solo sacaba la última
                                    // (TRAMPAS.md/CLAUDE.md ya actualizados).
                                    _IconoAccion(
                                      icono: IconosPlazoleta.deleteOutline,
                                      etiqueta: 'Quitar ${linea.nombreProducto}',
                                      onTap: () {
                                        final controlador = context.read<VentaControlador>();
                                        controlador.eliminarLinea(index);
                                        // Un toque saca la línea sin confirmar, así que se
                                        // puede deshacer. El snackbar flota a la izquierda
                                        // para no tapar el cobro (regla dura de Venta).
                                        final mensajero = ScaffoldMessenger.of(context);
                                        mensajero.clearSnackBars();
                                        mensajero.showSnackBar(
                                          SnackBar(
                                            behavior: SnackBarBehavior.floating,
                                            margin: const EdgeInsets.only(
                                              left: Espaciado.lg,
                                              right: Medidas.anchoPanelCobroVenta + Espaciado.lg,
                                              bottom: Espaciado.lg,
                                            ),
                                            duration: const Duration(seconds: 5),
                                            content: Text('Quitaste ${linea.nombreProducto}'),
                                            action: SnackBarAction(
                                              label: 'Deshacer',
                                              onPressed: () => controlador.restaurarLinea(index, linea),
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                  ],
                                );
                              },
                            ),
                          ),
                        ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ),
      ],
    );
  }

  /// Una línea por producto (sumar el mismo producto sube la cantidad); "Varios" puede repetirse, así que su clave
  /// lleva también la posición.
  ValueKey<String> _claveLinea(LineaVenta linea, int index) =>
      ValueKey('linea-${linea.productoId}${linea.esVarios ? '-$index' : ''}');

  String _descripcionCantidad(LineaVenta linea) {
    return switch (linea) {
      LineaVentaPorUnidad u => 'x${u.cantidad}',
      LineaVentaPesable p => '${p.gramos} g',
    };
  }

  Future<void> _editarCantidad(
    BuildContext context,
    int index,
    LineaVentaPorUnidad linea,
  ) async {
    final nuevaCantidad = await mostrarDialogoEditarCantidad(
      context,
      titulo: 'Cantidad',
      valorActual: linea.cantidad,
      linea: linea,
    );
    if (nuevaCantidad == null) return;
    if (!context.mounted) return;
    context.read<VentaControlador>().editarCantidadExacta(index, nuevaCantidad);
  }

  Future<void> _editarGramos(
    BuildContext context,
    int index,
    LineaVentaPesable linea,
  ) async {
    final nuevosGramos = await mostrarDialogoEditarCantidad(
      context,
      titulo: 'Gramos',
      valorActual: linea.gramos,
      linea: linea,
    );
    if (nuevosGramos == null) return;
    if (!context.mounted) return;
    context.read<VentaControlador>().editarGramosExacto(index, nuevosGramos);
  }

  // El stock ya descontado por esta línea todavía no existe hasta cobrar:
  // esto es una previsualización con el stock actual del catálogo, no el
  // definitivo. Alcanza para la advertencia visual de Regla 8.
  bool _stockQuedaEnCeroONegativo(BuildContext context, LineaVenta linea) {
    final c = context.read<VentaControlador>();
    final producto = c.productoPorId(linea.productoId);
    // "Varios" no tiene stock en el sentido de Regla 8 (Regla 5: nunca lo
    // descuenta) — sin esto, cualquier línea de "Varios" se pintaba en rojo
    // como si tuviera un problema de stock que no existe.
    if (producto == null || producto.esVarios) return false;
    if (linea is LineaVentaPesable) {
      return (producto.stockGramos ?? 0) - linea.gramos <= 0;
    }
    final unidad = linea as LineaVentaPorUnidad;
    return producto.stock - unidad.cantidad <= 0;
  }
}

/// Ícono chico de acción para una fila de lista (tacho, "−", "+") — un
/// `InkWell` a mano, no `IconButton`: el tap target default de `IconButton`
/// es mucho más ancho que el ícono mismo, y en una fila con varias columnas
/// de datos el ancho importa (ver `TRAMPAS.md`, "La fila del carrito
/// necesita LayoutBuilder").
class _IconoAccion extends StatelessWidget {
  const _IconoAccion({required this.icono, required this.etiqueta, required this.onTap});
  final IconData icono;
  final String etiqueta;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SuperficieTactil(
      etiqueta: etiqueta,
      tamanoMinimo: Medidas.alturaControl,
      borderRadius: BorderRadius.circular(TactoVenta.radio),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(Espaciado.xs),
        child: Icon(
          icono,
          size: TactoVenta.icono,
          color: context.colores.textoSecundario,
        ),
      ),
    );
  }
}

/// Stepper de cantidad en cápsula — "−", el número (con su propio doble
/// clic para tipear el valor exacto) y "+" agrupados en una sola pieza en
/// vez de tres sueltas en la fila (rediseño de composición, el dueño:
/// "rediseño completo, no un remake que mantenga las bases" — el remake
/// anterior solo había cambiado color/blur, dejando la misma disposición).
class _EscalonCantidad extends StatelessWidget {
  const _EscalonCantidad({
    required this.texto,
    required this.onMenos,
    required this.onMas,
    required this.onDobleTap,
  });

  final String texto;
  final VoidCallback onMenos;
  final VoidCallback onMas;
  final VoidCallback onDobleTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.colores.fondo,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: context.colores.borde),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _celda(context, IconosPlazoleta.remove, 'Restar uno', onMenos),
          GestureDetector(
            onDoubleTap: onDobleTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: Espaciado.xs),
              child: Text(
                texto,
                style: Theme.of(context).textTheme.bodyMedium?.tabular,
              ),
            ),
          ),
          _celda(context, IconosPlazoleta.add, 'Sumar uno', onMas),
        ],
      ),
    );
  }

  Widget _celda(BuildContext context, IconData icono, String etiqueta, VoidCallback onTap) {
    return SuperficieTactil(
      etiqueta: etiqueta,
      tamanoMinimo: Medidas.alturaControl,
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Icon(icono, size: 16, color: context.colores.textoSecundario),
      ),
    );
  }
}

/// Sin venta confirmada todavía: el texto neutro de siempre. Con una
/// confirmada: número de venta y total cobrado, en `textoSecundario` — no
/// es ninguno de los tres usos ya asignados al acento, así que no le suma
/// un cuarto — más el botón de imprimir (fase 13, ítem 3), que solo tiene
/// sentido mientras hay algo reciente que reimprimir.
class _EstadoVacio extends StatelessWidget {
  const _EstadoVacio({
    required this.ventaId,
    required this.totalCentavos,
    required this.onImprimir,
  });

  final int? ventaId;
  final int? totalCentavos;
  final VoidCallback onImprimir;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    if (ventaId == null || totalCentavos == null) {
      return Text('El carrito está vacío', style: textTheme.bodyMedium);
    }
    // Cada cobro entra con un tilde y un zoom leve (2026-10-03): confirma que salió, sin frenar la venta siguiente
    // (el campo ya tiene el foco y se puede seguir escaneando mientras dura).
    final ganancia = context.acentosPlazoleta.ganancia;
    return Entrada(
      key: ValueKey('cobrada-$ventaId'),
      escala: 0.92,
      desplazamiento: 0,
      child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(color: ganancia.withValues(alpha: 0.14), shape: BoxShape.circle),
          child: Icon(Icons.check_rounded, size: 15, color: ganancia),
        ),
        const SizedBox(width: Espaciado.sm),
        // `Flexible`, no `Text` suelto: en el piso mínimo (1366×768,
        // `DISENO.md`) el carrito queda bastante más angosto que a
        // 1920×1080 — sin esto, un total de varias cifras desborda el
        // `RenderFlex` en vez de acortarse.
        Flexible(
          child: Text(
            'Venta #$ventaId cobrada · ${formatearARS(totalCentavos!)}',
            overflow: TextOverflow.ellipsis,
            style: textTheme.bodyMedium!
                .copyWith(color: context.colores.textoSecundario)
                .tabular,
          ),
        ),
        const SizedBox(width: Espaciado.sm),
        Tooltip(
          message: 'Imprimir ticket',
          child: SuperficieTactil(
            borderRadius: BorderRadius.circular(TactoVenta.radio),
            onTap: onImprimir,
            child: Padding(
              padding: const EdgeInsets.all(Espaciado.xs),
              child: Icon(
                IconosPlazoleta.printOutlined,
                size: TactoVenta.icono,
                color: context.colores.textoSecundario,
              ),
            ),
          ),
        ),
      ],
    ),
    );
  }
}

/// Pestañas de ventas abiertas (El dueño, 2026-09-29: "que la venta permanezca
/// y que pueda hacer más de 1 venta a la vez"). Mismo lenguaje que las
/// píldoras de categoría de la grilla: 44px de alto, redondeadas, rellenas
/// de acento la elegida y blancas planas las demás. "+" abre una venta
/// nueva sin perder la actual (Alt+N).
class _BarraVentasAbiertas extends StatelessWidget {
  const _BarraVentasAbiertas();

  @override
  Widget build(BuildContext context) {
    final c = context.watch<VentaControlador>();
    final resumen = c.resumenPestanas;
    final puedeAbrirOtra = c.carrito.isNotEmpty;

    return Row(
      children: [
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (var i = 0; i < resumen.length; i++) ...[
                  if (i > 0) const SizedBox(width: Espaciado.sm),
                  _PildoraVenta(
                    titulo: 'Venta ${i + 1}',
                    detalle: resumen.length == 1 || resumen[i].lineas == 0
                        ? null
                        : formatearARS(resumen[i].subtotalCentavos),
                    seleccionada: i == c.pestanaActiva,
                    puedeCerrar: i == c.pestanaActiva && resumen.length > 1,
                    onTap: () => c.cambiarAPestana(i),
                    onCerrar: () => cancelarVentaConDeshacer(context, c),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(width: Espaciado.sm),
        Tooltip(
          message: 'Nueva venta (Alt+N)',
          child: _BotonNuevaVenta(activo: puedeAbrirOtra, onTap: c.nuevaVenta),
        ),
      ],
    );
  }
}

class _PildoraVenta extends StatelessWidget {
  const _PildoraVenta({
    required this.titulo,
    required this.detalle,
    required this.seleccionada,
    required this.puedeCerrar,
    required this.onTap,
    required this.onCerrar,
  });

  final String titulo;
  final String? detalle;
  final bool seleccionada;
  final bool puedeCerrar;
  final VoidCallback onTap;
  final VoidCallback onCerrar;

  @override
  Widget build(BuildContext context) {
    final colores = context.colores;
    final textTheme = Theme.of(context).textTheme;
    final colorTexto = seleccionada
        ? colores.acentoTexto
        : colores.textoPrimario;
    return Container(
      height: Medidas.alturaControl,
      decoration: BoxDecoration(
        color: seleccionada ? colores.acento : colores.fondoBloque,
        borderRadius: BorderRadius.circular(999),
      ),
      child: SuperficieTactil(
        etiqueta: titulo,
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.only(
            left: Espaciado.lg,
            right: Espaciado.md,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                titulo,
                style: TextStyle(
                  color: colorTexto,
                  fontWeight: seleccionada ? Pesos.medium : Pesos.regular,
                ),
              ),
              if (detalle != null) ...[
                const SizedBox(width: Espaciado.sm),
                Text(
                  detalle!,
                  style: textTheme.bodySmall
                      ?.copyWith(
                        color: seleccionada
                            ? colorTexto.withValues(alpha: 0.85)
                            : colores.textoSecundario,
                      )
                      .tabular,
                ),
              ],
              if (puedeCerrar) ...[
                const SizedBox(width: Espaciado.sm),
                Tooltip(
                  message: 'Cerrar $titulo',
                  child: Semantics(
                    button: true,
                    label: 'Cerrar $titulo',
                    excludeSemantics: true,
                    onTap: onCerrar,
                    child: InkResponse(
                      onTap: onCerrar,
                      radius: 24,
                      child: SizedBox(
                        width: Medidas.alturaControl,
                        height: Medidas.alturaControl,
                        child: Icon(Icons.close_rounded, size: 18, color: colorTexto),
                      ),
                    ),
                  ),
                ),
              ] else
                const SizedBox(width: Espaciado.xs),
            ],
          ),
        ),
      ),
    );
  }
}

class _BotonNuevaVenta extends StatelessWidget {
  const _BotonNuevaVenta({required this.activo, required this.onTap});

  final bool activo;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colores = context.colores;
    return Container(
      width: Medidas.alturaControl,
      height: Medidas.alturaControl,
      decoration: BoxDecoration(
        color: colores.fondoBloque,
        shape: BoxShape.circle,
      ),
      child: SuperficieTactil(
        etiqueta: 'Nueva venta',
        borderRadius: BorderRadius.circular(999),
        onTap: activo ? onTap : null,
        child: Center(
          child: Icon(
            Icons.add,
            color: activo ? colores.acento : colores.textoTenue,
          ),
        ),
      ),
    );
  }
}
