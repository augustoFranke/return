#ifndef RETURN_AUDIO_RING_H
#define RETURN_AUDIO_RING_H

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct ReturnAudioRing ReturnAudioRing;

typedef struct {
    uint32_t fill_frames;
    uint32_t target_frames;
    uint64_t underflows;
    uint64_t overflows;
    uint64_t shortened_reads;
    uint64_t stretched_reads;
    uint64_t write_calls;
    uint64_t written_frames;
    uint64_t render_calls;
    uint64_t rendered_frames;
    uint32_t maximum_write_frames;
    uint32_t maximum_render_frames;
} ReturnAudioRingStats;

ReturnAudioRing *return_audio_ring_create(uint32_t capacity_frames, uint32_t target_frames);
void return_audio_ring_destroy(ReturnAudioRing *ring);
void return_audio_ring_reset(ReturnAudioRing *ring);
void return_audio_ring_set_volume(ReturnAudioRing *ring, float volume);
void return_audio_ring_write(ReturnAudioRing *ring, const float *input, uint32_t frame_count);
void return_audio_ring_render(ReturnAudioRing *ring, float *output, uint32_t frame_count);
ReturnAudioRingStats return_audio_ring_stats(const ReturnAudioRing *ring);

#ifdef __cplusplus
}
#endif

#endif
