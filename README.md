# Nodo Sur POS

Sistema de caja y gestión para comercios chicos (kioscos, almacenes, fiambrerías). App de escritorio en Flutter
para Windows, con una app companion para Android. Cada equipo tiene su base local y se sincronizan por la nube de
Nodo Sur (horsepos.com, repo `neaserisgod/NodoSurPage`) o por el wifi del local. **Para retomar el trabajo, empezá por
[`CONTEXTO.md`](./CONTEXTO.md).** Cada comercio pone su nombre y prende solo los módulos que usa (Configuración → Módulos). Nació para un
almacén de barrio, La Plazoleta (ver [`docs/perfiles/la-plazoleta.md`](./docs/perfiles/la-plazoleta.md)): de ahí
vienen el nombre interno del paquete (`la_plazoleta`) y algunos nombres internos del código.

Este repo está pensado para que alguien que nunca estuvo en las sesiones de
desarrollo (otra persona, otra sesión de Claude Code, Cowork) pueda seguir
trabajando sin tener que preguntar nada. Para eso, la documentación está
repartida en documentos con un dueño claro cada uno — **no hay dos
documentos diciendo cosas distintas sobre lo mismo**; cuando un tema se
toca en más de un lado, uno es la fuente de verdad y el resto apunta ahí.

**Cuenta de Nodo Sur (opcional).** Desde Configuración → Cuenta de Nodo Sur la PC se vincula a una cuenta de Google del
sitio (horsepos.com, en Cloudflare) para guardar copias cifradas de la base y restaurarlas, por ejemplo al reinstalar.
Las copias no incluyen el token de Mercado Pago ni el del celular. El servidor está en otro repositorio; ver
`DECISIONES.md` ("Nube: cuenta de Nodo Sur y copias").

## Mapa de documentación

| Documento | Es la fuente de verdad de... |
|---|---|
| [`CONTEXTO.md`](./CONTEXTO.md) | La puerta de entrada: el sistema completo (PC, celular y sitio), lo hecho hasta hoy, lo que quiere el dueño y cómo trabaja, cómo se publica y qué quedó pendiente. |
| [`CLAUDE.md`](./CLAUDE.md) | Cómo está armado el código: stack, arquitectura de carpetas, convenciones que no se rompen, qué es cada fase del roadmap, el flujo de trabajo (plan antes de código, ambigüedades marcadas, tests primero), la restricción de hardware, y la especificación completa de la pantalla de venta. |
| [`REGLAS-NEGOCIO.md`](./REGLAS-NEGOCIO.md) | El dominio del negocio: qué hace la app y por qué, regla por regla (dinero, cigarrillos, reposición, fiado, retiro, etc.), y qué módulo activa cada una. Si el código contradice esto, el código está mal. |
| [`docs/perfiles/la-plazoleta.md`](./docs/perfiles/la-plazoleta.md) | El comercio de origen: cómo está configurado y qué nombres de archivo no se pueden cambiar. |
| [`ESTADO.md`](./ESTADO.md) | El estado ACTUAL, corto: qué está publicado, métricas, qué existe, qué no se probó en real y qué falta. Se actualiza al cerrar cada sesión. El detalle histórico (hasta 2026-10-03) está en [`docs/ESTADO-ARCHIVO.md`](./docs/ESTADO-ARCHIVO.md). |
| [`docs/PLAN.md`](./docs/PLAN.md) | El plan vigente por fases (0 a 7) y, arriba, "Dónde quedamos": qué está hecho y qué sigue, para retomar con otra cuenta. |
| [`docs/ESTANDARES-GOOGLE.md`](./docs/ESTANDARES-GOOGLE.md) | Estética horsepos/antigravity y estándar de diseño y funcionamiento de Google, medido contra el código. |
| [`docs/REVISION-FRICCIONES.md`](./docs/REVISION-FRICCIONES.md) | Fricciones encontradas pantalla por pantalla (PC y celular). |
| [`DECISIONES.md`](./DECISIONES.md) | El PORQUÉ de decisiones de dominio y de arquitectura que sin el motivo parecen arbitrarias (por qué los cigarrillos quedan fuera de la reposición, por qué el costo es nullable, por qué el redondeo va después del recargo, etc.). |
| [`TRAMPAS.md`](./TRAMPAS.md) | Bugs y comportamientos inesperados ya encontrados y resueltos — para no volver a pisar el mismo palo (orden de `sesionCerradaAnterior`, el hang de `dart:io` en `testWidgets`, etc.). |
| [`DISENO.md`](./DISENO.md) | El sistema de diseño completo: escalas de espaciado y tipografía, colores, el acento único y sus tres usos, reglas de alineación y simetría, y las restricciones visuales por hardware. |

Antes de hacer público el repositorio, `python3 tool/limpiar_datos_personales.py --aplicar` reemplaza los datos
personales del comercio de origen por nombres genéricos (sin `--aplicar` solo muestra qué cambiaría).

Regla general: si vas a agregar algo que ya tiene dueño en esta lista,
agregalo en ese documento — no lo dupliques en otro. Si dos documentos se
contradicen, **vale lo más reciente** (la fecha escrita en el texto, o la del
commit) y lo viejo se corrige en el mismo cambio.

## Cómo correrlo

Requiere el SDK de Flutter con soporte para Windows desktop habilitado
(`flutter config --enable-windows-desktop`).

```powershell
# Instalar dependencias
flutter pub get

# Regenerar código de drift después de tocar un esquema (lib/data/tables/*, database.dart)
dart run build_runner build

# Análisis estático — tiene que dar "No issues found!" (CI lo exige)
flutter analyze

# Toda la suite de tests (~1981 al 2026-10-03), sin los benchmarks de 60.000 ventas
flutter test --exclude-tags bench
# Los benchmarks, aparte
flutter test --tags bench

# Build de desarrollo — se abre con hot reload
flutter run -d windows

# Build de debug sin correr (para probar el binario tal cual)
flutter build windows --debug
# Ejecutable en: build\windows\x64\runner\Debug\la_plazoleta.exe

# Build de producción — el que se instala en la PC del local
flutter build windows --release
# Ejecutable en: build\windows\x64\runner\Release\la_plazoleta.exe
```

### Publicar en la máquina que corre la app (2026-09-14)

`tool\publicar_actualizacion_desktop.ps1` compila en release y copia la
carpeta completa (`.exe` + `.dll` + `data\`, todo lo que hace falta para
que arranque en destino) a `C:\LaPlazoleta\app\` — nunca correr el `.exe`
directo desde `build\windows\x64\runner\Release\` del repo: esa carpeta la
pisa `flutter build`/`flutter clean` en cualquier momento, mala base para
un acceso directo que tiene que seguir andando entre una compilación y la
siguiente.

El mismo script actualiza el acceso directo del escritorio (si ya existe,
apuntándolo a la copia estable) y crea uno en el inicio de Windows —
El dueño, 2026-09-14: "si yo no abro el acceso directo la companion no
funciona" (el servidor embebido que usa el celular solo corre mientras
esta app está abierta, Regla del proyecto, no un bug — pero depender de
acordarse de abrirla a mano sí lo era). Correr:

```powershell
.\tool\publicar_actualizacion_desktop.ps1
```

`-SinAccesoDirecto` salta la parte de accesos directos/inicio de Windows,
por si alguna vez hace falta solo recompilar y copiar.

### Instalador y actualización automática (2026-09-30)

Para distribuir la app hay un instalador de Inno Setup
(`installer/la_plazoleta.iss`) y la app se actualiza sola desde
`horsepos.com`. **No reemplaza** a `publicar_actualizacion_desktop.ps1`, que
sigue sirviendo para la PC de desarrollo (y ahora también sube el build).

```powershell
# Claves de firma de las actualizaciones (UNA vez; la privada queda fuera del repo)
.\tool\generar_claves_actualizacion.ps1

# Instalador en dist\NodoSurPOS-Setup-<version>.exe (imprime el SHA-256)
.\tool\crear_instalador.ps1
.\tool\crear_instalador.ps1 -CertificadoDePrueba   # firma autofirmada, solo para probar

# Subir una versión (sube el build, instala, firma y llama a publicar-release.mjs)
.\tool\publicar_release.ps1 -Notas "..." -Rollout 10
.\tool\publicar_release.ps1 -DryRun                # ensayo: no sube nada
```

Variables de entorno (ninguna va al repo): `SIGN_PFX_PATH`,
`SIGN_PFX_PASSWORD` (o las de Azure Trusted Signing, ver el encabezado de
`crear_instalador.ps1`), `NODOSUR_SCRIPTS`, `RELEASE_TOKEN`. Requiere Inno
Setup 6. Motivos y trampas en `DECISIONES.md` y `TRAMPAS.md`; qué falta hacer
a mano, en `ESTADO.md`.

**Ojo con accesos directos viejos**: en el escritorio y el menú inicio de
esta máquina quedan accesos al sistema anterior (Tauri/Next.js,
`AppData\Local\La Plazoleta Soft\`) — no son esta app, no los toca el
script, y no deberían usarse.

**Revisar los cierres de una base real** (sin tocarla): copiar la base y
correr `$env:BASE_A_REVISAR="ruta\copia.sqlite"; flutter test tool/revisar_cierres_test.dart`
— compara cada cierre guardado contra el mismo cálculo corrido de nuevo,
una cuenta independiente por SQL, la cadena de la lata y los pagos de cada
venta.

La base de datos real vive fuera del repo, en
`C:\Users\el dueño\Documents\la_plazoleta.sqlite` en la máquina de el dueño — no
se versiona ni se copia como parte de un build.
