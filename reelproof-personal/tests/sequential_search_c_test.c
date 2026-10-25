#include "sequential_search.h"
#include <assert.h>
#include <math.h>
#include <stddef.h>

int main(void) {
    const float query[] = {1.0f, 0.0f};
    const float rows[] = {.8f,.6f, .6f,.8f, 1.f,0.f, 1.f,0.f};
    size_t indices[4], count = 99;
    float scores[4];
    assert(rp_sequential_search(query, rows, 4, 2, 2, 0, 0,
                                indices, scores, &count) == 0);
    assert(count == 2 && indices[0] == 2 && indices[1] == 3);
    assert(scores[0] == 1.f && scores[1] == 1.f);
    assert(rp_sequential_search(query, rows, 4, 2, 4, 1, 1.01,
                                indices, scores, &count) == 0 && count == 0);
    assert(rp_sequential_search(query, NULL, 0, 2, 4, 0, 0,
                                indices, scores, &count) == 0 && count == 0);
    assert(rp_sequential_search(query, rows, 4, 2, 0, 0, 0,
                                NULL, NULL, &count) == 0 && count == 0);
    const float zero[] = {0.f, 0.f};
    const float bad[] = {NAN, 0.f};
    assert(rp_sequential_search(zero, rows, 4, 2, 4, 0, 0,
                                indices, scores, &count) == -2 && count == 0);
    assert(rp_sequential_search(bad, rows, 4, 2, 4, 0, 0,
                                indices, scores, &count) == -2);
    assert(rp_sequential_search(query, rows, 4, 0, 4, 0, 0,
                                indices, scores, &count) == -1);
    return 0;
}
