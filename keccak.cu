// ComputeRoll: legacy Keccak-256 over exactly 84 packed bytes. No keys/signing.
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <string>
#include <iostream>
#include <sstream>
#include <chrono>
#ifndef CPU_ONLY
#include <cuda_runtime.h>
#define HD __host__ __device__
#else
#define HD
#endif
HD static inline uint64_t rol(uint64_t x, int n) { return (x<<n)|(x>>(64-n)); }
HD static void permute(uint64_t *s) {
  const uint64_t rc[24]={0x1ULL,0x8082ULL,0x800000000000808aULL,0x8000000080008000ULL,0x808bULL,0x80000001ULL,0x8000000080008081ULL,0x8000000000008009ULL,0x8aULL,0x88ULL,0x80008009ULL,0x8000000aULL,0x8000808bULL,0x800000000000008bULL,0x8000000000008089ULL,0x8000000000008003ULL,0x8000000000008002ULL,0x8000000000000080ULL,0x800aULL,0x800000008000000aULL,0x8000000080008081ULL,0x8000000000008080ULL,0x80000001ULL,0x8000000080008008ULL};
  const int rotation[24]={1,3,6,10,15,21,28,36,45,55,2,14,27,41,56,8,25,43,62,18,39,61,20,44};
  const int pi[24]={10,7,11,17,18,3,5,16,8,21,24,4,15,23,19,13,12,2,20,14,22,9,6,1};
  #pragma unroll 1
  for(int r=0;r<24;r++) {
    uint64_t c[5];
    #pragma unroll
    for(int i=0;i<5;i++) c[i]=s[i]^s[i+5]^s[i+10]^s[i+15]^s[i+20];
    #pragma unroll
    for(int i=0;i<5;i++) { uint64_t d=c[(i+4)%5]^rol(c[(i+1)%5],1);
      #pragma unroll
      for(int j=0;j<25;j+=5) s[j+i]^=d; }
    uint64_t t=s[1];
    #pragma unroll
    for(int i=0;i<24;i++) { int j=pi[i]; uint64_t u=s[j]; s[j]=rol(t,rotation[i]); t=u; }
    #pragma unroll
    for(int j=0;j<25;j+=5) {
      #pragma unroll
      for(int i=0;i<5;i++) c[i]=s[j+i];
      #pragma unroll
      for(int i=0;i<5;i++) s[j+i]=c[i]^((~c[(i+1)%5])&c[(i+2)%5]); }
    s[0]^=rc[r];
  }
}
HD static void digest84(const unsigned char *m,unsigned char *out) {
  uint64_t s[25]={0};
  
  #pragma unroll
  for(int i=0;i<84;i++) s[i/8]|=(uint64_t)m[i]<<((i%8)*8);
  s[10]^=0x100000000ULL; // Keccak suffix 0x01 at byte 84 (NOT SHA3 0x06).
  s[16]^=0x8000000000000000ULL;
  permute(s);
  
  #pragma unroll
  for(int i=0;i<32;i++) out[i]=(unsigned char)(s[i/8]>>((i%8)*8));
}
static bool unhex(const std::string &s,unsigned char *out,size_t len) {
  if(s.size()!=len*2) return false;
  for(size_t i=0;i<len;i++) { unsigned int n; if(s.substr(i*2,2).find_first_not_of("0123456789abcdefABCDEF")!=std::string::npos) return false; if(sscanf(s.substr(i*2,2).c_str(),"%2x",&n)!=1) return false; out[i]=(unsigned char)n; }
  return true;
}
static std::string hex(const unsigned char *b,size_t n) { std::string s; const char *h="0123456789abcdef"; for(size_t i=0;i<n;i++){s+=h[b[i]>>4];s+=h[b[i]&15];} return s; }
#ifndef CPU_ONLY
#define CUDA(x) do { cudaError_t e=(x); if(e!=cudaSuccess){std::cerr<<cudaGetErrorString(e)<<std::endl;exit(2);} }while(0)
__global__ static void vectorKernel(const unsigned char *m,unsigned char *out,int n) { int i=blockIdx.x*blockDim.x+threadIdx.x; if(i<n) digest84(m+i*84,out+i*32); }
__global__ static void scanKernel(const unsigned char *base,const unsigned char *target,uint64_t start,uint64_t count,uint64_t *found,int *flag) {
  for(uint64_t k=(uint64_t)blockIdx.x*blockDim.x+threadIdx.x;k<count;k+=(uint64_t)gridDim.x*blockDim.x) {
    unsigned char m[84],h[32];
    
  #pragma unroll
  for(int i=0;i<84;i++) m[i]=base[i];
    uint64_t nonce=start+k;
    
  #pragma unroll
  for(int i=0;i<8;i++) m[83-i]=(unsigned char)(nonce>>(8*i));
    digest84(m,h);
    bool less=false;
    for(int i=0;i<32;i++) {if(h[i]<target[i]){less=true;break;} if(h[i]>target[i])break;}
    if(less && atomicCAS(flag,0,1)==0) *found=nonce;
  }
}
#endif
int main(int argc,char **argv) {
  if(argc==2 && std::string(argv[1])=="--vectors") {
    std::string line;
    while(std::getline(std::cin,line)) {
      unsigned char m[84],out[32]; if(!unhex(line,m,84))return 1;
#ifdef CPU_ONLY
      digest84(m,out);
#else
      unsigned char *dm,*dh;CUDA(cudaMalloc(&dm,84));CUDA(cudaMalloc(&dh,32));CUDA(cudaMemcpy(dm,m,84,cudaMemcpyHostToDevice));vectorKernel<<<1,1>>>(dm,dh,1);CUDA(cudaGetLastError());CUDA(cudaMemcpy(out,dh,32,cudaMemcpyDeviceToHost));CUDA(cudaFree(dm));CUDA(cudaFree(dh));
#endif
      std::cout<<hex(out,32)<<std::endl;
    }
    return 0;
  }
#ifndef CPU_ONLY
  unsigned char *db,*dt; uint64_t *df;int *flag;
  CUDA(cudaMalloc(&db,84));CUDA(cudaMalloc(&dt,32));CUDA(cudaMalloc(&df,8));CUDA(cudaMalloc(&flag,4));
  cudaDeviceProp prop;CUDA(cudaGetDeviceProperties(&prop,0));
  std::cerr<<"GPU "<<prop.name<<" SMs "<<prop.multiProcessorCount<<std::endl;
  std::string line;
  while(std::getline(std::cin,line)) {
    std::istringstream in(line); std::string prefix,np,target,ss,cs;in>>prefix>>np>>target>>ss>>cs;
    unsigned char base[84]={0},t[32];
    if(!unhex(prefix,base,52)||!unhex(np,base+52,24)||!unhex(target,t,32))return 1;
    uint64_t start=std::stoull(ss),count=std::stoull(cs);if(count==0||count>(1ULL<<31)||start>UINT64_MAX-count)return 1;
    CUDA(cudaMemcpy(db,base,84,cudaMemcpyHostToDevice));CUDA(cudaMemcpy(dt,t,32,cudaMemcpyHostToDevice));CUDA(cudaMemset(flag,0,4));
    auto began=std::chrono::steady_clock::now();
    scanKernel<<<prop.multiProcessorCount*8,128>>>(db,dt,start,count,df,flag);CUDA(cudaGetLastError());CUDA(cudaDeviceSynchronize());
    double sec=std::chrono::duration<double>(std::chrono::steady_clock::now()-began).count();
    int f;CUDA(cudaMemcpy(&f,flag,4,cudaMemcpyDeviceToHost));uint64_t nonce=0;if(f)CUDA(cudaMemcpy(&nonce,df,8,cudaMemcpyDeviceToHost));
    std::cout<<"{\"hashes\":\""<<count<<"\",\"seconds\":"<<sec<<",\"found\":"<<(f?"true":"false")<<",\"counter\":\""<<nonce<<"\"}"<<std::endl;
  }
#else
  return 1;
#endif
}
