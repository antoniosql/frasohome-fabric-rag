# Guion de demo para la sesión

## Minuto 1: Problema

"FraSoHome tiene políticas en documentos y datos vivos en SQL. Un agente necesita decidir si aprueba un reemplazo, una devolución o una revisión manual."

## Minuto 2: SQL primero

Ejecuta:

```sql
EXEC rag.usp_get_return_case_context 'RET-2026-004219';
```

Remarca que el contexto operacional no está en PDFs: cliente, pedido, producto, stock y riesgo.

## Minuto 3: Retrieval

Ejecuta:

```sql
EXEC rag.usp_get_candidate_chunks
  @returnCaseId = 'RET-2026-004219',
  @question = N'Cliente Gold quiere devolver un sofá modular comprado online hace 34 días. Llegó con una pata dañada, tiene fotos del embalaje y pide reemplazo urgente.',
  @topN = 5;
```

Remarca filtros por vigencia, canal, categoría y país.

## Minuto 4: App

Abre la Fabric App y lanza la pregunta. Muestra:

- Recomendación.
- Motivos.
- Evidencias.
- Acciones.

## Minuto 5: Auditoría

```sql
SELECT TOP 10 *
FROM rag.AnswerAudit
ORDER BY CreatedAt DESC;
```

Mensaje final: "La IA responde, pero SQL gobierna qué contexto puede usar y cómo se audita."
