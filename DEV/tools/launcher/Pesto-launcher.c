/* Pesto 1.0 - Windows x64 GUI launcher.
 * Invokes wad/Pesto-Startup.ps1 through the installed Windows PowerShell 5.1.
 * Elevation stays in Pesto-Startup.ps1; this executable never collects credentials.
 * No CLR, shell command concatenation, encoded payload, downloads or services.
 * Build with tools/launcher/build_native.py (LLVM) or tools/Build-Pesto.ps1 (MSVC).
 */
#if !defined(_WIN64)
#error A Windows x64 target is required.
#endif
#define API __declspec(dllimport)
#define CALL __stdcall
typedef unsigned short WCHAR;
typedef unsigned long DWORD;
typedef int BOOL;
typedef void *HANDLE;
typedef unsigned long long SIZE_T;
typedef const WCHAR *PCWSTR;
typedef WCHAR *PWSTR;
typedef struct { DWORD nLength; void *lpSecurityDescriptor; BOOL bInheritHandle; } SECURITY_ATTRIBUTES;
typedef struct {
 DWORD cb; PWSTR lpReserved, lpDesktop, lpTitle;
 DWORD dwX,dwY,dwXSize,dwYSize,dwXCountChars,dwYCountChars,dwFillAttribute,dwFlags;
 unsigned short wShowWindow,cbReserved2; unsigned char *lpReserved2;
 HANDLE hStdInput,hStdOutput,hStdError;
} STARTUPINFOW;
typedef struct { HANDLE hProcess,hThread; DWORD dwProcessId,dwThreadId; } PROCESS_INFORMATION;
API DWORD CALL GetModuleFileNameW(HANDLE,PWSTR,DWORD);
API DWORD CALL GetWindowsDirectoryW(PWSTR,DWORD);
API DWORD CALL GetFullPathNameW(PCWSTR,DWORD,PWSTR,PWSTR*);
API DWORD CALL GetFileAttributesW(PCWSTR);
API BOOL CALL CreateDirectoryW(PCWSTR,SECURITY_ATTRIBUTES*);
API PWSTR CALL GetCommandLineW(void);
API PWSTR* CALL CommandLineToArgvW(PCWSTR,int*);
API HANDLE CALL LocalFree(HANDLE);
API DWORD CALL GetLastError(void);
API DWORD CALL FormatMessageW(DWORD,const void*,DWORD,DWORD,PWSTR,DWORD,void*);
API int CALL MessageBoxW(HANDLE,PCWSTR,PCWSTR,unsigned int);
API HANDLE CALL CreateFileW(PCWSTR,DWORD,DWORD,SECURITY_ATTRIBUTES*,DWORD,DWORD,HANDLE);
API BOOL CALL WriteFile(HANDLE,const void*,DWORD,DWORD*,void*);
API BOOL CALL CreateProcessW(PCWSTR,PWSTR,SECURITY_ATTRIBUTES*,SECURITY_ATTRIBUTES*,BOOL,DWORD,void*,PCWSTR,STARTUPINFOW*,PROCESS_INFORMATION*);
API DWORD CALL WaitForSingleObject(HANDLE,DWORD);
API BOOL CALL GetExitCodeProcess(HANDLE,DWORD*);
API BOOL CALL CloseHandle(HANDLE);
API HANDLE CALL CreateMutexW(SECURITY_ATTRIBUTES*,BOOL,PCWSTR);
API void CALL ExitProcess(unsigned int);
#define W(s) ((PCWSTR)L##s)
#define BAD_HANDLE ((HANDLE)(SIZE_T)-1)
#define CAP 32760
/* Exit codes (table in docs/V1_GUIDE.md, "Codes de sortie de Pesto.exe").
 * 0: --help, --version, or Windows PowerShell returned 0.
 * Any code returned by Windows PowerShell (Pesto-Startup.ps1: 0, 1, 20, 1223 UAC cancelled, engine codes)
 * is passed through unchanged. The launcher's own refusals and errors use 120-139 only, one value per
 * cause; a Win32 error is shown in the dialog, never returned as the exit code. 133-139 are reserved. */
#define X_USAGE 120      /* unknown, missing, duplicated or incompatible argument; unreadable or too long command line */
#define X_ARGFILE 121    /* -ConfigPath or --validate-plan draft not found, report path unusable */
#define X_PLACE 122      /* launcher path unknown or too long, derived path too long */
#define X_DRIVEROOT 123  /* started from a drive root */
#define X_MISSING 124    /* wad\Pesto-Startup.ps1, Pesto-Join.ps1 or Pesto-Join.xaml missing */
#define X_INTEGRITY 125  /* embedded SHA-256 binding refused: component missing, changed, linked or in use */
#define X_UPDATELOCK 126 /* .pesto-update.lock present: update interrupted or running */
#define X_LOCKCHECK 127  /* update lock cannot be checked */
#define X_RUNNING 128    /* already open from this folder in this mode: no UAC, nothing started */
#define X_INSTANCE 129   /* instance guard cannot be created */
#define X_NOPS 130       /* Windows PowerShell 5.1 x64 not found */
#define X_SPAWN 131      /* Windows PowerShell could not be started */
#define X_CHILDCODE 132  /* Windows PowerShell ran but its exit code is unreadable */
static WCHAR root[CAP],pspath[CAP],script[CAP],config[CAP],line[CAP],logpath[CAP],message[CAP],errorText[4096];
static STARTUPINFOW si;
static PROCESS_INFORMATION pi;
static SECURITY_ATTRIBUTES sa;
static int demo,demojoin,ask,haveconfig,check,diagnostic,quietcheck,havereport;
static WCHAR reportpath[CAP];
static DWORD used;
static WCHAR mutexname[64];
static HANDLE instance;
static DWORD length(PCWSTR s){DWORD n=0;if(s)while(s[n])++n;return n;}
static int put(PWSTR d,DWORD cap,PCWSTR src){DWORD n=length(d),m=length(src),i;if(n+m>=cap)return 0;for(i=0;i<=m;i++)d[n+i]=src[i];return 1;}
static int set(PWSTR d,DWORD cap,PCWSTR src){d[0]=0;return put(d,cap,src);}
static int eq(PCWSTR a,PCWSTR b){while(*a&&*b){WCHAR x=*a++,y=*b++;if(x>='A'&&x<='Z')x+=32;if(y>='A'&&y<='Z')y+=32;if(x!=y)return 0;}return !*a&&!*b;}
static int safe(PCWSTR s){for(;*s;s++)if(*s<32 || *s=='"')return 0;return 1;}
static int leaf(PCWSTR p){DWORD a=GetFileAttributesW(p);return a!=0xffffffff && !(a&0x10);}
static void num(PWSTR d,DWORD v){WCHAR b[12];int k=11;b[k]=0;do{b[--k]=(WCHAR)('0'+v%10);v/=10;}while(v);put(d,CAP,b+k);}
/* exitcode is one of X_*; error is the Win32 error to describe (0: none). */
static void die(PCWSTR reason,DWORD exitcode,DWORD error){
 set(message,CAP,reason);
 if(error){put(message,CAP,W("\r\n\r\nErreur Windows "));num(message,error);if(FormatMessageW(0x00001000|0x00000200,0,error,0,errorText,4096,0)){put(message,CAP,W(" : "));put(message,CAP,errorText);}}
 put(message,CAP,W("\r\n\r\nConservez Pesto.exe et le dossier wad ensemble.\r\nAucune opération AD n'est lancée par ce message.\r\nCode de sortie du lanceur : "));num(message,exitcode);put(message,CAP,W("."));
 if(!quietcheck)MessageBoxW(0,message,W("Pesto 1.0 | Démarrage"),0x10);ExitProcess(exitcode);
}
static void addchar(WCHAR c){if(used+2>=CAP)die(W("Arguments trop longs."),X_USAGE,0);line[used++]=c;line[used]=0;}
/* Windows argv quoting: backslashes are escaped only before quotes/end quote. */
static void arg(PCWSTR s){DWORD slashes=0,j;if(used)addchar(' ');addchar('"');for(;*s;s++){
 if(*s=='\\'){slashes++;continue;}
 if(*s=='"'){for(j=0;j<slashes*2+1;j++)addchar('\\');addchar('"');}
 else{for(j=0;j<slashes;j++)addchar('\\');addchar(*s);}slashes=0;
 }for(j=0;j<slashes*2;j++)addchar('\\');addchar('"');
}
#include "pesto_verify.h"
void CALL PestoEntry(void){
 DWORD n,code=0,err=0,written=0;int argc=0,i,consult=0,haveplan=0,started=1;static WCHAR planinput[CAP];PWSTR *argv;
 HANDLE output=BAD_HANDLE,input=BAD_HANDLE;
 /* Arguments first: silent modes also cover the location refusals below (seen on Windows: drive-root dialog under --quiet). */
 argv=CommandLineToArgvW(GetCommandLineW(),&argc);if(!argv)die(W("Arguments invalides."),X_USAGE,GetLastError());
 /* Silent modes hold for every later error, whatever the argument order. */
 for(i=1;i<argc;i++)if(eq(argv[i],W("--quiet")) || eq(argv[i],W("--check-json")) || eq(argv[i],W("--validate-plan")))quietcheck=1;
 n=GetModuleFileNameW(0,root,CAP);
 if(!n||n>=CAP-1)die(W("Chemin du lanceur introuvable ou trop long."),X_PLACE,GetLastError());
 while(n && root[n-1]!='\\' && root[n-1]!='/')--n;
 if(!n)die(W("Répertoire du lanceur introuvable."),X_PLACE,0);root[n-1]=0;
 /* "E:" would be a drive-relative path (current directory of E:), not the drive root. */
 if(n==3 && root[1]==':')die(W("Pesto.exe ne peut pas être lancé depuis la racine d'un lecteur. Placer Pesto.exe et wad dans un dossier."),X_DRIVEROOT,0);
 if(!set(script,CAP,root)||!put(script,CAP,W("\\wad\\Pesto-Startup.ps1")))die(W("Chemin de démarrage trop long."),X_PLACE,0);
 for(i=1;i<argc;i++){
   if(eq(argv[i],W("-Demo")) || eq(argv[i],W("--demo")))demo=1;
   else if(eq(argv[i],W("-DemoJoin")) || eq(argv[i],W("--demo-join"))){demo=1;demojoin=1;}
   else if(eq(argv[i],W("-AskCredential")))ask=1;
   else if(eq(argv[i],W("--consult")))consult=1;
   else if(eq(argv[i],W("--check")))check=1;
   else if(eq(argv[i],W("--quiet")))quietcheck=1;
   else if(eq(argv[i],W("--validate-plan"))){
     if(haveplan || havereport || i+2>=argc || !safe(argv[i+1]) || !safe(argv[i+2]) || !argv[i+1][0] || !argv[i+2][0])die(W("Utiliser --validate-plan <brouillon.json> <nouveau-rapport.json>."),X_USAGE,0);
     n=GetFullPathNameW(argv[++i],CAP,planinput,0);if(!n||n>=CAP||!leaf(planinput))die(W("Brouillon introuvable."),X_ARGFILE,0);
     n=GetFullPathNameW(argv[++i],CAP,reportpath,0);if(!n||n>=CAP)die(W("Chemin du rapport invalide."),X_ARGFILE,0);
     haveplan=1;havereport=1;check=1;quietcheck=1;
   }
   else if(eq(argv[i],W("--check-json"))){
     check=1;quietcheck=1;
     if(havereport || i+1>=argc || !safe(argv[i+1]) || !argv[i+1][0])die(W("Chemin du rapport absent ou invalide."),X_USAGE,0);
     n=GetFullPathNameW(argv[++i],CAP,reportpath,0);if(!n||n>=CAP)die(W("Chemin du rapport trop long."),X_ARGFILE,0);havereport=1;
   }
   else if(eq(argv[i],W("--diagnostic")))diagnostic=1;
   else if(eq(argv[i],W("-ConfigPath"))){
     if(haveconfig || i+1>=argc || !safe(argv[i+1]) || !argv[i+1][0])die(W("ConfigPath absent, duplique ou invalide."),X_USAGE,0);
     n=GetFullPathNameW(argv[++i],CAP,config,0);if(!n||n>=CAP || !leaf(config))die(W("Fichier de configuration introuvable."),X_ARGFILE,GetLastError());haveconfig=1;
   }
   else if(eq(argv[i],W("--version"))){MessageBoxW(0,W("Pesto 1.0\r\nLanceur natif Windows x64.\r\nSources et moteur dans le dossier du projet."),W("Pesto | Version"),0x40);LocalFree(argv);ExitProcess(0);}
   else if(eq(argv[i],W("--help")) || eq(argv[i],W("/?"))){MessageBoxW(0,W("Pesto.exe : lancement normal avec UAC si nécessaire.\r\n\r\n-Demo : interface sans mutation (pack DEV)\r\n-DemoJoin : démonstration de la jonction (pack DEV)\r\n-AskCredential : demander explicitement un autre compte AD\r\n-ConfigPath <fichier> : configuration alternative\r\n\r\n--check : vérifier le pack sans UAC ni AD\r\n--check --quiet : code de sortie sans fenêtre\r\n--check-json <fichier> : rapport local sans UAC ni AD\r\n--consult : consultation sans UAC, mutations interdites\r\n--validate-plan <brouillon> <rapport> : validation locale JSON, sans autorisation\r\n--diagnostic : ouvrir avec console\r\n\r\nCode de sortie 120 à 139 : refus ou erreur du lanceur.\r\nAutre code : rendu tel quel par Windows PowerShell.\r\n\r\nAucun mot de passe ne doit être passé en argument."),W("Pesto | Aide du lanceur"),0x40);LocalFree(argv);ExitProcess(0);}
   else die(W("Paramètre inconnu. Utiliser Pesto.exe --help."),X_USAGE,0);
 }
 if(haveplan && (demo || ask || consult || haveconfig))die(W("Validation de brouillon incompatible avec un lancement interactif."),X_USAGE,0);
 if(consult && (demo || ask))die(W("--consult ne se combine pas avec une démonstration ou un autre compte."),X_USAGE,0);
 if(quietcheck && !check)die(W("--quiet doit accompagner --check ou --check-json."),X_USAGE,0);
 /* No startup while code replacement or its recovery is unfinished. */
 if(!set(logpath,CAP,root)||!put(logpath,CAP,W("\\.pesto-update.lock")))die(W("Chemin de vérification de mise à jour trop long."),X_PLACE,0);
 n=GetFileAttributesW(logpath);
 if(n!=0xffffffff)die(W("Mise à jour interrompue ou en cours. Utilisez l'outil DEV avec --recover pour examiner le retour au code précédent. Ne supprimez pas le verrou pour lancer l'application."),X_UPDATELOCK,0);
 err=GetLastError();if(err!=2 && err!=3)die(W("Impossible de vérifier le verrou de mise à jour. Aucun moteur chargé."),X_LOCKCHECK,err);
 err=0;
 if(!leaf(script))die(W("wad\\Pesto-Startup.ps1 manque. Extraire tout le pack, pas uniquement Pesto.exe."),X_MISSING,0);
 set(logpath,CAP,root);if(!put(logpath,CAP,W("\\wad\\Pesto-Join.ps1"))||!leaf(logpath))die(W("wad\\Pesto-Join.ps1 manque. La mise à jour est incomplète."),X_MISSING,0);
 set(logpath,CAP,root);if(!put(logpath,CAP,W("\\wad\\Pesto-Join.xaml"))||!leaf(logpath))die(W("wad\\Pesto-Join.xaml manque. La mise à jour est incomplète."),X_MISSING,0);
 LocalFree(argv);
 if(!pesto_verify_runtime())die(W("Composant absent, modifié, lié ou en cours de modification. Le lanceur refuse de charger PowerShell. Réinstallez un pack cohérent, sans effacer les états."),X_INTEGRITY,0);
 /* Keep the legacy GP mutex namespace to coordinate with the previous brand.
  * Suppress duplicate launches before showing another UAC prompt. The script
  * retains its own cross-account guard; this one is per interactive session. */
 {
   DWORD h=2166136261u,j;WCHAR c;static const char hex[]="0123456789ABCDEF";
   for(j=0;root[j];j++){c=root[j];if(c>='A'&&c<='Z')c+=32;h=(h^(DWORD)c)*16777619u;}
   h=(h^(DWORD)demo)*16777619u;set(mutexname,64,W("Local\\GP_Launcher_"));n=length(mutexname);
   for(j=0;j<8;j++)mutexname[n+j]=(WCHAR)hex[(h>>(28-j*4))&15];mutexname[n+8]=0;
   instance=CreateMutexW(0,0,mutexname);
   if(!instance)die(W("Impossible de vérifier l'instance du lanceur. Pesto n'a pas été relancé."),X_INSTANCE,GetLastError());
   if(GetLastError()==183 && !check){CloseHandle(instance);MessageBoxW(0,W("Pesto est déjà ouvert depuis ce dossier.\r\nRevenez à la fenêtre existante. Aucune nouvelle demande UAC ni opération lancée."),W("Pesto | Déjà ouvert"),0x40);ExitProcess(X_RUNNING);}
 }
 n=GetWindowsDirectoryW(pspath,CAP);if(!n||n>=CAP)die(W("Dossier Windows introuvable."),X_NOPS,GetLastError());
 if(!put(pspath,CAP,W("\\System32\\WindowsPowerShell\\v1.0\\powershell.exe"))||!leaf(pspath))die(W("Windows PowerShell 5.1 x64 n'est pas disponible."),X_NOPS,0);
 arg(pspath);arg(W("-NoLogo"));arg(W("-NoProfile"));arg(W("-STA"));arg(W("-WindowStyle"));arg(diagnostic?W("Normal"):W("Hidden"));
 arg(W("-ExecutionPolicy"));arg(W("RemoteSigned"));arg(W("-File"));arg(script);
 if(check)arg(W("-CheckPackage"));if(quietcheck)arg(W("-QuietCheck"));if(havereport){arg(W("-CheckReportPath"));arg(reportpath);}
 if(haveplan){arg(W("-PlanInputPath"));arg(planinput);}
 if(consult)arg(W("-Consult"));
 if(demojoin)arg(W("-DemoJoin"));else if(demo)arg(W("-Demo"));if(ask)arg(W("-AskCredential"));if(haveconfig){arg(W("-ConfigPath"));arg(config);}
 si.cb=sizeof(si);si.dwFlags=1;si.wShowWindow=diagnostic?1:0;sa.nLength=sizeof(sa);sa.bInheritHandle=1;
 if(!set(logpath,CAP,root)||!put(logpath,CAP,W("\\wad\\logs")))die(W("Chemin du journal trop long."),X_PLACE,0);
 /* A read-only installation must not create files beside Pesto.exe. Logging is optional. */
 if(!quietcheck)CreateDirectoryW(logpath,0);
 if(!put(logpath,CAP,W("\\Pesto-lanceur.log")))die(W("Chemin du journal trop long."),X_PLACE,0);
 if(!quietcheck)output=CreateFileW(logpath,4,3,&sa,4,0x80,0);
 input=CreateFileW(W("NUL"),0x80000000,3,&sa,3,0x80,0);
 if(!diagnostic && output!=BAD_HANDLE && input!=BAD_HANDLE){
   static const char begin[]="\r\n[Pesto 1.0 launcher] Windows PowerShell startup\r\n";
   WriteFile(output,begin,sizeof(begin)-1,&written,0);
   si.dwFlags|=0x100;si.hStdOutput=output;si.hStdError=output;si.hStdInput=input;
 }
 if(!CreateProcessW(pspath,line,0,0,(si.dwFlags&0x100)?1:0,(diagnostic?0x00000010:0x08000000),0,root,&si,&pi)){started=0;err=GetLastError();}
 if(output!=BAD_HANDLE)CloseHandle(output);if(input!=BAD_HANDLE)CloseHandle(input);
 /* A failure without Win32 error must not wait on an empty handle. */
 if(!started)die(W("Impossible d'ouvrir Windows PowerShell. Vérifiez les restrictions de votre organisation."),X_SPAWN,err);
 CloseHandle(pi.hThread);WaitForSingleObject(pi.hProcess,0xffffffff);
 /* From here PowerShell has run: its code is passed through unchanged. */
 if(!GetExitCodeProcess(pi.hProcess,&code))code=X_CHILDCODE;CloseHandle(pi.hProcess);
 if(code && code!=1223 && !quietcheck){
    set(message,CAP,W("Pesto s'est terminé avec une erreur.\r\n\r\nConsultez les journaux de wad\\logs (Pesto-lanceur.log et Pesto-demarrage.log).\r\n\r\nUne fermeture ou une erreur ne prouve pas l'annulation d'une opération Windows déjà engagée. Ne relancez pas une mutation sans en vérifier l'état."));
    MessageBoxW(0,message,W("Pesto 1.0 | Diagnostic"),0x30);
 }
 ExitProcess(code);
}
