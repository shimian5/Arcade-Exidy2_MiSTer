# Increment 6 — connected descriptor, length and FAX matrix

Completed 2026-10-06. All 21 connected expectations pass in [results](increment-06.json). Production sources and the loader baseline remain unchanged.

Two full 192 KiB question images exercise FAX and FAX2 profiles through source file-command/GPIO/ACK transport. The FAX synthetic image explicitly leaves banks 22/23 zero; FAX2 fills all 24 banks. Every stored byte and 48 public read-port bank boundary accesses match independent fixture data. This tests profile/storage transport, not actual MAME or full game execution. Banks 24–31 remain a reference-parity gate.

Seventeen malformed-session cases retain reset, revoke expansion readiness and leave speech reads unready: wrong magic/version/mask/reserved/profile/question length/marker pairing; base before descriptor; speech before base; short/long speech; duplicate base; unknown trailing stream after successful speech; descriptor before marker; empty marker; short/long descriptor. The original two complete speech/backpressure positives also pass. These are a bounded set, not every possible malformed stream permutation.

No loader changes were necessary. Full production readiness must combine loader protocol state with adapter faults and quarantine/read enable. Next: actual verified NAS ROM expansion images through the connected transport, then the remaining session/read/reset contract and resource/CDC gates. No Quartus build, hardware deployment or release changes.
