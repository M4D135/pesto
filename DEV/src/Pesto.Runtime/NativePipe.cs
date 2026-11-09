using System;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;
namespace Pesto {
 public static class NativePipe17 {
  [DllImport("kernel32.dll", SetLastError=true)]
  [return: MarshalAs(UnmanagedType.Bool)]
  public static extern bool GetNamedPipeClientProcessId(SafePipeHandle pipe, out uint pid);
 }
}
