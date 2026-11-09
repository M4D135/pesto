using System.Buffers.Binary;
using System.ComponentModel;
using System.Diagnostics;
using System.Security.Cryptography;
using System.Text;
using Pesto.Core;

namespace Pesto.Engine.Live;

/// <summary>One on-demand, serialized reader per interactive application. Only the PowerShell process and its
/// imported module are reused. Each request runs the original compiled reader with private input and a fresh scope.</summary>
internal sealed class InteractiveReadSession : IDisposable
{
    internal const int RequestLimit = 1024 * 1024, ResponseLimit = 8 * 1024 * 1024;
    private const int HeaderBytes = 20;
    private const byte Ready = 0x50;
    private static readonly UTF8Encoding Utf8 = new(false, true);
    private readonly object gate = new();
    private readonly CancellationTokenSource stopping = new();
    private readonly TimeSpan timeout;
    private readonly string host;
    private readonly string? testShell;
    private Child? child;
    private int closed;

    // The application never supplies another shell. The override permits this same wire protocol to be tested on macOS.
    internal InteractiveReadSession(string script, TimeSpan timeout, string? testShell = null)
    {
        if (testShell is not null && OperatingSystem.IsWindows()) throw new InvalidOperationException("Windows uses the fixed PS5.1 host.");
        this.timeout = timeout;
        this.testShell = testShell;
        host = "$pestoRead = {\n" + script + "\n}\n"
            + FormattableString.Invariant($"$requestLimit={RequestLimit};$responseLimit={ResponseLimit};$headerBytes={HeaderBytes};$readyByte={Ready}\n") + Loop;
    }

    internal string Execute(string json, string? modulePath)
    {
        var length = Utf8.GetByteCount(json);
        if (length is < 1 or > RequestLimit) throw new PestoException("directory.unavailable", "Requête de lecture annuaire trop volumineuse.");
        var start = Stopwatch.GetTimestamp();
        if (!Monitor.TryEnter(gate, timeout)) throw new PestoException("directory.transient", "Le lecteur annuaire reste occupé.");
        try
        {
            if (Volatile.Read(ref closed) != 0) throw Closed();
            if (child is not null && !string.Equals(child.ModulePath, modulePath, StringComparison.OrdinalIgnoreCase)) StopChild(graceful: true);
            child ??= new Child(host, modulePath, testShell);
            var current = child;
            var remaining = timeout - Stopwatch.GetElapsedTime(start);
            var exchange = current.ExchangeAsync(host, json);
            try
            {
                if (remaining <= TimeSpan.Zero) throw new TimeoutException();
                return exchange.WaitAsync(remaining, stopping.Token).GetAwaiter().GetResult();
            }
            catch
            {
                // Close only this generation. Its late response can never satisfy a subsequent call.
                StopChild(graceful: false);
                _ = exchange.ContinueWith(task => _ = task.Exception, CancellationToken.None,
                    TaskContinuationOptions.OnlyOnFaulted | TaskContinuationOptions.ExecuteSynchronously, TaskScheduler.Default);
                throw;
            }
        }
        catch (OperationCanceledException) when (stopping.IsCancellationRequested) { throw Closed(); }
        catch (TimeoutException) { throw new PestoException("directory.transient", "Délai de lecture annuaire atteint. Aucun résultat partiel n’est publié."); }
        catch (InvalidDataException) { throw new PestoException("directory.unavailable", "Réponse du lecteur annuaire hors protocole. Aucun résultat n’est publié."); }
        catch (DecoderFallbackException) { throw new PestoException("directory.unavailable", "Réponse du lecteur annuaire illisible."); }
        catch (IOException) { throw new PestoException("directory.transient", "Le processus de lecture annuaire s’est interrompu. Aucun résultat partiel n’est publié."); }
        catch (Win32Exception) { throw new PestoException("directory.unavailable", "Le lecteur Windows PowerShell ne peut pas démarrer avec les protections requises."); }
        finally { Monitor.Exit(gate); }
    }

    private static PestoException Closed() => new("directory.unavailable", "Le lecteur annuaire de cette fenêtre est fermé.");
    private void StopChild(bool graceful) { var old = child; child = null; old?.Close(graceful); }
    public void Dispose()
    {
        if (Interlocked.Exchange(ref closed, 1) != 0) return;
        stopping.Cancel();
        lock (gate) { StopChild(graceful: true); stopping.Dispose(); }
    }

    private sealed class Child
    {
        private readonly Process process;
        private readonly OwnedMutationJob? job;
        private bool ready;
        public string? ModulePath { get; }
        public Child(string host, string? modulePath, string? testShell)
        {
            ModulePath = modulePath;
            var info = PowerShellFixedWorker.StartInfo(host);
            if (testShell is not null) info.FileName = testShell;
            else if (!OperatingSystem.IsWindows()) throw new PlatformNotSupportedException();
            // AD's implicit drive is unnecessary for these explicit -Server reads.
            info.Environment["ADPS_LoadDefaultDrive"] = "0";
            process = Process.Start(info) ?? throw new IOException();
            try
            {
                if (OperatingSystem.IsWindows()) job = OwnedMutationJob.Attach(process);
                // Drain diagnostics without storing a second copy of directory facts or an unbounded error stream.
                _ = process.StandardError.BaseStream.CopyToAsync(Stream.Null).ContinueWith(t => _ = t.Exception,
                    CancellationToken.None, TaskContinuationOptions.OnlyOnFaulted, TaskScheduler.Default);
            }
            catch { Close(graceful: false); throw; }
        }

        public async Task<string> ExchangeAsync(string host, string json)
        {
            var input = process.StandardInput.BaseStream;
            var output = process.StandardOutput.BaseStream;
            if (!ready)
            {
                using var initialization = DirectoryReadEvents.Log.Measure("reader", "worker.bootstrap");
                await PowerShellFixedWorker.SendScriptAsync(process, host).ConfigureAwait(false);
                // The bootstrap's text reader must consume only the script line before binary frames begin.
                var ack = new byte[1]; await output.ReadExactlyAsync(ack).ConfigureAwait(false);
                if (ack[0] != Ready) throw new InvalidDataException();
                ready = true;
            }
            var bytes = Utf8.GetBytes(json);
            var header = new byte[HeaderBytes];
            var id = Guid.NewGuid(); id.TryWriteBytes(header);
            BinaryPrimitives.WriteInt32LittleEndian(header.AsSpan(16), bytes.Length);
            try
            {
                await input.WriteAsync(header).ConfigureAwait(false);
                await input.WriteAsync(bytes).ConfigureAwait(false);
                await input.FlushAsync().ConfigureAwait(false);
            }
            finally { CryptographicOperations.ZeroMemory(bytes); }
            await output.ReadExactlyAsync(header).ConfigureAwait(false);
            var length = BinaryPrimitives.ReadInt32LittleEndian(header.AsSpan(16));
            if (new Guid(header.AsSpan(0, 16)) != id || length is < 1 or > ResponseLimit) throw new InvalidDataException();
            var response = new byte[length];
            try { await output.ReadExactlyAsync(response).ConfigureAwait(false); return Utf8.GetString(response); }
            finally { CryptographicOperations.ZeroMemory(response); }
        }

        public void Close(bool graceful)
        {
            try
            {
                if (graceful && !process.HasExited)
                {
                    process.StandardInput.Close();
                    process.WaitForExit(500);
                }
            }
            catch (Exception error) when (error is IOException or InvalidOperationException or Win32Exception) { }
            finally
            {
                if (job is not null) job.Dispose(); // Windows kills precisely this job's members.
                else
                {
                    try { if (!process.HasExited) process.Kill(); }
                    catch (Exception error) when (error is InvalidOperationException or Win32Exception) { }
                }
                process.Dispose();
            }
        }
    }

    // Frames: 16 opaque request-id bytes, 4 little-endian length bytes, then bounded UTF-8 JSON.
    // The bootstrap verifies this loop and the complete compiled body before exposing the pipe.
    private const string Loop = """
$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$wireIn=[Console]::OpenStandardInput();$wireOut=[Console]::OpenStandardOutput();$consoleReader=[Console]::In
$utf8=[Text.UTF8Encoding]::new($false,$true)
function Read-Bytes([byte[]]$buffer,[bool]$allowEof){
  $offset=0
  while($offset -lt $buffer.Length){
    $count=$wireIn.Read($buffer,$offset,$buffer.Length-$offset)
    if($count -eq 0){if($allowEof -and $offset -eq 0){return $false};throw 'Incomplete request'}
    $offset+=$count
  }
  return $true
}
function Invoke-ReadFrame([byte[]]$header){
  $length=[BitConverter]::ToInt32($header,16)
  if($length -lt 1 -or $length -gt $requestLimit){throw 'Invalid request length'}
  $bytes=[byte[]]::new($length);$reader=$null;$replyBytes=$null
  try{
    $null=Read-Bytes $bytes $false
    $reader=[IO.StringReader]::new($utf8.GetString($bytes));[Console]::SetIn($reader)
    $answer= & $pestoRead 3>$null 4>$null 5>$null 6>$null
    $size=if($answer -is [string]){$utf8.GetByteCount($answer)}else{0}
    if($size -lt 1 -or $size -gt $responseLimit){$size=-1}
    [BitConverter]::GetBytes([int]$size).CopyTo($header,16);$wireOut.Write($header,0,$header.Length)
    if($size -gt 0){$replyBytes=$utf8.GetBytes($answer);$wireOut.Write($replyBytes,0,$replyBytes.Length)}
    $wireOut.Flush()
    if($size -lt 0){throw 'Invalid response length'}
  }finally{
    [Console]::SetIn($consoleReader);if($reader){$reader.Dispose()}
    [Array]::Clear($bytes,0,$bytes.Length);if($null -ne $replyBytes){[Array]::Clear($replyBytes,0,$replyBytes.Length)}
    $Error.Clear()
  }
}
$wireOut.WriteByte($readyByte);$wireOut.Flush()
$header=[byte[]]::new($headerBytes)
while((Read-Bytes $header $true)){Invoke-ReadFrame $header}
""";
}
