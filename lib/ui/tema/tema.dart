// Arma los dos ThemeData (claro/oscuro) a partir de tokens.dart +
// colores_escritorio.dart + acentos.dart. Ninguna pantalla debería
// construir un ThemeData ni un TextStyle "suelto": todo sale de acá o de
// `Theme.of(context)`.
//
// Remake completo de la estética (El dueño, 2026-09-19: "quiero que en
// desktop remakeemos toda la estética basándonos en la estética actual del
// celular... basémonos al completo en el apk") — mismo armado que antes,
// pero con la paleta/acentos/radios/escala tipográfica que ya usa la
// companion (`lib/companion/tema/tema_companion.dart`), portados con
// fidelidad completa. Ver el plan del remake para el detalle fase por fase
// (`DISENO.md` se reescribe en el mismo cambio que cada fase, no todo de
// una).

import 'package:flutter/material.dart';

import 'acentos.dart';
import 'colores_escritorio.dart';
import 'tokens.dart';

/// Radio de `Superficie` — 28, tarjetas muy redondeadas como las de la web
/// de Nodo Sur (rediseño "antigravity"). Mismo valor que
/// `radioSuperficieCompanion`.
const double radioSuperficieEscritorio = 28;

/// Radio de controles rectangulares (campos, chips de ícono, filas
/// resaltadas dentro de una tarjeta) — 16. Los botones no lo usan: son
/// pastilla (`StadiumBorder`).
const double radioControlEscritorio = 16;

abstract final class TemaPlazoleta {
  static ThemeData get claro => _construir(coloresEscritorioClaro, acentosEscritorioClaro, Brightness.light);
  static ThemeData get oscuro => _construir(coloresEscritorioOscuro, acentosEscritorioOscuro, Brightness.dark);

  static ThemeData _construir(ColoresPlazoleta colores, AcentosPlazoleta acentos, Brightness brillo) {
    final colorScheme = ColorScheme(
      brightness: brillo,
      primary: colores.acento,
      onPrimary: colores.acentoTexto,
      secondary: acentos.dinero,
      onSecondary: acentos.textoSobreColor,
      error: colores.error,
      onError: colores.errorTexto,
      surface: colores.fondo,
      onSurface: colores.textoPrimario,
    );

    final base = ThemeData(
      useMaterial3: true,
      brightness: brillo,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: colores.fondo,
      fontFamily: familiaTipografica,
      // Transición corta entre pantallas (fase 13, sin tocar en el remake —
      // es una decisión de navegación, no de estética: esta app no tiene
      // jerarquía de "entrar desde la derecha" como sí la tiene la
      // companion con su pila de pestañas).
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.windows: _TransicionCorta(),
          TargetPlatform.linux: _TransicionCorta(),
          TargetPlatform.macOS: _TransicionCorta(),
        },
      ),
      splashColor: colores.acento.withValues(alpha: 0.16),
      highlightColor: colores.acento.withValues(alpha: 0.08),
      hoverColor: colores.textoPrimario.withValues(alpha: 0.04),
    );

    final textTheme = _construirTextTheme(base.textTheme, colores);

    return base.copyWith(
      textTheme: textTheme,
      extensions: [colores, acentos],
      dividerTheme: DividerThemeData(color: colores.borde, thickness: Bordes.fino, space: Espaciado.lg),
      appBarTheme: AppBarTheme(
        backgroundColor: colores.fondo,
        foregroundColor: colores.textoPrimario,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: textTheme.titleLarge,
      ),
      // Fallback para cualquier `Card` que quede de código viejo mientras
      // dura el rollout (`Superficie` es lo que se usa en código nuevo).
      cardTheme: CardThemeData(
        color: colores.fondoBloque,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radioSuperficieEscritorio)),
      ),
      // Fondo transparente + sin elevación acá a propósito: `Modal`
      // (`lib/ui/comun/modal.dart`) arma su propia superficie de vidrio
      // (blur + relleno translúcido + sombra propia), igual que
      // `mostrarHojaVidrio` en la companion — este tema solo cubre la
      // forma (radio) para cualquier `Dialog`/`AlertDialog` suelto que no
      // pase por `Modal`.
      dialogTheme: DialogThemeData(
        backgroundColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radioSuperficieEscritorio)),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: colores.textoPrimario,
        contentTextStyle: textTheme.bodyMedium?.copyWith(color: colores.fondo),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radioControlEscritorio)),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: colores.fondoBloque,
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radioControlEscritorio)),
        textStyle: textTheme.bodyMedium,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colores.fondoBloque,
        contentPadding: const EdgeInsets.symmetric(horizontal: Espaciado.lg, vertical: Espaciado.md),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radioControlEscritorio),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radioControlEscritorio),
          borderSide: BorderSide.none,
        ),
        // Sin borde en reposo; el foco sí necesita una señal funcional —
        // no es un borde decorativo, es el único indicio de qué campo
        // tiene el foco en una app que se maneja sobre todo con teclado.
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radioControlEscritorio),
          borderSide: BorderSide(color: colores.acento, width: Bordes.fino * 1.5),
        ),
        labelStyle: TextStyle(color: colores.textoSecundario),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: colores.acento,
          foregroundColor: colores.acentoTexto,
          disabledBackgroundColor: colores.borde,
          disabledForegroundColor: colores.textoTenue,
          textStyle: TextStyle(fontFamily: familiaTipografica, fontSize: TamanioTexto.cuerpo, fontWeight: Pesos.medium),
          minimumSize: const Size.fromHeight(Medidas.alturaControl),
          shape: const StadiumBorder(),
          padding: const EdgeInsets.symmetric(horizontal: Espaciado.lg),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: colores.acento,
          foregroundColor: colores.acentoTexto,
          elevation: 0,
          // Nunca `textTheme.labelLarge` acá (bug real ya encontrado: ese
          // rol hornea `colores.textoPrimario` adentro del `TextStyle`, y
          // ese color explícito puede ganarle a `foregroundColor`).
          textStyle: TextStyle(fontFamily: familiaTipografica, fontSize: TamanioTexto.cuerpo, fontWeight: Pesos.medium),
          shape: const StadiumBorder(),
          padding: const EdgeInsets.symmetric(horizontal: Espaciado.xl, vertical: Espaciado.md),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: colores.textoPrimario,
          side: BorderSide(color: colores.borde, width: Bordes.fino),
          textStyle: textTheme.labelLarge,
          shape: const StadiumBorder(),
          padding: const EdgeInsets.symmetric(horizontal: Espaciado.xl, vertical: Espaciado.md),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: colores.acento,
          textStyle: textTheme.labelLarge,
        ),
      ),
      iconTheme: IconThemeData(color: colores.textoSecundario),
      listTileTheme: ListTileThemeData(
        iconColor: colores.textoSecundario,
        textColor: colores.textoPrimario,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? colores.acentoTexto : colores.fondo,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? colores.acento : colores.textoTenue.withValues(alpha: 0.5),
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: colores.acento, circularTrackColor: colores.borde),
    );
  }

  static TextTheme _construirTextTheme(TextTheme base, ColoresPlazoleta colores) {
    TextStyle estilo(double tamanio, FontWeight peso, Color color, {double altura = 1.25}) => TextStyle(
          fontFamily: familiaTipografica,
          fontSize: tamanio,
          fontWeight: peso,
          color: color,
          height: altura,
        );

    // Titulares livianos y apretados (peso 400/500), como la web y la
    // companion: la jerarquía la da el tamaño, no el negrita. Un rol de
    // texto = un tamaño = un peso, siempre el mismo en toda la app.
    TextStyle apretado(double tamanio, FontWeight peso, Color color, {double altura = 1.25, double espaciado = 0}) =>
        estilo(tamanio, peso, color, altura: altura).copyWith(letterSpacing: tamanio * espaciado);

    return base.copyWith(
      displayLarge: apretado(TamanioTexto.total, FontWeight.w400, colores.textoPrimario, altura: 1.05, espaciado: -0.05).tabular,
      headlineMedium: apretado(TamanioTexto.grande, FontWeight.w400, colores.textoPrimario, altura: 1.08, espaciado: -0.045).tabular,
      titleLarge: apretado(TamanioTexto.titulo, FontWeight.w500, colores.textoPrimario, espaciado: -0.03),
      titleMedium: apretado(TamanioTexto.subtitulo, FontWeight.w500, colores.textoPrimario, espaciado: -0.02),
      titleSmall: estilo(TamanioTexto.cuerpo, Pesos.medium, colores.textoPrimario),
      bodyLarge: estilo(TamanioTexto.subtitulo, Pesos.regular, colores.textoPrimario),
      bodyMedium: estilo(TamanioTexto.cuerpo, Pesos.regular, colores.textoPrimario),
      bodySmall: estilo(TamanioTexto.secundario, Pesos.regular, colores.textoSecundario),
      labelLarge: estilo(TamanioTexto.cuerpo, Pesos.medium, colores.textoPrimario),
      labelMedium: estilo(TamanioTexto.etiqueta, Pesos.regular, colores.textoSecundario),
      labelSmall: estilo(TamanioTexto.pequeno, Pesos.regular, colores.textoTenue),
    );
  }
}

/// Fundido corto con un acercamiento muy leve (98% → 100%) y la pantalla de abajo que se aleja un poco: se siente
/// fluido sin "viajar" de costado (El dueño, 2026-10-03: "que se vea todo fluido"). Sin desplazamiento lateral: esta app
/// no tiene jerarquía de pestañas como la companion. Al volver, la misma animación al revés.
class _TransicionCorta extends PageTransitionsBuilder {
  const _TransicionCorta();

  @override
  Duration get transitionDuration => Animaciones.media;

  @override
  Duration get reverseTransitionDuration => Animaciones.corta;

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final entrada = CurvedAnimation(parent: animation, curve: Animaciones.curva, reverseCurve: Curves.easeInCubic);
    final tapada = CurvedAnimation(parent: secondaryAnimation, curve: Animaciones.curva, reverseCurve: Curves.easeInCubic);
    // 2026-10-03 (el dueño: "las animaciones son una miseria"): la pantalla nueva sube un poco además de fundirse y
    // crecer, y la de abajo se achica y se atenúa, para que el cambio se lea como un paso. Misma duración.
    return FadeTransition(
      opacity: entrada,
      child: SlideTransition(
        position: Tween<Offset>(begin: const Offset(0, 0.015), end: Offset.zero).animate(entrada),
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.97, end: 1).animate(entrada),
          child: FadeTransition(
            opacity: Tween<double>(begin: 1, end: 0.7).animate(tapada),
            child: ScaleTransition(
              scale: Tween<double>(begin: 1, end: 0.985).animate(tapada),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}
