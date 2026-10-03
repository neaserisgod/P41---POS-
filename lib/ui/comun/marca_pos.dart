// El ícono de Nodo Sur POS dibujado con widgets (opción 4 elegida por el dueño, 2026-10-03): cuadrado redondeado con
// "pos" en Figtree y un punto debajo. Misma geometría que `assets/icon/logo_pos.png` (SVG de 96×96: radio 22, "pos" de
// 34 con la línea de base en 60, punto de radio 4 en 48, 74), así el ícono de la barra de tareas y la marca de la
// ventana se ven iguales. Con widgets y no con la imagen porque cambia de color con el tema y con el foco de la ventana.

import 'package:flutter/material.dart';

import '../tema/tokens.dart';

class MarcaPos extends StatelessWidget {
  const MarcaPos({super.key, this.tamanio = 22, required this.fondo, required this.tinta});

  final double tamanio;

  /// El cuadrado (la tinta del tema en claro) y las letras y el punto (su contraste).
  final Color fondo;
  final Color tinta;

  @override
  Widget build(BuildContext context) {
    final u = tamanio / 96;
    return SizedBox(
      width: tamanio,
      height: tamanio,
      child: DecoratedBox(
        decoration: BoxDecoration(color: fondo, borderRadius: BorderRadius.circular(22 * u)),
        child: Stack(
          children: [
            Positioned.fill(
              child: Align(
                // "pos" lleva descendente (la p): un poco por arriba del centro, para dejar lugar al punto.
                alignment: const Alignment(0, -0.05),
                child: Text(
                  'pos',
                  style: TextStyle(
                    fontFamily: familiaTipografica,
                    fontSize: 34 * u,
                    height: 1,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -1.2 * u,
                    color: tinta,
                  ),
                ),
              ),
            ),
            Positioned(
              left: (48 - 4) * u,
              top: (74 - 4) * u,
              child: Container(
                width: 8 * u,
                height: 8 * u,
                decoration: BoxDecoration(color: tinta, shape: BoxShape.circle),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
