#include <stdio.h>
#include <stdint.h>
#include <string.h>
#include "cuda.h"
#include "cuda_runtime.h"
#include "cryptonight.h"

#ifndef _WIN32
#include <unistd.h>
#endif

#ifdef __CUDACC__
__constant__
#else
const
#endif
uint64_t keccakf_rndc[24] ={
                            0x0000000000000001, 0x0000000000008082, 0x800000000000808a,
                            0x8000000080008000, 0x000000000000808b, 0x0000000080000001,
                            0x8000000080008081, 0x8000000000008009, 0x000000000000008a,
                            0x0000000000000088, 0x0000000080008009, 0x000000008000000a,
                            0x000000008000808b, 0x800000000000008b, 0x8000000000008089,
                            0x8000000000008003, 0x8000000000008002, 0x8000000000000080,
                            0x000000000000800a, 0x800000008000000a, 0x8000000080008081,
                            0x8000000000008080, 0x0000000080000001, 0x8000000080008008
};

typedef unsigned char BitSequence;
typedef unsigned long long DataLength;

static uint32_t *d_input[8];
static uint32_t *d_target[8];
static uint32_t *d_resultNonce[8];

#include "cuda_cryptonight_keccak.hpp"
#include "cuda_cryptonight_blake.hpp"
#include "cuda_cryptonight_groestl.hpp"
#include "cuda_cryptonight_jh.hpp"
#include "cuda_cryptonight_skein.hpp"
#include "cuda_device.hpp"

__constant__ uint8_t d_sub_byte[16][16] ={
    {0x63, 0x7c, 0x77, 0x7b, 0xf2, 0x6b, 0x6f, 0xc5, 0x30, 0x01, 0x67, 0x2b, 0xfe, 0xd7, 0xab, 0x76 },
    {0xca, 0x82, 0xc9, 0x7d, 0xfa, 0x59, 0x47, 0xf0, 0xad, 0xd4, 0xa2, 0xaf, 0x9c, 0xa4, 0x72, 0xc0 },
    {0xb7, 0xfd, 0x93, 0x26, 0x36, 0x3f, 0xf7, 0xcc, 0x34, 0xa5, 0xe5, 0xf1, 0x71, 0xd8, 0x31, 0x15 },
    {0x04, 0xc7, 0x23, 0xc3, 0x18, 0x96, 0x05, 0x9a, 0x07, 0x12, 0x80, 0xe2, 0xeb, 0x27, 0xb2, 0x75 },
    {0x09, 0x83, 0x2c, 0x1a, 0x1b, 0x6e, 0x5a, 0xa0, 0x52, 0x3b, 0xd6, 0xb3, 0x29, 0xe3, 0x2f, 0x84 },
    {0x53, 0xd1, 0x00, 0xed, 0x20, 0xfc, 0xb1, 0x5b, 0x6a, 0xcb, 0xbe, 0x39, 0x4a, 0x4c, 0x58, 0xcf },
    {0xd0, 0xef, 0xaa, 0xfb, 0x43, 0x4d, 0x33, 0x85, 0x45, 0xf9, 0x02, 0x7f, 0x50, 0x3c, 0x9f, 0xa8 },
    {0x51, 0xa3, 0x40, 0x8f, 0x92, 0x9d, 0x38, 0xf5, 0xbc, 0xb6, 0xda, 0x21, 0x10, 0xff, 0xf3, 0xd2 },
    {0xcd, 0x0c, 0x13, 0xec, 0x5f, 0x97, 0x44, 0x17, 0xc4, 0xa7, 0x7e, 0x3d, 0x64, 0x5d, 0x19, 0x73 },
    {0x60, 0x81, 0x4f, 0xdc, 0x22, 0x2a, 0x90, 0x88, 0x46, 0xee, 0xb8, 0x14, 0xde, 0x5e, 0x0b, 0xdb },
    {0xe0, 0x32, 0x3a, 0x0a, 0x49, 0x06, 0x24, 0x5c, 0xc2, 0xd3, 0xac, 0x62, 0x91, 0x95, 0xe4, 0x79 },
    {0xe7, 0xc8, 0x37, 0x6d, 0x8d, 0xd5, 0x4e, 0xa9, 0x6c, 0x56, 0xf4, 0xea, 0x65, 0x7a, 0xae, 0x08 },
    {0xba, 0x78, 0x25, 0x2e, 0x1c, 0xa6, 0xb4, 0xc6, 0xe8, 0xdd, 0x74, 0x1f, 0x4b, 0xbd, 0x8b, 0x8a },
    {0x70, 0x3e, 0xb5, 0x66, 0x48, 0x03, 0xf6, 0x0e, 0x61, 0x35, 0x57, 0xb9, 0x86, 0xc1, 0x1d, 0x9e },
    {0xe1, 0xf8, 0x98, 0x11, 0x69, 0xd9, 0x8e, 0x94, 0x9b, 0x1e, 0x87, 0xe9, 0xce, 0x55, 0x28, 0xdf },
    {0x8c, 0xa1, 0x89, 0x0d, 0xbf, 0xe6, 0x42, 0x68, 0x41, 0x99, 0x2d, 0x0f, 0xb0, 0x54, 0xbb, 0x16 }
};

__device__ __forceinline__ void cryptonight_aes_set_key( uint32_t * __restrict__ key, const uint32_t * __restrict__ data )
{
    int i, j;
    uint8_t temp[4];
    const uint32_t aes_gf[] ={
                              0x01, 0x02, 0x04, 0x08, 0x10, 0x20, 0x40, 0x80, 0x1b, 0x36
    };

    MEMSET4( key, 0, 40 );
    MEMCPY4( key, data, 8 );
#pragma unroll
    for ( i = 8; i < 40; i++ )
    {
        *(uint32_t *) temp = key[i - 1];
        if ( i % 8 == 0 )
        {
            *(uint32_t *) temp = ROTR32( *(uint32_t *) temp, 8 );
            for ( j = 0; j < 4; j++ )
                temp[j] = d_sub_byte[( temp[j] >> 4 ) & 0x0f][temp[j] & 0x0f];
            *(uint32_t *) temp ^= aes_gf[i / 8 - 1];
        }
        else
            if ( i % 8 == 4 )
#pragma unroll
            for ( j = 0; j < 4; j++ )
                temp[j] = d_sub_byte[( temp[j] >> 4 ) & 0x0f][temp[j] & 0x0f];
        key[i] = key[( i - 8 )] ^ *(uint32_t *) temp;
    }
}

__global__ void cryptonight_extra_gpu_prepare( int threads, uint32_t * __restrict__ d_input, uint32_t startNonce,
	uint32_t * __restrict__ d_ctx_state, uint32_t * __restrict__ d_ctx_a,
	uint32_t * __restrict__ d_ctx_b, uint32_t * __restrict__ d_ctx_key1, uint32_t * __restrict__ d_ctx_key2,
	int variant, uint32_t * d_ctx_tweak1_2
	)
{
    int thread = ( blockDim.x * blockIdx.x + threadIdx.x );

    if ( thread < threads )
    {
        uint32_t ctx_state[50];
        uint32_t ctx_a[4];
        uint32_t ctx_b[4];
        uint32_t ctx_key1[40];
        uint32_t ctx_key2[40];
        uint32_t input[19];
		uint32_t tweak1_2[2];

        MEMCPY4( input, d_input, 19 );
        //*((uint32_t *)(((char *)input) + 39)) = startNonce + thread;
        uint32_t nonce = startNonce + thread;
        for ( int i = 0; i < sizeof (uint32_t ); ++i )
            ( ( (char *) input ) + 39 )[i] = ( (char*) ( &nonce ) )[i]; //take care of pointer alignment

        cn_keccak( (uint8_t *) input, (uint8_t *) ctx_state );
        cryptonight_aes_set_key( ctx_key1, ctx_state );
        cryptonight_aes_set_key( ctx_key2, ctx_state + 8 );
        XOR_BLOCKS_DST( ctx_state, ctx_state + 8, ctx_a );
        XOR_BLOCKS_DST( ctx_state + 4, ctx_state + 12, ctx_b );

		if (variant > 0)
 		{
 			tweak1_2[0] = (input[8] >> 24) | (input[9] << 8);
			tweak1_2[0] ^= ctx_state[48];
			tweak1_2[1] = nonce;
			tweak1_2[1] ^= ctx_state[49];
			MEMCPY4(d_ctx_tweak1_2 + thread * 2, tweak1_2, 2);
		}

        memcpy( d_ctx_state + thread * 50, ctx_state, 50 * 4 );
        memcpy( d_ctx_a + thread * 4, ctx_a, 4 * 4 );
        memcpy( d_ctx_b + thread * 4, ctx_b, 4 * 4 );
        memcpy( d_ctx_key1 + thread * 40, ctx_key1, 40 * 4 );
        memcpy( d_ctx_key2 + thread * 40, ctx_key2, 40 * 4 );
    }
}

__global__ void cryptonight_extra_gpu_final( int threads, uint32_t startNonce, const uint32_t * __restrict__ d_target, uint32_t * __restrict__ resNonce, uint32_t * __restrict__ d_ctx_state )
{
    const int thread = blockDim.x * blockIdx.x + threadIdx.x;

    if ( thread < threads )
    {
        int i;
        const uint32_t nonce = startNonce + thread;
        uint32_t * __restrict__ ctx_state = d_ctx_state + thread * 50;
        uint32_t hash[8];
        uint32_t state[50];

#pragma unroll
        for ( i = 0; i < 50; i++ )
            state[i] = ctx_state[i];

        cn_keccakf2( (uint64_t *) state );

        switch ( ( (uint8_t *) state )[0] & 0x03 )
        {
        case 0:
            cn_blake( (const uint8_t *) state, 200, (uint8_t *) hash );
            break;
        case 1:
            cn_groestl( (const BitSequence *) state, 200, (BitSequence *) hash );
            break;
        case 2:
            cn_jh( (const BitSequence *) state, 200, (BitSequence *) hash );
            break;
        case 3:
            cn_skein( (const BitSequence *) state, 200, (BitSequence *) hash );
            break;
        default:
            break;
        }

        int position = -1;
        bool rc = true;

#pragma unroll 8
        for ( i = 7; i >= 0; i-- )
        {
            if ( hash[i] > d_target[i] )
            {
                if ( position < i )
                {
                    position = i;
                    rc = false;
                }
            }
            if ( hash[i] < d_target[i] )
            {
                if ( position < i )
                {
                    position = i;
                    rc = true;
                }
            }
        }

        if ( rc == true )
        {
            uint32_t tmp = atomicExch( resNonce, nonce );
            if ( tmp != 0xffffffff )
                resNonce[1] = tmp;
        }
    }
}

__host__ void cryptonight_extra_cpu_setData( int thr_id, const void *data, const void *pTargetIn )
{
    cudaMemcpy( d_input[thr_id], data, 19 * sizeof (uint32_t ), cudaMemcpyHostToDevice );
    cudaMemcpy( d_target[thr_id], pTargetIn, 8 * sizeof (uint32_t ), cudaMemcpyHostToDevice );
    exit_if_cudaerror( thr_id, __FILE__, __LINE__ );
}

__host__ void cryptonight_extra_cpu_init( int thr_id )
{
    cudaMalloc( &d_input[thr_id], 19 * sizeof (uint32_t ) );
    cudaMalloc( &d_target[thr_id], 8 * sizeof (uint32_t ) );
    cudaMalloc( &d_resultNonce[thr_id], 2 * sizeof (uint32_t ) );
    exit_if_cudaerror( thr_id, __FILE__, __LINE__ );
}

__host__ void cryptonight_extra_cpu_prepare( int thr_id, int threads, uint32_t startNonce, uint32_t *d_ctx_state, uint32_t *d_ctx_a, uint32_t *d_ctx_b, uint32_t *d_ctx_key1, uint32_t *d_ctx_key2, int variant, uint32_t *d_ctx_tweak1_2 )
{
    int threadsperblock = 128;

    dim3 grid( ( threads + threadsperblock - 1 ) / threadsperblock );
    dim3 block( threadsperblock );

    cryptonight_extra_gpu_prepare<<<grid, block >>>( threads, d_input[thr_id], startNonce, d_ctx_state, d_ctx_a, d_ctx_b, d_ctx_key1, d_ctx_key2, variant, d_ctx_tweak1_2 );
    exit_if_cudaerror( thr_id, __FILE__, __LINE__ );
}

__host__ void cryptonight_extra_cpu_final( int thr_id, int threads, uint32_t startNonce, uint32_t *resnonce, uint32_t *d_ctx_state )
{
    int threadsperblock = 128;

    dim3 grid( ( threads + threadsperblock - 1 ) / threadsperblock );
    dim3 block( threadsperblock );

    cudaMemset( d_resultNonce[thr_id], 0xFF, 2 * sizeof (uint32_t ) );
    exit_if_cudaerror( thr_id, __FILE__, __LINE__ );
    cryptonight_extra_gpu_final<<<grid, block >>>( threads, startNonce, d_target[thr_id], d_resultNonce[thr_id], d_ctx_state );
    exit_if_cudaerror( thr_id, __FILE__, __LINE__ );
    cudaMemcpy( resnonce, d_resultNonce[thr_id], 2 * sizeof (uint32_t ), cudaMemcpyDeviceToHost );
    exit_if_cudaerror( thr_id, __FILE__, __LINE__ );
}
