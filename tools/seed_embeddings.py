#!/usr/bin/env python3
"""
Genera embeddings deterministas de demo y los guarda en rag.ChunkEmbeddings.

Este script es opcional. El flujo principal usa recuperación T-SQL. Sirve para enseñar
cómo versionar embeddings aunque aún no tengas vector search habilitado en SQL.
"""
import argparse
import hashlib
import json
import math
import os
import re
from typing import Iterable, List


def embed(text: str, dimensions: int = 64) -> List[float]:
    vec = [0.0] * dimensions
    tokens = re.findall(r"[\wáéíóúüñ]+", text.lower())
    for token in tokens:
        digest = hashlib.sha256(token.encode("utf-8")).digest()
        idx = int.from_bytes(digest[:4], "big") % dimensions
        sign = 1.0 if digest[4] % 2 == 0 else -1.0
        vec[idx] += sign
    norm = math.sqrt(sum(v * v for v in vec)) or 1.0
    return [round(v / norm, 6) for v in vec]


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--dimensions", type=int, default=int(os.getenv("RAG_EMBEDDING_DIMENSIONS", "64")))
    parser.add_argument("--out", default="embeddings.preview.json")
    parser.add_argument("texts", nargs="*")
    args = parser.parse_args()
    texts = args.texts or [
        "daños en transporte con evidencia fotográfica",
        "muebles voluminosos con stock de reemplazo",
        "clientes Gold con bajo riesgo",
    ]
    payload = [{"text": t, "embedding": embed(t, args.dimensions)} for t in texts]
    with open(args.out, "w", encoding="utf-8") as f:
        json.dump(payload, f, indent=2, ensure_ascii=False)
    print(f"Wrote {args.out}")


if __name__ == "__main__":
    main()
