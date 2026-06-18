# Seguridad, gobierno y notas de preview

## Seguridad

- No exponer claves ni secretos en el frontend.
- Usar Microsoft Entra para autenticar llamadas a endpoints UDF.
- Usar conexiones Fabric administradas para que la UDF acceda a SQL sin connection strings en código.
- Aplicar permisos SQL por rol y `GRANT EXECUTE` a procedimientos en lugar de acceso directo a tablas.
- Registrar auditoría de preguntas, chunks recuperados, recomendación y modelo usado.

## Gobierno RAG

Buenas prácticas incluidas:

- Citas obligatorias.
- Filtros por vigencia, país, canal y categoría.
- Respuesta con `confidence` y `requiresManualReview`.
- Auditoría en `rag.AnswerAudit`.
- Recuperación híbrida con filtros de negocio, score lexical y `VECTOR_DISTANCE`.
- Fallback lexical cuando una ejecución de UDF no puede usar la ruta vectorial.

## Funcionalidades preview

Fabric Apps, User Data Functions, vector indexes y funciones AI SQL-native pueden estar en preview o tener disponibilidad regional/tenant. Por eso el repositorio incluye:

- Camino principal vector-first con `VECTOR(1536)` y embeddings deterministas generados por Python.
- Script opcional `database/sql/90_optional_sql_native_embeddings.sql` para tenants con `AI_GENERATE_CHUNKS`, `AI_GENERATE_EMBEDDINGS` y un `EXTERNAL MODEL` configurado.
- Pasos manuales claros para URL pública UDF y app registration.
