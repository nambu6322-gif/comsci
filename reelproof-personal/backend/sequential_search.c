/* ReelProof: sequential search over original-text embedding vectors. */
#include "sequential_search.h"
#include <math.h>
#include <stdint.h>
#include <stdlib.h>

const char *rp_scan_implementation(void) {
    return "c-sequential-cosine-v1";
}

int rp_sequential_search(const float *query, const float *vectors,
                         size_t row_count, size_t dimensions, size_t top_k,
                         int use_threshold, double threshold,
                         size_t *indices, float *scores, size_t *result_count) {
    if (!result_count) return -1;
    *result_count = 0;
    if (!query || !dimensions || dimensions > SIZE_MAX / sizeof(float) ||
        row_count > SIZE_MAX / dimensions ||
        (row_count && !vectors) || (top_k && (!indices || !scores))) return -1;
    if (!top_k) return 0;
    if (use_threshold && !isfinite(threshold)) return -1;

    double squared_norm = 0.0;
    for (size_t d = 0; d < dimensions; ++d) {
        if (!isfinite(query[d])) return -2;
        squared_norm += (double)query[d] * query[d];
    }
    if (!isfinite(squared_norm) || squared_norm == 0.0) return -2;
    float *normalized = malloc(dimensions * sizeof(*normalized));
    if (!normalized) return -3;
    double norm = sqrt(squared_norm);
    for (size_t d = 0; d < dimensions; ++d)
        normalized[d] = (float)(query[d] / norm);

    size_t count = 0;
    /* SEQUENTIAL SEARCH: visit EVERY original-text vector, first to last. */
    for (size_t row = 0; row < row_count; ++row) {
        double dot_product = 0.0;
        for (size_t d = 0; d < dimensions; ++d)
            dot_product += (double)vectors[row * dimensions + d] * normalized[d];
        float similarity = (float)dot_product;
        if (!isfinite(similarity)) continue;
        if (use_threshold && similarity < threshold) continue;

        /* Keep only the best k results. Equal scores keep original order. */
        size_t position = 0;
        while (position < count && scores[position] >= similarity) ++position;
        if (position >= top_k) continue;
        size_t end = count < top_k ? count : top_k - 1;
        for (size_t j = end; j > position; --j) {
            scores[j] = scores[j - 1];
            indices[j] = indices[j - 1];
        }
        scores[position] = similarity;
        indices[position] = row;
        if (count < top_k) ++count;
    }
    free(normalized);
    *result_count = count;
    return 0;
}
