# MC7304 voice capability spike

## Result

- ModemManager exposes `org.freedesktop.ModemManager1.Modem.Voice`, including
  `CreateCall` and `ListCalls`. This confirms the control API is present, not that
  this firmware can complete calls.
- `mmcli -m any --voice-list-calls` returned `No calls were found`.
- The installed firmware is `SWI9X15C_05.05.78.00`; the modem is not registered
  to a cellular network, so no real call was attempted.
- A Sierra Wireless forum support reply says MC73xx firmware 4.x supports voice
  and data, while 5.x is data-only; it also says a data-only version should not
  be upgradeable/downgradeable to a voice-enabled firmware variant. See
  [MC7304 firmware downgrade discussion](https://forum.sierrawireless.com/t/fw-downgrade-for-mc7304-to-4th-gen/7738).
- A separate user reported voice-call signalling with Vodafone-approved
  `SWI9X15C_05.05.39.02`, but not with generic `05.05.58.00`. That is not
  confirmation of incoming calls, audio, or compatibility with this modem's
  `05.05.78.00` firmware. See
  [MC7304 CS voice discussion](https://forum.sierrawireless.com/t/mc7304-cs-voice/8062).

## Decision

Voice calling is **not confirmed and should not be assumed to work** on the
installed data-only firmware. Voice-enabled MC7304 variants/firmware are
reported to exist, but the available reports do not establish a safe firmware
upgrade path for this specific unit. A live call also requires a registered
network and operator support. Do not flash unofficial firmware as a test.
