# Autenticación no interactiva

Esta demo puede automatizar Fabric CLI (`fab`) y `sqlcmd` sin abrir navegador usando service principals o managed identities.

## Requisitos de tenant y permisos

- En Fabric Admin Portal, habilita **Allow service principals to use Fabric APIs** para el grupo de seguridad donde esté el service principal o la managed identity.
- Añade esa identidad al workspace con permisos suficientes para crear/desplegar items.
- Para ejecutar T-SQL, crea un usuario de base de datos para esa identidad y concédele permisos sobre la SQL Database.
- No guardes secretos reales en Git. Usa `.env` local, GitHub Actions secrets, Azure DevOps secret variables o federated credentials.

Ejemplo orientativo para preparar la identidad en SQL, ejecutado una vez con un administrador Microsoft Entra de la base de datos:

```sql
CREATE USER [frasohome-fabric-deployer] FROM EXTERNAL PROVIDER;
ALTER ROLE db_owner ADD MEMBER [frasohome-fabric-deployer];
```

Para una identidad que solo invoque procedimientos de la demo después del despliegue, usa el rol limitado que crea `06_create_security.sql`:

```sql
CREATE USER [frasohome-rag-runtime] FROM EXTERNAL PROVIDER;
ALTER ROLE frasohome_rag_executor ADD MEMBER [frasohome-rag-runtime];
```

## Opción A: service principal con secreto

En `.env`:

```dotenv
FAB_TENANT_ID="00000000-0000-0000-0000-000000000000"
FAB_SPN_CLIENT_ID="00000000-0000-0000-0000-000000000000"
FAB_SPN_CLIENT_SECRET="<client-secret>"

FABRIC_SQL_AUTH_MODE="service-principal"
FABRIC_UDF_AUTH_MODE="service-principal"
```

Los scripts PowerShell cargan `.env` y `fab` usa automáticamente las variables `FAB_*`. Para SQL, `apply_sql.ps1` invoca `sqlcmd` con `ActiveDirectoryServicePrincipal`.

## Opción B: service principal con certificado

En `.env`:

```dotenv
FAB_TENANT_ID="00000000-0000-0000-0000-000000000000"
FAB_SPN_CLIENT_ID="00000000-0000-0000-0000-000000000000"
FAB_SPN_CERT_PATH="C:\certs\fabric-spn.pfx"
FAB_SPN_CERT_PASSWORD="<certificate-password>"

FABRIC_SQL_AUTH_MODE="default"
```

El certificado aplica a Fabric CLI. Para `sqlcmd`, usa `FABRIC_SQL_AUTH_MODE="default"` si tu entorno expone credenciales compatibles con `ActiveDirectoryDefault`, o usa secreto/managed identity para la conexión SQL.

## Opción C: federated credential

En pipelines con OIDC, define:

```dotenv
FAB_TENANT_ID="00000000-0000-0000-0000-000000000000"
FAB_SPN_CLIENT_ID="00000000-0000-0000-0000-000000000000"
FAB_SPN_FEDERATED_TOKEN="<token-oidc>"

FABRIC_SQL_AUTH_MODE="default"
```

En GitHub Actions normalmente no se escribe el token en `.env`: se obtiene en el job y se expone como variable de entorno/secreto temporal.

## Opción D: managed identity

En una VM o recurso Azure con managed identity:

```dotenv
FAB_MANAGED_IDENTITY="true"
FABRIC_SQL_AUTH_MODE="managed-identity"
FABRIC_UDF_AUTH_MODE="managed-identity"
```

Para una user-assigned managed identity:

```dotenv
FAB_MANAGED_IDENTITY="true"
FAB_SPN_CLIENT_ID="00000000-0000-0000-0000-000000000000"
FABRIC_SQL_AUTH_MODE="managed-identity"
FABRIC_SQL_MANAGED_IDENTITY_CLIENT_ID="00000000-0000-0000-0000-000000000000"
FABRIC_UDF_AUTH_MODE="managed-identity"
FABRIC_UDF_MANAGED_IDENTITY_CLIENT_ID="00000000-0000-0000-0000-000000000000"
```

## Ejecutar

```powershell
.\scripts\bootstrap.ps1
.\scripts\deploy_fabric_sql.ps1
.\scripts\apply_sql.ps1
.\scripts\publish_udf.ps1
python tools/call_udf.py --auth-mode service-principal
```

## Limitación actual de Rayfin

Según la referencia actual de Microsoft, `rayfin login` muestra opciones de service principal, pero esas opciones todavía no están soportadas. Por eso `deploy_app.ps1` puede requerir una sesión Rayfin interactiva previa hasta que Rayfin habilite autenticación no interactiva real.

## Login del usuario final

La app React sigue usando MSAL en navegador para que un usuario final invoque la UDF con permisos delegados. Esa autenticación pertenece a la experiencia de usuario de la demo, no al despliegue automatizado. Service principal y managed identity se usan para automatizar despliegue, SQL y pruebas de consola.

## Referencias

- Fabric CLI authentication and environment variables: https://microsoft.github.io/fabric-cli/essentials/env_vars/
- Fabric CLI auth examples: https://microsoft.github.io/fabric-cli/examples/auth_examples/
- Rayfin CLI reference: https://learn.microsoft.com/en-us/fabric/apps/cli-reference
