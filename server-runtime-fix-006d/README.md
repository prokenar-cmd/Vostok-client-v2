# VOSTOK SERVER RUNTIME FIX 006D

Stack target: current server Candidate 006C (compile PASS, runtime gate still pending).

The installer scans Desktop for the current `new.pwn` and refuses unrelated sources.

Changes are deliberately narrow:
- Courier marker: moves only Courier-owned 005E4 map-icon operations from slot 96 to dedicated slot 95, avoiding collision with other personal navigation while preserving donor GPS slot 98.
- Rental: self-heals a stale rental guard only when the source proves that the guarded state is a native GTA vehicle id. It does NOT blindly remove the one-rental protection.
- Keeps 006C model viewer/prokat/current gameplay; DB is untouched.
- Creates source backup and `VOSTOK_SERVER_006D_PATCH_REPORT.txt`.

Run:
`0_APPLY_SERVER_FIX_006D.cmd`

Then compile as usual. This is a Candidate until compile + runtime smoke.
