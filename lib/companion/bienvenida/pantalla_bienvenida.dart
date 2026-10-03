// Bienvenida de la companion: lo primero que ve una instalación nueva, antes de elegir el modo de uso.
//
// Es la misma pieza que la historia de Instagram de Nodo Sur (la web, `marketing/historia-v2/`), llevada al celular con
// las funciones que el celular sí tiene (El dueño, 2026-10-03: "muy similar si no es que igual a eso, pero evidentemente
// que sea un onboarding"; eligió las funciones del celular, que la vea toda instalación nueva, y avanzar con un botón
// Siguiente en vez de reproducirse sola). Comparar proveedores, que abre la historia, existe solo en la PC: acá la
// frase de apertura pasa a "Tu plata, en orden." y muestra cuánto separar para cada proveedor.
//
// Cada escena nace de la anterior en vez de cortar: la frase de apertura sube y queda de título; las barras de los
// proveedores se recogen en puntos que saltan y se juntan en uno verde, que espera el conteo de la caja y se vuelve el
// tilde; el tilde se achica hasta ser el punto del wifi; un círculo oscuro se abre para el escáner y se cierra en el
// punto del logo (blanco al aterrizar).
//
// Toda la animación sale de una línea de tiempo en segundos (`_cuadro(t)`), como la historia: "Siguiente" la hace
// correr hasta la próxima parada. Con "reducir animaciones" salta directo a la parada.

import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../../domain/dinero.dart';
import '../../ui/tema/tokens.dart';
import '../tema/campo_particulas.dart';
import '../tema/tema_companion.dart';
import 'marca_nodo_sur.dart';

/// Segundo en que se detiene cada escena (la última es el final de la línea de tiempo).
const paradasBienvenida = [1.5, 3.9, 6.7, 8.8, 10.9, 13.1];

class PantallaBienvenida extends StatefulWidget {
  const PantallaBienvenida({super.key, required this.alTerminar, this.pasoInicial = 0, this.segundoFijo});

  /// "Empezar" en la última escena, o "Saltar" en cualquiera.
  final void Function(BuildContext context) alTerminar;

  /// Solo para tests y capturas: en qué escena arranca.
  @visibleForTesting
  final int pasoInicial;

  /// Solo para capturas: congela la animación en ese segundo de la línea de tiempo (para ver una transición a medias).
  @visibleForTesting
  final double? segundoFijo;

  @override
  State<PantallaBienvenida> createState() => _PantallaBienvenidaState();
}

class _PantallaBienvenidaState extends State<PantallaBienvenida> with SingleTickerProviderStateMixin {
  static final _total = paradasBienvenida.last;

  late final AnimationController _reloj = AnimationController(
    vsync: this,
    duration: Duration(milliseconds: (_total * 1000).round()),
  );
  int _paso = 0;
  bool _arrancado = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_arrancado) return;
    _arrancado = true;
    _paso = widget.pasoInicial;
    if (widget.segundoFijo != null) {
      _reloj.value = widget.segundoFijo! / _total;
      return;
    }
    _irA(_paso);
  }

  @override
  void dispose() {
    _reloj.dispose();
    super.dispose();
  }

  void _irA(int paso) {
    final destino = paradasBienvenida[paso] / _total;
    if (MediaQuery.disableAnimationsOf(context)) {
      _reloj.value = destino;
      return;
    }
    final faltan = (destino - _reloj.value).abs() * _total;
    _reloj.animateTo(destino, duration: Duration(milliseconds: (faltan * 1000).round()), curve: Curves.linear);
  }

  void _siguiente() {
    if (_paso == paradasBienvenida.length - 1) {
      widget.alTerminar(context);
      return;
    }
    setState(() => _paso++);
    _irA(_paso);
  }

  @override
  Widget build(BuildContext context) {
    final esUltimo = _paso == paradasBienvenida.length - 1;
    return Scaffold(
      body: AnimatedBuilder(
        animation: _reloj,
        builder: (context, _) {
          final t = _reloj.value * _total;
          final p = _Paleta.de(context);
          final cubierto = _cubierto(t);
          final sobreOscuro = cubierto > 0.5;
          return Stack(
            children: [
              Positioned.fill(
                child: CampoParticulas(
                  colores: p.temaOscuro ? particulasSobreNegro : particulasSobreClaro,
                  centro: const Alignment(0, -0.1),
                  densidad: 0.8,
                ),
              ),
              Positioned.fill(
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 64, bottom: 132),
                    child: LayoutBuilder(
                      builder: (context, caja) {
                        // La escena se diseña en 390×600 y se escala para entrar entera en cualquier celular.
                        final s = math.min(caja.maxWidth / _ancho, caja.maxHeight / _alto);
                        final ox = (caja.maxWidth - _ancho * s) / 2;
                        final oy = (caja.maxHeight - _alto * s) * 0.35;
                        return Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Positioned(
                              left: ox,
                              top: oy,
                              child: Transform.scale(
                                scale: s,
                                alignment: Alignment.topLeft,
                                child: SizedBox(width: _ancho, height: _alto, child: _Escena(t: t, p: p)),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: SafeArea(
                  bottom: false,
                  child: SizedBox(
                    height: 56,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: Espaciado.lg),
                      child: Row(
                        children: [
                          Opacity(
                            opacity: 1 - _ac(_pr(t, 10.9, 0.3)),
                            child: Row(
                              children: [
                                const MarcaNodoSur(tamanio: 28),
                                const SizedBox(width: Espaciado.sm),
                                Text(
                                  'Nodo Sur',
                                  style: TextStyle(
                                    fontFamily: familiaTipografica,
                                    fontSize: 17,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: -0.3,
                                    color: Color.lerp(p.tinta, Colors.white, cubierto),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Spacer(),
                          if (!esUltimo)
                            TextButton(
                              key: const Key('bienvenida-saltar'),
                              onPressed: () => widget.alTerminar(context),
                              style: TextButton.styleFrom(
                                foregroundColor: Color.lerp(p.secundario, const Color(0xFFC9CDD6), cubierto),
                              ),
                              child: const Text('Saltar'),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(Espaciado.xl, 0, Espaciado.xl, Espaciado.xl),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _Puntos(actual: _paso, total: paradasBienvenida.length, color: sobreOscuro ? Colors.white : p.tinta),
                        const SizedBox(height: Espaciado.xl),
                        SizedBox(
                          width: double.infinity,
                          height: alturaControlCompanion,
                          child: FilledButton(
                            key: const Key('bienvenida-siguiente'),
                            onPressed: _siguiente,
                            style: FilledButton.styleFrom(
                              backgroundColor: Color.lerp(p.acento, Colors.white, p.temaOscuro ? 0 : cubierto),
                              foregroundColor: Color.lerp(p.acentoTexto, const Color(0xFF121317), p.temaOscuro ? 0 : cubierto),
                            ),
                            child: Text(esUltimo ? 'Empezar' : 'Siguiente'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Cuánto de la pantalla tapa el círculo oscuro del escáner (0 a 1): los controles cambian de color con él.
double _cubierto(double t) => t < 8.8 ? 0 : _em(_pr(t, 8.8, 0.9)) * (1 - _em(_pr(t, 11.0, 0.7)));

class _Puntos extends StatelessWidget {
  const _Puntos({required this.actual, required this.total, required this.color});

  final int actual;
  final int total;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < total; i++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutCubic,
            margin: const EdgeInsets.symmetric(horizontal: 3),
            width: i == actual ? 22 : 6,
            height: 6,
            decoration: BoxDecoration(
              color: color.withValues(alpha: i == actual ? 1 : 0.25),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------------------------------------------------
// Línea de tiempo

const _ancho = 390.0;
const _alto = 600.0;

// Curvas de Material 3: enfatizada, desacelerada, acelerada y estándar.
const _cEm = Cubic(0.2, 0, 0, 1);
const _cDe = Cubic(0.05, 0.7, 0.1, 1);
const _cAc = Cubic(0.3, 0, 0.8, 0.15);
const _cSm = Cubic(0.4, 0, 0.2, 1);
double _em(double x) => _cEm.transform(x);
double _de(double x) => _cDe.transform(x);
double _ac(double x) => _cAc.transform(x);
double _sm(double x) => _cSm.transform(x);

/// Avance de 0 a 1 de algo que empieza en [a] y dura [d] segundos.
double _pr(double t, double a, double d) => ((t - a) / d).clamp(0.0, 1.0);
double _lerp(double a, double b, double k) => a + (b - a) * k;

/// Montos de ejemplo de la bienvenida, en centavos (Regla: la plata siempre en centavos).
const _separarHoy = 98750000;
const _teQueda = 37630000;
const _deberiaHaber = 24870000;
const _proveedores = [('Distribuidora Andina', 41230000), ('Mayorista Nevado', 26890000), ('Almacén Cordillera', 30630000)];

// Barras de proveedores: largo (proporcional al monto), altura en la escena y color.
const _largoBarra = [310.0, 202.0, 230.0];
const _yBarra = [278.0, 328.0, 378.0];
const _colorBarra = [Color(0xFF4F7CFF), Color(0xFF18C3A4), Color(0xFFD36BB5)];

const _verdeOk = Color(0xFF1E8E3E);
const _gradiente = LinearGradient(colors: [Color(0xFF3B6CFF), Color(0xFF8A5CF6), Color(0xFF18C3A4)]);

/// Dónde termina el punto verde, sobre el logo de la última escena (logo de 96 en 147, 152).
const _ladoLogo = 96.0;
const _origenLogo = Offset(147, 152);
final _puntoLogo = _origenLogo + Offset(centroPuntoMarca.dx * _ladoLogo, centroPuntoMarca.dy * _ladoLogo);

class _Paleta {
  const _Paleta({
    required this.temaOscuro,
    required this.fondo,
    required this.tinta,
    required this.bloque,
    required this.borde,
    required this.secundario,
    required this.tenue,
    required this.acento,
    required this.acentoTexto,
  });

  factory _Paleta.de(BuildContext context) {
    final c = context.colores;
    return _Paleta(
      temaOscuro: Theme.of(context).brightness == Brightness.dark,
      fondo: c.fondo,
      tinta: c.textoPrimario,
      bloque: c.fondoBloque,
      borde: c.borde,
      secundario: c.textoSecundario,
      tenue: c.textoTenue,
      acento: c.acento,
      acentoTexto: c.acentoTexto,
    );
  }

  final bool temaOscuro;
  final Color fondo;
  final Color tinta;
  final Color bloque;
  final Color borde;
  final Color secundario;
  final Color tenue;
  final Color acento;
  final Color acentoTexto;

  /// El círculo que se abre para el escáner: casi negro en claro; azul noche en oscuro, para que se note sobre el negro.
  Color get revelado => temaOscuro ? const Color(0xFF1B1F3A) : const Color(0xFF121317);

  /// La tarjeta de lo que hay que separar: siempre oscura, como el bloque de la web.
  Color get tarjetaOscura => temaOscuro ? const Color(0xFF14161C) : const Color(0xFF1F1F1F);
}

// ---------------------------------------------------------------------------------------------------------------------
// Escena

class _Escena extends StatelessWidget {
  const _Escena({required this.t, required this.p});

  final double t;
  final _Paleta p;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(child: CustomPaint(painter: _PintorFondo(t: t, p: p))),
        ..._apertura(),
        ..._separar(),
        ..._cierre(),
        ..._sinInternet(),
        ..._escaner(),
        ..._final(),
        Positioned.fill(child: IgnorePointer(child: CustomPaint(painter: _PintorFrente(t: t, p: p)))),
      ],
    );
  }

  TextStyle _estilo(double tamanio, {FontWeight peso = FontWeight.w400, Color? color, double apretado = -0.045}) => TextStyle(
        fontFamily: familiaTipografica,
        fontSize: tamanio,
        fontWeight: peso,
        height: 1.08,
        letterSpacing: tamanio * apretado,
        color: color ?? p.tinta,
      );

  /// Texto con el degradé de la marca.
  Widget _degrade(Widget hijo) => ShaderMask(
        blendMode: BlendMode.srcIn,
        shaderCallback: (r) => _gradiente.createShader(Rect.fromLTWH(0, 0, r.width, r.height)),
        child: hijo,
      );

  /// Pieza que aparece subiendo y se va subiendo.
  Widget _pieza({required double entrada, double salida = 0, double sube = 16, required Widget child}) {
    final o = entrada * (1 - salida);
    if (o <= 0.001) return const SizedBox.shrink();
    return Opacity(
      opacity: o.clamp(0.0, 1.0),
      child: Transform.translate(offset: Offset(0, (1 - entrada) * sube - salida * sube), child: child),
    );
  }

  /// Titular centrado palabra por palabra: cada palabra sube y aparece 70 ms después de la anterior; las marcadas con
  /// `*` llevan el degradé.
  Widget _titular(List<String> lineas, double tamanio, {required double inicio, required double fin, Color? color, double dur = 0.6}) {
    var i = 0;
    final filas = <Widget>[];
    for (final linea in lineas) {
      final palabras = <Widget>[];
      for (final cruda in linea.split(' ')) {
        final conDegrade = cruda.startsWith('*');
        final palabra = cruda.replaceAll('*', '');
        final k = _de(_pr(t, inicio + i * 0.07, dur));
        final o = _ac(_pr(t, fin + i * 0.03, 0.35));
        Widget texto = Text(palabra, style: _estilo(tamanio, color: conDegrade ? Colors.white : color));
        if (conDegrade) texto = _degrade(texto);
        palabras.add(
          Padding(
            padding: EdgeInsets.symmetric(horizontal: tamanio * 0.11),
            child: Opacity(
              opacity: (k * (1 - o)).clamp(0.0, 1.0),
              child: Transform.translate(offset: Offset(0, (1 - k) * 16 - o * 16), child: texto),
            ),
          ),
        );
        i++;
      }
      filas.add(Row(mainAxisSize: MainAxisSize.min, children: palabras));
    }
    return Column(mainAxisSize: MainAxisSize.min, children: filas);
  }

  Widget _centrado(double y, Widget hijo) => Positioned(left: 0, right: 0, top: y, child: Center(child: hijo));

  // 0 → 1 · "Tu almacén, en orden." sube, queda de título y "almacén" se cambia por "plata".
  List<Widget> _apertura() {
    if (t > 4.4) return const [];
    final sube = _em(_pr(t, 1.6, 0.8));
    final cambio = _em(_pr(t, 2.2, 0.6));
    final sale = _ac(_pr(t, 3.9, 0.35));
    final a1 = _de(_pr(t, 0.35, 0.7));
    final a2 = _de(_pr(t, 0.5, 0.7));
    const tamanio = 52.0;
    const alto = tamanio * 1.14;
    final linea1 = ClipRect(
      child: SizedBox(
        width: _ancho,
        height: alto,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Opacity(
              opacity: (a1 * (1 - cambio)).clamp(0.0, 1.0),
              child: Transform.translate(offset: Offset(0, (1 - a1) * 16 - cambio * alto), child: Text('Tu almacén,', style: _estilo(tamanio))),
            ),
            Opacity(
              opacity: (cambio * (1 - sale)).clamp(0.0, 1.0),
              child: Transform.translate(offset: Offset(0, (1 - cambio) * alto - sale * 16), child: Text('Tu plata,', style: _estilo(tamanio))),
            ),
          ],
        ),
      ),
    );
    final linea2 = Opacity(
      opacity: (a2 * (1 - sale)).clamp(0.0, 1.0),
      child: Transform.translate(
        offset: Offset(0, (1 - a2) * 16 - sale * 16),
        child: _degrade(Text('en orden.', style: _estilo(tamanio, color: Colors.white))),
      ),
    );
    return [
      _centrado(
        150,
        _pieza(
          entrada: _de(_pr(t, 0.1, 0.7)),
          salida: _ac(_pr(t, 1.5, 0.35)),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(color: p.bloque, borderRadius: BorderRadius.circular(999)),
            child: Text('Sistema de caja para kioscos y almacenes',
                style: _estilo(13, peso: FontWeight.w500, color: p.secundario, apretado: 0)),
          ),
        ),
      ),
      Positioned(
        left: 0,
        right: 0,
        top: _lerp(200, 16, sube),
        child: Transform.scale(
          scale: _lerp(1, 0.72, sube),
          alignment: Alignment.topCenter,
          child: Column(mainAxisSize: MainAxisSize.min, children: [linea1, linea2]),
        ),
      ),
    ];
  }

  // 1 · Cuánto separar para cada proveedor (las barras las dibuja el pintor de adelante).
  List<Widget> _separar() {
    if (t < 2.3 || t > 4.4) return const [];
    final entra = _de(_pr(t, 2.4, 0.6));
    final sale = _ac(_pr(t, 3.95, 0.3));
    final cuenta = _sm(_pr(t, 2.6, 0.9));
    const blanco = Colors.white;
    return [
      Positioned(
        left: 20,
        top: 140 + (1 - entra) * 24,
        width: 350,
        height: 330,
        child: Opacity(
          opacity: (entra * (1 - sale)).clamp(0.0, 1.0),
          child: DecoratedBox(decoration: BoxDecoration(color: p.tarjetaOscura, borderRadius: BorderRadius.circular(28))),
        ),
      ),
      Positioned(
        left: 40,
        top: 160,
        child: _pieza(
          entrada: _de(_pr(t, 2.55, 0.6)),
          salida: sale,
          child: Text('Separar para proveedores · hoy', style: _estilo(13, color: const Color(0xFFB8BCC6), apretado: 0)),
        ),
      ),
      Positioned(
        left: 38,
        top: 182,
        child: _pieza(
          entrada: _de(_pr(t, 2.6, 0.6)),
          salida: sale,
          child: Text(formatearARS((_separarHoy * cuenta).round()),
              style: _estilo(40, peso: FontWeight.w700, color: blanco, apretado: -0.035).copyWith(
                fontFeatures: const [FontFeature.tabularFigures()],
              )),
        ),
      ),
      for (var i = 0; i < 3; i++) ...[
        Positioned(
          left: 40,
          top: _yBarra[i] - 28,
          child: _pieza(
            entrada: _de(_pr(t, 2.75 + i * 0.12, 0.6)),
            salida: sale,
            child: Text(_proveedores[i].$1, style: _estilo(14, color: const Color(0xFFC9CDD6), apretado: 0)),
          ),
        ),
        Positioned(
          right: 40,
          top: _yBarra[i] - 29,
          child: _pieza(
            entrada: _de(_pr(t, 2.8 + i * 0.12, 0.6)),
            salida: sale,
            child: Text(formatearARS(_proveedores[i].$2), style: _estilo(15, peso: FontWeight.w700, color: blanco, apretado: 0)),
          ),
        ),
      ],
      Positioned(
        left: 40,
        top: 410,
        child: _pieza(
          entrada: _em(_pr(t, 3.4, 0.5)),
          salida: sale,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(color: const Color(0xFF173D26), borderRadius: BorderRadius.circular(999)),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text('Te queda a vos', style: _estilo(14, color: const Color(0xFFC8F0D5), apretado: 0)),
                const SizedBox(width: 10),
                Text(formatearARS(_teQueda), style: _estilo(20, peso: FontWeight.w700, color: const Color(0xFF5BD38A), apretado: -0.02)),
              ],
            ),
          ),
        ),
      ),
    ];
  }

  // 2 · Cierre a ciegas: se cuenta sin ver cuánto debería haber.
  List<Widget> _cierre() {
    if (t < 4.6 || t > 7.2) return const [];
    final sale = _ac(_pr(t, 6.7, 0.35));
    final cuenta = _sm(_pr(t, 5.4, 0.8));
    final revela = _de(_pr(t, 6.15, 0.35));
    final entra = _de(_pr(t, 4.95, 0.6));
    Widget fila(String etiqueta, Widget valor, {bool linea = true}) => Container(
          height: 52,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          decoration: BoxDecoration(border: linea ? Border(bottom: BorderSide(color: p.borde)) : null),
          child: Row(
            children: [
              Text(etiqueta, style: _estilo(16, apretado: 0)),
              const Spacer(),
              valor,
            ],
          ),
        );
    final cifra = _estilo(16, peso: FontWeight.w700, apretado: -0.01).copyWith(fontFeatures: const [FontFeature.tabularFigures()]);
    return [
      _centrado(16, _titular(const ['Contás la caja', '*a* *ciegas.*'], 38, inicio: 4.7, fin: 6.7)),
      _centrado(
        110,
        _pieza(
          entrada: _de(_pr(t, 4.9, 0.6)),
          salida: sale,
          child: Text('Primero se cuenta. Después, la diferencia.', style: _estilo(14, color: p.secundario, apretado: 0)),
        ),
      ),
      Positioned(
        left: 20,
        top: 150 + (1 - entra) * 20 - sale * 20,
        width: 350,
        child: Opacity(
          opacity: (entra * (1 - sale)).clamp(0.0, 1.0),
          child: Container(
            decoration: BoxDecoration(
              color: p.fondo,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: p.borde),
              boxShadow: const [BoxShadow(color: Color(0x1F121317), blurRadius: 40, offset: Offset(0, 18), spreadRadius: -16)],
            ),
            child: Column(
              children: [
                fila('Contaste', Text(formatearARS((_deberiaHaber * cuenta).round()), style: cifra)),
                fila(
                  'Debería haber',
                  // Tapado hasta terminar de contar: así nadie acomoda la cuenta a lo que espera ver.
                  Opacity(
                    opacity: _lerp(0.45, 1, revela),
                    child: ImageFiltered(
                      imageFilter: ImageFilter.blur(sigmaX: (1 - revela) * 6, sigmaY: (1 - revela) * 6),
                      child: Text(formatearARS(_deberiaHaber), style: cifra),
                    ),
                  ),
                ),
                fila(
                  'Diferencia',
                  Text(revela < 0.5 ? '—' : formatearARS(0), style: cifra.copyWith(color: revela < 0.5 ? p.tenue : _verdeOk)),
                  linea: false,
                ),
              ],
            ),
          ),
        ),
      ),
      _centrado(
        424,
        _pieza(
          entrada: _de(_pr(t, 6.2, 0.45)),
          salida: sale,
          child: Text('La caja cierra', style: _estilo(17, peso: FontWeight.w700, color: _verdeOk, apretado: 0)),
        ),
      ),
    ];
  }

  // 3 · Sin internet: las ondas salen del punto, se tachan y la venta queda guardada igual.
  List<Widget> _sinInternet() {
    if (t < 7.0 || t > 9.3) return const [];
    final sale = _ac(_pr(t, 8.8, 0.35));
    const tamanio = 34.0;
    const alto = tamanio * 1.16;
    Widget linea(int i, Widget texto) {
      final k = _em(_pr(t, 7.2 + i * 0.12, 0.7));
      final o = _ac(_pr(t, 8.8 + i * 0.05, 0.4));
      return ClipRect(
        child: SizedBox(
          height: alto,
          child: Transform.translate(offset: Offset(0, (1 - k) * alto - o * alto), child: texto),
        ),
      );
    }

    return [
      _centrado(
        16,
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            linea(0, Text('Se corta internet,', style: _estilo(tamanio))),
            linea(1, _degrade(Text('y seguís vendiendo.', style: _estilo(tamanio, color: Colors.white)))),
          ],
        ),
      ),
      Positioned(
        left: 55,
        width: 280,
        top: 395,
        child: _pieza(
          entrada: _em(_pr(t, 8.15, 0.5)),
          salida: sale,
          sube: 30,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: p.fondo,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: p.borde),
              boxShadow: const [BoxShadow(color: Color(0x29121317), blurRadius: 36, offset: Offset(0, 14), spreadRadius: -12)],
            ),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: const BoxDecoration(color: Color(0xFFE6F4EA), shape: BoxShape.circle),
                  child: const Icon(Icons.check_rounded, color: _verdeOk, size: 20),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Venta guardada', style: _estilo(16, peso: FontWeight.w600, apretado: -0.01)),
                    const SizedBox(height: 2),
                    Text('${formatearARS(420000)} · efectivo', style: _estilo(13, color: p.secundario, apretado: 0)),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
      _centrado(
        480,
        _pieza(
          entrada: _de(_pr(t, 8.3, 0.45)),
          salida: sale,
          child: Text('Todo se pone al día cuando vuelve.', style: _estilo(14, color: p.secundario, apretado: 0)),
        ),
      ),
    ];
  }

  // 4 · Contar el stock con la cámara (sobre el círculo oscuro; el visor y el código los dibuja el pintor de adelante).
  List<Widget> _escaner() {
    if (t < 9.1 || t > 11.4) return const [];
    final sale = _ac(_pr(t, 10.9, 0.3));
    return [
      _centrado(16, _titular(const ['Contás el stock', 'con la *cámara.*'], 38, inicio: 9.35, fin: 10.9, color: Colors.white)),
      Positioned(
        left: 20,
        width: 350,
        top: 400,
        child: _pieza(
          entrada: _em(_pr(t, 10.25, 0.5)),
          salida: sale,
          sube: 40,
          child: Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(color: p.fondo, borderRadius: BorderRadius.circular(24)),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Yerba 1 kg', style: _estilo(18, peso: FontWeight.w600, apretado: -0.02)),
                      const SizedBox(height: 4),
                      Text('Había 12 en el sistema', style: _estilo(13, color: p.secundario, apretado: 0)),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Contaste', style: _estilo(12, color: p.secundario, apretado: 0)),
                    Text('14', style: _estilo(34, peso: FontWeight.w700, apretado: -0.03)),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    ];
  }

  // 5 · El logo crece desde el punto verde que llegó volando.
  List<Widget> _final() {
    if (t < 11.6) return const [];
    final crece = _em(_pr(t, 12.0, 0.5));
    return [
      if (crece > 0)
        Positioned(
          left: _origenLogo.dx,
          top: _origenLogo.dy,
          child: Transform.scale(
            scale: crece,
            alignment: Alignment(centroPuntoMarca.dx * 2 - 1, centroPuntoMarca.dy * 2 - 1),
            child: MarcaNodoSur(tamanio: _ladoLogo, conPunto: false, opacidadTexto: _de(_pr(t, 12.3, 0.4))),
          ),
        ),
      _centrado(282, _titular(const ['Todo listo', 'para *empezar.*'], 44, inicio: 12.25, fin: 99, dur: 0.5)),
      _centrado(
        400,
        _pieza(
          entrada: _de(_pr(t, 12.6, 0.45)),
          child: Text('Configuremos este celular: son dos pasos.', style: _estilo(15, color: p.secundario, apretado: 0)),
        ),
      ),
    ];
  }
}

// ---------------------------------------------------------------------------------------------------------------------
// Pintores

/// El círculo oscuro que se abre desde la venta guardada y se cierra en el punto verde del logo. Se pinta más allá de
/// la escena, hasta cubrir la pantalla entera.
class _PintorFondo extends CustomPainter {
  _PintorFondo({required this.t, required this.p});

  final double t;
  final _Paleta p;

  @override
  void paint(Canvas canvas, Size size) {
    if (t < 8.8) return;
    final abre = _em(_pr(t, 8.8, 0.9));
    final cierra = _em(_pr(t, 11.0, 0.7));
    final r = 1600 * abre * (1 - cierra);
    if (r <= 0) return;
    final centro = Offset(195, _lerp(440, 300, cierra));
    canvas.drawCircle(centro, r, Paint()..color = p.revelado);
  }

  @override
  bool shouldRepaint(_PintorFondo viejo) => viejo.t != t || viejo.p.revelado != p.revelado;
}

/// Lo que viaja entre escenas: las barras que se vuelven puntos y el punto verde (tilde, wifi, logo); más el wifi, el
/// visor del escáner y el código de barras.
class _PintorFrente extends CustomPainter {
  _PintorFrente({required this.t, required this.p});

  final double t;
  final _Paleta p;

  @override
  void paint(Canvas canvas, Size size) {
    _barrasYPunto(canvas);
    _tilde(canvas);
    _wifi(canvas);
    _visor(canvas);
    _puntoFinal(canvas);
  }

  void _pastilla(Canvas canvas, Offset centro, double w, double h, Color color) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromCenter(center: centro, width: w, height: h), Radius.circular(math.min(w, h) / 2)),
      Paint()..color = color,
    );
  }

  // Barras de proveedores → tres puntos que saltan → uno verde que espera el conteo, crece hasta el tilde y se achica
  // hasta ser el punto del wifi.
  void _barrasYPunto(Canvas canvas) {
    if (t < 2.8 || t > 9.2) return;
    for (var i = 0; i < 3; i++) {
      final largo = _largoBarra[i];
      final crece = _de(_pr(t, 2.8 + i * 0.12, 0.8));
      var w = largo * crece;
      var h = 10.0;
      var cx = 40 + w / 2;
      var cy = _yBarra[i];
      var color = _colorBarra[i];
      var alfa = 1.0;
      final recoge = _em(_pr(t, 4.05, 0.55));
      if (recoge > 0) {
        w = _lerp(largo, 10, recoge);
        cx = _lerp(40 + largo / 2, [175.0, 195.0, 215.0][i], recoge);
        cy = _lerp(_yBarra[i], 300, recoge);
      }
      cy -= 18 * math.sin(math.pi * _pr(t, 4.6 + i * 0.08, 0.35));
      final junta = _em(_pr(t, 4.95, 0.45));
      if (i != 1) {
        if (junta >= 1) continue;
        cx = _lerp(cx, 195, junta);
        alfa = 1 - junta;
      } else {
        color = Color.lerp(color, verdeMarca, junta)!;
        cy = _lerp(cy, 380, junta);
        final pulso = t > 5.4 && t < 6.2 ? 1 + 0.14 * math.sin((t - 5.4) * 5) : 1.0;
        if (junta > 0) {
          w = 10 * pulso;
          h = w;
        }
        final tilde = _em(_pr(t, 6.2, 0.4));
        final achica = _em(_pr(t, 6.75, 0.5));
        if (tilde > 0) {
          w = h = _lerp(10, 64, tilde) * (1 - achica) + 12 * achica;
          color = Color.lerp(verdeMarca, _verdeOk, tilde)!;
        }
        if (achica > 0) {
          cy = _lerp(380, 330, achica);
          color = Color.lerp(_verdeOk, p.tinta, achica)!;
        }
        alfa = 1 - _ac(_pr(t, 8.8, 0.3));
      }
      if (alfa <= 0) continue;
      _pastilla(canvas, Offset(cx, cy), w, h, color.withValues(alpha: alfa));
    }
  }

  void _tilde(Canvas canvas) {
    final k = _sm(_pr(t, 6.35, 0.3)) * (1 - _pr(t, 6.7, 0.15));
    if (k <= 0) return;
    final camino = Path()
      ..moveTo(181, 381)
      ..lineTo(191, 391)
      ..lineTo(211, 369);
    _trazo(canvas, camino, k, Paint()
      ..color = Colors.white
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke);
  }

  void _wifi(Canvas canvas) {
    if (t < 7.1 || t > 9.4) return;
    final borra = _sm(_pr(t, 8.8, 0.3));
    final gris = _sm(_pr(t, 7.8, 0.3));
    const centro = Offset(195, 330);
    for (var i = 0; i < 3; i++) {
      final k = _de(_pr(t, 7.2 + i * 0.12, 0.45)) * (1 - borra);
      if (k <= 0) continue;
      final r = [30.0, 56.0, 82.0][i];
      final camino = Path()..addArc(Rect.fromCircle(center: centro, radius: r), -math.pi * 3 / 4, math.pi / 2);
      _trazo(canvas, camino, k, Paint()
        ..color = Color.lerp(p.tinta, const Color(0xFFC3C8D1), gris)!
        ..strokeWidth = 8
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke);
    }
    final tacha = _sm(_pr(t, 7.9, 0.3)) * (1 - borra);
    if (tacha > 0) {
      _trazo(canvas, Path()..moveTo(132, 236)..lineTo(258, 344), tacha, Paint()
        ..color = const Color(0xFFEA4335)
        ..strokeWidth = 8
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke);
    }
  }

  // Esquinas del visor, un código de barras y la línea que lo recorre.
  void _visor(Canvas canvas) {
    if (t < 9.4 || t > 11.3) return;
    final sale = _ac(_pr(t, 10.9, 0.3));
    final entra = _em(_pr(t, 9.5, 0.5));
    final alfa = entra * (1 - sale);
    if (alfa <= 0) return;
    const centro = Offset(195, 265);
    final lado = 190 * _lerp(1.15, 1, entra);
    final r = Rect.fromCenter(center: centro, width: lado, height: lado);
    final esquina = Paint()
      ..color = Colors.white.withValues(alpha: alfa)
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    const l = 34.0;
    for (final (o, dx, dy) in [(r.topLeft, 1.0, 1.0), (r.topRight, -1.0, 1.0), (r.bottomLeft, 1.0, -1.0), (r.bottomRight, -1.0, -1.0)]) {
      canvas.drawPath(Path()..moveTo(o.dx, o.dy + dy * l)..lineTo(o.dx, o.dy)..lineTo(o.dx + dx * l, o.dy), esquina);
    }
    final codigo = _de(_pr(t, 9.6, 0.5)) * (1 - sale);
    if (codigo > 0) {
      // Anchos fijos para que el código se vea igual siempre.
      const anchos = [3, 1, 2, 1, 3, 2, 1, 1, 3, 1, 2, 2, 1, 3, 1, 1, 2, 3, 1, 2, 1, 1, 3, 2];
      final total = anchos.fold<int>(0, (a, b) => a + b) + anchos.length;
      final unidad = 140 / total;
      var x = 125.0;
      final barra = Paint()..color = Colors.white.withValues(alpha: 0.92 * codigo);
      for (final a in anchos) {
        canvas.drawRect(Rect.fromLTWH(x, 220, a * unidad, 90), barra);
        x += (a + 1) * unidad;
      }
    }
    final barre = _pr(t, 9.8, 0.6);
    if (barre > 0 && barre < 1) {
      final y = _lerp(185, 345, _sm(barre));
      final brillo = math.sin(math.pi * barre) * (1 - sale);
      canvas.drawLine(
        Offset(110, y),
        Offset(280, y),
        Paint()
          ..color = verdeMarca.withValues(alpha: brillo)
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round,
      );
      canvas.drawLine(
        Offset(110, y),
        Offset(280, y),
        Paint()
          ..color = verdeMarca.withValues(alpha: 0.5 * brillo)
          ..strokeWidth = 10
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
      );
    }
  }

  // El círculo oscuro se cierra en un punto verde, que vuela hasta su lugar en el logo y ahí se vuelve blanco.
  void _puntoFinal(Canvas canvas) {
    final aparece = _em(_pr(t, 11.45, 0.3));
    if (aparece <= 0) return;
    final vuela = _em(_pr(t, 11.7, 0.5));
    const desde = Offset(195, 300);
    const control = Offset(250, 250);
    final hasta = _puntoLogo;
    final x = (1 - vuela) * (1 - vuela) * desde.dx + 2 * (1 - vuela) * vuela * control.dx + vuela * vuela * hasta.dx;
    final y = (1 - vuela) * (1 - vuela) * desde.dy + 2 * (1 - vuela) * vuela * control.dy + vuela * vuela * hasta.dy;
    final lado = diametroPuntoMarca * _ladoLogo * aparece;
    // Vuela verde (el "todo bien" de la escena) y al llegar queda blanco, como el punto del logo.
    canvas.drawCircle(Offset(x, y), lado / 2, Paint()..color = Color.lerp(verdeMarca, colorPuntoMarca, vuela)!);
  }

  void _trazo(Canvas canvas, Path camino, double fraccion, Paint pincel) {
    for (final m in camino.computeMetrics()) {
      canvas.drawPath(m.extractPath(0, m.length * fraccion), pincel);
    }
  }

  @override
  bool shouldRepaint(_PintorFrente viejo) => viejo.t != t || viejo.p.tinta != p.tinta;
}
