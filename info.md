# FraSoHome ReturnOps 360: descripción técnica actualizada

## Visión general

Este repositorio despliega una demo RAG empresarial sobre **Microsoft Fabric** para **FraSoHome ReturnOps 360**, un caso ficticio de soporte de devoluciones en un retailer de hogar y decoración.

La solución ayuda a un agente a decidir si debe aprobar una devolución, un reemplazo o una revisión manual combinando:

- Datos operacionales de clientes, pedidos, productos, stock y casos de devolución.
- Políticas internas versionadas como documentos de conocimiento.
- Chunks recuperables con metadatos de negocio.
- Embeddings almacenados como vectores nativos `VECTOR(1536)`.
- Procedimientos SQL para recuperación contextual, búsqueda vectorial y búsqueda híbrida.
- Una **Fabric User Data Function** en Python como backend serverless.
- Una **Fabric App** en React/Vite desplegada con Rayfin.
- Auditoría completa de cada recomendación generada.

La idea principal es que **SQL Database in Microsoft Fabric** actúa como capa de control del RAG: almacena los datos, aplica filtros de negocio, guarda embeddings nativos, calcula similitud vectorial, recupera evidencias, centraliza permisos y deja trazabilidad auditable.

## Arquitectura en ejecución

```text
Usuario / agente de soporte
        │
        ▼
Fabric App / Rayfin / React
        │ POST autenticado con Microsoft Entra
        ▼
Fabric User Data Function: answerReturnCase
        │ conexión administrada por alias
        ▼
SQL Database in Microsoft Fabric
        ├─ fraso.*: datos operacionales
        ├─ rag.Documents: documentos de conocimiento
        ├─ rag.Chunks: fragmentos recuperables
        ├─ rag.ChunkEmbeddings: embeddings nativos VECTOR(1536)
        ├─ rag.usp_get_return_case_context
        ├─ rag.usp_get_candidate_chunks
        ├─ rag.usp_get_hybrid_candidate_chunks
        ├─ rag.usp_get_vector_candidate_chunks
        ├─ rag.usp_get_ann_candidate_chunks
        └─ rag.AnswerAudit
```

## Componentes principales

### 1. SQL Database in Microsoft Fabric

Es el núcleo de datos, recuperación y gobierno. Se crea con:

```powershell
.\scripts\deploy_fabric_sql.ps1
```

La base contiene dos esquemas principales.

### Esquema `fraso`

Modela la operación del retailer:

- `fraso.Customers`: clientes, segmento, ciudad, email y riesgo de devolución.
- `fraso.Products`: catálogo, categoría, subcategoría, si el producto es voluminoso, si es personalizado, garantía y precio.
- `fraso.Orders`: pedidos, fechas, canal, tienda, estado e importe.
- `fraso.OrderLines`: líneas de pedido.
- `fraso.Stock`: stock por ubicación, unidades disponibles y stock de seguridad.
- `fraso.ReturnCases`: casos de devolución, motivo, fotos, resultado deseado y estado.

Este esquema aporta la verdad operacional: quién es el cliente, qué compró, cuándo se entregó, qué stock hay y qué tipo de producto está afectado.

### Esquema `rag`

Modela la parte RAG:

- `rag.Documents`: documentos internos versionados.
- `rag.Chunks`: fragmentos recuperables, con metadatos de canal, categoría, país, vigencia y keywords.
- `rag.ChunkEmbeddings`: embeddings nativos `VECTOR(1536)` asociados a cada chunk, con proveedor, modelo, dimensiones, hash de origen y fecha de vectorización.
- `rag.VectorizationRuns`: trazabilidad de ejecuciones de vectorización.
- `rag.AnswerAudit`: auditoría de preguntas, recuperación, recomendación, evidencias y modelo usado.

La separación permite cruzar datos transaccionales y conocimiento documental desde SQL.

## Procedimientos SQL

### `rag.usp_get_return_case_context`

Recupera el contexto completo de un caso de devolución. Une cliente, pedido, producto, caso y stock.

Calcula elementos útiles para la decisión:

- Días desde la entrega.
- Segmento del cliente.
- Riesgo de devolución.
- Si el producto es voluminoso.
- Si el producto es personalizado.
- Unidades reemplazables por encima del stock de seguridad.
- Ubicaciones donde hay stock.

### `rag.usp_get_candidate_chunks`

Recupera los chunks candidatos para un caso y una pregunta.

Es la recuperación lexical explicable y queda como fallback. Usa filtros y scoring por:

- País.
- Canal.
- Categoría de producto.
- Vigencia de la política.
- Señales de daño, embalaje, fotos, reemplazo, stock, cliente Gold/Platinum y producto voluminoso.

Esto permite comparar la parte puramente lexical con la recuperación híbrida y mantener una ruta de contingencia si la UDF no puede ejecutar el procedimiento vectorial.

### `rag.usp_get_vector_candidate_chunks`

Ejecuta búsqueda vectorial exacta sobre `rag.ChunkEmbeddings.EmbeddingVector`.

Recibe el embedding de la pregunta como JSON, lo convierte a `vector(1536)` y calcula:

```sql
VECTOR_DISTANCE('cosine', @questionVector, ce.EmbeddingVector)
```

Devuelve `VectorDistance`, `VectorScore` y los metadatos del chunk.

### `rag.usp_get_ann_candidate_chunks`

Ejecuta búsqueda aproximada con `VECTOR_SEARCH`.

Usa la sintaxis moderna de Fabric Database / SQL:

```sql
SELECT TOP (@topN) WITH APPROXIMATE
FROM VECTOR_SEARCH(...)
ORDER BY distance;
```

Si existe un índice DiskANN compatible, SQL puede usarlo. Si no existe, la consulta sigue pudiendo usar kNN exacto según las capacidades disponibles.

### `rag.usp_get_hybrid_candidate_chunks`

Es la ruta principal de recuperación RAG.

Combina:

- `LexicalScore`: señales de negocio y coincidencia textual.
- `VectorScore`: similitud semántica calculada con `VECTOR_DISTANCE`.
- `HybridScore`: mezcla ponderada de ambas señales.

Por defecto:

```text
HybridScore = 0.55 * LexicalNormalized + 0.45 * VectorScore
```

Los pesos se controlan con:

```dotenv
RAG_HYBRID_LEXICAL_WEIGHT="0.55"
RAG_HYBRID_VECTOR_WEIGHT="0.45"
```

### `rag.usp_insert_answer_audit`

Guarda la respuesta generada en `rag.AnswerAudit`, incluyendo:

- Caso.
- Pregunta.
- Recomendación.
- Confianza.
- JSON completo de respuesta.
- Documentos citados.
- Traza de chunks recuperados.
- Nombre del modelo o motor de decisión.

### `rag.usp_get_last_answers`

Permite consultar las últimas respuestas auditadas.

## Datos semilla iniciales

El despliegue base carga datos mediante:

- `database/sql/03_seed_operational_data.sql`
- `database/sql/04_seed_documents_chunks.sql`

El caso principal es `RET-2026-004219`: una cliente Gold solicita reemplazo urgente de un sofá modular comprado online porque llegó con una pata dañada, embalaje golpeado y fotos adjuntas.

Ese caso activa políticas como:

- `POL-DMG-002`: daños en transporte.
- `POL-MUE-003`: productos voluminosos.
- `POL-VIP-004`: priorización de clientes Gold/Platinum.
- `SOP-RET-005`: procedimiento interno de aprobación de reemplazos.

## Nuevo flujo realista de ingesta Markdown

Además de los datos semilla SQL, el repo incluye ahora un flujo más cercano a producción para crear documentos, chunks y embeddings a partir de políticas Markdown.

```text
docs/policies/*.md
        │
        ▼
tools/ingest_policy_markdown.py
        ├─ lee frontmatter
        ├─ extrae contenido Markdown
        ├─ genera chunks por secciones y párrafos
        ├─ infiere keywords de apoyo
        ├─ calcula embeddings deterministas de demo o Azure OpenAI
        └─ genera SQL idempotente
        │
        ▼
scripts/ingest_policy_markdown.ps1
        ├─ aplica el SQL con sqlcmd
        └─ ejecuta smoke test de recuperación
        │
        ▼
rag.Documents / rag.Chunks / rag.ChunkEmbeddings(VECTOR(1536))
```

### Documentos Markdown de ejemplo

Se han añadido dos políticas en `docs/policies`:

- `MD-POL-DMG-010-danos-transporte-ecommerce.md`
- `MD-POL-VIP-011-prioridad-clientes-gold.md`

Cada documento usa frontmatter para definir metadatos:

```yaml
---
document_code: MD-POL-DMG-010
document_title: Política Markdown de daños de transporte en ecommerce
document_type: policy
valid_from: 2026-01-01
security_level: internal
source_uri: docs/policies/MD-POL-DMG-010-danos-transporte-ecommerce.md
product_category: furniture
channel: ecommerce
country_code: ES
keywords: daño transporte evidencia fotográfica embalaje reemplazo mueble voluminoso stock seguridad ecommerce
---
```

Estos campos se transforman en columnas de `rag.Documents` y `rag.Chunks`.

### Generación de chunks

El script `tools/ingest_policy_markdown.py` no usa chunks escritos a mano. Lee el Markdown y genera fragmentos de forma automática:

1. Separa el frontmatter del contenido.
2. Divide el documento por encabezados Markdown.
3. Si una sección es larga, la divide por párrafos.
4. Limpia sintaxis Markdown para obtener texto plano.
5. Conserva metadatos de categoría, canal, país y vigencia.
6. Asigna `ChunkNumber` secuencial por documento.

Con los dos documentos actuales, el generador produce:

- 2 documentos.
- 7 chunks.

### Generación de embeddings vectoriales

Los embeddings se calculan de forma local y determinista con `tools/seed_embeddings.py`.

El modelo de demo se llama:

```text
demo-hash-embedding-v1
```

El algoritmo:

1. Tokeniza el texto del chunk.
2. Calcula `sha256` por token.
3. Usa el hash para elegir una dimensión del vector.
4. Suma `+1` o `-1` según el hash.
5. Normaliza el vector.
6. Emite el vector como array JSON.
7. El SQL generado lo convierte y guarda como `VECTOR(1536)` en `rag.ChunkEmbeddings.EmbeddingVector`.

Por defecto genera vectores de 1536 dimensiones, compatibles con modelos habituales como `text-embedding-ada-002` o `text-embedding-3-small`:

```dotenv
RAG_EMBEDDING_DIMENSIONS="1536"
```

Este embedding no pretende sustituir a Azure OpenAI o Foundry embeddings. Sirve para que la demo tenga un flujo completo reproducible sin depender de servicios externos, pero usando el mismo tipo nativo `vector` que usaría una solución real.

En producción, el mismo generador puede usar Azure OpenAI configurando:

```dotenv
RAG_EMBEDDING_PROVIDER="azure-openai"
RAG_USE_EXTERNAL_MODELS="true"
AZURE_OPENAI_ENDPOINT="https://<recurso>.openai.azure.com"
AZURE_OPENAI_API_KEY="<api-key>"
AZURE_OPENAI_EMBEDDING_DEPLOYMENT="<deployment-name>"
AZURE_OPENAI_API_VERSION="2024-10-21"
```

### Inserción en SQL

El generador produce SQL idempotente en:

```text
database/generated/ingest_policy_markdown.sql
```

Ese archivo queda ignorado por Git porque es un artefacto generado.

La inserción hace:

1. `MERGE` en `rag.Documents` por `DocumentCode`.
2. Borrado de embeddings anteriores del documento.
3. Borrado de chunks anteriores del documento.
4. Inserción de chunks nuevos en `rag.Chunks`.
5. Inserción de embeddings nuevos en `rag.ChunkEmbeddings.EmbeddingVector`.
6. Registro de la ejecución en `rag.VectorizationRuns`.

El flujo se ejecuta con:

```powershell
.\scripts\ingest_policy_markdown.ps1
```

El script reutiliza la misma configuración de `.env` que el resto del repo:

- `FABRIC_SQL_SERVER`
- `FABRIC_SQL_DATABASE_NAME`
- `FABRIC_SQL_AUTH_MODE`
- `FAB_SPN_CLIENT_ID`
- `FAB_SPN_CLIENT_SECRET`
- `RAG_POLICY_MARKDOWN_DIR`
- `RAG_EMBEDDING_DIMENSIONS`

## Validación del nuevo flujo

El smoke test específico está en:

```text
database/sql/98_smoke_test_markdown_ingestion.sql
```

Lanza una pregunta similar a la demo:

```text
El cliente Gold quiere devolver un sofá modular comprado online hace 34 días.
Indica que llegó con una pata dañada, conserva fotos del embalaje y solicita reemplazo urgente.
¿Debemos aprobar devolución, reemplazo o revisión manual?
```

Después ejecuta `rag.usp_get_candidate_chunks` sobre el caso `RET-2026-004219` y falla si no aparecen:

- `MD-POL-DMG-010`
- `MD-POL-VIP-011`

La respuesta esperada sigue siendo:

```text
Aprobar reemplazo prioritario condicionado a validación visual
```

La razón es que los documentos Markdown contienen señales relevantes para el scoring:

- Daño de transporte.
- Evidencia fotográfica.
- Embalaje golpeado.
- Producto voluminoso.
- Stock de reemplazo.
- Cliente Gold.
- Priorización condicionada a revisión visual.

## Recuperación y búsqueda híbrida

### Recuperación actual

La ruta principal de la UDF usa `rag.usp_get_hybrid_candidate_chunks`.

Ese procedimiento realiza una recuperación híbrida en SQL:

1. Lee el contexto del caso (`ReturnCaseId`).
2. Extrae categoría, canal, fecha de apertura, motivo, fotos y si el producto es voluminoso.
3. Filtra chunks por:
   - Vigencia.
   - País.
   - Canal.
   - Categoría de producto.
4. Calcula un `Score` lexical por señales de negocio:
   - Daño.
   - Embalaje.
   - Fotos/evidencia.
   - Reemplazo.
   - Producto voluminoso.
   - Cliente Gold/Platinum.
   - Stock.
5. Convierte el embedding de la pregunta a `vector(1536)`.
6. Calcula distancia coseno con `VECTOR_DISTANCE`.
7. Combina score lexical normalizado y score vectorial.
8. Devuelve los chunks ordenados por `HybridScore`.

`rag.usp_get_candidate_chunks` se conserva como fallback lexical explicable.

### Flujo híbrido real

Para búsquedas híbridas se ha añadido:

```text
database/sql/07_create_hybrid_search.sql
tools/render_hybrid_search_sql.py
scripts/hybrid_search.ps1
```

El procedimiento nuevo es:

```sql
rag.usp_get_hybrid_candidate_chunks
```

Este procedimiento combina dos señales:

- `LexicalScore`: el mismo scoring contextual de negocio que usa la recuperación actual.
- `VectorScore`: similitud coseno entre el embedding de la pregunta y `rag.ChunkEmbeddings.EmbeddingVector`.

Después calcula:

```text
HybridScore = lexicalWeight * LexicalNormalized + vectorWeight * VectorScore
```

Por defecto:

```dotenv
RAG_HYBRID_LEXICAL_WEIGHT="0.55"
RAG_HYBRID_VECTOR_WEIGHT="0.45"
```

El flujo de ejecución es:

```text
Pregunta del usuario
        │
        ▼
tools/render_hybrid_search_sql.py
        ├─ genera embedding de la pregunta
        └─ renderiza SQL de consulta
        │
        ▼
rag.usp_get_hybrid_candidate_chunks
        ├─ calcula score lexical
        ├─ convierte la pregunta a vector(1536)
        ├─ calcula VECTOR_DISTANCE('cosine', ...)
        └─ devuelve ranking híbrido
```

Para probarlo:

```powershell
.\scripts\hybrid_search.ps1
```

Ese script aplica el procedimiento híbrido, genera `database/generated/hybrid_search_query.sql` y ejecuta la búsqueda contra SQL Database.

### Búsqueda vectorial exacta y aproximada

El repo incluye también:

```sql
rag.usp_get_vector_candidate_chunks
rag.usp_get_ann_candidate_chunks
```

`rag.usp_get_vector_candidate_chunks` usa `VECTOR_DISTANCE`, que calcula distancia exacta.

`rag.usp_get_ann_candidate_chunks` usa `VECTOR_SEARCH` con:

```sql
SELECT TOP (@topN) WITH APPROXIMATE
```

Para acelerar la búsqueda aproximada cuando haya suficiente volumen, se añade:

```text
database/sql/08_create_vector_indexes.sql
```

Ese script crea un índice DiskANN sobre `rag.ChunkEmbeddings.EmbeddingVector` cuando hay al menos 100 vectores no nulos. La semilla de demo tiene menos registros, así que el script omite el índice hasta que el corpus crezca.

### Embeddings de demo y embeddings reales

Por defecto, el repo usa embeddings deterministas de demo:

```dotenv
RAG_EMBEDDING_PROVIDER="demo"
RAG_EMBEDDING_MODEL="demo-hash-embedding-v1"
```

Para usar embeddings reales con Azure OpenAI:

```dotenv
RAG_EMBEDDING_PROVIDER="azure-openai"
RAG_USE_EXTERNAL_MODELS="true"
AZURE_OPENAI_ENDPOINT="https://<recurso>.openai.azure.com"
AZURE_OPENAI_API_KEY="<api-key>"
AZURE_OPENAI_EMBEDDING_DEPLOYMENT="<deployment-name>"
AZURE_OPENAI_API_VERSION="2024-10-21"
```

La condición importante es que la ingesta Markdown y la búsqueda usen el mismo proveedor y deployment. Si los documentos se embeben con un modelo y la pregunta con otro, la similitud vectorial deja de ser fiable.

## User Data Function en Fabric

La UDF se despliega como item de Fabric desde:

```text
fabric/items/FrasoHome_RAG_UDF.UserDataFunction
```

El código principal está en:

```text
fabric/items/FrasoHome_RAG_UDF.UserDataFunction/function_app.py
```

Expone tres funciones:

- `healthCheck`: endpoint de salud.
- `getReturnCaseContext`: recupera contexto operacional desde SQL.
- `answerReturnCase`: orquesta la demo RAG.

`answerReturnCase` hace:

1. Valida `returnCaseId`, `question` y `maxChunks`.
2. Ejecuta `rag.usp_get_return_case_context`.
3. Genera un embedding determinista de la pregunta con `demo-hash-embedding-v1`.
4. Ejecuta `rag.usp_get_hybrid_candidate_chunks`.
5. Si la búsqueda híbrida falla, cae a `rag.usp_get_candidate_chunks`.
6. Aplica reglas Python deterministas.
7. Construye recomendación, motivos, acciones y evidencias.
8. Guarda auditoría con `rag.usp_insert_answer_audit`.
9. Devuelve JSON al frontend.

El motor declarado es:

```text
frasohome-rag-rulebased-v1
```

La demo no llama a un LLM externo para redactar la respuesta. La decisión sigue siendo determinista, explicable y auditable, pero la recuperación ya combina señales lexicales y semánticas sobre vectores nativos en SQL.

## Conexión administrada entre UDF y SQL

La UDF no contiene connection strings ni secretos.

La conexión se define en `definition.json.template` con:

- `artifactType`: `SqlDbNative`
- `workspaceId`: workspace Fabric
- `artifactId`: item id de la SQL Database
- `alias`: `frasohomesql` por defecto

En Python se consume así:

```python
@udf.connection(argName="sqlDB", alias=SQL_ALIAS)
```

Esto deja la conexión bajo gobierno de Fabric, no del frontend ni del código cliente.

## Fabric App / Rayfin / React

El frontend vive en:

```text
app/frasohome-returnops-app
```

Es una aplicación React/Vite publicada como Fabric App mediante Rayfin.

Funcionalmente ofrece:

- Selector de `ReturnCaseId`.
- Caja de pregunta RAG.
- Invocación de la UDF.
- Visualización de recomendación.
- Porcentaje de confianza.
- Indicador de revisión manual.
- Motivos.
- Acciones sugeridas.
- Evidencias recuperadas.
- `auditId` y modelo usado.

La app se despliega con:

```powershell
.\scripts\deploy_app.ps1
```

Rayfin aloja la experiencia web. La lógica de negocio vive en la UDF y en SQL.

## Autenticación

### Usuario final

El frontend usa `@azure/msal-browser`.

Flujo:

1. El usuario inicia sesión con Microsoft Entra.
2. MSAL obtiene un token.
3. La app llama al endpoint público de la UDF.
4. Envía el token en `Authorization: Bearer`.
5. La UDF responde con JSON.

Scope usado:

```text
https://analysis.windows.net/powerbi/api/.default
```

Variables relevantes:

- `VITE_UDF_FUNCTION_URL`
- `VITE_ENTRA_CLIENT_ID`
- `VITE_ENTRA_TENANT_ID`

### Despliegue y automatización

Los scripts soportan:

- Service principal con secreto.
- Service principal con certificado.
- Federated credential.
- Managed identity.
- `ActiveDirectoryDefault`.

Para SQL, `sqlcmd` usa el modo definido por:

```dotenv
FABRIC_SQL_AUTH_MODE="service-principal"
```

Rayfin puede requerir sesión interactiva para `rayfin up`, aunque SQL y UDF se automaticen con service principal o managed identity.

## Seguridad y gobierno

La solución incorpora varias decisiones de gobierno:

- No se exponen secretos en el frontend.
- La UDF conecta a SQL con alias administrado por Fabric.
- SQL tiene un rol específico: `frasohome_rag_executor`.
- El rol recibe `SELECT` sobre `fraso` y `rag`, y `EXECUTE` sobre `rag`.
- Las respuestas se auditan en `rag.AnswerAudit`.
- Cada respuesta incluye evidencias citadas.
- La recuperación filtra por país, canal, categoría y vigencia.
- La respuesta incluye `confidence` y `requiresManualReview`.
- El nuevo pipeline conserva metadatos desde Markdown hasta SQL.
- Los embeddings quedan versionados con `EmbeddingProvider`, `EmbeddingModel`, `EmbeddingDimensions`, `SourceTextHash` y `VectorizedAt`.

## Camino SQL-native opcional para embeddings

El script:

```text
database/sql/90_optional_sql_native_embeddings.sql
```

prepara un camino opcional para generar chunks y embeddings dentro de SQL Database in Fabric.

Este camino requiere configurar previamente un `EXTERNAL MODEL` de embeddings, por ejemplo contra Azure OpenAI. Una vez creado el modelo, el script añade procedimientos para:

- Dividir documentos con `AI_GENERATE_CHUNKS`.
- Generar embeddings con `AI_GENERATE_EMBEDDINGS`.
- Guardarlos en `rag.ChunkEmbeddings.EmbeddingVector` como `VECTOR(1536)`.
- Registrar ejecuciones en `rag.VectorizationRuns`.

El flujo principal no depende de credenciales externas porque usa embeddings deterministas generados en Python, pero la estructura de tablas y procedimientos ya usa las mismas capacidades vectoriales nativas que el camino SQL-native.

## Scripts principales

- `scripts/bootstrap.ps1`: instala prerequisitos locales.
- `scripts/deploy_fabric_sql.ps1`: crea la SQL Database en Fabric.
- `scripts/apply_sql.ps1`: aplica DDL, datos semilla, procedimientos y seguridad.
- `scripts/ingest_policy_markdown.ps1`: ingiere políticas Markdown, chunks y embeddings.
- `scripts/smoke_test_sql.ps1`: ejecuta el smoke test SQL base.
- `scripts/publish_udf.ps1`: publica la User Data Function.
- `scripts/deploy_app.ps1`: compila y despliega la Fabric App.
- `scripts/deploy_all.ps1`: orquesta el despliegue general.

## Flujo recomendado de demo

1. Crear la SQL Database:

```powershell
.\scripts\deploy_fabric_sql.ps1
```

2. Aplicar modelo base, datos y procedimientos:

```powershell
.\scripts\apply_sql.ps1
```

3. Ingerir políticas Markdown reales:

```powershell
.\scripts\ingest_policy_markdown.ps1
```

4. Publicar la UDF:

```powershell
.\scripts\publish_udf.ps1
```

5. Desplegar la app:

```powershell
.\scripts\deploy_app.ps1
```

6. Probar la pregunta demo desde la app o desde consola:

```powershell
python tools/call_udf.py --auth-mode service-principal --return-case-id "RET-2026-004219"
```

## Resumen para presentación

La solución muestra una arquitectura RAG gobernada sobre Microsoft Fabric:

- **Fabric App** proporciona la experiencia de usuario.
- **Microsoft Entra** autentica al usuario y protege la invocación.
- **User Data Function** actúa como backend serverless.
- **SQL Database in Fabric** centraliza datos operacionales, conocimiento, vectores, recuperación, permisos y auditoría.
- **Markdown policies** representan una fuente realista de conocimiento empresarial.
- **Chunking automático** convierte documentos en fragmentos recuperables.
- **Embeddings versionados** se almacenan como `VECTOR(1536)`.
- **Procedimientos SQL** mantienen filtros, scoring, `VECTOR_DISTANCE`, `VECTOR_SEARCH` y trazabilidad cerca de los datos.
- **Rayfin** publica la app estática dentro de Fabric.

El valor técnico de la demo está en que el RAG no se plantea como una caja negra: las políticas se versionan, los chunks se generan, los embeddings se almacenan como vectores nativos, la recuperación híbrida es inspeccionable, las evidencias se citan y cada recomendación queda auditada.
