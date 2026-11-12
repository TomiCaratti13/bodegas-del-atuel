"""Esquemas Pydantic de entrada. No contienen logica de calculo de negocio."""

from __future__ import annotations

from datetime import date
from decimal import Decimal
from typing import Literal

from pydantic import BaseModel, Field


class ComposicionItem(BaseModel):
    id_cepa: int
    porcentaje: Decimal


class VinoCreate(BaseModel):
    nombre: str = Field(..., min_length=1, max_length=100)
    tipo: Literal["tinto", "blanco", "rosado", "espumante"]
    anada: int
    volumen_ml: int
    graduacion: Decimal
    precio: Decimal
    cuit_bodega: str
    composiciones: list[ComposicionItem] = Field(..., min_length=1)
    maridajes_ids: list[int] = Field(default_factory=list)


class VinoUpdate(BaseModel):
    nombre: str | None = None
    tipo: Literal["tinto", "blanco", "rosado", "espumante"] | None = None
    anada: int | None = None
    volumen_ml: int | None = None
    graduacion: Decimal | None = None
    precio: Decimal | None = None


class PermisoExportacionCreate(BaseModel):
    codigo: str
    fecha_emision: date
    fecha_vencimiento: date


class ClienteCreate(BaseModel):
    tipo_cliente: Literal["socio", "distribuidor", "exportador"]
    nombre_razon_social: str
    tipo_documento: str
    nro_documento: str
    direccion: str
    id_localidad: int
    zona_cobertura: str | None = None
    nro_habilitacion: str | None = None
    pais_destino_principal: str | None = None
    permisos: list[PermisoExportacionCreate] = Field(default_factory=list)


class ClienteUpdate(BaseModel):
    nombre_razon_social: str | None = None
    direccion: str | None = None
    id_localidad: int | None = None
    zona_cobertura: str | None = None
    pais_destino_principal: str | None = None


class RenglonVentaCreate(BaseModel):
    cod_vino: int
    cantidad: int


class ComprobanteCreate(BaseModel):
    id_cliente: int
    id_sala: int
    renglones: list[RenglonVentaCreate] = Field(..., min_length=1)


class TransferenciaCreate(BaseModel):
    id_sala: int


class RenglonDocumentoCreate(BaseModel):
    cod_vino: int
    cantidad: int


class IngresoCreate(BaseModel):
    cod_transportista: int
    cuit_bodega: str
