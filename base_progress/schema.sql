-- =====================================================================
-- Esquema: Sistema de Gamificación de Hábitos (Puntajes - Libro maestro)
-- Motor: SQLite
-- =====================================================================
PRAGMA foreign_keys = ON;

-- Tabla de niveles y el XP necesario para alcanzar cada uno
CREATE TABLE IF NOT EXISTS niveles (
    nivel           INTEGER PRIMARY KEY,
    xp_necesario    REAL NOT NULL
);

-- Categorías de hábitos (Habitos Fundamentales, Alimentación, Ejercicio,
-- Disiplina Digital, Responsabilidad, Academicas, Ingles, Programación,
-- Matemáticas)
CREATE TABLE IF NOT EXISTS categorias (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    nombre          TEXT NOT NULL UNIQUE
);

-- Hábitos/tareas positivas dentro de cada categoría
CREATE TABLE IF NOT EXISTS habitos (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    categoria_id    INTEGER NOT NULL REFERENCES categorias(id) ON DELETE CASCADE,
    nombre          TEXT NOT NULL,
    condiciones     TEXT,
    limite_por_dia  REAL,
    xp              REAL,
    creditos        REAL,
    integridad      REAL,
    UNIQUE (categoria_id, nombre)
);

-- Penalizaciones. Se conservan tanto el nombre de categoría tal cual
-- aparece en el archivo original ("Ingles - PENALIZACIONES") como el
-- enlace (si existe) a la categoría de hábitos correspondiente.
CREATE TABLE IF NOT EXISTS penalizaciones (
    id                          INTEGER PRIMARY KEY AUTOINCREMENT,
    categoria_id                INTEGER REFERENCES categorias(id) ON DELETE SET NULL,
    nombre_categoria_original   TEXT NOT NULL,
    nombre                      TEXT NOT NULL,
    condiciones                 TEXT,
    limite_por_dia              REAL,
    xp                          REAL,
    creditos                    REAL,
    integridad                  REAL,
    UNIQUE (nombre_categoria_original, nombre)
);

-- Tiendas (Tienda Individual, Tienda de Pareja, ...)
CREATE TABLE IF NOT EXISTS tiendas (
    id      INTEGER PRIMARY KEY AUTOINCREMENT,
    nombre  TEXT NOT NULL UNIQUE
);

CREATE TABLE IF NOT EXISTS articulos_tienda (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    tienda_id       INTEGER NOT NULL REFERENCES tiendas(id) ON DELETE CASCADE,
    nombre          TEXT NOT NULL,
    descripcion     TEXT,
    costo           REAL,
    usos_diarios    REAL,
    UNIQUE (tienda_id, nombre)
);

-- Personas (jugadores del sistema)
CREATE TABLE IF NOT EXISTS personas (
    id      INTEGER PRIMARY KEY AUTOINCREMENT,
    nombre  TEXT NOT NULL UNIQUE
);

-- Perfil general de cada persona (tomado de la primera fila de cada
-- tabla "Perfil", que es la única donde el archivo original registra
-- Créditos y Vida globales).
CREATE TABLE IF NOT EXISTS perfiles (
    id                          INTEGER PRIMARY KEY AUTOINCREMENT,
    persona_id                  INTEGER NOT NULL UNIQUE REFERENCES personas(id) ON DELETE CASCADE,
    creditos_disponibles        REAL,
    vida                        REAL CHECK (vida IS NULL OR vida >= 0),
    xp_total_acumulado          REAL  -- XP total acumulado de la persona (suma del XP de todas sus categorías; venía suelto en el Excel bajo la tabla de perfil)
);

-- La vida tiene tope de 150: si un INSERT o UPDATE la deja por encima,
-- estos triggers la recortan automáticamente a 150 (no rechazan la
-- operación, solo la limitan).
CREATE TRIGGER IF NOT EXISTS trg_perfiles_vida_tope_insert
AFTER INSERT ON perfiles
FOR EACH ROW WHEN NEW.vida > 150
BEGIN
    UPDATE perfiles SET vida = 150 WHERE id = NEW.id;
END;

CREATE TRIGGER IF NOT EXISTS trg_perfiles_vida_tope_update
AFTER UPDATE OF vida ON perfiles
FOR EACH ROW WHEN NEW.vida > 150
BEGIN
    UPDATE perfiles SET vida = 150 WHERE id = NEW.id;
END;

-- Progreso de cada persona por categoría (Nivel y XP por categoría)
CREATE TABLE IF NOT EXISTS progreso_categoria (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    perfil_id       INTEGER NOT NULL REFERENCES perfiles(id) ON DELETE CASCADE,
    etiqueta        TEXT NOT NULL,   -- texto tal cual aparece, p.ej. "Bilingue Lvl."
    categoria_id    INTEGER REFERENCES categorias(id) ON DELETE SET NULL,
    nivel           REAL,
    xp              REAL,
    UNIQUE (perfil_id, etiqueta)
);

-- Bitácora de actividad: para uso de la aplicación en Python que
-- registrará el cumplimiento diario de hábitos y penalizaciones.
CREATE TABLE IF NOT EXISTS registros (
    id                  INTEGER PRIMARY KEY AUTOINCREMENT,
    persona_id          INTEGER NOT NULL REFERENCES personas(id) ON DELETE CASCADE,
    habito_id           INTEGER REFERENCES habitos(id) ON DELETE CASCADE,
    penalizacion_id     INTEGER REFERENCES penalizaciones(id) ON DELETE CASCADE,
    fecha               TEXT NOT NULL,     -- formato ISO 8601 (YYYY-MM-DD)
    veces               INTEGER NOT NULL DEFAULT 1,
    xp_obtenido         REAL,
    creditos_obtenidos  REAL,
    integridad_obtenida REAL,
    nota                TEXT,
    CHECK (
        (habito_id IS NOT NULL AND penalizacion_id IS NULL)
        OR
        (habito_id IS NULL AND penalizacion_id IS NOT NULL)
    )
);

CREATE INDEX IF NOT EXISTS idx_habitos_categoria        ON habitos(categoria_id);
CREATE INDEX IF NOT EXISTS idx_penalizaciones_categoria  ON penalizaciones(categoria_id);
CREATE INDEX IF NOT EXISTS idx_articulos_tienda          ON articulos_tienda(tienda_id);
CREATE INDEX IF NOT EXISTS idx_progreso_perfil           ON progreso_categoria(perfil_id);
CREATE INDEX IF NOT EXISTS idx_registros_persona_fecha   ON registros(persona_id, fecha);

-- =====================================================================
-- Vistas de consulta (pensadas para navegar cómodamente desde
-- DB Browser for SQLite, en la pestaña "Browse Data" o "Execute SQL")
-- =====================================================================

-- Hábitos con el nombre de su categoría ya resuelto
CREATE VIEW IF NOT EXISTS v_habitos AS
SELECT
    h.id,
    c.nombre AS categoria,
    h.nombre AS habito,
    h.condiciones,
    h.limite_por_dia,
    h.xp,
    h.creditos,
    h.integridad
FROM habitos h
JOIN categorias c ON c.id = h.categoria_id;

-- Penalizaciones con el nombre de categoría resuelto cuando existe
-- (si no hay coincidencia, se muestra el nombre original del Excel)
CREATE VIEW IF NOT EXISTS v_penalizaciones AS
SELECT
    p.id,
    COALESCE(c.nombre, p.nombre_categoria_original) AS categoria,
    p.nombre_categoria_original,
    p.nombre AS penalizacion,
    p.condiciones,
    p.limite_por_dia,
    p.xp,
    p.creditos,
    p.integridad
FROM penalizaciones p
LEFT JOIN categorias c ON c.id = p.categoria_id;

-- Artículos de tienda con el nombre de su tienda
CREATE VIEW IF NOT EXISTS v_articulos_tienda AS
SELECT
    a.id,
    t.nombre AS tienda,
    a.nombre AS articulo,
    a.descripcion,
    a.costo,
    a.usos_diarios
FROM articulos_tienda a
JOIN tiendas t ON t.id = a.tienda_id;

-- Perfil general de cada persona
CREATE VIEW IF NOT EXISTS v_perfiles AS
SELECT
    pe.id AS perfil_id,
    pr.nombre AS persona,
    pe.creditos_disponibles,
    pe.vida,
    pe.xp_total_acumulado
FROM perfiles pe
JOIN personas pr ON pr.id = pe.persona_id;

-- Progreso por categoría de cada persona
CREATE VIEW IF NOT EXISTS v_progreso_categoria AS
SELECT
    pr.nombre AS persona,
    pc.etiqueta,
    c.nombre AS categoria,
    pc.nivel,
    pc.xp
FROM progreso_categoria pc
JOIN perfiles pe ON pe.id = pc.perfil_id
JOIN personas pr ON pr.id = pe.persona_id
LEFT JOIN categorias c ON c.id = pc.categoria_id;

-- XP total acumulado (suma de todas las categorías) por persona
CREATE VIEW IF NOT EXISTS v_xp_total_por_persona AS
SELECT
    pr.nombre AS persona,
    SUM(pc.xp) AS xp_total_categorias
FROM progreso_categoria pc
JOIN perfiles pe ON pe.id = pc.perfil_id
JOIN personas pr ON pr.id = pe.persona_id
GROUP BY pr.nombre;

-- Bitácora de actividad ya con nombres legibles en vez de ids
CREATE VIEW IF NOT EXISTS v_registros AS
SELECT
    r.id,
    pr.nombre AS persona,
    r.fecha,
    CASE WHEN r.habito_id IS NOT NULL THEN 'Habito' ELSE 'Penalizacion' END AS tipo,
    COALESCE(h.nombre, p.nombre) AS actividad,
    COALESCE(hc.nombre, pcat.nombre, p.nombre_categoria_original) AS categoria,
    r.veces,
    r.xp_obtenido,
    r.creditos_obtenidos,
    r.integridad_obtenida,
    r.nota
FROM registros r
JOIN personas pr ON pr.id = r.persona_id
LEFT JOIN habitos h ON h.id = r.habito_id
LEFT JOIN categorias hc ON hc.id = h.categoria_id
LEFT JOIN penalizaciones p ON p.id = r.penalizacion_id
LEFT JOIN categorias pcat ON pcat.id = p.categoria_id;
