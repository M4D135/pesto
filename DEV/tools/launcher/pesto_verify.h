/* Hash each immutable component before any PowerShell code is loaded.
 * Open files deny concurrent writes/deletion and remain open until child exit.
 * Signing this EXE with the organization's certificate is still required for
 * publisher authentication. Never auto-trust certificates. */
#include "pesto_sha256.h"
#include "pesto_runtime.h"
API BOOL CALL ReadFile(HANDLE,void*,DWORD,DWORD*,void*);
static HANDLE pesto_verified_handles[PESTO_RUNTIME_COUNT+1];
static unsigned char pesto_verify_buffer[65536];
static int pesto_verify_runtime(void){
 unsigned i,j;DWORD got;PestoSHA sha;unsigned char digest[32];static WCHAR path[CAP];
 DWORD attr;
 if(pesto_runtime_description[0]!='P')return 0;
 attr=GetFileAttributesW(root);
 if(attr==0xffffffff || (attr&0x400))return 0;
 /* Root held against rename/deletion: FILE_LIST_DIRECTORY, sharing read/write without delete.
  * With access 0 Windows ignores the sharing mode and the handle locked nothing (seen on Windows). */
 pesto_verified_handles[PESTO_RUNTIME_COUNT]=CreateFileW(root,0x1,3,0,3,0x02200000,0);
 if(pesto_verified_handles[PESTO_RUNTIME_COUNT]==BAD_HANDLE)return 0;
 for(i=0;i<PESTO_RUNTIME_COUNT;i++){
  if(!set(path,CAP,root)||!put(path,CAP,W("\\"))||!put(path,CAP,(PCWSTR)pesto_runtime[i].name))return 0;
  for(j=length(root)+1;path[j];j++){
   if(path[j]=='\\'){path[j]=0;attr=GetFileAttributesW(path);path[j]='\\';if(attr==0xffffffff||(attr&0x400))return 0;}
  }
  attr=GetFileAttributesW(path);if(attr==0xffffffff||(attr&(0x400|0x10)))return 0;
  pesto_verified_handles[i]=CreateFileW(path,0x80000000,1,0,3,0x00200000,0);
  if(pesto_verified_handles[i]==BAD_HANDLE)return 0;
  pesto_sha_init(&sha);
  for(;;){got=0;if(!ReadFile(pesto_verified_handles[i],pesto_verify_buffer,sizeof(pesto_verify_buffer),&got,0))return 0;if(!got)break;pesto_sha_update(&sha,pesto_verify_buffer,got);}
  pesto_sha_final(&sha,digest);
  for(j=0;j<32;j++)if(digest[j]!=pesto_runtime[i].hash[j])return 0;
 }
 return 1;
}
