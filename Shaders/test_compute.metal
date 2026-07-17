#include <metal_stdlib>
using namespace metal;


kernel void compute_test(device float   *output [[ buffer(0) ]],
                         constant float &time   [[ buffer(1) ]],
                         uint id [[ thread_position_in_grid ]])
{
    // Try swapping sin -> cos, or changing the multiplier, then save.
    output[id] = cos(time + id * 0.25);
}
