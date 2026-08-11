# ADR 0008: Cache format, locking, and hashing

- Status: Accepted
- Date: 2026-08-11
- Compatibility baseline: `just 1.57.0`

## Context

Phase 9 introduces persistent recipe caching. A cache hit can suppress command
execution, so a false hit is a correctness and security failure. Cache entries
may be observed by concurrent MoonJust processes, interrupted during commit, or
modified by an untrusted local user. The format must therefore be versioned,
deterministic, atomically published, and treated as untrusted input.

The upstream baseline hashes a serialized key with BLAKE3 and holds an
exclusive lock while deciding whether a recipe must run. MoonJust preserves
the observable invalidation inputs without sharing the upstream on-disk format.

## Decision

- The cache root is `.moonjust-cache/v1` below the project directory. The `v1`
  component is part of the storage format and is never inferred from file
  contents.
- Entry names are lowercase 64-digit BLAKE3 digests followed by `.json`.
  MoonJust never accepts a manifest-supplied path as an entry filename.
- The key encoding is project-owned and length-delimited. It includes the
  format version, algorithm identifier, recipe identity, evaluated body,
  interpreter and arguments, exported environment, extension, working
  directory, positional values, `extra`, and sorted input path/digest pairs.
- Input files are hashed incrementally with BLAKE3 through bounded HostFs
  ranges. Missing inputs and directory inputs are typed failures.
- A manifest records its schema version, algorithm, complete key digest,
  recipe identity, and validated relative output paths. Unknown versions,
  malformed JSON, oversized documents, digest mismatches, duplicate outputs,
  absolute paths, parent traversal, drive prefixes, and control characters are
  corruption and can never produce a hit. Manifests are limited to 256 KiB,
  input and output collections to 1,024 paths each, and host reads to that
  limit plus one sentinel byte.
- Each digest has a permanent sibling `.lock` file. The adapter holds an OS
  exclusive lock across lookup, recipe execution, output verification, and
  commit. OS lock ownership provides crash release; lock files are not removed
  during normal operation, avoiding unlink-and-recreate split-lock races.
- A successful entry is written to an exclusively created same-directory
  temporary file with mode `0600`, fully synchronized, and atomically renamed
  over the entry. Failed, cancelled, or partially completed recipes never
  publish a manifest. After acquiring a digest lock, adapters remove only stale
  temporary names that exactly match MoonJust's digest and random/fallback
  suffix grammar; similar user files are preserved.
- Corrupt or truncated manifests are cache misses. A later successful run
  replaces them atomically. `--clean` removes only recognized digest manifests
  while preserving unrelated files and coordinating with entry locks. Lease
  tokens are checked against their exact directory and digest before every
  read, write, and release.
- `--no-cache` bypasses both lookup and publication. Dry-run does not read
  inputs, acquire cache locks, or write cache state.
- Native and wasm1 adapters implement the same project-owned HostCacheStore
  contract. Wasm execution still requires explicit filesystem policy grants.

## Consequences

Cache data is not compatible with upstream `just` or future MoonJust versions
unless an explicit migration is added. Deleting `.moonjust-cache` is always a
safe rollback. Persistent lock files consume small bounded metadata but prevent
split-lock races. Holding a lock during execution intentionally serializes
concurrent processes that compute the same key while allowing unrelated keys
to proceed independently.

The cache is an optimization only: corruption yields a miss, never execution
suppression. Output existence is rechecked from the current recipe contract,
not trusted from an old manifest.
