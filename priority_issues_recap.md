# Priority Issues Recap

## 1. ~~Playback queue / backpressure on iOS~~ ✅ FIXED

- ~~The biggest issue is likely on the iOS side, not the server.~~
- ~~Audio appears to be queued faster than it is actually played.~~
- ~~`audio_buffer_duration_ms` keeps growing instead of draining, which suggests playback backlog or stalled real-time consumption.~~

**Fixed (2026-03-01):** Three bugs in `AssistantPlaybackEngine` were causing audio to play all at once or be silently dropped:
1. Hard chunk drop removed — the 3000ms backpressure ceiling was silently discarding ~70+ chunks per response on Bluetooth HFP (hardware drains slower than streaming rate). Now logs a warning but never drops audio.
2. `startResponse()` changed from `playerNode.stop()` + `reset()` to `reset()` only — `stop()` was triggering a spurious route-change notification that temporarily disconnected the player node, causing the first scheduled buffer per response to be discarded without decrementing `pendingBufferCount` (+1 phantom leak per response).
3. Operation order in `appendPCMData` corrected — `ensureEngineRunning` + reconnection + `play()` now happen before `pendingBufferCount += 1` and `scheduleBuffer()`, preventing count leaks when `AVAudioEngine.connect()` resets the node mid-chunk.

## 2. Capture buffers are not being trimmed properly

- Audio buffer grows from roughly 10 seconds to more than 130 seconds.
- Video buffer also remains high, around 30 seconds.
- After clip export/upload, old media should be retired, but the logs suggest the rolling buffer is not truly rolling.

## 3. Bluetooth HFP route is a red flag

- Playback route is `BluetoothHFP`, which is often fragile for continuous streamed assistant playback.
- HFP can introduce route instability, low-bandwidth behavior, and AVAudioEngine issues.
- This may be contributing directly to playback slowdown or graph instability.

## 4. AVAudioEngine / player node instability

- The app logs show `Player node disconnected, attempting reconnection`.
- That should not normally happen during stable streaming playback.
- This points to audio session or route change issues that may be causing queued audio to pile up.

## 5. New queries start while old backlog still exists

- A new wakeword/query is triggered while audio/video buffers are already very large.
- That means the system is allowing overlap before the previous media pipeline has truly returned to steady state.
- This can compound latency and make debugging much harder.

## 6. WebSocket disconnect is likely secondary, not the root cause

- The websocket does disconnect and reconnect.
- But the backend itself looks mostly healthy: requests complete, model calls succeed, and the server keeps processing queries.
- The disconnect looks more like a symptom of client-side media/transport stress than the main backend failure.

## Bottom line

The main priority is to debug the iOS media pipeline, especially:

1. playback queue growth,
2. rolling buffer trimming,
3. AVAudioSession / Bluetooth HFP behavior,
4. overlap protection between consecutive queries.
