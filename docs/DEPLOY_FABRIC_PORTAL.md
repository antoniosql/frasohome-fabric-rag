# Despliegue completo desde el portal de Microsoft Fabric

Esta guia describe como desplegar la demo **FraSoHome ReturnOps 360** usando el portal de Microsoft Fabric como superficie principal de creacion, configuracion y validacion. El repositorio sigue siendo la fuente de los artefactos: scripts SQL, codigo de User Data Functions y frontend React/Fabric App.

> Objetivo: crear una SQL Database in Microsoft Fabric, cargar datos y procedimientos RAG, publicar una User Data Function con endpoint publico y desplegar la Fabric App que consume ese endpoint.

## Arquitectura que se despliega

```text
Fabric App / Rayfin / React
        |
        | POST con token Microsoft Entra
        v
Fabric User Data Function: answerReturnCase
        |
        | Conexion Fabric administrada por alias: frasohomesql
        v
SQL Database in Microsoft Fabric: FrasoHomeRagDB
```

Componentes:

- `SQL Database in Microsoft Fabric`: tablas operacionales `fraso.*`, tablas RAG `rag.*`, procedimientos y auditoria.
- `User Data Functions`: backend Python serverless con `healthCheck`, `getReturnCaseContext` y `answerReturnCase`.
- `Fabric App`: frontend React/Vite publicado con Rayfin y administrado desde Fabric.
- `Microsoft Entra ID`: app registration publica para que el frontend obtenga token y llame a la UDF.

## Requisitos previos

Antes de empezar, confirma:

- Tenant con Microsoft Fabric habilitado.
- Workspace asignado a una capacidad Fabric.
- Permisos de `Contributor` o superior en el workspace.
- SQL database, User Data Functions y Fabric Apps habilitados en el tenant.
- Permisos para crear o administrar una app registration en Microsoft Entra.
- Repositorio clonado en una maquina con PowerShell, Node.js 20 o superior y Python 3.10 o superior.

Referencias oficiales:

- Crear SQL Database in Microsoft Fabric: <https://learn.microsoft.com/en-us/fabric/database/sql/tutorial-create-database>
- Crear User Data Functions desde el portal: <https://learn.microsoft.com/en-us/fabric/data-engineering/user-data-functions/create-user-data-functions-portal>
- Overview de User Data Functions: <https://learn.microsoft.com/en-us/fabric/data-engineering/user-data-functions/user-data-functions-overview>

## 1. Preparar el workspace en Fabric

1. Entra en <https://app.fabric.microsoft.com>.
2. Abre o crea el workspace de la demo, por ejemplo `FrasoHome Fabric RAG Demo`.
3. Comprueba que el workspace esta asignado a una capacidad Fabric:
   - Abre **Workspace settings**.
   - Revisa **License info** o **Capacity**.
   - Asigna una capacidad si aparece como workspace sin capacidad.
4. Copia el **Workspace ID** desde la URL o desde la configuracion del workspace.

Valores que usaras durante el despliegue:

```dotenv
FABRIC_WORKSPACE_NAME="FrasoHome Fabric RAG Demo"
FABRIC_WORKSPACE_ID="<workspace-id>"
FABRIC_SQL_DATABASE_NAME="FrasoHomeRagDB"
FABRIC_UDF_ITEM_NAME="FrasoHome_RAG_UDF"
FABRIC_UDF_SQL_ALIAS="frasohomesql"
```

## 2. Crear la SQL Database desde el portal

1. Abre el workspace en Fabric.
2. Selecciona **+ New item**.
3. Busca **SQL database**.
4. Crea una base con nombre:

```text
FrasoHomeRagDB
```

5. Espera a que Fabric abra la nueva base.
6. Abre **Settings** o **Connection strings** y copia el servidor TDS.

Guarda el valor con este formato:

```dotenv
FABRIC_SQL_SERVER="tcp:<server>.database.fabric.microsoft.com,1433"
FABRIC_SQL_DATABASE_NAME="FrasoHomeRagDB"
```

## 3. Crear los objetos SQL desde el editor del portal

La forma mas directa desde el portal es ejecutar los archivos SQL del repositorio, en orden, desde el editor de consultas de la SQL Database.

1. Abre `FrasoHomeRagDB` en Fabric.
2. Entra en **Query editor**.
3. Crea una nueva consulta.
4. Copia y ejecuta el contenido de cada archivo, respetando este orden:

```text
database/sql/00_create_schemas.sql
database/sql/01_create_operational_tables.sql
database/sql/02_create_rag_tables.sql
database/sql/03_seed_operational_data.sql
database/sql/04_seed_documents_chunks.sql
database/sql/05_create_procedures.sql
database/sql/06_create_security.sql
database/sql/07_create_hybrid_search.sql
```

Opcionalmente, si tu tenant tiene habilitadas las capacidades vectoriales SQL preview, ejecuta tambien:

```text
database/sql/90_optional_vector_preview.sql
```

Al terminar, ejecuta el smoke test:

```text
database/sql/99_smoke_test.sql
```

Resultado esperado:

- Existen los esquemas `fraso` y `rag`.
- Existen datos de demo para el caso `RET-2026-004219`.
- El procedimiento `rag.usp_get_candidate_chunks` devuelve politicas relevantes.
- La tabla `rag.AnswerAudit` esta lista para registrar respuestas.

## 4. Probar la base desde el portal

En el Query editor de la SQL Database, ejecuta:

```sql
EXEC rag.usp_get_return_case_context
    @ReturnCaseId = 'RET-2026-004219';

EXEC rag.usp_get_candidate_chunks
    @ReturnCaseId = 'RET-2026-004219',
    @Question = N'El cliente quiere devolver un sofa modular comprado online hace 34 dias. Indica que llego con una pata danada, conserva fotos del embalaje y solicita reemplazo urgente.',
    @MaxChunks = 6;
```

Comprueba que aparecen evidencias de politicas como:

- `POL-DMG-002`
- `POL-MUE-003`
- `POL-VIP-004`

## 5. Crear la User Data Function desde el portal

1. Vuelve al workspace.
2. Selecciona **+ New item**.
3. Busca **User data functions**.
4. Crea un item con nombre:

```text
FrasoHome_RAG_UDF
```

5. Abre el item en modo **Develop**.
6. En **Library management**, confirma que existe la libreria:

```text
fabric-user-data-functions
```

Si el portal pide version, usa la version disponible mas reciente compatible con Fabric. El repo declara `1.0` en `fabric/items/FrasoHome_RAG_UDF.UserDataFunction/definition.json.template`.

## 6. Configurar la conexion de la UDF a SQL Database

La UDF usa un alias de conexion llamado:

```text
frasohomesql
```

En el item `FrasoHome_RAG_UDF`:

1. Abre **Manage connections** o la seccion equivalente de conexiones del item.
2. Agrega una conexion a una fuente Fabric.
3. Selecciona la SQL Database `FrasoHomeRagDB`.
4. Define el alias exactamente como:

```text
frasohomesql
```

5. Guarda la conexion.

Este alias debe coincidir con la constante del codigo:

```python
SQL_ALIAS = 'frasohomesql'
```

## 7. Cargar el codigo Python de la UDF

1. En `FrasoHome_RAG_UDF`, abre el editor de codigo.
2. Sustituye el contenido del archivo de ejemplo por el contenido completo de:

```text
fabric/items/FrasoHome_RAG_UDF.UserDataFunction/function_app.py
```

3. Revisa que aparezcan estas funciones en el explorador:

```text
healthCheck
getReturnCaseContext
answerReturnCase
```

4. Selecciona **Publish**.
5. Espera a que la publicacion termine correctamente.

## 8. Probar la UDF desde el portal

En `FrasoHome_RAG_UDF`, cambia a **Run only** o usa el panel de ejecucion de funciones.

Primero ejecuta:

```text
healthCheck
```

Debe devolver un JSON con:

```json
{
  "status": "ok",
  "service": "FrasoHome_RAG_UDF"
}
```

Despues ejecuta `answerReturnCase` con estos parametros:

```json
{
  "returnCaseId": "RET-2026-004219",
  "question": "El cliente quiere devolver un sofa modular comprado online hace 34 dias. Indica que llego con una pata danada, conserva fotos del embalaje y solicita reemplazo urgente. Debemos aprobar devolucion, reemplazo o revision manual?",
  "maxChunks": 6
}
```

Respuesta esperada:

```text
Aprobar reemplazo prioritario condicionado a validacion visual
```

Si la funcion falla al conectar con SQL, revisa:

- Que la conexion Fabric apunta a `FrasoHomeRagDB`.
- Que el alias es exactamente `frasohomesql`.
- Que el usuario que ejecuta la UDF tiene permisos sobre la base.
- Que los procedimientos `rag.usp_get_return_case_context`, `rag.usp_get_candidate_chunks` y `rag.usp_insert_answer_audit` existen.

## 9. Habilitar endpoints publicos de la UDF

Para que la Fabric App pueda llamar al backend:

1. Abre `FrasoHome_RAG_UDF`.
2. Selecciona la funcion `answerReturnCase`.
3. Habilita **Public endpoint**.
4. Copia la URL publica de la funcion.
5. Repite si quieres exponer tambien `healthCheck` para diagnostico.

Guarda la URL:

```dotenv
VITE_UDF_FUNCTION_URL="https://.../answerReturnCase"
```

La invocacion del endpoint usa autenticacion Microsoft Entra; no publiques endpoints sin revisar las politicas de acceso del tenant.

## 10. Crear la app registration del frontend en Entra

Aunque el despliegue principal se realiza en Fabric, el frontend necesita una app registration para MSAL.

1. Abre Microsoft Entra admin center.
2. Ve a **Identity > Applications > App registrations > New registration**.
3. Nombre sugerido:

```text
frasohome-returnops-app
```

4. Usa **Accounts in this organizational directory only**.
5. En **Authentication**, agrega plataforma **Single-page application**.
6. Agrega temporalmente:

```text
http://localhost:5173
```

7. Copia:

```dotenv
VITE_ENTRA_CLIENT_ID="<application-client-id>"
VITE_ENTRA_TENANT_ID="<tenant-id>"
```

8. En **API permissions**, concede los permisos delegados que tu tenant requiera para invocar User Data Functions/Fabric APIs. En esta demo el frontend solicita scope:

```text
https://analysis.windows.net/powerbi/api/.default
```

9. Concede **admin consent** si la organizacion lo exige.

## 11. Preparar la Fabric App

El portal de Fabric administra el item y su acceso, pero la app React/Vite se compila localmente y se publica con Rayfin.

Desde la raiz del repo, crea o actualiza:

```text
app/frasohome-returnops-app/.env.local
```

Con este contenido:

```dotenv
VITE_UDF_FUNCTION_URL="https://.../answerReturnCase"
VITE_ENTRA_CLIENT_ID="<application-client-id>"
VITE_ENTRA_TENANT_ID="<tenant-id>"
```

Instala dependencias y valida el build:

```powershell
cd app/frasohome-returnops-app
npm install
npm run build
```

## 12. Publicar la Fabric App en el workspace

Desde `app/frasohome-returnops-app`, ejecuta:

```powershell
npx rayfin up --workspace-id <workspace-id> --yes
```

Si Rayfin solicita autenticacion, inicia sesion con un usuario con permisos sobre el workspace.

Cuando termine:

1. Vuelve al workspace en Fabric.
2. Busca el item **FraSoHome ReturnOps 360**.
3. Abre la app y copia su URL final.

El archivo de configuracion de Rayfin esta en:

```text
app/frasohome-returnops-app/rayfin/rayfin.yml
```

## 13. Completar redirect URI final

Despues de conocer la URL final de la Fabric App:

1. Vuelve a la app registration `frasohome-returnops-app` en Entra.
2. Abre **Authentication**.
3. Agrega la URL final de la Fabric App como redirect URI de SPA.
4. Si la app usa una ruta de callback adicional en tu tenant, agrega tambien:

```text
https://<tu-app>.webapp.fabricapps.net/auth/callback
```

5. Guarda los cambios.

## 14. Validacion end-to-end

1. Abre la URL de la Fabric App.
2. Inicia sesion cuando MSAL lo solicite.
3. Usa el caso:

```text
RET-2026-004219
```

4. Pregunta:

```text
El cliente quiere devolver un sofa modular comprado online hace 34 dias. Indica que llego con una pata danada, conserva fotos del embalaje y solicita reemplazo urgente. Debemos aprobar devolucion, reemplazo o revision manual?
```

Resultado esperado:

```text
Recomendacion: aprobar reemplazo prioritario condicionado a validacion visual.
```

La respuesta debe incluir evidencias, motivos, siguientes acciones y un `auditId`.

Para confirmar auditoria, vuelve al Query editor de `FrasoHomeRagDB` y ejecuta:

```sql
SELECT TOP (20)
    AnswerAuditId,
    ReturnCaseId,
    Recommendation,
    Confidence,
    CreatedAtUtc,
    CitedDocuments
FROM rag.AnswerAudit
ORDER BY AnswerAuditId DESC;
```

## 15. Ingesta opcional de politicas Markdown

El repo incluye politicas adicionales en:

```text
docs/policies/*.md
```

El portal no convierte Markdown a chunks RAG automaticamente. Para preparar el SQL de ingesta desde local:

```powershell
python -m pip install -r requirements.txt
python tools/ingest_policy_markdown.py `
  --input-dir docs/policies `
  --output-sql database/generated/ingest_policy_markdown.sql
```

Despues, abre en el portal el archivo generado:

```text
database/generated/ingest_policy_markdown.sql
```

Copia su contenido en el Query editor de `FrasoHomeRagDB` y ejecutalo.

Valida con:

```text
database/sql/98_smoke_test_markdown_ingestion.sql
```

## 16. Checklist de cierre

- Workspace asignado a capacidad Fabric.
- SQL Database `FrasoHomeRagDB` creada.
- Scripts SQL `00` a `07` ejecutados en orden.
- Smoke test SQL ejecutado correctamente.
- User Data Function `FrasoHome_RAG_UDF` creada y publicada.
- Conexion UDF a SQL configurada con alias `frasohomesql`.
- Endpoint publico de `answerReturnCase` habilitado.
- App registration SPA creada en Entra.
- Fabric App publicada con Rayfin.
- Redirect URI final agregado a la app registration.
- Prueba end-to-end devuelve recomendacion y registra auditoria.

## Solucion de problemas

### La UDF no muestra las funciones

Revisa que el codigo incluya:

```python
import fabric.functions as fn
udf = fn.UserDataFunctions()
```

Y que cada funcion publicada tenga:

```python
@udf.function()
```

### La UDF no conecta con SQL

Comprueba el alias `frasohomesql`, la conexion Fabric del item y los permisos del usuario. Si cambiaste el alias, actualiza tambien `SQL_ALIAS` en `function_app.py`.

### El frontend abre, pero dice que no esta configurado

Revisa que `.env.local` se genero antes de `npm run build` y que contiene:

```dotenv
VITE_UDF_FUNCTION_URL=
VITE_ENTRA_CLIENT_ID=
VITE_ENTRA_TENANT_ID=
```

Vuelve a compilar y publicar la app.

### MSAL falla con redirect_uri

Agrega exactamente la URL de la Fabric App en la app registration de Entra como redirect URI de tipo **Single-page application**. Si pruebas localmente, conserva tambien `http://localhost:5173`.

### El endpoint devuelve 401 o 403

Revisa permisos delegados, admin consent y acceso al item UDF/Fabric. El usuario que inicia sesion en la app debe poder invocar la User Data Function.

### El resultado no incluye auditoria

Ejecuta de nuevo `database/sql/05_create_procedures.sql` y `database/sql/06_create_security.sql` desde el Query editor. Luego prueba `answerReturnCase` otra vez.
