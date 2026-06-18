PRINT '07_create_hybrid_search.sql';
GO

CREATE OR ALTER PROCEDURE rag.usp_get_vector_candidate_chunks
    @returnCaseId varchar(30),
    @questionEmbeddingJson nvarchar(max),
    @embeddingModel nvarchar(120) = N'demo-hash-embedding-v1',
    @topN int = 6
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE
        @category varchar(80),
        @channel varchar(40),
        @openedDate date,
        @questionVector vector(1536);

    SELECT
        @category = p.Category,
        @channel = o.Channel,
        @openedDate = CAST(rc.OpenedAt AS date)
    FROM fraso.ReturnCases AS rc
    JOIN fraso.Orders AS o ON o.OrderId = rc.OrderId
    JOIN fraso.Products AS p ON p.ProductId = rc.ProductId
    WHERE rc.ReturnCaseId = @returnCaseId;

    SET @questionVector = CAST(@questionEmbeddingJson AS vector(1536));

    SELECT TOP (@topN)
        c.ChunkId,
        d.DocumentCode,
        d.DocumentTitle,
        d.DocumentType,
        d.SecurityLevel,
        c.ChunkNumber,
        c.ChunkText,
        c.ProductCategory,
        c.Channel,
        c.CountryCode,
        c.Keywords,
        Score = CAST(CASE WHEN VECTOR_DISTANCE('cosine', @questionVector, ce.EmbeddingVector) <= 1.0 THEN 1.0 - VECTOR_DISTANCE('cosine', @questionVector, ce.EmbeddingVector) ELSE 0 END AS decimal(9,6)),
        VectorDistance = CAST(VECTOR_DISTANCE('cosine', @questionVector, ce.EmbeddingVector) AS decimal(9,6)),
        VectorScore = CAST(CASE WHEN VECTOR_DISTANCE('cosine', @questionVector, ce.EmbeddingVector) <= 1.0 THEN 1.0 - VECTOR_DISTANCE('cosine', @questionVector, ce.EmbeddingVector) ELSE 0 END AS decimal(9,6)),
        ce.EmbeddingModel,
        ce.EmbeddingProvider
    FROM rag.Chunks AS c
    JOIN rag.Documents AS d
        ON d.DocumentId = c.DocumentId
    JOIN rag.ChunkEmbeddings AS ce
        ON ce.ChunkId = c.ChunkId
       AND ce.EmbeddingModel = @embeddingModel
    WHERE c.ValidFrom <= @openedDate
      AND (c.ValidTo IS NULL OR c.ValidTo >= @openedDate)
      AND (c.CountryCode IN ('ES', 'all') OR c.CountryCode IS NULL)
      AND (c.Channel IN (@channel, 'all') OR c.Channel IS NULL)
      AND (c.ProductCategory IN (@category, 'all') OR c.ProductCategory IS NULL)
    ORDER BY VectorDistance ASC, DocumentCode, ChunkNumber;
END;
GO

CREATE OR ALTER PROCEDURE rag.usp_get_ann_candidate_chunks
    @returnCaseId varchar(30),
    @questionEmbeddingJson nvarchar(max),
    @embeddingModel nvarchar(120) = N'demo-hash-embedding-v1',
    @topN int = 6
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE
        @category varchar(80),
        @channel varchar(40),
        @openedDate date,
        @questionVector vector(1536);

    SELECT
        @category = p.Category,
        @channel = o.Channel,
        @openedDate = CAST(rc.OpenedAt AS date)
    FROM fraso.ReturnCases AS rc
    JOIN fraso.Orders AS o ON o.OrderId = rc.OrderId
    JOIN fraso.Products AS p ON p.ProductId = rc.ProductId
    WHERE rc.ReturnCaseId = @returnCaseId;

    SET @questionVector = CAST(@questionEmbeddingJson AS vector(1536));

    SELECT TOP (@topN) WITH APPROXIMATE
        ch.ChunkId,
        d.DocumentCode,
        d.DocumentTitle,
        d.DocumentType,
        d.SecurityLevel,
        ch.ChunkNumber,
        ch.ChunkText,
        ch.ProductCategory,
        ch.Channel,
        ch.CountryCode,
        ch.Keywords,
        Score = CAST(CASE WHEN vs.distance <= 1.0 THEN 1.0 - vs.distance ELSE 0 END AS decimal(9,6)),
        VectorDistance = CAST(vs.distance AS decimal(9,6)),
        VectorScore = CAST(CASE WHEN vs.distance <= 1.0 THEN 1.0 - vs.distance ELSE 0 END AS decimal(9,6)),
        c.EmbeddingModel,
        c.EmbeddingProvider
    FROM VECTOR_SEARCH(
            TABLE = rag.ChunkEmbeddings AS c,
            COLUMN = EmbeddingVector,
            SIMILAR_TO = @questionVector,
            METRIC = 'cosine'
        ) AS vs
    JOIN rag.Chunks AS ch
        ON ch.ChunkId = c.ChunkId
    JOIN rag.Documents AS d
        ON d.DocumentId = ch.DocumentId
    WHERE c.EmbeddingModel = @embeddingModel
      AND ch.ValidFrom <= @openedDate
      AND (ch.ValidTo IS NULL OR ch.ValidTo >= @openedDate)
      AND (ch.CountryCode IN ('ES', 'all') OR ch.CountryCode IS NULL)
      AND (ch.Channel IN (@channel, 'all') OR ch.Channel IS NULL)
      AND (ch.ProductCategory IN (@category, 'all') OR ch.ProductCategory IS NULL)
    ORDER BY vs.distance ASC;
END;
GO

CREATE OR ALTER PROCEDURE rag.usp_get_hybrid_candidate_chunks
    @returnCaseId varchar(30),
    @question nvarchar(max),
    @questionEmbeddingJson nvarchar(max),
    @embeddingModel nvarchar(120) = N'demo-hash-embedding-v1',
    @topN int = 6,
    @lexicalWeight decimal(5,4) = 0.5500,
    @vectorWeight decimal(5,4) = 0.4500
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE
        @category varchar(80),
        @channel varchar(40),
        @openedDate date,
        @q nvarchar(max),
        @reason nvarchar(max),
        @hasPhotos bit,
        @isBulky bit,
        @questionVector vector(1536);

    SELECT
        @category = p.Category,
        @channel = o.Channel,
        @openedDate = CAST(rc.OpenedAt AS date),
        @reason = rc.ReasonText,
        @hasPhotos = rc.HasPhotos,
        @isBulky = p.IsBulky
    FROM fraso.ReturnCases AS rc
    JOIN fraso.Orders AS o ON o.OrderId = rc.OrderId
    JOIN fraso.Products AS p ON p.ProductId = rc.ProductId
    WHERE rc.ReturnCaseId = @returnCaseId;

    SET @q = LOWER(CONCAT(@question, N' ', @reason));
    SET @questionVector = CAST(@questionEmbeddingJson AS vector(1536));

    ;WITH Candidate AS
    (
        SELECT
            c.ChunkId,
            d.DocumentCode,
            d.DocumentTitle,
            d.DocumentType,
            d.SecurityLevel,
            c.ChunkNumber,
            c.ChunkText,
            c.ProductCategory,
            c.Channel,
            c.CountryCode,
            c.Keywords,
            LexicalScore =
                CAST(0 AS decimal(9,4))
                + CASE WHEN c.CountryCode IN ('ES', 'all') THEN 0.50 ELSE 0 END
                + CASE WHEN c.Channel IN (@channel, 'all') THEN 1.00 ELSE 0 END
                + CASE WHEN c.ProductCategory IN (@category, 'all') THEN 1.00 ELSE 0 END
                + CASE WHEN @q LIKE N'%dañ%' OR @q LIKE N'%rota%' OR @q LIKE N'%golpe%' THEN CASE WHEN c.ChunkText LIKE N'%daño%' OR c.Keywords LIKE N'%daño%' THEN 3.00 ELSE 0 END ELSE 0 END
                + CASE WHEN @q LIKE N'%embalaje%' THEN CASE WHEN c.ChunkText LIKE N'%embalaje%' OR c.Keywords LIKE N'%embalaje%' THEN 2.50 ELSE 0 END ELSE 0 END
                + CASE WHEN @q LIKE N'%foto%' OR @hasPhotos = 1 THEN CASE WHEN c.ChunkText LIKE N'%fotográfica%' OR c.ChunkText LIKE N'%evidencia%' OR c.Keywords LIKE N'%evidencia%' THEN 2.00 ELSE 0 END ELSE 0 END
                + CASE WHEN @q LIKE N'%reemplazo%' OR @q LIKE N'%sustitución%' THEN CASE WHEN c.ChunkText LIKE N'%reemplazo%' OR c.Keywords LIKE N'%reemplazo%' THEN 2.00 ELSE 0 END ELSE 0 END
                + CASE WHEN @isBulky = 1 THEN CASE WHEN c.ChunkText LIKE N'%voluminoso%' OR c.Keywords LIKE N'%voluminoso%' THEN 2.25 ELSE 0 END ELSE 0 END
                + CASE WHEN @q LIKE N'%gold%' OR @q LIKE N'%platinum%' THEN CASE WHEN c.ChunkText LIKE N'%Gold%' OR c.ChunkText LIKE N'%Platinum%' THEN 2.25 ELSE 0 END ELSE 0 END
                + CASE WHEN @q LIKE N'%stock%' THEN CASE WHEN c.ChunkText LIKE N'%stock%' OR c.Keywords LIKE N'%stock%' THEN 1.50 ELSE 0 END ELSE 0 END,
            VectorDistance = VECTOR_DISTANCE('cosine', @questionVector, ce.EmbeddingVector),
            ce.EmbeddingModel,
            ce.EmbeddingProvider
        FROM rag.Chunks AS c
        JOIN rag.Documents AS d
            ON d.DocumentId = c.DocumentId
        JOIN rag.ChunkEmbeddings AS ce
            ON ce.ChunkId = c.ChunkId
           AND ce.EmbeddingModel = @embeddingModel
        WHERE c.ValidFrom <= @openedDate
          AND (c.ValidTo IS NULL OR c.ValidTo >= @openedDate)
          AND (c.CountryCode IN ('ES', 'all') OR c.CountryCode IS NULL)
          AND (c.Channel IN (@channel, 'all') OR c.Channel IS NULL)
          AND (c.ProductCategory IN (@category, 'all') OR c.ProductCategory IS NULL)
    ),
    Scored AS
    (
        SELECT
            c.ChunkId,
            c.DocumentCode,
            c.DocumentTitle,
            c.DocumentType,
            c.SecurityLevel,
            c.ChunkNumber,
            c.ChunkText,
            c.ProductCategory,
            c.Channel,
            c.CountryCode,
            c.Keywords,
            c.LexicalScore,
            c.VectorDistance,
            c.EmbeddingModel,
            c.EmbeddingProvider,
            LexicalNormalized =
                CAST(
                    CASE
                        WHEN MAX(c.LexicalScore) OVER () > 0
                        THEN c.LexicalScore / MAX(c.LexicalScore) OVER ()
                        ELSE 0
                    END
                    AS decimal(9,6)
                ),
            VectorScore =
                CAST(
                    CASE
                        WHEN c.VectorDistance IS NOT NULL AND c.VectorDistance <= 1.0
                        THEN 1.0 - c.VectorDistance
                        WHEN c.VectorDistance IS NOT NULL
                        THEN 0
                        ELSE 0
                    END
                    AS decimal(9,6)
                )
        FROM Candidate AS c
        WHERE c.LexicalScore > 0 OR c.VectorDistance IS NOT NULL
    ),
    Hybrid AS
    (
        SELECT
            ChunkId,
            DocumentCode,
            DocumentTitle,
            DocumentType,
            SecurityLevel,
            ChunkNumber,
            ChunkText,
            ProductCategory,
            Channel,
            CountryCode,
            Keywords,
            LexicalScore,
            LexicalNormalized,
            VectorDistance,
            VectorScore,
            EmbeddingModel,
            EmbeddingProvider,
            HybridScore =
                CAST((@lexicalWeight * LexicalNormalized) + (@vectorWeight * VectorScore) AS decimal(9,6))
        FROM Scored
    )
    SELECT TOP (@topN)
        ChunkId,
        DocumentCode,
        DocumentTitle,
        DocumentType,
        SecurityLevel,
        ChunkNumber,
        ChunkText,
        ProductCategory,
        Channel,
        CountryCode,
        Keywords,
        Score = HybridScore,
        LexicalScore,
        LexicalNormalized,
        VectorDistance,
        VectorScore,
        HybridScore,
        EmbeddingModel,
        EmbeddingProvider
    FROM Hybrid
    ORDER BY HybridScore DESC, VectorScore DESC, LexicalScore DESC, DocumentCode, ChunkNumber;
END;
GO
