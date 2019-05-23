#include <THC/THCTensorRandom.h>
#include <THC/THCDeviceUtils.cuh>
#include <THC/THCGeneral.h>
#include <THC/THCTensorCopy.h>
#include <THC/THCTensorMath.h>
#include <THC/THCReduceApplyUtils.cuh>
#include <THC/THCTensorRandom.cuh>
#include <THC/THCGenerator.hpp>
#include <ATen/Config.h>

#include <ATen/cuda/_curand_mtgp32_host.h>

#include <thrust/functional.h>

#define MAX_NUM_BLOCKS 200
#define BLOCK_SIZE 256


THCGenerator* THCRandom_getGenerator(THCState* state);

/* Creates a new generator state given the seed. Not thread-safe. */
__host__ void createGeneratorState(THCGenerator* gen, uint64_t seed)
{
  // seed and offset for philox
  gen->state.initial_seed = seed;
  gen->state.philox_seed_offset = 0;
}

THC_API __host__ void THCRandom_getRNGState(THCState* state, THByteTensor *rng_state)
{
  THCGenerator* gen = THCRandom_getGenerator(state);
  std::lock_guard<std::mutex> lock(gen->mutex);

  // The RNG state comprises the seed, and an offset used for Philox
  static const size_t states_size = MAX_NUM_BLOCKS * sizeof(curandStateMtgp32); // this line is just here for BC reason
  static const size_t seed_size = sizeof(gen->state.initial_seed);
  static const size_t offset_size = sizeof(gen->state.philox_seed_offset);
  static const size_t total_size = states_size + seed_size + offset_size;
  THByteTensor_resize1d(rng_state, total_size);
  THArgCheck(THByteTensor_nElement(rng_state) == total_size, 1, "RNG state is wrong size");
  THArgCheck(THByteTensor_isContiguous(rng_state), 1, "RNG state must be contiguous");
  // since curandStateMTGP is not used anymore, fill gen_states of THCGenerator with deterministic garbage value of -1
  memset(THByteTensor_data(rng_state), -1, states_size);
  memcpy(THByteTensor_data(rng_state) + states_size, &gen->state.initial_seed, seed_size);
  memcpy(THByteTensor_data(rng_state) + states_size + seed_size, &gen->state.philox_seed_offset, offset_size);
}

THC_API __host__ void THCRandom_setRNGState(THCState* state, THByteTensor *rng_state)
{
  THCGenerator* gen = THCRandom_getGenerator(state);
  std::lock_guard<std::mutex> lock(gen->mutex);

  static const size_t states_size = MAX_NUM_BLOCKS * sizeof(curandStateMtgp32); // this line is just here for BC reason
  static const size_t seed_size = sizeof(gen->state.initial_seed);
  static const size_t offset_size = sizeof(gen->state.philox_seed_offset);
  static const size_t total_size = states_size + seed_size + offset_size;
  bool no_philox_seed = false;
  if (THByteTensor_nElement(rng_state) == total_size - offset_size) {
    no_philox_seed = true;
  }
  else {
    THArgCheck(THByteTensor_nElement(rng_state) == total_size, 1, "RNG state is wrong size");
  }
  THArgCheck(THByteTensor_isContiguous(rng_state), 1, "RNG state must be contiguous");
  memcpy(&gen->state.initial_seed, THByteTensor_data(rng_state) + states_size, seed_size);
  if (!no_philox_seed) {
    memcpy(&gen->state.philox_seed_offset, THByteTensor_data(rng_state) + states_size + seed_size, offset_size);
  }
  else {
    gen->state.philox_seed_offset = 0;
  }
}

#include <THC/generic/THCTensorRandom.cu>
#include <THC/THCGenerateAllTypes.h>

#include <THC/generic/THCTensorRandom.cu>
#include <THC/THCGenerateBoolType.h>
