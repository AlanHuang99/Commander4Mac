# Local performance, October 16, 2026

Measured on Mac16,10, Apple M4, 16 GiB RAM, macOS 27.0.1 (26A434), Xcode 27.0. The data volume is APFS on an external PCI-Express SSD. Native measurements use the signed Debug app installed in `/Applications`; core measurements use the UITest debug configuration. Thumbnails are disabled. Fixtures contain 10,000 simple seven-byte files. Two cached native tabs use different directory entries; the second fixture uses hard links to conserve storage.

Warm means that the same directory's metadata has already been enumerated. No system cache purge was performed. Controlled cold-cache timing is unverified. p95 is the nearest-rank 19th sorted sample of 20. Raw native samples are in [performance-samples.json](performance-samples.json).

| Native metric | Samples | p95 | Target | Scope |
|---|---:|---:|---:|---|
| Warm rows visible | 20 | 357.926 ms | 500 ms | Navigation/refresh request through table layout with loaded rows |
| Cached tab visible | 20 | 29.688 ms | 100 ms | Tab activation through layout of the cached native view |
| Keyboard delivery during copy | 20 | 16.745 ms | 100 ms | NSEvent timestamp through entry into the native key handler |

The last measure is event delivery, not end-to-photon latency. All 20 samples fall between the installed app's running/completed events for an actual 10,000-file copy, which took about 3.3 seconds. Tab changed the active pane during that job; the destination stayed captured. Both 10,000-entry copy outputs were checked. Input rendering was observed but not instrumented through the display compositor.

The core opt-in test separately measured 20 warm listings (p95 199.790 ms), 20 first useful model row preparations (p95 256.103 ms), and 20 main-actor scheduling lateness samples during a recursive copy (p95 2.556 ms). Cached model switching was p95 0.001416 ms. These model numbers are not substitutes for native rendering measurements.

The initial provider fetched package and cloud metadata for every entry and measured p95 849.020 ms. Package metadata is now requested for directories only; data-less placeholder state comes from the SDK's `SF_DATALESS` stat flag. An actual process sample then showed full array equality repeatedly calling `FileLocation.url` and URL standardization from both the native view and Observation's generated setter. Large visible-entry arrays now publish a scalar revision, and selection uses a cached ID-to-row map. Native warm refresh improved from p95 728.424 ms to 357.926 ms. File-copy progress now aggregates actual per-file counts and emits at most approximately every 80 ms plus a final update.

Reproduce the core fixture with `COMMANDER_PERFORMANCE=1 ./script/test.sh LocalPerformanceTests`. Native measurements were driven through the app with CUA while collecting Apple's unified logs in the Performance and Operations categories. The code emits no filenames or document contents into these metrics. Native scrolling was inspected and process-sampled during refresh work; an independent scrolling frame-time/energy benchmark remains unverified.
