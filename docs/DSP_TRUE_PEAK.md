# True-peak limiter

## Design

| Feature | Value |
|---------|--------|
| Oversampling | 4× linear inter-sample peak detect |
| Look-ahead | ~3 ms delay line (per channel, fixed max 512) |
| Ceiling | −1.0 dBFS (headphones) / −1.5 dBFS (speaker) |
| Attack | ~0.5–1 ms |
| Release | ~60–100 ms |
| Gain floor | 0.05 (−26 dB) to avoid mute zipper |

## Chain position

```
… → DVC → true-peak limiter → soft-clip → out
```

DVC cannot defeat the ceiling; soft-clip is a last-resort net only.

## Hardening

- NaN/Inf sanitize on input and after biquads
- EQ gain clamped ±24 dB
- All delay/scratch memory allocated at `dsp_create`
