#include "ReturnAudioRing.h"

#include <stdatomic.h>
#include <stdlib.h>
#include <string.h>

struct ReturnAudioRing {
    float *samples;
    uint32_t capacity;
    uint32_t target;
    _Atomic uint64_t write_index;
    _Atomic uint64_t read_index;
    _Atomic float volume;
    _Atomic float last_sample;
    _Atomic bool started;
    _Atomic uint64_t underflows;
    _Atomic uint64_t overflows;
    _Atomic uint64_t shortened_reads;
    _Atomic uint64_t stretched_reads;
    _Atomic uint64_t write_calls;
    _Atomic uint64_t written_frames;
    _Atomic uint64_t render_calls;
    _Atomic uint64_t rendered_frames;
    _Atomic uint32_t maximum_write_frames;
    _Atomic uint32_t maximum_render_frames;
};

static void update_maximum(_Atomic uint32_t *maximum, uint32_t value) {
    uint32_t current = atomic_load_explicit(maximum, memory_order_relaxed);
    while (value > current && !atomic_compare_exchange_weak_explicit(
        maximum, &current, value, memory_order_relaxed, memory_order_relaxed
    )) {}
}

static uint64_t available_frames(const ReturnAudioRing *ring) {
    const uint64_t write = atomic_load_explicit(&ring->write_index, memory_order_acquire);
    const uint64_t read = atomic_load_explicit(&ring->read_index, memory_order_relaxed);
    return write - read;
}

static void fill_with_sample(float *output, uint32_t frame_count, float sample, float volume) {
    const float value = sample * volume;
    for (uint32_t frame = 0; frame < frame_count; ++frame) {
        output[frame] = value;
    }
}

static void resample_consume(
    ReturnAudioRing *ring,
    float *output,
    uint32_t frame_count,
    uint32_t consume,
    uint64_t read,
    float volume
) {
    if (frame_count == 1 || consume == 1) {
        const float sample = ring->samples[read % ring->capacity];
        output[0] = sample * volume;
        atomic_store_explicit(&ring->last_sample, sample, memory_order_relaxed);
        return;
    }

    const double scale = (double)(consume - 1) / (double)(frame_count - 1);
    float last = 0.0f;
    for (uint32_t frame = 0; frame < frame_count; ++frame) {
        const double source_position = (double)frame * scale;
        const uint32_t lower = (uint32_t)source_position;
        const uint32_t upper = lower + 1 < consume ? lower + 1 : lower;
        const float fraction = (float)(source_position - lower);
        const float a = ring->samples[(read + lower) % ring->capacity];
        const float b = ring->samples[(read + upper) % ring->capacity];
        last = a + (b - a) * fraction;
        output[frame] = last * volume;
    }
    atomic_store_explicit(&ring->last_sample, last, memory_order_relaxed);
}

ReturnAudioRing *return_audio_ring_create(uint32_t capacity_frames, uint32_t target_frames) {
    if (capacity_frames < 4 || target_frames >= capacity_frames) {
        return NULL;
    }

    ReturnAudioRing *ring = calloc(1, sizeof(ReturnAudioRing));
    if (ring == NULL) {
        return NULL;
    }

    ring->samples = calloc(capacity_frames, sizeof(float));
    if (ring->samples == NULL) {
        free(ring);
        return NULL;
    }

    ring->capacity = capacity_frames;
    ring->target = target_frames;
    atomic_init(&ring->volume, 1.0f);
    atomic_init(&ring->last_sample, 0.0f);
    return ring;
}

void return_audio_ring_destroy(ReturnAudioRing *ring) {
    if (ring == NULL) {
        return;
    }
    free(ring->samples);
    free(ring);
}

void return_audio_ring_reset(ReturnAudioRing *ring) {
    if (ring == NULL) {
        return;
    }
    atomic_store_explicit(&ring->write_index, 0, memory_order_relaxed);
    atomic_store_explicit(&ring->read_index, 0, memory_order_relaxed);
    atomic_store_explicit(&ring->last_sample, 0.0f, memory_order_relaxed);
    atomic_store_explicit(&ring->started, false, memory_order_relaxed);
    atomic_store_explicit(&ring->underflows, 0, memory_order_relaxed);
    atomic_store_explicit(&ring->overflows, 0, memory_order_relaxed);
    atomic_store_explicit(&ring->shortened_reads, 0, memory_order_relaxed);
    atomic_store_explicit(&ring->stretched_reads, 0, memory_order_relaxed);
    atomic_store_explicit(&ring->write_calls, 0, memory_order_relaxed);
    atomic_store_explicit(&ring->written_frames, 0, memory_order_relaxed);
    atomic_store_explicit(&ring->render_calls, 0, memory_order_relaxed);
    atomic_store_explicit(&ring->rendered_frames, 0, memory_order_relaxed);
    atomic_store_explicit(&ring->maximum_write_frames, 0, memory_order_relaxed);
    atomic_store_explicit(&ring->maximum_render_frames, 0, memory_order_relaxed);
}

void return_audio_ring_set_volume(ReturnAudioRing *ring, float volume) {
    if (ring != NULL) {
        atomic_store_explicit(&ring->volume, volume, memory_order_relaxed);
    }
}

void return_audio_ring_write(ReturnAudioRing *ring, const float *input, uint32_t frame_count) {
    if (ring == NULL || input == NULL || frame_count == 0) {
        return;
    }

    atomic_fetch_add_explicit(&ring->write_calls, 1, memory_order_relaxed);
    atomic_fetch_add_explicit(&ring->written_frames, frame_count, memory_order_relaxed);
    update_maximum(&ring->maximum_write_frames, frame_count);

    uint64_t write = atomic_load_explicit(&ring->write_index, memory_order_relaxed);
    const uint64_t read = atomic_load_explicit(&ring->read_index, memory_order_acquire);
    const uint64_t used = write - read;
    const uint64_t free_frames = used < ring->capacity ? ring->capacity - used : 0;

    if (frame_count > free_frames) {
        atomic_fetch_add_explicit(&ring->overflows, 1, memory_order_relaxed);
        frame_count = (uint32_t)free_frames;
    }

    for (uint32_t frame = 0; frame < frame_count; ++frame) {
        ring->samples[(write + frame) % ring->capacity] = input[frame];
    }

    atomic_store_explicit(&ring->write_index, write + frame_count, memory_order_release);
}

void return_audio_ring_render(ReturnAudioRing *ring, float *output, uint32_t frame_count) {
    if (output == NULL || frame_count == 0) {
        return;
    }
    if (ring == NULL) {
        memset(output, 0, frame_count * sizeof(float));
        return;
    }

    atomic_fetch_add_explicit(&ring->render_calls, 1, memory_order_relaxed);
    atomic_fetch_add_explicit(&ring->rendered_frames, frame_count, memory_order_relaxed);
    update_maximum(&ring->maximum_render_frames, frame_count);

    const float volume = atomic_load_explicit(&ring->volume, memory_order_relaxed);
    uint64_t available = available_frames(ring);
    bool started = atomic_load_explicit(&ring->started, memory_order_relaxed);
    if (!started) {
        if (available < ring->target) {
            fill_with_sample(
                output, frame_count,
                atomic_load_explicit(&ring->last_sample, memory_order_relaxed),
                volume
            );
            return;
        }
        atomic_store_explicit(&ring->started, true, memory_order_relaxed);
    }

    if (available < frame_count) {
        atomic_fetch_add_explicit(&ring->underflows, 1, memory_order_relaxed);
        const uint64_t read = atomic_load_explicit(&ring->read_index, memory_order_relaxed);
        float last = atomic_load_explicit(&ring->last_sample, memory_order_relaxed);

        for (uint32_t frame = 0; frame < (uint32_t)available; ++frame) {
            last = ring->samples[(read + frame) % ring->capacity];
            output[frame] = last * volume;
        }
        for (uint32_t frame = (uint32_t)available; frame < frame_count; ++frame) {
            output[frame] = last * volume;
        }

        atomic_store_explicit(&ring->last_sample, last, memory_order_relaxed);
        if (available > 0) {
            atomic_store_explicit(&ring->read_index, read + available, memory_order_release);
        }
        return;
    }

    uint32_t consume = frame_count;
    // Band scales with target so stretch still works when target is small.
    const uint32_t correction_band = ring->target > 4 ? ring->target / 4 : 1;
    if (available > (uint64_t)ring->target + correction_band && available > frame_count) {
        consume = frame_count + 1;
        atomic_fetch_add_explicit(&ring->shortened_reads, 1, memory_order_relaxed);
    } else if (available + correction_band < ring->target && frame_count > 1) {
        consume = frame_count - 1;
        atomic_fetch_add_explicit(&ring->stretched_reads, 1, memory_order_relaxed);
    }

    const uint64_t read = atomic_load_explicit(&ring->read_index, memory_order_relaxed);
    resample_consume(ring, output, frame_count, consume, read, volume);
    atomic_store_explicit(&ring->read_index, read + consume, memory_order_release);
}

ReturnAudioRingStats return_audio_ring_stats(const ReturnAudioRing *ring) {
    ReturnAudioRingStats stats = {0};
    if (ring == NULL) {
        return stats;
    }
    stats.fill_frames = (uint32_t)available_frames(ring);
    stats.underflows = atomic_load_explicit(&ring->underflows, memory_order_relaxed);
    stats.overflows = atomic_load_explicit(&ring->overflows, memory_order_relaxed);
    stats.shortened_reads = atomic_load_explicit(&ring->shortened_reads, memory_order_relaxed);
    stats.stretched_reads = atomic_load_explicit(&ring->stretched_reads, memory_order_relaxed);
    stats.write_calls = atomic_load_explicit(&ring->write_calls, memory_order_relaxed);
    stats.written_frames = atomic_load_explicit(&ring->written_frames, memory_order_relaxed);
    stats.render_calls = atomic_load_explicit(&ring->render_calls, memory_order_relaxed);
    stats.rendered_frames = atomic_load_explicit(&ring->rendered_frames, memory_order_relaxed);
    stats.maximum_write_frames = atomic_load_explicit(&ring->maximum_write_frames, memory_order_relaxed);
    stats.maximum_render_frames = atomic_load_explicit(&ring->maximum_render_frames, memory_order_relaxed);
    return stats;
}
