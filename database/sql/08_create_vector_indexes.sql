PRINT '08_create_vector_indexes.sql';
GO

/*
    DiskANN vector indexes require enough vectors to build a useful graph. The
    demo seed is intentionally small, so this script creates the index only when
    the knowledge base has enough rows. Exact VECTOR_DISTANCE search works either
    way; VECTOR_SEARCH can fall back to kNN when no matching vector index exists.
*/

DECLARE @embeddingCount bigint;

SELECT @embeddingCount = COUNT_BIG(*)
FROM rag.ChunkEmbeddings
WHERE EmbeddingVector IS NOT NULL;

IF @embeddingCount >= 100
   AND NOT EXISTS
   (
       SELECT 1
       FROM sys.indexes
       WHERE object_id = OBJECT_ID(N'rag.ChunkEmbeddings')
         AND name = N'VIX_RagChunkEmbeddings_EmbeddingVector_Cosine'
   )
BEGIN
    PRINT 'Creating DiskANN vector index on rag.ChunkEmbeddings.EmbeddingVector.';
    CREATE VECTOR INDEX VIX_RagChunkEmbeddings_EmbeddingVector_Cosine
    ON rag.ChunkEmbeddings(EmbeddingVector)
    WITH (METRIC = 'cosine', TYPE = 'diskann');
END
ELSE
BEGIN
    PRINT CONCAT('Skipping vector index creation. Current embedding count: ', @embeddingCount, '. Minimum recommended for latest vector indexes: 100.');
END;
GO
