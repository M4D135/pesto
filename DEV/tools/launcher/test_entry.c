/* Portable simulation of the C entry point. No WinAPI/UAC/PowerShell runs here. */
#define _WIN64 1
#include "Pesto-launcher.c"
#include <stdio.h>
#include <stdlib.h>
static int scenario,created,expected_create=1,dialogs,mkdirs,opens;
static DWORD last_error,expected_exit,child_exit;
static const char *fixture_root;
static FILE *opened[PESTO_RUNTIME_COUNT];
static int runtime_opens;
static PCWSTR sample_exe=W("C:\\Outils Pesto [QA] & \u00e9t\u00e9\\Pesto.exe");
static PCWSTR sample_root=W("C:\\Outils Pesto [QA] & \u00e9t\u00e9");
static PCWSTR sample_start=W("C:\\Outils Pesto [QA] & \u00e9t\u00e9\\wad\\Pesto-Startup.ps1");
static PCWSTR sample_ps=W("C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe");
static PCWSTR sample_logdir=W("C:\\Outils Pesto [QA] & \u00e9t\u00e9\\wad\\logs");
static PCWSTR sample_log=W("C:\\Outils Pesto [QA] & \u00e9t\u00e9\\wad\\logs\\Pesto-lanceur.log");
static PCWSTR sample_config=W("C:\\Donn\u00e9es\\Pesto cfg & [1].json");
static PWSTR arguments[10];static int argument_count;
static void demand(int ok,const char *what){if(!ok){fprintf(stderr,"scenario=%d failure=%s\n",scenario,what);exit(99);}}
static int contains(PCWSTR hay,PCWSTR needle){for(DWORD i=0;hay[i];i++){DWORD j=0;while(hay[i+j]&&needle[j]&&hay[i+j]==needle[j])j++;if(!needle[j])return 1;}return 0;}
/* Independent CRT-like decoder; checks literal argument boundaries, not PS syntax. */
static WCHAR decoded[32][2048];static int decoded_count;
static void decode(PCWSTR p){
 while(*p){int n=0,q=0;while(*p==' '||*p=='\t')p++;if(!*p)break;demand(decoded_count<32,"argument count");
  while(*p){int bs=0;if(!q&&(*p==' '||*p=='\t'))break;while(*p=='\\'){bs++;p++;}
   if(*p=='"'){for(int j=0;j<bs/2;j++)decoded[decoded_count][n++]='\\';if(bs%2)decoded[decoded_count][n++]='"';else q=!q;p++;}
   else{for(int j=0;j<bs;j++)decoded[decoded_count][n++]='\\';if(*p)decoded[decoded_count][n++]=*p++;}
   demand(n<2000,"decoded argument length");
  }demand(!q,"balanced argument quote");decoded[decoded_count++][n]=0;
 }
}
DWORD CALL GetModuleFileNameW(HANDLE h,PWSTR out,DWORD cap){(void)h;demand(set(out,cap,(scenario==36||scenario==47)?W("E:\\Pesto.exe"):sample_exe),"exe path");if(scenario==44){last_error=122;return cap;}if(scenario==46){last_error=1450;return 0;}return length(out);}
DWORD CALL GetWindowsDirectoryW(PWSTR out,DWORD cap){demand(set(out,cap,W("C:\\Windows")),"windows path");return length(out);}
DWORD CALL GetFullPathNameW(PCWSTR in,DWORD cap,PWSTR out,PWSTR*part){(void)part;demand(eq(in,W(".\\config.json"))||eq(in,W(".\\report.json")),"relative config/report source");demand(set(out,cap,sample_config),"absolute config");return length(out);}
static int runtime_index(PCWSTR path){
 WCHAR full[CAP];unsigned i;
 for(i=0;i<PESTO_RUNTIME_COUNT;i++){set(full,CAP,sample_root);put(full,CAP,W("\\"));put(full,CAP,pesto_runtime[i].name);if(eq(path,full))return (int)i;}
 return -1;
}
DWORD CALL GetFileAttributesW(PCWSTR path){demand(scenario!=36,"no component access from a drive root");
 int idx=runtime_index(path);
 if(contains(path,W("\\.pesto-update.lock"))){
   if(scenario==32 || scenario==34)return 0;
   if(scenario==33){last_error=5;return 0xffffffff;}
   last_error=2;return 0xffffffff;
 }
 demand(!contains(path,W("\\Pesto.ps1")),"old root entry was accessed");
 if(eq(path,sample_start)&&scenario==8)return 0xffffffff;
 if(scenario==42&&contains(path,W("\\wad\\Pesto-Join.xaml")))return 0xffffffff;
 if(eq(path,sample_ps)&&scenario==40)return 0xffffffff;
 if(eq(path,sample_config)&&scenario==41){last_error=2;return 0xffffffff;}
 if(idx>=0){
   if(scenario==22&&idx==(int)PESTO_RUNTIME_COUNT-1)return 0xffffffff;
   if(scenario==15&&idx==0)return 0x400;
   return 0;
 }
 if(eq(path,sample_ps)||eq(path,sample_config))return 0;
 if(eq(path,sample_root))return scenario==23?0x410:0x10;
 if(contains(path,W("\\wad")))return 0x10;
 return 0xffffffff;
}
BOOL CALL CreateDirectoryW(PCWSTR path,SECURITY_ATTRIBUTES *a){(void)a;demand(eq(path,sample_logdir),"only wad/logs directory");mkdirs++;return 1;}
PWSTR CALL GetCommandLineW(void){return (PWSTR)W("not parsed by this simulation");}
PWSTR* CALL CommandLineToArgvW(PCWSTR raw,int*count){(void)raw;*count=argument_count;return arguments;}
HANDLE CALL LocalFree(HANDLE h){(void)h;return 0;}
DWORD CALL GetLastError(void){return last_error;}
DWORD CALL FormatMessageW(DWORD a,const void*b,DWORD c,DWORD d,PWSTR e,DWORD f,void*g){(void)a;(void)b;(void)c;(void)d;(void)e;(void)f;(void)g;return 0;}
int CALL MessageBoxW(HANDLE a,PCWSTR text,PCWSTR title,unsigned int flags){(void)a;(void)title;(void)flags;demand(!contains(text,W("Conservez Pesto.exe, Pesto.ps1")),"old missing-file advice");
 if(scenario==9)demand(contains(text,W("déjà ouvert")),"already-open notice");
 if(scenario==32)demand(contains(text,W("Code de sortie du lanceur : 126.")),"exit code shown");
 if(scenario==33)demand(contains(text,W("Erreur Windows 5"))&&contains(text,W("Code de sortie du lanceur : 127.")),"Win32 error shown, not returned");
 /* 44: truncated path, realistic ERROR_INSUFFICIENT_BUFFER (122) equals X_PLACE; 46 tells them apart. */
 if(scenario==44)demand(contains(text,W("Erreur Windows 122"))&&contains(text,W("Code de sortie du lanceur : 122.")),"multi-digit Win32 error");
 if(scenario==46)demand(contains(text,W("Erreur Windows 1450"))&&contains(text,W("Code de sortie du lanceur : 122.")),"Win32 error shown, X_PLACE returned");
 dialogs++;return 1;}
HANDLE CALL CreateFileW(PCWSTR path,DWORD access,DWORD sharing,SECURITY_ATTRIBUTES*a,DWORD disp,DWORD flags,HANDLE tpl){
 int idx=runtime_index(path);(void)access;(void)a;(void)disp;(void)flags;(void)tpl;
 if(eq(path,sample_root)){demand(access==0x1&&sharing==3&&flags==0x02200000,"root held: list access, no delete sharing");return (HANDLE)500;}
 if(idx>=0){
   char name[4096];unsigned j,k=0;const unsigned short *src=pesto_runtime[idx].name;
   demand(sharing==1,"runtime not shared for writes/deletes");
   k=(unsigned)snprintf(name,sizeof(name),"%s/",fixture_root);
   for(j=0;src[j];j++){demand(k<sizeof(name)-2,"path bound");name[k++]=(src[j]=='\\')?'/':(char)src[j];}name[k]=0;
   opened[idx]=fopen(name,"rb");demand(opened[idx]!=0,"runtime fixture exists");runtime_opens++;
   return (HANDLE)(SIZE_T)(100+idx);
 }
 demand(eq(path,sample_log)||eq(path,W("NUL")),"only wad/logs file or NUL");opens++;return (HANDLE)(SIZE_T)(opens+10);
}
BOOL CALL ReadFile(HANDLE h,void*buf,DWORD len,DWORD*done,void*async){
 int idx=(int)(SIZE_T)h-100;(void)async;
 demand(idx>=0&&idx<(int)PESTO_RUNTIME_COUNT,"read verified file");
 if(scenario==16&&idx==0)return 0;
 *done=(DWORD)fread(buf,1,(size_t)len,opened[idx]);
 if((scenario==14||scenario==20)&&idx==0&&*done)((unsigned char*)buf)[0]^=1;
 return ferror(opened[idx])?0:1;
}
BOOL CALL WriteFile(HANDLE h,const void*buf,DWORD len,DWORD*done,void*async){(void)h;(void)buf;(void)async;*done=len;return 1;}
BOOL CALL CreateProcessW(PCWSTR exe,PWSTR cmd,SECURITY_ATTRIBUTES*a,SECURITY_ATTRIBUTES*b,BOOL inherit,DWORD flags,void*env,PCWSTR cwd,STARTUPINFOW*info,PROCESS_INFORMATION*out){
 (void)a;(void)b;(void)inherit;(void)env;(void)info;created++;
 demand(eq(exe,sample_ps),"system PowerShell x64");demand(eq(cwd,sample_root),"stable application directory");
 demand(!contains(cmd,W("\\Pesto.ps1")),"no old script in command");
 demand(flags==(scenario==4?0x10u:0x08000000u),"console mode");decode(cmd);
 demand(decoded_count>=10,"PowerShell switches");demand(eq(decoded[0],sample_ps),"argument exe");
 demand(eq(decoded[3],W("-STA")),"STA");demand(eq(decoded[7],W("RemoteSigned")),"policy unchanged");
 demand(eq(decoded[8],W("-File"))&&eq(decoded[9],sample_start),"direct wad entry");
 if(scenario==1||scenario==10)demand(decoded_count==11&&eq(decoded[10],W("-CheckPackage")),"package check route");
 if(scenario==2)demand(decoded_count==11&&eq(decoded[10],W("-Demo")),"demo route");
 if(scenario==3)demand(decoded_count==11&&eq(decoded[10],W("-DemoJoin")),"join demo route");
 if(scenario==5)demand(decoded_count==11&&eq(decoded[10],W("-AskCredential")),"explicit account route");
 if(scenario==6)demand(decoded_count==12&&eq(decoded[10],W("-ConfigPath"))&&eq(decoded[11],sample_config),"absolute literal config");
 if(scenario==18)demand(contains(cmd,W("-QuietCheck"))&&contains(cmd,W("-CheckPackage")),"quiet check flags");
 if(scenario==19)demand(contains(cmd,W("-CheckReportPath"))&&contains(cmd,W("-QuietCheck")),"json flags");
 if(scenario==24)demand(decoded_count==11&&eq(decoded[10],W("-Consult")),"consultation route");
 if(scenario==27)demand(contains(cmd,W("-PlanInputPath"))&&contains(cmd,W("-CheckReportPath"))&&contains(cmd,W("-QuietCheck")),"draft validation route");
 if(scenario==11){last_error=5;return 0;}
 if(scenario==43){last_error=0;return 0;}
 out->hProcess=(HANDLE)2;out->hThread=(HANDLE)3;out->dwProcessId=1234;return 1;
}
DWORD CALL WaitForSingleObject(HANDLE h,DWORD ms){demand(h==(HANDLE)2,"wait only on a started child");demand(ms==0xffffffff,"wait child");return 0;}
BOOL CALL GetExitCodeProcess(HANDLE h,DWORD*code){(void)h;if(scenario==37){last_error=6;return 0;}*code=child_exit;return 1;}
BOOL CALL CloseHandle(HANDLE h){(void)h;return 1;}
HANDLE CALL CreateMutexW(SECURITY_ATTRIBUTES*a,BOOL owner,PCWSTR name){(void)a;(void)owner;demand(contains(name,W("Local\\GP_Launcher_")),"launcher guard preserved");if(scenario==39){last_error=5;return 0;}last_error=(scenario==9||scenario==10)?183:0;return (HANDLE)4;}
void CALL ExitProcess(unsigned int code){
 demand(code==expected_exit,"exit code preserved");demand(created==expected_create,"expected PowerShell launches");
 /* L4: the launcher's own refusals and errors use 120-139; PowerShell codes pass through unchanged. */
 if(expected_exit && expected_exit!=child_exit)demand(code>=120&&code<=139,"launcher code in its own range");
 if(scenario==9||scenario==37||scenario==38||scenario==44||scenario==46)demand(dialogs==1,"one dialog");
 if(created){if(quietcheck)demand(mkdirs==0&&opens==1&&dialogs==0,"quiet: no log writes/dialog");else demand(mkdirs==1&&opens==2,"runtime logs contained in wad");}
 if(created)demand(runtime_opens==PESTO_RUNTIME_COUNT,"every component was verified before launch");
 if(scenario==20||scenario==21)demand(dialogs==0,"quiet failures have no popup");
 if(scenario==12)demand(dialogs==0,"cancel no error popup");
 if(scenario==35)demand(dialogs==0,"--quiet honoured before an earlier argument error");
 if(scenario==47)demand(dialogs==0,"--quiet honoured for the drive-root refusal");
 printf("OK entry simulation %d (no Windows APIs executed)\n",scenario);exit(0);
}
int main(int argc,char**argv){
 demand(argc==3,"scenario and source root required");fixture_root=argv[2];scenario=atoi(argv[1]);arguments[argument_count++]=(PWSTR)sample_exe;
 switch(scenario){
 case 0:break;case 1:arguments[argument_count++]=(PWSTR)W("--check");break;
 case 2:arguments[argument_count++]=(PWSTR)W("--demo");break;
 case 3:arguments[argument_count++]=(PWSTR)W("--demo-join");break;
 case 4:arguments[argument_count++]=(PWSTR)W("--diagnostic");break;
 case 5:arguments[argument_count++]=(PWSTR)W("-AskCredential");break;
 case 6:arguments[argument_count++]=(PWSTR)W("-ConfigPath");arguments[argument_count++]=(PWSTR)W(".\\config.json");break;
 case 7:arguments[argument_count++]=(PWSTR)W("--unknown");expected_exit=120;expected_create=0;break;
 case 8:expected_exit=124;expected_create=0;break;
 case 9:expected_exit=128;expected_create=0;break;
 case 10:arguments[argument_count++]=(PWSTR)W("--check");break;
 case 11:expected_exit=131;break;
 case 12:expected_exit=1223;child_exit=1223;break;
 case 13:expected_exit=7;child_exit=7;break;
 case 14:case 15:case 16:case 22:case 23:expected_exit=125;expected_create=0;break;
 case 17:arguments[argument_count++]=(PWSTR)W("--help");expected_create=0;break;
 case 18:arguments[argument_count++]=(PWSTR)W("--check");arguments[argument_count++]=(PWSTR)W("--quiet");break;
 case 19:arguments[argument_count++]=(PWSTR)W("--check-json");arguments[argument_count++]=(PWSTR)W(".\\report.json");break;
 case 20:arguments[argument_count++]=(PWSTR)W("--check");arguments[argument_count++]=(PWSTR)W("--quiet");expected_exit=125;expected_create=0;break;
 case 21:arguments[argument_count++]=(PWSTR)W("--check-json");expected_exit=120;expected_create=0;break;
 case 24:arguments[argument_count++]=(PWSTR)W("--consult");break;
 case 25:arguments[argument_count++]=(PWSTR)W("--consult");arguments[argument_count++]=(PWSTR)W("-AskCredential");expected_exit=120;expected_create=0;break;
 case 26:arguments[argument_count++]=(PWSTR)W("--consult");arguments[argument_count++]=(PWSTR)W("--demo");expected_exit=120;expected_create=0;break;
 case 27:arguments[argument_count++]=(PWSTR)W("--validate-plan");arguments[argument_count++]=(PWSTR)W(".\\config.json");arguments[argument_count++]=(PWSTR)W(".\\report.json");break;
 case 28:arguments[argument_count++]=(PWSTR)W("--validate-plan");expected_exit=120;expected_create=0;break;
 case 29:arguments[argument_count++]=(PWSTR)W("--validate-plan");arguments[argument_count++]=(PWSTR)W(".\\config.json");arguments[argument_count++]=(PWSTR)W(".\\report.json");arguments[argument_count++]=(PWSTR)W("-AskCredential");expected_exit=120;expected_create=0;break;
 case 30:arguments[argument_count++]=(PWSTR)W("--validate-plan");arguments[argument_count++]=(PWSTR)W(".\\config.json");arguments[argument_count++]=(PWSTR)W(".\\report.json");arguments[argument_count++]=(PWSTR)W("-ConfigPath");arguments[argument_count++]=(PWSTR)W(".\\config.json");expected_exit=120;expected_create=0;break;
 case 31:arguments[argument_count++]=(PWSTR)W("--quiet");expected_exit=120;expected_create=0;break;
 case 32:expected_exit=126;expected_create=0;break;
 case 33:expected_exit=127;expected_create=0;break;
 case 34:arguments[argument_count++]=(PWSTR)W("--help");expected_create=0;break;
 case 35:arguments[argument_count++]=(PWSTR)W("--unknown");arguments[argument_count++]=(PWSTR)W("--check");arguments[argument_count++]=(PWSTR)W("--quiet");expected_exit=120;expected_create=0;break;
 case 36:expected_exit=123;expected_create=0;break;
 case 47:arguments[argument_count++]=(PWSTR)W("--check");arguments[argument_count++]=(PWSTR)W("--quiet");expected_exit=123;expected_create=0;break;
 case 37:expected_exit=132;break;
 case 38:expected_exit=32;child_exit=32;break;
 case 39:expected_exit=129;expected_create=0;break;
 case 40:expected_exit=130;expected_create=0;break;
 case 41:arguments[argument_count++]=(PWSTR)W("-ConfigPath");arguments[argument_count++]=(PWSTR)W(".\\config.json");expected_exit=121;expected_create=0;break;
 case 42:expected_exit=124;expected_create=0;break;
 case 43:expected_exit=131;break;
 case 44:expected_exit=122;expected_create=0;break;
 case 46:expected_exit=122;expected_create=0;break;
 case 45:arguments[argument_count++]=(PWSTR)W("--version");expected_create=0;break;
 default:demand(0,"unknown scenario");
 }PestoEntry();return 99;
}
