// El logo de Nodo Sur (el mismo de horsepos.com, opción A elegida por el dueño el 2026-10-03): cuadrado de tinta
// redondeado con "ns" en minúscula (Figtree) y un punto blanco arriba a la derecha — el nodo. Sin el verde de la versión
// anterior: la estética nueva es tinta y blanco. Se dibuja con widgets en vez de un asset porque la bienvenida lo arma
// por partes: el punto llega primero y el cuadrado crece desde él.

import 'package:flutter/material.dart';

import '../../ui/tema/tokens.dart';

/// Verde de "todo bien" de la bienvenida (el punto que vuela hasta el logo). Ya no es parte del logo: al aterrizar se
/// vuelve [colorPuntoMarca].
const verdeMarca = Color(0xFF34A853);

/// Tinta del cuadrado y blanco del punto y de las letras (`favicon.svg` de horsepos.com, viewBox 96×96).
const fondoMarca = Color(0xFF121317);
const colorPuntoMarca = Colors.white;

/// Dónde cae el centro del punto dentro del logo, como fracción del lado (en el SVG de 96×96 está en 73, 30).
const centroPuntoMarca = Offset(73 / 96, 30 / 96);

/// Diámetro del punto, como fracción del lado (radio 5 sobre 96).
const diametroPuntoMarca = 10 / 96;

class MarcaNodoSur extends StatelessWidget {
  const MarcaNodoSur({super.key, this.tamanio = 40, this.opacidadTexto = 1, this.conPunto = true});

  final double tamanio;

  /// La bienvenida hace aparecer las letras después del cuadrado.
  final double opacidadTexto;

  /// Sin punto cuando lo dibuja aparte la animación (llega volando y se queda en su lugar).
  final bool conPunto;

  @override
  Widget build(BuildContext context) {
    final u = tamanio / 96;
    final punto = diametroPuntoMarca * tamanio;
    return SizedBox(
      width: tamanio,
      height: tamanio,
      child: DecoratedBox(
        decoration: BoxDecoration(color: fondoMarca, borderRadius: BorderRadius.circular(22 * u)),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: Align(
                // Las letras de "ns" son todas de altura de x: un poco por debajo del centro quedan ópticamente
                // centradas, igual que en el SVG (línea de base en 62 sobre 96).
                alignment: const Alignment(-0.04, 0.12),
                child: Opacity(
                  opacity: opacidadTexto.clamp(0.0, 1.0),
                  child: Text(
                    'ns',
                    style: TextStyle(
                      fontFamily: familiaTipografica,
                      fontSize: 44 * u,
                      height: 1,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -1.5 * u,
                      color: colorPuntoMarca,
                    ),
                  ),
                ),
              ),
            ),
            if (conPunto)
              Positioned(
                left: centroPuntoMarca.dx * tamanio - punto / 2,
                top: centroPuntoMarca.dy * tamanio - punto / 2,
                child: Container(
                  width: punto,
                  height: punto,
                  decoration: const BoxDecoration(color: colorPuntoMarca, shape: BoxShape.circle),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
