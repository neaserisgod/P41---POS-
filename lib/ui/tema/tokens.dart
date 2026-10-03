// Fase 11 — sistema de diseño, estilo bento. Todos los valores de estilo de
// la app viven acá: si mañana cambia un color, un espaciado o un radio, se
// toca este archivo y nada más. Ninguna pantalla debería tener un
// Color(0x...), un EdgeInsets.all(número suelto) o un fontWeight
// hardcodeado.
//
// Regla de armonía (El dueño, fase 11): UNA sola escala de espaciado, UNA sola
// escala tipográfica, UN solo acento de color. Si un valor no sale de acá,
// está mal — no importa cuánto "quede bien" en una pantalla suelta. Esto se
// mira doce horas por día, seis días por semana: la consistencia entre
// pantallas no es estética, es lo que evita el cansancio visual.

import 'package:flutter/material.dart';

/// Paleta de un modo (claro u oscuro). No es el `ColorScheme` de Material
/// directamente porque acá hacen falta más matices de los que Material trae
/// de fábrica, y menos "roles" de los que Material ofrece por defecto —
/// tres niveles de texto, un fondo, un fondo de bloque, un acento. Nada más.
@immutable
class ColoresPlazoleta extends ThemeExtension<ColoresPlazoleta> {
  const ColoresPlazoleta({
    required this.fondo,
    required this.fondoBloque,
    required this.borde,
    required this.textoPrimario,
    required this.textoSecundario,
    required this.textoTenue,
    required this.acento,
    required this.acentoTexto,
    required this.error,
    required this.errorTexto,
  });

  /// Fondo de la pantalla (el "canvas" del bento). Contraste MEDIDO, no
  /// máximo: nunca negro puro — vibra contra el texto claro y cansa la
  /// vista en una sesión de doce horas.
  final Color fondo;

  /// Fondo de cada bloque: un paso apenas por encima de `fondo`, sin borde.
  /// Es la única herramienta de jerarquía visual en ausencia de sombras.
  final Color fondoBloque;

  /// Único uso que le queda a un "borde" real en la app: el borde de
  /// `OutlinedButton`, el riel apagado de un `Switch`. Nunca para separar
  /// bloques o filas — eso se resuelve con espacio (ver `Espaciado`).
  final Color borde;

  /// Tres niveles de texto y solo tres. Si hace falta un cuarto matiz, se
  /// resuelve con espacio, no con otro gris.
  final Color textoPrimario;
  final Color textoSecundario;
  final Color textoTenue;

  /// EL acento de toda la app — un solo color, ámbar. Se usa con
  /// moderación: el total, el medio de pago elegido, la línea recién
  /// agregada al carrito, y (agregado 2026-09-12, pensado dos veces según
  /// pedía este comentario) el punto que marca "esto tiene algo pendiente"
  /// en una `FilaLista` (`tienePendiente`) — mismo espíritu que los otros
  /// tres, "esto importa ahora". En cualquier otro lado deja de señalar
  /// algo y se vuelve ruido — no agregar un uso más sin pensarlo dos veces.
  final Color acento;

  /// Texto/ícono sobre una superficie pintada sólida con `acento` (ej. el
  /// medio de pago elegido).
  final Color acentoTexto;

  /// El único otro color con significado en la app. Exclusivo de lo que
  /// está mal: stock agotado, diferencia de caja distinta de cero (sobrar
  /// plata también es un descuadre — solo el cero va sin color). Nunca
  /// decorativo, y nunca para un flujo normal del negocio aunque suene a
  /// advertencia (ej. la separación parcial de cigarrillos que arrastra
  /// pendiente al próximo cierre — mismo día o siguiente, un turno es una
  /// sesión completa — Regla 6: eso es `textoSecundario`).
  final Color error;

  /// Texto/ícono sobre una superficie pintada sólida con `error` (ej. el
  /// botón de confirmar una acción destructiva). Mismo motivo que
  /// `acentoTexto`: un color con su propio contraste, no blanco a mano en
  /// cada lugar que lo necesita.
  final Color errorTexto;

  /// Resalte de una fila "elegida" o "recién agregada" dentro de una lista
  /// (última línea del carrito, fila preseleccionada del buscador, medio de
  /// pago elegido si se pinta como chip). Se calcula a partir del acento en
  /// vez de guardarse aparte: así solo hay UN color de acento que mantener,
  /// y el resalte lo sigue automáticamente si cambia.
  Color get destacado =>
      Color.alphaBlend(acento.withValues(alpha: 0.16), fondoBloque);

  @override
  ColoresPlazoleta copyWith({
    Color? fondo,
    Color? fondoBloque,
    Color? borde,
    Color? textoPrimario,
    Color? textoSecundario,
    Color? textoTenue,
    Color? acento,
    Color? acentoTexto,
    Color? error,
    Color? errorTexto,
  }) {
    return ColoresPlazoleta(
      fondo: fondo ?? this.fondo,
      fondoBloque: fondoBloque ?? this.fondoBloque,
      borde: borde ?? this.borde,
      textoPrimario: textoPrimario ?? this.textoPrimario,
      textoSecundario: textoSecundario ?? this.textoSecundario,
      textoTenue: textoTenue ?? this.textoTenue,
      acento: acento ?? this.acento,
      acentoTexto: acentoTexto ?? this.acentoTexto,
      error: error ?? this.error,
      errorTexto: errorTexto ?? this.errorTexto,
    );
  }

  @override
  ColoresPlazoleta lerp(ThemeExtension<ColoresPlazoleta>? other, double t) {
    // Sin transiciones (CLAUDE.md): esto solo existe porque ThemeExtension
    // lo pide, nunca se anima en la práctica.
    if (other is! ColoresPlazoleta) return this;
    return t < 0.5 ? this : other;
  }
}

/// La única escala de espaciado de la app: márgenes, padding, huecos entre
/// bloques. Todo valor de layout sale de acá — 4, 8, 12, 16, 24, 32. Nunca
/// un número suelto (7, 13, 22...). La pantalla de venta logra su densidad
/// eligiendo los valores CHICOS de esta misma escala (`xs`/`sm`), no con
/// una escala aparte.
abstract final class Espaciado {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;

  /// Sumado en el remake de la estética (El dueño, 2026-09-19) para piezas
  /// "hero" grandes — mismo valor que `Espaciado.xxxl`.
  static const double xxxl = 48;
}

/// Medidas del estilo bento. Un solo radio de bloque, un solo hueco entre
/// bloques (igual en horizontal y en vertical), un solo padding — tanto el
/// externo de pantalla como el interno de cada bloque son el mismo valor.
/// Si un bloque necesita otro padding, es la jerarquía la que está mal, no
/// el padding (El dueño).
abstract final class Bento {
  static const double radio = 14;
  static const double hueco = Espaciado.md;
  static const double paddingPantalla = Espaciado.lg;
  static const double paddingBloque = Espaciado.lg;
}

/// Radio único para controles internos (botones, campos, filas resaltadas
/// dentro de un bloque) — distinto del radio de bloque a propósito, para
/// que un botón nunca se confunda visualmente con un bloque de contenido.
/// Ningún tercer radio en ningún lado.
abstract final class Radios {
  static const double control = 8;
}

/// Medidas puntuales que no son "espaciado" (márgenes/huecos) pero necesitan
/// ser un solo número reutilizado, no una constante suelta por archivo.
abstract final class Medidas {
  /// Ancho del valor final (siempre a la derecha) en cualquier fila de
  /// lista con etiqueta a la izquierda y monto a la derecha — carrito,
  /// dropdown de búsqueda, y cualquier lista futura con el mismo patrón.
  /// Subido de 90 a 110 junto con la escala tipográfica (fase 13): el mismo
  /// monto tabular ocupa más ancho con `cuerpo` en 16 que en 13.5.
  static const double anchoValorLista = 110;

  /// Altura de un botón que pertenece a un grupo de opciones del mismo
  /// tamaño (ej. los tres medios de pago): "tres rectángulos idénticos".
  /// Subida en la pasada de fatiga visual de la fase 13 (era 40) — mismo
  /// criterio que el resto de la escala: más aire ahora que 1080px sobra.
  static const double alturaControl = 48;

  /// Ancho de la barra lateral de navegación desplegada — icono + nombre de
  /// cada sección. Subido de 220 a 300 en la corrección post-revisión: a
  /// 220 el encabezado ("La Plazoleta" + botón de plegar) desbordaba 70px
  /// con la escala tipográfica de la pasada de fatiga visual — bug real que
  /// ningún test ejercitaba porque hasta esa misma corrección la barra
  /// arrancaba plegada en todos lados, así que el layout desplegado casi
  /// nunca se renderizaba. Sigue entrando cómoda en el piso mínimo
  /// (1366×768) sin perder densidad de carrito.
  static const double anchoBarraLateral = 300;

  /// Ancho de la barra lateral plegada — solo íconos, con tooltip. Ya no es
  /// el default de arranque (corrección post-revisión, ver el comentario de
  /// `configuracion_tabla.barraLateralPlegada`), pero sigue siendo una
  /// opción: un clic explícito, nunca automática al pasar el mouse.
  static const double anchoBarraLateralPlegada = 64;

  /// Ancho máximo de una columna de contenido tipo formulario (patrón A) o
  /// del contenido de un bloque de detalle (patrón lista + detalle) — y,
  /// desde la pasada de fatiga visual (fase 13), de cualquier fila de lista
  /// que hoy tiene una columna de sobra a lo ancho (el carrito de venta):
  /// más allá de este ancho, conectar una etiqueta con su valor obliga al
  /// ojo a recorrer más de lo necesario (principio rector, `DISENO.md`).
  /// Subido de 640 (objetivo 1366×768) a 760 al resolver la revisión
  /// pendiente contra 1920×1080.
  static const double anchoMaximoContenido = 760;

  /// Ancho máximo de una fila del carrito de venta. Subido de 640 a 960
  /// en el remake de disposición (2026-09-19): el carrito dejó de
  /// compartir la zona derecha con una columna de cobro aparte (ver
  /// `pantalla_venta.dart`/`columna_cobro.dart`), así que le sobra bastante
  /// más ancho que antes — sigue con tope (regla 1, `DISENO.md`: ninguna
  /// fila cruza la pantalla entera) pero más generoso que el viejo 640.
  static const double anchoFilaCarrito = 960;

  /// Ancho del modal de cierre de caja en su fase "revisado" — el único
  /// diálogo de la app con layout de dos columnas (Arqueo a la izquierda,
  /// Cigarrillos y Resumen del día a la derecha, `DISENO.md`). No entra en
  /// `anchoMaximoContenido` (760, una sola columna de campos) sin apretar
  /// las dos columnas a un ancho incómodo.
  static const double anchoModalCierre = 960;

  /// Ancho fijo de la barra de búsqueda de venta (rediseño 2026-09-25,
  /// El dueño: "la barra de busqueda debe ocpar un espacio fijo al centro, no
  /// extenderse en todos lados") — reemplaza al viejo `Expanded` que la
  /// estiraba a todo el ancho disponible de la franja superior. Mismo
  /// orden de magnitud que la caja de búsqueda de Gmail/Drive en un
  /// monitor de escritorio. `pantalla_venta.dart` la reduce por
  /// `LayoutBuilder` si el espacio real es menor (ventanas angostas), nunca
  /// desborda.
  static const double anchoBarraBusquedaVenta = 640;

  /// Ancho de la búsqueda de la barra superior en las pantallas de gestión
  /// (a la derecha de las pastillas de secciones).
  static const double anchoBarraBusquedaGestion = 300;

  /// Ancho fijo del panel de carrito + cobro a la derecha de la pantalla de
  /// venta (rediseño 2026-09-25, segunda pasada: El dueño mandó una referencia
  /// de POS con el carrito en un panel fijo y contestó "1 pero manteniendo
  /// la estructura de dropdown" — vuelve el panel fijo, la izquierda pasa a
  /// ser la tira de directos + la grilla de productos navegable).
  ///
  /// 560, no un valor más chico: la fila del carrito esconde precio
  /// unitario y el stepper en cápsula por debajo de 380px de ancho real
  /// (`hayLugarParaDetalle`, `columna_carrito.dart`) — descontando el
  /// padding de `Superficie` (16×2) y el de la fila (12×2), un panel de
  /// 420 dejaba solo 364px (por DEBAJO del umbral: el stepper no aparecía
  /// NUNCA, ni a 1920×1080 — bug real, encontrado por
  /// `pantalla_venta_test.dart`, "los botones −/+ ajustan la cantidad") y
  /// uno de 460 lo cruzaba de milagro pero sin dejarle nada al nombre del
  /// producto (se veía "Coca-C…", visto en `capturas/venta-oscuro.png` de
  /// esta misma pasada — el stepper + precio unitario + subtotal + tacho ya
  /// suman ~330px fijos). 560 le deja al nombre un ancho real, no solo
  /// technically-por-encima-del-umbral.
  static const double anchoPanelCobroVenta = 560;

  /// Ancho fijo de la columna angosta en cualquier pantalla con patrón
  /// lista + detalle (Proveedores, Productos, Configuración). Historia:
  /// 320 → 460 al llegar a Proveedores (fase 13, tres niveles de
  /// información) → 580 en la primera corrección post-revisión, al separar
  /// "stock" (a precio) de "costo" en filas de cuatro cifras → **360** en
  /// la segunda corrección post-revisión (dibujo de el dueño): las cifras
  /// dejaron de vivir en la lista — son del proveedor elegido, no de todos
  /// a la vez — así que la columna vuelve a ser angosta ("nombre y poco
  /// más"). Sigue siendo un valor compartido con Productos, que va a seguir
  /// el mismo esquema de tres paneles.
  static const double anchoListaMaestra = 360;

  /// Ancho de una columna de valor en una fila de lista con VARIAS cifras
  /// una al lado de la otra (Proveedores/Productos nivel 1: stock, vendido,
  /// ganancia / precio, stock, vendido, margen) — más angosto que
  /// `anchoValorLista` (pensado para una sola cifra al final de una fila,
  /// carrito) porque acá tienen que entrar varias en el mismo ancho de
  /// columna angosta.
  static const double anchoValorListaCompacto = 84;
}

/// Grosor del único borde real que queda en la app (`ColoresPlazoleta.borde`).
abstract final class Bordes {
  static const double fino = 1;
}

/// Figtree (El dueño, "Lenguaje de diseño" 2026-09-26) reemplazó a Glacial
/// Indifference — toda la app pasa por esta única familia y única escala
/// (Regla de armonía, fase 11). Trae los cuatro pesos que usa el lenguaje
/// nuevo como archivos reales (ver `pubspec.yaml`), así que ningún peso de
/// `Pesos` se simula. Glacial además no tenía glifos para ✓ › · y su Bold
/// dibujaba mal la "é" en algunos tamaños.
const String familiaTipografica = 'Figtree';

/// Regla de pesos: Regular para leer, Medium (600) para lo que destaca
/// (títulos, etiquetas, botones), Fuerte (700) solo para cifras y títulos
/// de pantalla — igual que en los mocks. `medium` vale 600 y no 500 a
/// propósito: es el peso "de título" del mock, y cambiarlo acá mueve toda
/// la app de una sin tocar las pantallas.
abstract final class Pesos {
  static const FontWeight regular = FontWeight.w400;
  static const FontWeight medium = FontWeight.w600;
  static const FontWeight fuerte = FontWeight.w700;
}

/// La única escala tipográfica de la app, con un rol fijo por tamaño —
/// nunca el mismo tamaño con un rol distinto en otra pantalla. Realineada
/// en el remake de la estética (El dueño, 2026-09-19: "basémonos al completo
/// en el apk") a los mismos valores que ya usa la companion
/// (`TemaCompanion._construirTextTheme`) — `etiqueta`/`secundario`/`cuerpo`
/// ya coincidían de antes, solo `subtitulo`/`titulo`/`total` bajan un
/// toque (19→18, 24→22, 48→44) y se suman `pequeno`/`grande` para los dos
/// roles que la companion tiene y el escritorio no usaba todavía:
/// - `pequeno` (12): la más chica, uso puntual (labelSmall).
/// - `etiqueta` (13): aclaraciones chicas, atajos entre paréntesis.
/// - `secundario` (14): texto mutado, de apoyo.
/// - `cuerpo` (16): texto de lista estándar (nombres, filas).
/// - `subtitulo` (18): título de un bloque o de un diálogo.
/// - `titulo` (22): título de la pantalla (AppBar).
/// - `grande` (32): uso puntual, un paso antes de `total` (headlineMedium).
/// - `total` (44): la cifra grande — el total de una venta, de un mes.
abstract final class TamanioTexto {
  static const double pequeno = 12;
  static const double etiqueta = 13;
  static const double secundario = 14;
  static const double cuerpo = 16;
  static const double subtitulo = 18;
  static const double titulo = 22;
  static const double grande = 32;
  static const double total = 44;
}

/// Números tabulares (misma métrica para cada dígito, columnas alineadas)
/// para todo lo que sea plata, sin excepción: precios, subtotales, el total
/// de la pantalla de venta. Sin esto, dos columnas de números en una lista
/// no alinean y se nota en la caja.
extension NumerosTabulares on TextStyle {
  TextStyle get tabular =>
      copyWith(fontFeatures: const [FontFeature.tabularFigures()]);
}

/// Acceso corto a la paleta del tema activo: `context.colores.textoSecundario`.
extension ColoresDelContexto on BuildContext {
  ColoresPlazoleta get colores => Theme.of(this).extension<ColoresPlazoleta>()!;
}

/// Animaciones (fase 13, hardware): la prohibición de fase 11 se cayó junto
/// con la PC de 2008 que la motivaba (`CLAUDE.md`, "Hardware — qué cambió y
/// qué no") — vuelven, cortas, y desde el 2026-10-03 en toda la app,
/// también en Venta (el dueño eligió animar todo; ver `movimiento.dart`):
/// nunca demoran lo que se tipea ni el cobro. `corta` es para lo que cambia dentro de una misma
/// pantalla (plegar la barra lateral, resaltar la sección activa); `media`
/// es para la transición entre pantallas.
abstract final class Animaciones {
  static const Duration corta = Duration(milliseconds: 160);
  static const Duration media = Duration(milliseconds: 220);
  static const Curve curva = Curves.easeOutCubic;

  /// "Dark glass premium" (El dueño, rediseño 2026-09-25): overshoot leve,
  /// aproxima un spring de baja fricción sin agregar ninguna dependencia
  /// nueva de física — para elementos que APARECEN o se SELECCIONAN (la
  /// pastilla de sección activa de la navbar, `Presionable`). No reemplaza
  /// a [curva]: una transición de página/fade con rebote se ve rota, esa
  /// sigue con `easeOutCubic`.
  static const Curve curvaSpring = Curves.easeOutBack;
}
