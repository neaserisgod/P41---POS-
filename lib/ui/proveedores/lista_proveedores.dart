// Columna izquierda de Proveedores ("Lenguaje de diseño", el dueño 2026-09-26,
// mock `Proveedores.dc.html`): una tarjeta por proveedor — iniciales, nombre,
// cuántos productos tiene y una insignia si alguno avisa por stock — con
// "Todos" arriba y "Sin proveedor" abajo. Tocar una elige esa vista a la
// derecha, sin salir de la pantalla. Reemplaza al picker de tarjetas grandes
// (séptima pasada del 2026-09-25), que obligaba a entrar y salir.

import 'package:flutter/material.dart';

import '../../domain/dinero.dart';
import '../comun/tarjetas.dart';
import '../tema/iconos.dart';
import '../tema/tema_inverso.dart';
import '../tema/presionable.dart';
import '../tema/tema.dart';
import '../tema/tokens.dart';
import 'proveedores_controlador.dart';
import '../tema/movimiento.dart';

/// Ancho de la columna: nombre, "N productos" y la insignia en una fila,
/// sin cortar nombres de proveedor normales.
const double anchoListaProveedores = 340;

String _productos(int n) => '$n producto${n == 1 ? '' : 's'}';

class ListaProveedores extends StatelessWidget {
  const ListaProveedores({super.key, required this.controlador});

  final ProveedoresControlador controlador;

  @override
  Widget build(BuildContext context) {
    final c = controlador;
    final filas = <Widget>[
      _FilaProveedor(
        nombre: 'Todos',
        icono: IconosPlazoleta.inventory2Outlined,
        detalle: _productos(c.todosLosProductos.length),
        stockBajo: c.stockBajoTotal,
        elegida: c.vista == SeleccionProveedor.todos,
        onTap: c.seleccionarTodos,
      ),
      for (final r in c.resumenes.where((r) => c.proveedorVisible(r.proveedor)))
        _FilaProveedor(
          nombre: r.proveedor.nombre,
          detalle: [
            _productos(c.cantidadDeProductos(r.proveedor.id)),
            if (r.vendidoCentavos > 0)
              'vendió ${formatearARS(r.vendidoCentavos)}',
            if (c.deudaDe(r.proveedor.id) > 0)
              'le debés ${formatearARS(c.deudaDe(r.proveedor.id))}',
          ].join(' · '),
          stockBajo: c.stockBajoDe(r.proveedor.id),
          apagada: r.sinMovimiento,
          elegida:
              c.vista == SeleccionProveedor.proveedor &&
              c.seleccionado?.id == r.proveedor.id,
          onTap: () => c.seleccionar(r.proveedor.id),
        ),
      if (c.sinProveedorVisible)
        _FilaProveedor(
          nombre: 'Sin proveedor',
          icono: IconosPlazoleta.helpOutline,
          detalle: _productos(c.cantidadDeProductos(null)),
          stockBajo: c.stockBajoDe(null),
          elegida: c.vista == SeleccionProveedor.sinProveedor,
          onTap: c.seleccionarSinProveedor,
        ),
    ];
    return ListView.separated(
      itemCount: filas.length,
      separatorBuilder: (_, _) => const SizedBox(height: Espaciado.sm),
      itemBuilder: (_, i) => entradaEnLista(i, filas[i]),
    );
  }
}

class _FilaProveedor extends StatelessWidget {
  const _FilaProveedor({
    required this.nombre,
    required this.detalle,
    required this.stockBajo,
    required this.elegida,
    required this.onTap,
    this.icono,
    this.apagada = false,
  });

  final String nombre;
  final String detalle;
  final int stockBajo;
  final bool elegida;
  final VoidCallback onTap;

  /// Para "Todos"/"Sin proveedor": un ícono en vez de iniciales.
  final IconData? icono;

  /// Sin movimiento en el período: el nombre en gris.
  final bool apagada;

  @override
  Widget build(BuildContext context) {
    final inv = coloresDeFila(context, elegida);
    final colores = inv.colores;
    final textTheme = inv.textTheme;
    return Presionable(
      radio: radioControlEscritorio + 4,
      onTap: onTap,
      color: elegida ? colores.acento : colores.fondoBloque,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Espaciado.md,
          vertical: Espaciado.md,
        ),
        child: Row(
          children: [
            AvatarIniciales(
              texto: inicialesDe(nombre),
              icono: icono,
              elegido: elegida,
            ),
            const SizedBox(width: Espaciado.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    nombre,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.bodyMedium?.copyWith(
                      fontWeight: Pesos.fuerte,
                      color: apagada && !elegida
                          ? colores.textoSecundario
                          : colores.textoPrimario,
                    ),
                  ),
                  Text(
                    detalle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            if (stockBajo > 0) ...[
              const SizedBox(width: Espaciado.sm),
              Insignia(texto: '$stockBajo', tono: Tono.alerta),
            ],
            const SizedBox(width: Espaciado.xs),
            Icon(IconosPlazoleta.chevronRight, color: colores.textoSecundario),
          ],
        ),
      ),
    );
  }
}
