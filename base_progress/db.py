# Sirve para conectarse a la base de datos progress_together.db desde
# Python. Aquí está la clase Database, con funciones ya hechas para
# consultar hábitos, penalizaciones y artículos, calcular el nivel según
# el XP, y registrar lo que la persona cumplió o no cada día.
#
# Ejemplo de uso:
#   from db import Database
#
#   with Database("progress_together.db") as db:
#       habitos = db.get_habitos(categoria="Ingles")
#       db.registrar_habito(persona="Yael", habito_id=3, fecha="2026-07-16")
#       print(db.resumen_persona("Yael"))
from __future__ import annotations

import sqlite3
from dataclasses import dataclass
from datetime import date
from pathlib import Path
from typing import Optional


class Database:
    """Envoltura sobre sqlite3 con utilidades específicas del dominio."""

    def __init__(self, ruta_bd: str | Path = "gamificacion.db"):
        self.ruta_bd = str(ruta_bd)
        self.conn: Optional[sqlite3.Connection] = None

    # ------------------------------------------------------------------
    # Ciclo de vida de la conexión
    # ------------------------------------------------------------------
    def conectar(self) -> "Database":
        self.conn = sqlite3.connect(self.ruta_bd)
        self.conn.row_factory = sqlite3.Row
        self.conn.execute("PRAGMA foreign_keys = ON;")
        return self

    def cerrar(self) -> None:
        if self.conn is not None:
            self.conn.close()
            self.conn = None

    def __enter__(self) -> "Database":
        return self.conectar()

    def __exit__(self, exc_type, exc_val, exc_tb) -> None:
        self.cerrar()

    def inicializar_esquema(self, ruta_schema: str | Path = "schema.sql") -> None:
        """Crea las tablas a partir de schema.sql (idempotente)."""
        sql = Path(ruta_schema).read_text(encoding="utf-8")
        self.conn.executescript(sql)
        self.conn.commit()

    # ------------------------------------------------------------------
    # Consultas de catálogo
    # ------------------------------------------------------------------
    def get_categorias(self) -> list[sqlite3.Row]:
        return self.conn.execute(
            "SELECT * FROM categorias ORDER BY nombre"
        ).fetchall()

    def get_habitos(self, categoria: Optional[str] = None) -> list[sqlite3.Row]:
        if categoria:
            return self.conn.execute(
                """
                SELECT h.*, c.nombre AS categoria
                FROM habitos h
                JOIN categorias c ON c.id = h.categoria_id
                WHERE c.nombre = ?
                ORDER BY h.id
                """,
                (categoria,),
            ).fetchall()
        return self.conn.execute(
            """
            SELECT h.*, c.nombre AS categoria
            FROM habitos h
            JOIN categorias c ON c.id = h.categoria_id
            ORDER BY c.nombre, h.id
            """
        ).fetchall()

    def get_penalizaciones(self, categoria: Optional[str] = None) -> list[sqlite3.Row]:
        if categoria:
            return self.conn.execute(
                """
                SELECT * FROM penalizaciones
                WHERE nombre_categoria_original LIKE ?
                ORDER BY id
                """,
                (f"{categoria}%",),
            ).fetchall()
        return self.conn.execute(
            "SELECT * FROM penalizaciones ORDER BY nombre_categoria_original, id"
        ).fetchall()

    def get_articulos(self, tienda: Optional[str] = None) -> list[sqlite3.Row]:
        if tienda:
            return self.conn.execute(
                """
                SELECT a.*, t.nombre AS tienda
                FROM articulos_tienda a
                JOIN tiendas t ON t.id = a.tienda_id
                WHERE t.nombre = ?
                ORDER BY a.costo
                """,
                (tienda,),
            ).fetchall()
        return self.conn.execute(
            """
            SELECT a.*, t.nombre AS tienda
            FROM articulos_tienda a
            JOIN tiendas t ON t.id = a.tienda_id
            ORDER BY t.nombre, a.costo
            """
        ).fetchall()

    def nivel_por_xp(self, xp_total: float) -> int:
        """Devuelve el nivel más alto cuyo xp_necesario <= xp_total."""
        row = self.conn.execute(
            """
            SELECT nivel FROM niveles
            WHERE xp_necesario <= ?
            ORDER BY nivel DESC
            LIMIT 1
            """,
            (xp_total,),
        ).fetchone()
        return row["nivel"] if row else 1

    # ------------------------------------------------------------------
    # Personas y perfiles
    # ------------------------------------------------------------------
    def get_persona_id(self, persona: str) -> Optional[int]:
        row = self.conn.execute(
            "SELECT id FROM personas WHERE nombre = ?", (persona,)
        ).fetchone()
        return row["id"] if row else None

    def resumen_persona(self, persona: str) -> Optional[dict]:
        p = self.conn.execute(
            """
            SELECT pe.*, pr.nombre AS persona
            FROM perfiles pe
            JOIN personas pr ON pr.id = pe.persona_id
            WHERE pr.nombre = ?
            """,
            (persona,),
        ).fetchone()
        if p is None:
            return None
        categorias = self.conn.execute(
            """
            SELECT etiqueta, nivel, xp
            FROM progreso_categoria
            WHERE perfil_id = ?
            ORDER BY etiqueta
            """,
            (p["id"],),
        ).fetchall()
        return {"perfil": dict(p), "categorias": [dict(c) for c in categorias]}

    # ------------------------------------------------------------------
    # Registro de actividad diaria
    # ------------------------------------------------------------------
    def registrar_habito(
        self,
        persona: str,
        habito_id: int,
        fecha: Optional[str] = None,
        veces: int = 1,
        nota: Optional[str] = None,
    ) -> int:
        persona_id = self._persona_id_o_falla(persona)
        habito = self.conn.execute(
            "SELECT * FROM habitos WHERE id = ?", (habito_id,)
        ).fetchone()
        if habito is None:
            raise ValueError(f"No existe el hábito con id={habito_id}")

        fecha = fecha or date.today().isoformat()
        xp = (habito["xp"] or 0) * veces
        creditos = (habito["creditos"] or 0) * veces
        integridad = (habito["integridad"] or 0) * veces

        cur = self.conn.execute(
            """
            INSERT INTO registros
                (persona_id, habito_id, fecha, veces,
                 xp_obtenido, creditos_obtenidos, integridad_obtenida, nota)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (persona_id, habito_id, fecha, veces, xp, creditos, integridad, nota),
        )
        self.conn.commit()
        return cur.lastrowid

    def registrar_penalizacion(
        self,
        persona: str,
        penalizacion_id: int,
        fecha: Optional[str] = None,
        veces: int = 1,
        nota: Optional[str] = None,
    ) -> int:
        persona_id = self._persona_id_o_falla(persona)
        pen = self.conn.execute(
            "SELECT * FROM penalizaciones WHERE id = ?", (penalizacion_id,)
        ).fetchone()
        if pen is None:
            raise ValueError(f"No existe la penalización con id={penalizacion_id}")

        fecha = fecha or date.today().isoformat()
        xp = (pen["xp"] or 0) * veces
        creditos = (pen["creditos"] or 0) * veces
        integridad = (pen["integridad"] or 0) * veces

        cur = self.conn.execute(
            """
            INSERT INTO registros
                (persona_id, penalizacion_id, fecha, veces,
                 xp_obtenido, creditos_obtenidos, integridad_obtenida, nota)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (persona_id, penalizacion_id, fecha, veces, xp, creditos, integridad, nota),
        )
        self.conn.commit()
        return cur.lastrowid

    def _persona_id_o_falla(self, persona: str) -> int:
        persona_id = self.get_persona_id(persona)
        if persona_id is None:
            raise ValueError(f"No existe la persona '{persona}'")
        return persona_id


if __name__ == "__main__":
    # Ejemplo rápido de uso
    with Database("gamificacion.db") as db:
        print("Categorías:", [c["nombre"] for c in db.get_categorias()])
        print("Nivel para 500 XP:", db.nivel_por_xp(500))
