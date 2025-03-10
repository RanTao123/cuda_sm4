#include "GPU_SM4.h"
//#include "cuda_uint128.h"

//__device__ int cube(int x)
//{
//	int y;
//	asm(".reg .u32 t1;\n\t"              // temp reg t1
//		" mul.lo.u32 t1, %1, %1;\n\t"    // t1 = x * x
//		" mul.lo.u32 %0, t1, %1;"        // y = t1 * x
//		: "=r"(y) : "r" (x));
//	return y;
//}

//template<typename T>
//__device__ __forceinline__ u1 get_byte(size_t byte_num, T input)
//{
//   return static_cast<u1>(
//	   input >> ((sizeof(T) - 1 - (byte_num & (sizeof(T) - 1))) << 3)
//      );
//}


template<typename T>
__device__ __forceinline__ u1 get_byte(size_t byte_num, T input)
{
	u4 result, t1;
	asm(
		"and.b32 %4, %1, %3;\n"    // r3 = byte_num & (sizeof(T)-1)
		"sub.u32 %4, %3, %4;\n"    // r4 = sizeof(T)-1 - r3
		"shl.b32 %4, %4, 3;\n"     // r5 = r4 << 3
		"shr.b32 %0, %2, %4;\n"    // r6 = input >> r5
		: "=r"((result))              // Output: result
		: "r"(static_cast<u4>(byte_num)),            // Input: byte_num
		"r"(input),               // Input: input
		"n"(sizeof(T) - 1),          // Constant: sizeof(T)-1
		"r"(t1)
		);
	//u1 res = static_cast<u1>(result);
	return (result);
}

template<typename T>
__device__ __forceinline__ T load_be(const uint8_t in[], size_t off)
{
   in += off * sizeof(T);
   T out = 0;
   for(size_t i = 0; i != sizeof(T); ++i)
      out = static_cast<T>((out << 8) | in[i]);
   return out;
}


__device__ __forceinline__ void store_be(uint32_t in, uint8_t out[4])
{
   out[0] = get_byte(0, in);
   out[1] = get_byte(1, in);
   out[2] = get_byte(2, in);
   out[3] = get_byte(3, in);
}


template<typename T>
__device__ __forceinline__ void store_be(uint8_t out[], T x0, T x1)
{
   store_be(x0, out + (0 * sizeof(T)));
   store_be(x1, out + (1 * sizeof(T)));
}

template<typename T>
__device__ __forceinline__ void store_be(uint8_t out[], T x0, T x1, T x2, T x3)
{
   store_be(x0, out + (0 * sizeof(T)));
   store_be(x1, out + (1 * sizeof(T)));
   store_be(x2, out + (2 * sizeof(T)));
   store_be(x3, out + (3 * sizeof(T)));
}

template<size_t ROT, typename T>
__device__ __forceinline__ T rotl(T input)
{
	// static_assert(ROT > 0 && ROT < 8*sizeof(T), "Invalid rotation constant");
	return static_cast<T>((input << ROT) | (input >> (8*sizeof(T) - ROT)));
}



__device__ __forceinline__ uint32_t make_uint32(uint8_t i0, uint8_t i1, uint8_t i2, uint8_t i3)
{
   return ((static_cast<uint32_t>(i0) << 24) |
           (static_cast<uint32_t>(i1) << 16) |
           (static_cast<uint32_t>(i2) <<  8) |
           (static_cast<uint32_t>(i3)));
}


// Variant of T for key schedule
__device__ __forceinline__ u4 SM4_Tp(u4 b)
{
	const u4 t = make_uint32(Sbox[get_byte(0,b)], Sbox[get_byte(1,b)], Sbox[get_byte(2,b)], Sbox[get_byte(3,b)]);

	// L' linear transform
	return t ^ rotl<13>(t) ^ rotl<23>(t);
}


__device__ __forceinline__ u4 SM4_T(u4 b)
{
	return Sbox_T[get_byte(0,b)] ^ (Sbox_T8[get_byte(1,b)]) ^ (Sbox_T16[get_byte(2,b)]) ^ (Sbox_T24[get_byte(3,b)]);
	// return Sbox_T[get_byte(0,b)] ^ rotr<8>(Sbox_T[get_byte(1,b)]) ^ rotr<16>(Sbox_T[get_byte(2,b)]) ^ rotr<24>(Sbox_T[get_byte(3,b)]);
}


//key explansion

__global__ void SM4_key_schedule(const u1 key[SM4_KEY_SIZE], u4 rkey[SM4_RND_KEY_SIZE / sizeof(u4)])
{
	// System parameter or family key
	const u4 FK[4] = { 0xa3b1bac6, 0x56aa3350, 0x677d9197, 0xb27022dc };

	const u4 CK[32] = {
	0x00070E15, 0x1C232A31, 0x383F464D, 0x545B6269,
	0x70777E85, 0x8C939AA1, 0xA8AFB6BD, 0xC4CBD2D9,
	0xE0E7EEF5, 0xFC030A11, 0x181F262D, 0x343B4249,
	0x50575E65, 0x6C737A81, 0x888F969D, 0xA4ABB2B9,
	0xC0C7CED5, 0xDCE3EAF1, 0xF8FF060D, 0x141B2229,
	0x30373E45, 0x4C535A61, 0x686F767D, 0x848B9299,
	0xA0A7AEB5, 0xBCC3CAD1, 0xD8DFE6ED, 0xF4FB0209,
	0x10171E25, 0x2C333A41, 0x484F565D, 0x646B7279
  };

	u4 K[4];

	K[0] = load_be<u4>(key, 0) ^ FK[0];
	K[1] = load_be<u4>(key, 1) ^ FK[1];
	K[2] = load_be<u4>(key, 2) ^ FK[2];
	K[3] = load_be<u4>(key, 3) ^ FK[3];

	forloop (i, 0, 32)
	{
		K[i % 4] ^= SM4_Tp(K[(i+1)%4] ^ K[(i+2)%4] ^ K[(i+3)%4] ^ CK[i]);
		rkey[i] = K[i % 4];
	}
}

__device__ void SM4_enc_block(const u1 in[SM4_BLOCK_SIZE], u1 out[SM4_BLOCK_SIZE], const u4 rkey[SM4_RND_KEY_SIZE / sizeof(u4)])
{
  u4 B0 = load_be<u4>(in, 0);
  u4 B1 = load_be<u4>(in, 1);
  u4 B2 = load_be<u4>(in, 2);
  u4 B3 = load_be<u4>(in, 3);

  // SM4_RNDS( 0,  1,  2,  3, SM4_T_slow);
  SM4_RNDS( 0,  1,  2,  3, SM4_T);
  SM4_RNDS( 4,  5,  6,  7, SM4_T);
  SM4_RNDS( 8,  9, 10, 11, SM4_T);
  SM4_RNDS(12, 13, 14, 15, SM4_T);
  SM4_RNDS(16, 17, 18, 19, SM4_T);
  SM4_RNDS(20, 21, 22, 23, SM4_T);
  SM4_RNDS(24, 25, 26, 27, SM4_T);
  SM4_RNDS(28, 29, 30, 31, SM4_T);
  // SM4_RNDS(28, 29, 30, 31, SM4_T_slow);

  store_be(out, B3, B2, B1, B0);
}

__device__ void SM4_dec_block(const u1 in[SM4_BLOCK_SIZE], u1 out[SM4_BLOCK_SIZE], const u4 rkey[SM4_RND_KEY_SIZE / sizeof (u4)])
{
	u4 B0 = load_be<u4>(in, 0);
	u4 B1 = load_be<u4>(in, 1);
	u4 B2 = load_be<u4>(in, 2);
	u4 B3 = load_be<u4>(in, 3);

	// SM4_RNDS(31, 30, 29, 28, SM4_T_slow);
	SM4_RNDS(31, 30, 29, 28, SM4_T);
	SM4_RNDS(27, 26, 25, 24, SM4_T);
	SM4_RNDS(23, 22, 21, 20, SM4_T);
	SM4_RNDS(19, 18, 17, 16, SM4_T);
	SM4_RNDS(15, 14, 13, 12, SM4_T);
	SM4_RNDS(11, 10,  9,  8, SM4_T);
	SM4_RNDS( 7,  6,  5,  4, SM4_T);
	SM4_RNDS( 3,  2,  1,  0, SM4_T);
	// SM4_RNDS( 3,  2,  1,  0, SM4_T_slow);

	store_be(out, B3, B2, B1, B0);
}




__global__ void SM4_dec_blocks(int n_block, const u1 *in, u1 *out, const u4 *rkey)
{
  int index = blockIdx.x*blockDim.x+threadIdx.x;
  int stride = blockDim.x*gridDim.x;
 /* int cur_idx = threadIdx.x;
  __shared__ u1 sm1[128 * (SM4_BLOCK_SIZE + 1)];
  __shared__ u1 sm2[128 * (SM4_BLOCK_SIZE + 1)];*/
  for (int i = index; i < n_block; i += stride) {
	  SM4_dec_block(in+16*i, out+16*i, rkey);
	  /*for (int j = 0;j < SM4_BLOCK_SIZE;j++) {
		  sm1[cur_idx * 16 + j] = in[16 * i + j];
	  }
	  SM4_dec_block(sm1 + cur_idx * 16, sm2 + cur_idx * 16, rkey);
	  for (int j = 0;j < SM4_BLOCK_SIZE;j++) {
		  out[16 * i + j] = sm2[cur_idx * 16 + j];
	  }*/
  }
}



__host__ __device__ void SM4Crypt(const u1* input, const u1* output, const u4* rk, int flag = 0, const u1* plaintext = NULL) {
	//
	u4 r, mid, x0, x1, x2, x3, * p;
	p = (u4*)input;
	x0 = p[0]; x1 = p[1]; x2 = p[2]; x3 = p[3];

	//

	for(r = 0; r < 32; r += 4){
		mid = x1 ^ x2 ^ x3 ^ rk[r + 0];
		mid = S_box(mid);
		x0 ^= L1(mid);
		mid = x2 ^ x3 ^ x0 ^ rk[r + 1];
		mid = S_box(mid);
		x1 ^= L1(mid);
		mid = x3 ^ x0 ^ x1 ^ rk[r + 2];
		mid = S_box(mid);
		x2 ^= L1(mid);
		mid = x0 ^ x1 ^ x2 ^ rk[r + 3];
		mid = S_box(mid);
		x3 ^= L1(mid);
	}

	p = (u4*)output;
	p[0] = x3;
	p[1] = x2;
	p[2] = x1;
	p[3] = x0;

	if (flag == 1) {
		u4* ct;
		ct = (u4*)plaintext;
		p[0] ^= ct[0]; p[1] ^= ct[1]; p[2] ^= ct[2]; p[3] ^= ct[3];
	}
}

__global__ void SM4_enc_blocks(int n_block, u1* in, u1* out, const u4* rkey)
{

	int index = blockIdx.x * blockDim.x + threadIdx.x;
	int stride = blockDim.x * gridDim.x;
	int cur_idx = threadIdx.x;
	__shared__ u1 sm1[256*16];
	//__shared__ u1 sm2[128 * (SM4_BLOCK_SIZE + 1)];
	for (int i = index; i < n_block; i += stride) {
		//SM4_enc_block(in + 16 * i, out + 16 * i, rkey);

		//reinterpret_cast<u8*>(sm1)[cur_idx] = reinterpret_cast<u8*>(in)[16 * i];
		//u8* ptr;
		//u8 value;

		//ptr = reinterpret_cast<u8*>(sm1 + 16 * cur_idx) ;  // 计算第 cur_idx 行的第 8 个元素的位置
		//value = reinterpret_cast<u8*>(in)[16 * i];
		//*ptr = value;

		//ptr = reinterpret_cast<u8*>(sm1 + 16 * cur_idx + 8);  // 计算第 cur_idx 行的第 8 个元素的位置
		//value = reinterpret_cast<u8*>(in)[16 * i + 8];
		//*ptr = value;
		/*sm1[cur_idx][0] = lo[0];
		sm1[cur_idx][1] = lo[1];
		sm1[cur_idx][2] = lo[2];
		sm1[cur_idx][3] = lo[3];
		sm1[cur_idx][4] = lo[4];
		sm1[cur_idx][5] = lo[5];
		sm1[cur_idx][6] = lo[6];
		sm1[cur_idx][7] = lo[7];
		sm1[cur_idx][8] = hi[0];
		sm1[cur_idx][9] = hi[1];
		sm1[cur_idx][10] = hi[2];
		sm1[cur_idx][11] = hi[3];
		sm1[cur_idx][12] = hi[4];
		sm1[cur_idx][13] = hi[5];
		sm1[cur_idx][14] = hi[6];
		sm1[cur_idx][15] = hi[7];*/
		sm1[cur_idx * 16 + 0] = in[16 * i];
		sm1[cur_idx * 16 + 1] = in[16 * i + 1];
		sm1[cur_idx * 16 + 2] = in[16 * i + 2];
		sm1[cur_idx * 16 + 3] = in[16 * i + 3];
		sm1[cur_idx * 16 + 4] = in[16 * i + 4];
		sm1[cur_idx * 16 + 5] = in[16 * i + 5];
		sm1[cur_idx * 16 + 6] = in[16 * i + 6];
		sm1[cur_idx * 16 + 7] = in[16 * i + 7];
		sm1[cur_idx * 16 + 8] = in[16 * i + 8];
		sm1[cur_idx * 16 + 9] = in[16 * i + 9];
		sm1[cur_idx * 16 + 10] = in[16 * i + 10];
		sm1[cur_idx * 16 + 11] = in[16 * i + 11];
		sm1[cur_idx * 16 + 12] = in[16 * i + 12];
		sm1[cur_idx * 16 + 13] = in[16 * i + 13];
		sm1[cur_idx * 16 + 14] = in[16 * i + 14];
		sm1[cur_idx * 16 + 15] = in[16 * i + 15];
		//__syncthreads();
		SM4_enc_block(sm1+16 * cur_idx, out + 16 * i, rkey);
		/*for (int j = 0;j < SM4_BLOCK_SIZE;j++) {
			out[16 * i + j] = sm2[cur_idx * 16 + j];
		}*/
	}
	//SM4Crypt(&(in[index * 16]), &(out[index * 16]), rkey);
}

__global__  void SM4_encrypt_cuda_ecb(const uint8_t* p, u1* c, u4* rk, int num_cipher_blocks) {
	int i = (blockIdx.x * blockDim.x) + threadIdx.x;
	if (i < num_cipher_blocks) {

		SM4Crypt(&(p[i * 16]), &(c[i * 16]), rk);
	}
	//
	//printf("num_cipher_blocks:%d\n",num_cipher_blocks);
	//printf("thread:i=%d\n",i);

}

void gpu_sm4_encrypt( uint8_t *plain, const uint8_t *key, uint8_t *cipher, int n_block)
{
  u4 *rkey;
  cudaMallocManaged(&rkey,sizeof(u4)*(SM4_RND_KEY_SIZE / sizeof(u4)));

  SM4_key_schedule<<<1,1>>>(key, rkey);
  cudaDeviceSynchronize();

  int blockSize = 256;
  int numBlocks = (n_block + blockSize -1) /blockSize;

  SM4_enc_blocks<<<numBlocks,blockSize>>>(n_block, plain, cipher, rkey);
  //SM4_encrypt_cuda_ecb <<<numBlocks, blockSize >>> (plain, cipher, rkey, n_block);
  //SM4Crypt(&(p[i * 16]), &(c[i * 16]), rk);
  cudaDeviceSynchronize();
}

void gpu_sm4_decrypt(uint8_t *plain, const uint8_t *key, const uint8_t *cipher, int n_block)
{
  u4 *rkey;
  cudaMallocManaged(&rkey,sizeof(u4)*(SM4_RND_KEY_SIZE / sizeof(u4)));

  SM4_key_schedule<<<1,1>>>(key, rkey);
	cudaDeviceSynchronize();

  int blockSize = 128;
  int numBlocks = (n_block + blockSize -1) /blockSize;

  SM4_dec_blocks<<<numBlocks,blockSize>>>(n_block, cipher, plain, rkey);
  cudaDeviceSynchronize();
}

void outputChar(u1 *text, size_t len)
{
    forloop( i, 0, len )
    {
        printf("0x%02x, ", text[i]);
        if (i % 16 == 15)
            puts("");
    }
    puts("");
}

void benchmark_sm4_encrypt( uint8_t *p, const uint8_t *key, uint8_t *c, int n_block)
{
  int turns = 100;
	clock_t t=clock();
  for(int i=0; i<turns; i++)
  {

    gpu_sm4_encrypt(p,key,c,n_block);
  }
	double tt = (double)(clock() - t)/(CLOCKS_PER_SEC*turns);
	double speed =(double) (16*n_block)/(1024*1024*tt);
	printf("SM4_encrypt>>> blocks: %d, time: %f s, speed: %f MB/s\n",n_block,tt,speed);
}

void benchmark_sm4_decrypt(uint8_t *p, const uint8_t *key, const uint8_t *c, int n_block)
{
  int turns = 100;
	clock_t t=clock();
  for(int i=0; i<turns; i++)
  {
    gpu_sm4_decrypt(p,key,c,n_block);
  }
	double tt = (double)(clock() - t)/(CLOCKS_PER_SEC*turns);
	double speed =(double) (16*n_block)/(1024*1024*tt);
	printf("SM4_decrypt>>> blocks: %d, time: %f s, speed: %f MB/s\n",n_block,tt,speed);
}
