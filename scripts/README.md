# Scripts

- `bootstrap.ps1`: instala herramientas Python/Node locales.
- `deploy_fabric_sql.ps1`: crea la SQL Database en Fabric con `fab create`.
- `apply_sql.ps1`: aplica scripts T-SQL con `sqlcmd` y autenticación Microsoft Entra no interactiva.
- `smoke_test_sql.ps1`: ejecuta el smoke test SQL con la misma autenticación que `apply_sql.ps1`.
- `get_item_ids.py`: localiza item ids con `fab api`.
- `render_udf_definition.py`: renderiza `definition.json` y `config.yml`.
- `publish_udf.ps1`: publica la User Data Function con `fab deploy`.
- `deploy_app.ps1`: publica la Fabric App con Rayfin.
- `deploy_all.ps1`: orquestador de despliegue.
