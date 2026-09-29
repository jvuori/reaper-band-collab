# Spike 1.3: checksums in pure Lua

Script: `docs/spikes/scripts/checksum_bench.lua` (`BENCH_FILE=<file> [BENCH_OUT=<file>]`; runs in REAPER or plain Lua 5.4).
Test data: 300 MiB (314.6 MB) of random bytes, the worst case for entropy; file was in the OS page cache.
Machine: the developer's Linux desktop. **Numbers for Windows are still to be measured** (task 1.7); the algorithm is integer-only so results should be similar.

## Measurements

| Algorithm | Where | Throughput | Whole 314.6 MB file |
|---|---|---|---|
| 64-bit multiply/xorshift hash over 8-byte words (`string.unpack`, 64 bytes per loop turn) | REAPER's Lua 5.4 | **150 MB/s** | 2.1 s |
| same | plain Lua 5.4 | 174 MB/s | 1.8 s |
| CRC-32 (byte table) | REAPER's Lua 5.4 | 14 MB/s | about 22 s (extrapolated from the first 32 MB) |

- The word-wise hash gives **the identical value in REAPER and in plain Lua** (`ec9e96ffd8bc7090` for the test file), so a manifest written on one machine verifies on another.
- Changing one byte changes the hash (checked).
- CRC-32 is about 11 times slower here because it must process every byte in Lua. A cryptographic hash (SHA-256) would be slower still; it was not measured, since we do not need tamper resistance (see D3: import ignores everything outside the owner's folder).

## Decision

- **Algorithm:** the 64-bit word hash above, recorded in the manifest as `hash64` with a version field, so it can be changed later without ambiguity.
- **Policy:** every file listed in a manifest gets its **size and full-file hash**. Size is compared first (it catches truncated or still-downloading files instantly); the hash is computed only when the size matches.
- **Cost:** about 7 seconds per GB in REAPER. A typical 3 GB rehearsal takes about 20 seconds to hash; that is acceptable if it does not freeze REAPER.
- **Must not block the UI:** hashing runs in slices from the `defer` loop (for example 16-32 MiB per tick, with a progress bar and cancel), never in one long call.
- **Chunk size must be a multiple of 64 bytes** so the result does not depend on how the file was read (the script uses 1 MiB).
- **Not cryptographic.** The manifest protects against incomplete or corrupt sync, not against a person forging files. That is consistent with the design (the producer's tool accepts only the owner's folder from a delivery).

## Still open

- Measure on Windows.
- Measure with a cold cache (disk-bound); the hash itself is fast enough that disk speed will dominate.
