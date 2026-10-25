#ifndef REELPROOF_SEQUENTIAL_SEARCH_H
#define REELPROOF_SEQUENTIAL_SEARCH_H
#include <stddef.h>

/* Stored rows are normalized vectors. Output is sorted by descending cosine
 * similarity, preserving input order for ties. Returns 0 on success, -1 for
 * invalid dimensions/pointers, -2 for an invalid query, -3 for allocation failure.
 */
int rp_sequential_search(const float *query, const float *vectors,
                         size_t row_count, size_t dimensions, size_t top_k,
                         int use_threshold, double threshold,
                         size_t *indices, float *scores, size_t *result_count);
const char *rp_scan_implementation(void);
#endif
