#include "GPU_SM4.h"

#define test_blocks (1<<25)

void __global__ add(const int* x, const int* y, int* z, const int N)
{
	const int n = blockDim.x * blockIdx.x + threadIdx.x;

	if (n < N)
	{
		for (int i = 0; i < 10000; ++i)
		{
			z[n] = x[n] + y[n];
		}
	}
}
int main()
{
	
	//u1 * key;
	//cudaMallocManaged(&key,sizeof(u1)*16);
	u1* key = new u1[sizeof(u1) * 16];
	//u1 * p;
	//cudaMallocManaged(&p,sizeof(u1)*16*test_blocks);
	u1* p = new u1[sizeof(u1) * 16 * test_blocks];
	//u1 *c;
	//cudaMallocManaged(&c,sizeof(u1)*16*test_blocks);
	u1* c = new u1[sizeof(u1) * 16 * test_blocks];


	u1 p2[SM4_BLOCK_SIZE] = {0x01, 0x23, 0x45, 0x67, 0x89, 0xab, 0xcd, 0xef, 0xfe, 0xdc, 0xba, 0x98, 0x76, 0x54, 0x32, 0x10};

	u1 key2[SM4_KEY_SIZE] = {0x01, 0x23, 0x45, 0x67, 0x89, 0xab, 0xcd, 0xef, 0xfe, 0xdc, 0xba, 0x98, 0x76, 0x54, 0x32, 0x10};
	for (int i=0; i<16; i++)
	{
		key[i] = key2[i];
	}

  for (int i=0; i<test_blocks*16; i++)
  {
    p[i] = p2[i%16];
  }
  u1* d_key;
  u1* d_p;
  u1* d_c;
  cudaMalloc((void**)&d_key, sizeof(u1) * 16);
  cudaMalloc((void**)&d_p, sizeof(u1) * 16 * test_blocks);
  cudaMalloc((void**)&d_c, sizeof(u1) * 16 * test_blocks);
  cudaMemcpy(d_key, key, sizeof(u1) * 16, cudaMemcpyHostToDevice);
  cudaMemcpy(d_p, p, sizeof(u1) * 16 * test_blocks, cudaMemcpyHostToDevice);
  cudaMemcpy(d_c, c, sizeof(u1) * 16 * test_blocks, cudaMemcpyHostToDevice);
  gpu_sm4_encrypt(d_p,d_key,d_c,4);
  cudaMemcpy(c, d_c, sizeof(u1) * 16 * test_blocks, cudaMemcpyDeviceToHost);
  outputChar(c, 16*4);

  gpu_sm4_decrypt(d_p,d_key,d_c,4);
  cudaMemcpy(p, d_p, sizeof(u1) * 16 * test_blocks, cudaMemcpyDeviceToHost);
  outputChar(p, 16*4);

	//benchmark

	int* d_x, * d_y, * d_z;
	
	
  
  
	
	//double tt = (double)(elapsed_time) / (100);
	//double speed = (double)(16 * 1 << 4) / (1024 * 1024 * tt);
	//printf("SM4_encrypt>>> blocks: %d, time: %f s, speed: %f MB/s\n", 1 << 4, tt, speed);
	benchmark_sm4_encrypt(p, key, c, d_p, d_key, d_c, 1 << 4);
	benchmark_sm4_decrypt(p,key,c, d_p, d_key, d_c,1<<4);

	benchmark_sm4_encrypt(p,key,c, d_p, d_key, d_c,1<<8);
	benchmark_sm4_decrypt(p,key,c, d_p, d_key, d_c,1<<8);

	benchmark_sm4_encrypt(p,key,c, d_p, d_key, d_c,1<<10);
	benchmark_sm4_decrypt(p,key,c, d_p, d_key, d_c,1<<10);

	benchmark_sm4_encrypt(p,key,c, d_p, d_key, d_c,1<<12);
	benchmark_sm4_decrypt(p,key,c, d_p, d_key, d_c,1<<12);

	benchmark_sm4_encrypt(p,key,c, d_p, d_key, d_c,1<<16);
	benchmark_sm4_decrypt(p,key,c, d_p, d_key, d_c,1<<16);

	benchmark_sm4_encrypt(p,key,c, d_p, d_key, d_c,1<<18);
	benchmark_sm4_decrypt(p,key,c, d_p, d_key, d_c,1<<18);

	benchmark_sm4_encrypt(p,key,c, d_p, d_key, d_c,1<<20);
	benchmark_sm4_decrypt(p,key,c, d_p, d_key, d_c,1<<20);

	benchmark_sm4_encrypt(p,key,c, d_p, d_key, d_c, 1 << 25);
	benchmark_sm4_decrypt(p,key,c, d_p, d_key, d_c, 1 << 25);
}
