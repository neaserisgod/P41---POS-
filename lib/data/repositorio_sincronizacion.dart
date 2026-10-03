// Motor de sincronización fila por fila entre dos bases SQLite
// independientes (la de escritorio y la que va a tener la companion
// Android) — fase 2 del rediseño que empezó la migración v29→v30 (ver su
// comentario completo en `database.dart`).
//
// Trabaja en SQL crudo, no con las clases Dart que genera drift por tabla, a
// propósito: las tablas sincronizables no tienen nada en común del lado
// Dart (cada una es un tipo distinto, con su propio `Companion`), pero SÍ
// tienen la misma forma del lado SQL (`global_id`, y `actualizado_en` en las
// que se editan) — una sola función sirve para todas en vez de escribir el
// mismo upsert una vez por tabla (Regla 3). La misma función sirve tanto para que
// el servidor reciba filas del celular como para que el celular reciba
// filas de la PC: sincronizar es simétrico, no le importa quién le manda a
// quién.
//
// Nunca sincroniza `productos.stock`/`stock_gramos` como el resto de las
// columnas de esa fila (perdería ventas hechas en paralelo en los dos
// dispositivos si gana "la última que sincronizó") — `movimientos_de_stock`
// viaja como cualquier otro log (dedupeado por `global_id`, nunca se pisa),
// y cada movimiento REALMENTE NUEVO que aparece ahí mueve el stock local con
// su delta (`lib/domain/stock.dart::DeltaStock`, fase 4 del rediseño,
// 2026-09-17) — ver `_aplicarDeltaDeMovimientoStock` más abajo.

import 'dart:collection';
import 'dart:convert';

import 'package:drift/drift.dart';

import '../domain/stock.dart';
import 'database.dart';

/// Las tablas que participan de la sincronización y si comparan
/// `actualizado_en` para decidir quién gana un conflicto (`true`) o son un
/// log de solo-inserción que nunca se pisa, dedupeado por `global_id` nada
/// más (`false` — Regla 6: un movimiento ya escrito no se edita).
///
/// En el orden en que hay que aplicarlas: las que otras tablas referencian
/// por clave foránea (`PRAGMA foreign_keys = ON`, `database.dart`) van
/// primero, para que un `INSERT` no falle por apuntar a una fila que todavía
/// no llegó. `usuarios` entró en la migración v31→v32 (El dueño, 2026-09-18) —
/// va primero porque `ventas`/`sesiones_de_caja`/etc. la referencian por
/// `usuario_id`.
const Map<String, bool> tablasSincronizables = {
  'usuarios': true,
  'categorias': true,
  'proveedores': true,
  'clientes': true,
  'productos': true,
  'configuracion_negocio_tabla': true,
  'medios_de_pago': true,
  'sesiones_de_caja': true,
  'ventas': true,
  'lineas_de_venta': true,
  'pagos': true,
  'movimientos_de_stock': false,
  'movimientos_de_caja': false,
  'arqueos_intermedios': false,
  'historial_de_precios': false,
  'pendientes': true,
};

bool _tablaValida(String tabla) {
  if (!tablasSincronizables.containsKey(tabla)) {
    throw ArgumentError('Tabla no sincronizable: $tabla');
  }
  return tablasSincronizables[tabla]!;
}

/// Columnas que son clave foránea local a OTRA tabla sincronizada, por
/// tabla. El `id` que guardan es autoincrement de SQLite — solo tiene
/// sentido en la base que lo generó, nunca en la del otro dispositivo
/// (El dueño, 2026-09-18: "revisa que hay 2 bruno" llevó a encontrar esto —
/// una venta con `sesion_caja_id=25` de la PC, que tiene 25 sesiones
/// históricas, no encuentra nada en una companion recién instalada que
/// solo recibió 6). [cambiosDesde] manda, además del `id` crudo (que se
/// ignora al aplicar), el `global_id` de la fila referenciada — así
/// [_aplicarUnaFila] resuelve el id LOCAL correcto en la base que recibe,
/// sea cual sea. No incluye columnas que referencian tablas NO
/// sincronizadas (`medio_pago_id`, `caja_id`, `gasto_fijo_id`): esas son un
/// catálogo fijo, sembrado igual en los dos dispositivos, así que su `id`
/// ya coincide por convención sin necesidad de traducirlo.
const Map<String, Map<String, String>> _referenciasCruzadas = {
  'productos': {'categoria_id': 'categorias', 'proveedor_id': 'proveedores'},
  'configuracion_negocio_tabla': {'producto_vuelto_id': 'productos'},
  'sesiones_de_caja': {'usuario_abrio_id': 'usuarios', 'usuario_cerro_id': 'usuarios'},
  'ventas': {
    'sesion_caja_id': 'sesiones_de_caja',
    'cliente_id': 'clientes',
    'usuario_id': 'usuarios',
    'editada_por_id': 'usuarios',
    'anulada_por_id': 'usuarios',
  },
  'lineas_de_venta': {
    'venta_id': 'ventas',
    'producto_id': 'productos',
    'proveedor_id_foto': 'proveedores',
  },
  'pagos': {'venta_id': 'ventas'},
  'movimientos_de_stock': {
    'producto_id': 'productos',
    'venta_id': 'ventas',
    'usuario_id': 'usuarios',
  },
  'movimientos_de_caja': {
    'sesion_caja_id': 'sesiones_de_caja',
    'venta_id': 'ventas',
    'proveedor_id': 'proveedores',
    'usuario_id': 'usuarios',
  },
  'arqueos_intermedios': {'sesion_caja_id': 'sesiones_de_caja', 'usuario_id': 'usuarios'},
  'historial_de_precios': {'producto_id': 'productos', 'usuario_id': 'usuarios'},
  'pendientes': {'cliente_id': 'clientes', 'venta_id': 'ventas', 'usuario_id': 'usuarios'},
};

/// Nombre de la columna extra (no es una columna real de [tabla], se
/// descarta antes de aplicar — ver [_resolverReferencias]) que lleva el
/// `global_id` de la fila referenciada por la clave foránea [columna].
String _claveGlobalDe(String columna) => '${columna}_gid';

/// `actualizado_en` en las tablas que se editan, `id` (autoincrement,
/// monotónico con el orden de inserción) en los logs que nunca se editan —
/// las dos sirven igual de bien como "qué es nuevo desde la última vez" y
/// las dos son enteros, así que el que llama no necesita saber cuál es cuál.
String _columnaCursor(String tabla) =>
    tablasSincronizables[tabla]! ? 'actualizado_en' : 'id';

/// Filas de [tabla] nuevas o cambiadas desde el cursor [desde] (0 la primera
/// vez: "traeme todo lo que tiene identidad de sincronización"). Devuelve
/// columnas SQL crudas (snake_case, enteros para fechas y booleanos — mismo
/// formato en el que drift ya guarda todo) listas para mandar tal cual por
/// JSON: no hay traducción de nombres, así que [aplicarCambios] del otro
/// lado las puede volver a escribir sin reinterpretar nada.
/// `>=`, no `>`, a propósito: `actualizado_en` guarda segundos enteros, así
/// que dos filas editadas dentro del mismo segundo real comparten cursor —
/// con `>` estricto, la segunda de esas dos quedaría "vieja" para siempre
/// apenas el cursor avanza a ese valor, sin volver a aparecer en ningún pull
/// futuro (bug real, encontrado escribiendo el test de esta función). El
/// costo es volver a traer la fila del borde una vez de más en cada pull —
/// inofensivo, [aplicarCambios] la descarta sola por no ser "más nueva" que
/// lo que ya hay (o, en un log, por `global_id` ya visto).
Future<List<Map<String, dynamic>>> cambiosDesde(
  AppDatabase db, {
  required String tabla,
  required int desde,
}) async {
  _tablaValida(tabla);
  final columnaCursor = _columnaCursor(tabla);
  final referencias = _referenciasCruzadas[tabla];
  final columnasExtra = referencias == null
      ? ''
      : referencias.keys
          .map((c) => ', ${c}_ref.global_id AS ${_claveGlobalDe(c)}')
          .join();
  final joins = referencias == null
      ? ''
      : referencias.entries
          .map((e) => ' LEFT JOIN ${e.value} AS ${e.key}_ref ON ${e.key}_ref.id = $tabla.${e.key}')
          .join();
  final filas = await db
      .customSelect(
        'SELECT $tabla.*$columnasExtra FROM $tabla$joins '
        'WHERE $tabla.global_id IS NOT NULL AND COALESCE($tabla.$columnaCursor, 0) >= ? '
        'ORDER BY $tabla.$columnaCursor ASC',
        variables: [Variable.withInt(desde)],
      )
      .get();
  return [for (final fila in filas) fila.data];
}

/// La fila de [tabla] con ese [globalId], con la misma forma que las que
/// devuelve [cambiosDesde] (incluye las columnas `*_gid`), o null si no
/// existe. La usa la sync por la nube para saber cómo quedó una fila DESPUÉS
/// de aplicarla, y así no volver a subirla como si fuera un cambio propio.
Future<Map<String, dynamic>?> filaLocalPorGlobalId(
  AppDatabase db, {
  required String tabla,
  required String globalId,
}) async {
  _tablaValida(tabla);
  final referencias = _referenciasCruzadas[tabla];
  final columnasExtra = referencias == null
      ? ''
      : referencias.keys
          .map((c) => ', ${c}_ref.global_id AS ${_claveGlobalDe(c)}')
          .join();
  final joins = referencias == null
      ? ''
      : referencias.entries
          .map((e) => ' LEFT JOIN ${e.value} AS ${e.key}_ref ON ${e.key}_ref.id = $tabla.${e.key}')
          .join();
  final fila = await db
      .customSelect(
        'SELECT $tabla.*$columnasExtra FROM $tabla$joins WHERE $tabla.global_id = ?',
        variables: [Variable.withString(globalId)],
      )
      .getSingleOrNull();
  return fila?.data;
}

/// El cursor más alto entre [filas] (lo que devolvió [cambiosDesde]) para
/// [tabla] — lo que el que pidió el pull tiene que guardar como su próximo
/// `desde`. 0 si [filas] está vacía (no avanza el cursor).
int cursorMaximo(String tabla, List<Map<String, dynamic>> filas) {
  if (filas.isEmpty) return 0;
  return filas.map((f) => valorCursorDe(tabla, f)).reduce((a, b) => a > b ? a : b);
}

/// Qué subir de verdad de lo que devolvió [cambiosDesde], y con qué cursor y
/// "borde" quedarse para la próxima vuelta.
///
/// Bug real (2026-09-26, cuota del plan gratis de Supabase agotada: 25 GB de
/// egress y 8,7 millones de mensajes de Realtime en seis días, con el
/// contador `rev` del servidor en 20,7 millones para una base de ~2.000
/// filas): el `>=` de [cambiosDesde] (necesario, ver su comentario) hacía
/// que cada tick volviera a subir las filas del borde — como mínimo una por
/// tabla, y la tabla ENTERA en `proveedores`/`usuarios`, que tienen todas
/// sus filas en `actualizado_en = 0` (época 0 a propósito, v30→v31) y por
/// eso su cursor de push no pasaba nunca de 0. Cada upsert repetido pisaba
/// `rev` en el servidor y disparaba Realtime, y Realtime dispara un tick
/// nuevo (`sincronizacion_supabase.dart`) — que volvía a subir lo mismo: un
/// ping-pong sin fin, ya no acotado por los 20s del timer, ni siquiera con
/// un solo dispositivo conectado (su propio eco lo despertaba).
///
/// El arreglo mantiene el `>=` (no se pierde una fila editada en el mismo
/// segundo que otra) pero recuerda qué filas del borde ya subió y con qué
/// contenido: [borde] es `global_id → huella` de las filas que quedaron
/// exactamente en [cursor]. Una fila en el cursor con la misma huella ya
/// está arriba y se saltea; si cambió (una segunda edición dentro del mismo
/// segundo), la huella no coincide y se sube igual.
({List<Map<String, dynamic>> aSubir, int cursor, Map<String, String> borde}) filtrarYaSubidas(
  String tabla, {
  required List<Map<String, dynamic>> filas,
  required int cursor,
  required Map<String, String> borde,
}) {
  final aSubir = [
    for (final f in filas)
      if (!(valorCursorDe(tabla, f) == cursor && borde[f['global_id']] == huellaDeFila(f))) f,
  ];
  if (aSubir.isEmpty) return (aSubir: aSubir, cursor: cursor, borde: borde);

  final nuevoCursor = cursorMaximo(tabla, filas) > cursor ? cursorMaximo(tabla, filas) : cursor;
  // De TODAS las filas (no solo las que se suben): las que se saltearon por
  // estar ya arriba siguen siendo parte del borde si el cursor no se movió.
  final nuevoBorde = {
    for (final f in filas)
      if (valorCursorDe(tabla, f) == nuevoCursor) f['global_id'] as String: huellaDeFila(f),
  };
  return (aSubir: aSubir, cursor: nuevoCursor, borde: nuevoBorde);
}

/// Representación estable del contenido de una fila (claves ordenadas) —
/// para saber si una fila del borde cambió desde la última subida.
String huellaDeFila(Map<String, dynamic> fila) => jsonEncode(SplayTreeMap<String, dynamic>.of(fila));

/// El valor de cursor de una fila de [cambiosDesde] (`actualizado_en` o
/// `id`, según [tabla]) — null cuenta como 0, igual que el `COALESCE` de la
/// consulta.
int valorCursorDe(String tabla, Map<String, dynamic> fila) =>
    (fila[_columnaCursor(tabla)] as num?)?.toInt() ?? 0;

Variable _variableDesde(Object? v) {
  if (v == null) return const Variable<Object>(null);
  if (v is int) return Variable.withInt(v);
  if (v is double) return Variable.withReal(v);
  if (v is String) return Variable.withString(v);
  throw ArgumentError('Tipo no soportado en sincronización: ${v.runtimeType}');
}

/// Columnas que [aplicarCambios] nunca escribe en un `UPDATE` de `productos`
/// — `stock`/`stock_gramos` no son "el último valor que ganó", son un
/// contador que dos dispositivos pueden mover en paralelo (Regla 8: vender
/// nunca bloquea, ni siquiera sin red). Sincronizarlos como cualquier otra
/// columna perdería la venta que no alcanzó a verse — por eso viajan en la
/// fila de todos modos (útil para el alta de un producto nuevo, donde no hay
/// nada que preservar) pero se ignoran al actualizar uno que ya existe: el
/// número de verdad lo arma [_aplicarDeltaDeMovimientoStock] fila por fila,
/// a partir del log de `movimientos_de_stock` (`lib/domain/stock.dart`).
const _columnasStockDeProductos = {'stock', 'stock_gramos'};

/// Cuando [fila] es un movimiento de stock recién insertado (no uno que ya
/// existía, ver [aplicarCambios]), aplica su delta al `productos` local
/// correspondiente — mismo mecanismo que ya prueba
/// `lib/domain/stock_test.dart`, acá conectado de verdad al pipeline de
/// sync. Se salta sola si el producto todavía no llegó (no debería pasar:
/// `tablasSincronizables` sincroniza `productos` antes que
/// `movimientos_de_stock`), para no tirar todo el pull por una fila fuera
/// de orden.
Future<void> _aplicarDeltaDeMovimientoStock(
  AppDatabase db,
  Map<String, dynamic> fila,
) async {
  final productoId = (fila['producto_id'] as num?)?.toInt();
  if (productoId == null) return;

  final stockAnterior = (fila['stock_anterior'] as num?)?.toInt();
  final stockPosterior = (fila['stock_posterior'] as num?)?.toInt();
  if (stockAnterior != null && stockPosterior != null) {
    final delta = DeltaStock(anterior: stockAnterior, posterior: stockPosterior).delta;
    await db.customUpdate(
      'UPDATE productos SET stock = stock + ? WHERE id = ?',
      variables: [Variable.withInt(delta), Variable.withInt(productoId)],
    );
  }

  final gramosAnterior = (fila['gramos_anterior'] as num?)?.toInt();
  final gramosPosterior = (fila['gramos_posterior'] as num?)?.toInt();
  if (gramosAnterior != null && gramosPosterior != null) {
    final delta = DeltaStock(anterior: gramosAnterior, posterior: gramosPosterior).delta;
    await db.customUpdate(
      'UPDATE productos SET stock_gramos = COALESCE(stock_gramos, 0) + ? WHERE id = ?',
      variables: [Variable.withInt(delta), Variable.withInt(productoId)],
    );
  }
}

/// Aplica [filas] (mismo formato crudo que devuelve [cambiosDesde]) a
/// [tabla] en [db]: upsert por `global_id`, nunca por `id` (el `id` numérico
/// es autoincrement y solo tiene sentido dentro de su propia base — la
/// identidad entre dispositivos es siempre `global_id`). Al insertar una
/// fila nueva, se omite su columna `id` de origen para que SQLite le asigne
/// el que le toque en esta base.
///
/// En las tablas que comparan `actualizado_en`, una fila entrante más vieja
/// que la que ya está se descarta (gana el cambio más reciente, decisión de
/// El dueño) — salvo `stock`/`stock_gramos` de `productos`, que nunca se pisan
/// así (ver [_columnasStockDeProductos]). En los logs de solo-inserción, una
/// fila cuyo `global_id` ya existe simplemente se ignora — son inmutables,
/// no hay "más nueva" que aplicar, y volver a insertarla duplicaría el
/// movimiento; una recién insertada en `movimientos_de_stock`, en cambio,
/// es un movimiento real que nadie vio todavía en esta base, y mueve el
/// stock de verdad ([_aplicarDeltaDeMovimientoStock]).
/// Devuelve las filas de [filas] que NO se pudieron aplicar todavía — nunca
/// lanza por una fila puntual (El dueño, 2026-09-18: "no veo productos... ni
/// suelto, ni leche" — un producto cuya categoría/proveedor todavía no
/// había llegado a esta base bloqueaba, con `PRAGMA foreign_keys = ON`, no
/// solo esa fila sino TODAS las que venían después de ella en el mismo
/// lote, aunque no tuvieran nada que ver). Cada fila se intenta por
/// separado; una que falla (típicamente por eso, una referencia que
/// todavía no existe localmente) se separa y el resto sigue su curso. El
/// llamador decide qué hacer con las devueltas — en
/// `sincronizacion_supabase.dart`, reintentarlas en el próximo tick.
///
/// Con [ordenDeLlegada] (la sync por la nube) no se compara `actualizado_en`:
/// quien aplica va recibiendo los lotes en el orden en que llegaron al
/// servidor y el último pisa a los anteriores (El dueño, 2026-10-01: "porque
/// no usamos el horario del server y que se vea qué elemento llegó último").
/// Así el reloj de cada dispositivo deja de decidir quién gana un conflicto.
Future<List<Map<String, dynamic>>> aplicarCambios(
  AppDatabase db, {
  required String tabla,
  required List<Map<String, dynamic>> filas,
  bool ordenDeLlegada = false,
}) async {
  final comparaActualizado = _tablaValida(tabla);
  final noAplicadas = <Map<String, dynamic>>[];

  for (final fila in filas) {
    try {
      await _aplicarUnaFila(
        db,
        tabla: tabla,
        fila: fila,
        comparaActualizado: comparaActualizado,
        ordenDeLlegada: ordenDeLlegada,
      );
    } catch (e) {
      // ignore: avoid_print
      print('aplicarCambios: $tabla (global_id=${fila['global_id']}) no se pudo aplicar: $e');
      noAplicadas.add(fila);
    }
  }
  return noAplicadas;
}

/// Traduce las claves foráneas de [fila] (ver [_referenciasCruzadas]) del
/// id local del dispositivo que la mandó al id local de ESTA base — busca
/// cada fila referenciada por su `global_id` (que viaja aparte, ver
/// [_claveGlobalDe]) y la reemplaza por el id que tiene acá. Devuelve una
/// copia de [fila] sin las columnas auxiliares `*_gid` (nunca son columnas
/// reales de [tabla]).
///
/// Si la fila referenciada todavía no llegó a esta base, lanza — mismo
/// mecanismo que ya usa [aplicarCambios] para lo que falla por
/// `PRAGMA foreign_keys = ON`: la fila entera vuelve a la cola para
/// reintentarse en el próximo ciclo, en vez de aplicarse con un id
/// equivocado o inexistente.
///
/// Una fila vieja, de antes de que existiera la sincronización, puede no
/// tener `global_id` en la referenciada (columna `_gid` en null) aunque su
/// id crudo no sea null — ahí no hay nada que resolver, se deja el id tal
/// cual llegó (mejor esfuerzo, caso raro y ya tolerado desde siempre).
Future<Map<String, dynamic>> _resolverReferencias(
  AppDatabase db, {
  required String tabla,
  required Map<String, dynamic> fila,
}) async {
  final referencias = _referenciasCruzadas[tabla];
  if (referencias == null) return fila;

  final resuelta = Map<String, dynamic>.of(fila);
  for (final entry in referencias.entries) {
    final columna = entry.key;
    final tablaReferenciada = entry.value;
    final globalIdReferenciado = resuelta.remove(_claveGlobalDe(columna)) as String?;
    if (resuelta[columna] == null) continue; // FK nulo, nada que resolver
    if (globalIdReferenciado == null) continue; // fila vieja sin global_id
    final referenciada = await db
        .customSelect(
          'SELECT id FROM $tablaReferenciada WHERE global_id = ?',
          variables: [Variable.withString(globalIdReferenciado)],
        )
        .getSingleOrNull();
    if (referenciada == null) {
      throw StateError(
        '$tabla.$columna: todavía no llegó la fila referenciada de '
        '$tablaReferenciada (global_id=$globalIdReferenciado)',
      );
    }
    resuelta[columna] = referenciada.data['id'];
  }
  return resuelta;
}

/// Los nombres de columna de cada tabla, leídos una vez del propio esquema. Un SQL armado con claves que vienen de un JSON
/// remoto solo puede usar columnas que existan de verdad en esta base: una clave rara (o de una versión más nueva del
/// esquema) se descarta en vez de inyectarse en el `INSERT`/`UPDATE`.
final _columnasPorTabla = <String, Set<String>>{};

Future<Map<String, dynamic>> _soloColumnasDeLaTabla(
  AppDatabase db,
  String tabla,
  Map<String, dynamic> fila,
) async {
  var validas = _columnasPorTabla[tabla];
  if (validas == null) {
    final info = await db.customSelect('PRAGMA table_info($tabla)').get();
    validas = {for (final c in info) c.data['name'] as String};
    _columnasPorTabla[tabla] = validas;
  }
  return {
    for (final e in fila.entries)
      if (validas.contains(e.key)) e.key: e.value,
  };
}

Future<void> _aplicarUnaFila(
  AppDatabase db, {
  required String tabla,
  required Map<String, dynamic> fila,
  required bool comparaActualizado,
  required bool ordenDeLlegada,
}) async {
  final globalId = fila['global_id'] as String?;
  if (globalId == null) return; // no debería pasar, pero no explota

  fila = await _resolverReferencias(db, tabla: tabla, fila: fila);
  fila = await _soloColumnasDeLaTabla(db, tabla, fila);

  var existente = await db
      .customSelect(
        'SELECT * FROM $tabla WHERE global_id = ?',
        variables: [Variable.withString(globalId)],
      )
      .getSingleOrNull();

  // La configuración del negocio es UNA fila por equipo (todo el código la lee con `getSingle`). Si cada equipo creó
  // la suya con otro `global_id` (la PC al instalarse, el celular en "Configurá tu negocio", o versiones viejas con un
  // id al azar), la que llega es la misma fila: se compara contra la local en vez de insertar una segunda, que dejaba
  // al equipo sin poder leer su configuración (revisión 2026-10-03).
  if (existente == null && tabla == 'configuracion_negocio_tabla') {
    existente = await db.customSelect('SELECT * FROM $tabla ORDER BY id LIMIT 1').getSingleOrNull();
  }

  if (existente == null) {
    final columnas = fila.keys.where((k) => k != 'id').toList();
    await db.customInsert(
      'INSERT INTO $tabla (${columnas.join(', ')}) '
      'VALUES (${List.filled(columnas.length, '?').join(', ')})',
      variables: [for (final c in columnas) _variableDesde(fila[c])],
    );
    if (tabla == 'movimientos_de_stock') {
      await _aplicarDeltaDeMovimientoStock(db, fila);
    }
    return;
  }

  if (!comparaActualizado) return; // log inmutable: ya existe, no se toca

  // Una caja ya CERRADA no vuelve a ABIERTA por una fila vieja que llega tarde
  // (un dispositivo que estuvo sin conexión y sube su copia de la apertura):
  // con "gana el último en llegar" ese eco borraba el cierre entero (contado,
  // esperado y diferencia en null) y la caja aparecía abierta otra vez.
  // Reabrir de verdad (Regla 6) sí pasa: `reabrirSesion` pisa `actualizado_en`
  // con una hora posterior a la del cierre.
  if (tabla == 'sesiones_de_caja' &&
      existente.data['estado'] == 'CERRADA' &&
      fila['estado'] == 'ABIERTA' &&
      ((fila['actualizado_en'] as num?)?.toInt() ?? 0) < ((existente.data['actualizado_en'] as num?)?.toInt() ?? 0)) {
    return;
  }

  if (!ordenDeLlegada) {
    final actualizadoLocal = (existente.data['actualizado_en'] as num?)?.toInt() ?? 0;
    final actualizadoEntrante = (fila['actualizado_en'] as num?)?.toInt() ?? 0;
    if (actualizadoEntrante <= actualizadoLocal) return; // gana el más nuevo
  }

  final columnasExcluidas = {
    'id',
    'global_id',
    if (tabla == 'productos') ..._columnasStockDeProductos,
  };
  final columnas = fila.keys.where((k) => !columnasExcluidas.contains(k)).toList();
  // Por `id` local: la fila de configuración puede tener otro `global_id` que la que llega (ver arriba).
  await db.customUpdate(
    'UPDATE $tabla SET ${columnas.map((c) => '$c = ?').join(', ')} '
    'WHERE id = ?',
    variables: [
      for (final c in columnas) _variableDesde(fila[c]),
      Variable.withInt((existente.data['id'] as num).toInt()),
    ],
  );
}
