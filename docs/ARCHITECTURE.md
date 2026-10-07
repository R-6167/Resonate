# DSP ENGINE architecture

## Goals

- Ultra-low latency (small buffers, fixed state, no RT alloc)
- Loud bass without hard clipping or stereo image shift
- Portable C ABI for embedding (Android NDK, desktop, etc.)

## Chain

1. Multi-band EQ (peaking biquads)
2. Speaker path (HPF + virtual bass) when enabled
3. Partial headroom from max positive EQ gain
4. DVC (linear volume)
5. Stereo-linked true-peak limiter (look-ahead + 4× OS detector)
6. Soft-clip safety net

## Real-time rules

- `dsp_process` / `dsp_process_pcm16` never allocate
- Scratch buffers owned by handle
- Look-ahead ~4 ms
