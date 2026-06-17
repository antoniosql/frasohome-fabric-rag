$ErrorActionPreference = "Stop"
Set-Location (Split-Path -Parent $PSScriptRoot)
. (Join-Path $PSScriptRoot "_env.ps1")

Require-Env "FABRIC_WORKSPACE_ID"
Require-Env "FABRIC_SQL_DATABASE_NAME"

Import-DotEnv -Path ".fabric.generated.env"

if ([string]::IsNullOrWhiteSpace($FABRIC_SQL_DATABASE_ITEM_ID)) {
    Write-Host "Resolviendo item id de SQL Database con fab api..."
    & python "scripts/get_item_ids.py" "--workspace-id" $FABRIC_WORKSPACE_ID "--sql-database-name" $FABRIC_SQL_DATABASE_NAME "--out" ".fabric.generated.env"
    Import-DotEnv -Path ".fabric.generated.env"
}

if ([string]::IsNullOrWhiteSpace($FABRIC_SQL_DATABASE_ITEM_ID)) {
    throw "No se pudo resolver FABRIC_SQL_DATABASE_ITEM_ID. Añádelo a .env o .fabric.generated.env."
}

Invoke-CheckedCommand -Command "python" -Arguments @(
    "scripts/render_udf_definition.py",
    "--workspace-id", $FABRIC_WORKSPACE_ID,
    "--sql-database-item-id", $FABRIC_SQL_DATABASE_ITEM_ID,
    "--sql-alias", $(if ([string]::IsNullOrWhiteSpace($FABRIC_UDF_SQL_ALIAS)) { "frasohome_sql" } else { $FABRIC_UDF_SQL_ALIAS })
)

Push-Location "fabric/items"
try {
    Invoke-CheckedCommand -Command "fab" -Arguments @("deploy", "--config", "config.yml")
}
finally {
    Pop-Location
}

Write-Host "UDF publicada con fab deploy."
Write-Host "Siguiente paso: abre el item FrasoHome_RAG_UDF en Fabric, confirma la conexión/alias y copia la URL pública de answerReturnCase en .env."
