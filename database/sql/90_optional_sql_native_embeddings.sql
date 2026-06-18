PRINT '90_optional_sql_native_embeddings.sql';
GO

/*
    Optional SQL-native vectorization path.

    Use this script after creating an EXTERNAL MODEL named FrasoHomeEmbeddingModel.
    It demonstrates the Fabric SQL RAG flow:

      1. AI_GENERATE_CHUNKS can split source text inside the database.
      2. AI_GENERATE_EMBEDDINGS calls the registered external embedding model.
      3. Embeddings are stored as native VECTOR(1536).
      4. Retrieval uses VECTOR_DISTANCE / VECTOR_SEARCH in 07_create_hybrid_search.sql.

    This script is not included in the default deployment because CREATE EXTERNAL
    MODEL requires tenant-specific endpoint, credential and secret values.

    Minimal setup pattern:

      EXECUTE sp_configure 'external rest endpoint enabled', 1;
      RECONFIGURE WITH OVERRIDE;

      CREATE MASTER KEY ENCRYPTION BY PASSWORD = N'<strong-password>';

      CREATE DATABASE SCOPED CREDENTIAL [https://<aoai>.openai.azure.com/]
      WITH IDENTITY = 'HTTPEndpointHeaders',
           SECRET = '{"api-key":"<key>"}';

      CREATE EXTERNAL MODEL FrasoHomeEmbeddingModel
      WITH
      (
          LOCATION = 'https://<aoai>.openai.azure.com/openai/deployments/<embedding-deployment>/embeddings?api-version=2024-10-21',
          API_FORMAT = 'Azure OpenAI',
          MODEL_TYPE = EMBEDDINGS,
          MODEL = '<embedding-model-name>',
          CREDENTIAL = [https://<aoai>.openai.azure.com/]
      );
*/

CREATE OR ALTER PROCEDURE rag.usp_vectorize_chunks_with_external_model
    @embeddingModel sysname = N'FrasoHomeEmbeddingModel',
    @modelLabel nvarchar(120) = N'FrasoHomeEmbeddingModel',
    @provider varchar(40) = 'sql-native',
    @dimensions int = 1536,
    @onlyMissing bit = 1
AS
BEGIN
    SET NOCOUNT ON;

    IF @dimensions <> 1536
    BEGIN
        THROW 51000, 'This demo schema uses VECTOR(1536). Recreate rag.ChunkEmbeddings if you need another dimension count.', 1;
    END;

    DECLARE @runId bigint;

    INSERT INTO rag.VectorizationRuns(Provider, EmbeddingModel, EmbeddingDimensions, Source, ChunkCount, Notes)
    SELECT
        @provider,
        @modelLabel,
        @dimensions,
        N'rag.Chunks via AI_GENERATE_EMBEDDINGS',
        COUNT_BIG(*),
        N'SQL-native vectorization using a pre-created EXTERNAL MODEL.'
    FROM rag.Chunks AS c
    WHERE @onlyMissing = 0
       OR NOT EXISTS
          (
              SELECT 1
              FROM rag.ChunkEmbeddings AS ce
              WHERE ce.ChunkId = c.ChunkId
                AND ce.EmbeddingModel = @modelLabel
          );

    SET @runId = CONVERT(bigint, SCOPE_IDENTITY());

    DECLARE @sql nvarchar(max) = N'
MERGE rag.ChunkEmbeddings AS target
USING
(
    SELECT
        c.ChunkId,
        EmbeddingProvider = @provider,
        EmbeddingModel = @modelLabel,
        EmbeddingDimensions = @dimensions,
        EmbeddingVector = AI_GENERATE_EMBEDDINGS(c.ChunkText USE MODEL ' + QUOTENAME(@embeddingModel) + N'),
        SourceTextHash = HASHBYTES(''SHA2_256'', CONVERT(varbinary(max), c.ChunkText))
    FROM rag.Chunks AS c
    WHERE @onlyMissing = 0
       OR NOT EXISTS
          (
              SELECT 1
              FROM rag.ChunkEmbeddings AS ce
              WHERE ce.ChunkId = c.ChunkId
                AND ce.EmbeddingModel = @modelLabel
          )
) AS source
ON target.ChunkId = source.ChunkId
WHEN MATCHED THEN UPDATE SET
    EmbeddingProvider = source.EmbeddingProvider,
    EmbeddingModel = source.EmbeddingModel,
    EmbeddingDimensions = source.EmbeddingDimensions,
    EmbeddingVector = source.EmbeddingVector,
    SourceTextHash = source.SourceTextHash,
    VectorizedAt = SYSUTCDATETIME()
WHEN NOT MATCHED THEN INSERT
(
    ChunkId,
    EmbeddingProvider,
    EmbeddingModel,
    EmbeddingDimensions,
    EmbeddingVector,
    SourceTextHash
)
VALUES
(
    source.ChunkId,
    source.EmbeddingProvider,
    source.EmbeddingModel,
    source.EmbeddingDimensions,
    source.EmbeddingVector,
    source.SourceTextHash
);';

    EXEC sp_executesql
        @sql,
        N'@provider varchar(40), @modelLabel nvarchar(120), @dimensions int, @onlyMissing bit',
        @provider = @provider,
        @modelLabel = @modelLabel,
        @dimensions = @dimensions,
        @onlyMissing = @onlyMissing;

    UPDATE rag.VectorizationRuns
    SET CompletedAt = SYSUTCDATETIME()
    WHERE VectorizationRunId = @runId;
END;
GO

CREATE OR ALTER PROCEDURE rag.usp_chunk_document_with_ai_generate_chunks
    @documentCode varchar(50),
    @chunkSize int = 900,
    @overlap int = 10
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @documentId int;

    SELECT @documentId = DocumentId
    FROM rag.Documents
    WHERE DocumentCode = @documentCode;

    IF @documentId IS NULL
    BEGIN
        THROW 51001, 'DocumentCode not found.', 1;
    END;

    IF @overlap < 0 OR @overlap > 50
    BEGIN
        THROW 51002, 'AI_GENERATE_CHUNKS overlap must be a percentage between 0 and 50.', 1;
    END;

    DELETE ce
    FROM rag.ChunkEmbeddings AS ce
    JOIN rag.Chunks AS c ON c.ChunkId = ce.ChunkId
    WHERE c.DocumentId = @documentId;

    DELETE FROM rag.Chunks
    WHERE DocumentId = @documentId;

    INSERT INTO rag.Chunks
    (
        DocumentId,
        ChunkNumber,
        ChunkText,
        ProductCategory,
        Channel,
        CountryCode,
        ValidFrom,
        ValidTo,
        Keywords
    )
    SELECT
        d.DocumentId,
        ROW_NUMBER() OVER (ORDER BY c.chunk_order),
        c.chunk,
        'all',
        'all',
        'ES',
        d.ValidFrom,
        d.ValidTo,
        NULL
    FROM rag.Documents AS d
    CROSS APPLY AI_GENERATE_CHUNKS
    (
        SOURCE = d.Content,
        CHUNK_TYPE = FIXED,
        CHUNK_SIZE = @chunkSize,
        OVERLAP = @overlap
    ) AS c
    WHERE d.DocumentId = @documentId;
END;
GO
