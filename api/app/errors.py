"""Mapeo centralizado de SQLSTATE de PostgreSQL a respuestas HTTP."""

from __future__ import annotations

from fastapi import Request
from fastapi.responses import JSONResponse
import psycopg

SQLSTATE_MAP: dict[str, tuple[int, str]] = {
    "23505": (409, "Conflicto de unicidad: el registro ya existe."),
    "23503": (409, "Conflicto referencial: registro relacionado inexistente o con movimientos asociados."),
    "23514": (422, "Valor fuera de las restricciones permitidas (CHECK)."),
    "23502": (422, "Falta un dato obligatorio (NOT NULL)."),
    "P0001": (409, "Regla de negocio rechazada por la base de datos."),
    "22P02": (400, "Formato invalido para el tipo de dato esperado."),
    "40001": (503, "Conflicto de serializacion; reintente la operacion."),
    "40P01": (503, "Deadlock detectado en la base; reintente la operacion."),
}


async def pg_error_handler(_request: Request, exc: psycopg.Error) -> JSONResponse:
    sqlstate = getattr(exc, "sqlstate", None) or "UNKNOWN"
    status_code, default_msg = SQLSTATE_MAP.get(sqlstate, (500, "Error interno de base de datos."))
    diag = getattr(exc, "diag", None)
    primary = getattr(diag, "message_primary", None) if diag else None
    detail_db = getattr(diag, "message_detail", None) if diag else None
    constraint = getattr(diag, "constraint_name", None) if diag else None

    # Para P0001 (RAISE EXCEPTION de triggers/procedimientos) devolvemos el mensaje exacto de la regla
    message = primary if (sqlstate == "P0001" and primary) else (primary or default_msg)

    headers = {"Retry-After": "1"} if sqlstate in ("40001", "40P01") else None
    return JSONResponse(
        status_code=status_code,
        headers=headers,
        content={
            "error": message,
            "sqlstate": sqlstate,
            "constraint": constraint,
            "detail": detail_db,
        },
    )


class NotFoundError(Exception):
    def __init__(self, message: str) -> None:
        self.message = message
        super().__init__(message)


async def not_found_handler(_request: Request, exc: NotFoundError) -> JSONResponse:
    return JSONResponse(status_code=404, content={"error": exc.message})
