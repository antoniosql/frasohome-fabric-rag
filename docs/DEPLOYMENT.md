# Guía de despliegue

## 1. Autenticación

Si PowerShell indica que algún script `.ps1` no está firmado, desbloquéalos en la copia local:

```powershell
Get-ChildItem .\scripts\*.ps1 | Unblock-File
```

Configura `.env` con service principal o managed identity siguiendo `docs/NON_INTERACTIVE_AUTH.md`. Los scripts cargan esas variables y evitan `fab auth login` interactivo.

```powershell
.\scripts\bootstrap.ps1
```

Nota: Rayfin todavía no soporta service principal en `rayfin login`; `deploy_app.ps1` puede requerir una sesión Rayfin interactiva previa.

## 2. Crear SQL Database

```powershell
.\scripts\deploy_fabric_sql.ps1
```

Después de crearla, copia el server name desde **Settings > Connection strings** en Fabric.

## 3. Aplicar SQL

```powershell
.\scripts\apply_sql.ps1
```

Este paso crea:

- Esquemas `fraso` y `rag`.
- Tablas operacionales.
- Tablas RAG.
- Datos de demo.
- Stored procedures.
- Roles/grants de ejemplo.

## 4. Publicar UDF

```powershell
.\scripts\publish_udf.ps1
```

El script intenta localizar el item id de la SQL Database con `fab api` y renderiza:

- `fabric/items/FrasoHome_RAG_UDF.UserDataFunction/definition.json`
- `fabric/items/config.yml`

Después ejecuta:

```powershell
cd fabric/items
fab deploy --config config.yml
```

Si la conexión por alias no aparece en el portal, créala desde **Manage connections** en el item UDF y usa el alias configurado en `.env`.

## 5. Habilitar endpoint público UDF

En el portal de Fabric:

1. Abre `FrasoHome_RAG_UDF`.
2. Publica si el portal lo solicita.
3. Habilita public endpoint para `answerReturnCase`.
4. Copia la URL pública en `VITE_UDF_FUNCTION_URL`.

## 6. App registration para invocar UDF

Crea una app registration en Entra ID para el frontend. Añade redirect URI:

- `http://localhost:5173`
- La URL final de tu Fabric App cuando la tengas desplegada.

Concede permisos delegados necesarios para invocar User Data Functions / Power BI API según tu tenant y otorga admin consent si aplica.

## 7. Desplegar Fabric App

```powershell
.\scripts\deploy_app.ps1
```

El script genera `.env.local`, instala dependencias y ejecuta:

```powershell
npx rayfin up --workspace-id $env:FABRIC_WORKSPACE_ID --yes
```

## 8. Probar

Abre la URL de la Fabric App y ejecuta la pregunta demo.
