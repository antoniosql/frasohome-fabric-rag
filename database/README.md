# SQL Database in Fabric

Ejecutar los scripts en orden con:

```powershell
.\scripts\apply_sql.ps1
```

Scripts:

1. `00_create_schemas.sql`
2. `01_create_operational_tables.sql`
3. `02_create_rag_tables.sql`
4. `03_seed_operational_data.sql`
5. `04_seed_documents_chunks.sql`
6. `05_create_procedures.sql`
7. `06_create_security.sql`
8. `90_optional_vector_preview.sql`
9. `99_smoke_test.sql`
