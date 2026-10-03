// Reemplazo de `Bloque` (ya borrado) para la companion — más
// redondeado, y con un modo de relleno sólido ("color-blocking": la tarjeta
// entera pintada con el acento, no solo el texto) para las piezas que
// tienen que saltar a la vista (el total del carrito, el resumen del día).
// El escritorio sigue usando `Bloque` tal cual; este widget no lo reemplaza
// ahí, solo le da a la companion su propia unidad visual.
//
// Rediseño "antigravity": bloque plano gris muy claro (negro azulado en
// oscuro), sin borde ni sombra y con esquinas de 28; lo más importante de
// cada pantalla va en `BloqueHero` (`piezas_companion.dart`).

import 'package:flutter/material.dart';

import '../../ui/tema/tokens.dart';
import 'tema_companion.dart';

class Superficie extends StatelessWidget {
  const Superficie({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(Espaciado.lg),
    this.relleno,
    this.degrade,
    this.colorTexto,
    this.resplandor = false,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  /// No nulo = "color-blocking": la superficie entera se pinta con este
  /// color sólido en vez del gris de `fondoBloque` — para la pieza que más
  /// importa de una pantalla (el total a cobrar, el resumen del día).
  final Color? relleno;

  /// Alternativa a [relleno]: dos o más colores en diagonal — para las
  /// piezas "hero" de la app (El dueño, 2026-09-18: "pensalo como una app
  /// moderna, útil y monetizable"). Gana sobre [relleno] si los dos están
  /// puestos.
  final List<Color>? degrade;

  /// Color de texto sugerido para cuando `relleno`/`degrade` está puesto (el
  /// llamador decide si lo usa — este widget no fuerza el color de sus hijos).
  final Color? colorTexto;

  /// Halo neón (El dueño, 2026-09-19: "la estética japonesa cyberpunk me vuela
  /// la gorra") — solo tiene efecto con `relleno`/`degrade` puesto (una
  /// superficie gris no tiene de qué color brillar). A propósito reservado
  /// para las piezas "hero" de cada pantalla (el CTA de vender, el resumen
  /// del día, el total a cobrar): si todas las superficies brillaran, el
  /// brillo dejaría de señalar nada.
  final bool resplandor;

  @override
  Widget build(BuildContext context) {
    // Plana, igual que la del escritorio ("Lenguaje de diseño", el dueño
    // 2026-09-26): relleno opaco, sin borde ni sombra ni brillo de vidrio.
    final gradiente = degrade;
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radioSuperficieCompanion),
        color: gradiente == null ? (relleno ?? context.colores.fondoBloque) : null,
        gradient: gradiente == null
            ? null
            : LinearGradient(colors: gradiente, begin: Alignment.topLeft, end: Alignment.bottomRight),
      ),
      child: child,
    );
  }
}
