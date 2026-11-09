using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Security.Cryptography;
using System.Threading;

namespace M4D.Admin.Common.IO
{
    /// <summary>Streaming SHA256. No metadata cache is an integrity proof.</summary>
    public static class ContentHash
    {
        public static string Sha256(string path, CancellationToken token)
        {
            if (String.IsNullOrWhiteSpace(path)) throw new ArgumentException("A file path is required.", "path");
            token.ThrowIfCancellationRequested();
            using (FileStream input = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read, 1048576, FileOptions.SequentialScan))
                return Sha256(input, token);
        }
        /// <summary>Reads from current position to EOF. Caller owns the stream.</summary>
        public static string Sha256(Stream input, CancellationToken token)
        {
            if (input == null) throw new ArgumentNullException("input");
            if (!input.CanRead) throw new ArgumentException("A readable stream is required.", "input");
            using (SHA256 sha = SHA256.Create())
            {
                byte[] buffer = new byte[1048576];
                while (true)
                {
                    token.ThrowIfCancellationRequested();
                    int count = input.Read(buffer, 0, buffer.Length);
                    if (count == 0) break;
                    token.ThrowIfCancellationRequested();
                    sha.TransformBlock(buffer, 0, count, buffer, 0);
                }
                token.ThrowIfCancellationRequested();
                sha.TransformFinalBlock(new byte[0], 0, 0);
                return BitConverter.ToString(sha.Hash).Replace("-", "");
            }
        }
    }
    public sealed class FootprintResult
    {
        public string Path { get; internal set; }
        public decimal Bytes { get; internal set; }
        public long Entries { get; internal set; }
        public long Unreadable { get; internal set; }
        public long LinksSkipped { get; internal set; }
        public long OtherLinks { get; internal set; }
        public long ReparseFiles { get; internal set; }
        public long MaximumFileBytes { get; internal set; }
        public bool Truncated { get; internal set; }
        public bool Complete { get; internal set; }
        public double ElapsedSeconds { get; internal set; }
        public string[] Issues { get; internal set; }
    }
    /// <summary>
    /// Metadata estimate only: no content read, no write, no snapshot guarantee.
    /// Cancellation/time budgets are cooperative between filesystem calls; an OS call can block.
    /// Reparse ancestors/root are refused. Children are rechecked before traversal.
    /// Hidden+System reparse directories are Windows compatibility exclusions; others make coverage incomplete.
    /// Concurrent rename/reparse replacement still requires product-specific handle guards before writes.
    /// </summary>
    public static class FileFootprint
    {
        private static void CheckAncestors(string full)
        {
            DirectoryInfo current = new DirectoryInfo(full);
            while (current != null)
            {
                FileAttributes attributes = File.GetAttributes(current.FullName);
                if ((attributes & FileAttributes.ReparsePoint) != 0)
                    throw new IOException("Reparse root or ancestor is not supported: " + current.FullName);
                if ((attributes & FileAttributes.Directory) == 0)
                    throw new IOException("A directory is required: " + current.FullName);
                current = current.Parent;
            }
        }
        private static void Issue(List<string> issues, string message)
        {
            if (issues.Count < 100) issues.Add(message.Length > 2048 ? message.Substring(0, 2048) : message);
        }
        private static bool LinkDirectory(FileAttributes attributes, string path, FootprintResult result, List<string> issues)
        {
            if ((attributes & (FileAttributes.Directory | FileAttributes.ReparsePoint)) != (FileAttributes.Directory | FileAttributes.ReparsePoint)) return false;
            if ((attributes & (FileAttributes.Hidden | FileAttributes.System)) == (FileAttributes.Hidden | FileAttributes.System)) result.LinksSkipped++;
            else { result.OtherLinks++; Issue(issues, "Directory link skipped: " + path); }
            return true;
        }
        public static FootprintResult Scan(string root, int maximumEntries, int maximumSeconds, CancellationToken token)
        {
            return Scan(root, maximumEntries, maximumSeconds, token, null);
        }
        /// <summary>Optional local cancellation marker, polled at most every 100ms between OS calls.</summary>
        public static FootprintResult Scan(string root, int maximumEntries, int maximumSeconds, CancellationToken token, string cancellationFile)
        {
            if (String.IsNullOrWhiteSpace(root) || !System.IO.Path.IsPathRooted(root)) throw new ArgumentException("An absolute root is required.", "root");
            if (maximumEntries < 1 || maximumEntries > 3000000) throw new ArgumentOutOfRangeException("maximumEntries");
            if (maximumSeconds < 1 || maximumSeconds > 300) throw new ArgumentOutOfRangeException("maximumSeconds");
            token.ThrowIfCancellationRequested();
            Stopwatch watch = Stopwatch.StartNew();
            long nextCancellationCheck = 0;
            Action check = delegate {
                token.ThrowIfCancellationRequested();
                if (!String.IsNullOrEmpty(cancellationFile) && watch.ElapsedMilliseconds >= nextCancellationCheck)
                {
                    nextCancellationCheck = watch.ElapsedMilliseconds + 100;
                    if (File.Exists(cancellationFile)) throw new OperationCanceledException("Cancellation marker present.", token);
                }
            };
            check();
            string full = System.IO.Path.GetFullPath(root);
            CheckAncestors(full);
            FootprintResult result = new FootprintResult { Path = full, Issues = new string[0] };
            List<string> issues = new List<string>();
            Stack<string> pending = new Stack<string>();
            pending.Push(full);
            while (pending.Count != 0 && !result.Truncated)
            {
                check();
                if (watch.Elapsed.TotalSeconds >= maximumSeconds) { result.Truncated = true; break; }
                string directory = pending.Pop();
                try
                {
                    FileAttributes current = File.GetAttributes(directory);
                    if (LinkDirectory(current, directory, result, issues)) continue;
                    using (IEnumerator<string> entries = Directory.EnumerateFileSystemEntries(directory).GetEnumerator())
                    {
                        while (true)
                        {
                            check();
                            if (watch.Elapsed.TotalSeconds >= maximumSeconds) { result.Truncated = true; break; }
                            if (!entries.MoveNext()) break;
                            if (result.Entries >= maximumEntries) { result.Truncated = true; break; }
                            string entry = entries.Current;
                            result.Entries++;
                            try
                            {
                                FileAttributes attributes = File.GetAttributes(entry);
                                if (LinkDirectory(attributes, entry, result, issues)) continue;
                                if ((attributes & FileAttributes.Directory) != 0) { pending.Push(entry); continue; }
                                FileInfo info = new FileInfo(entry);
                                long length = info.Length;
                                result.Bytes += length;
                                result.MaximumFileBytes = Math.Max(result.MaximumFileBytes, length);
                                if ((attributes & FileAttributes.ReparsePoint) != 0) result.ReparseFiles++;
                            }
                            catch (OperationCanceledException) { throw; }
                            catch (IOException ex) { result.Unreadable++; Issue(issues, entry + ": " + ex.Message); }
                            catch (UnauthorizedAccessException ex) { result.Unreadable++; Issue(issues, entry + ": " + ex.Message); }
                            catch (System.Security.SecurityException ex) { result.Unreadable++; Issue(issues, entry + ": " + ex.Message); }
                        }
                    }
                }
                catch (OperationCanceledException) { throw; }
                catch (IOException ex) { result.Unreadable++; Issue(issues, directory + ": " + ex.Message); }
                catch (UnauthorizedAccessException ex) { result.Unreadable++; Issue(issues, directory + ": " + ex.Message); }
                catch (System.Security.SecurityException ex) { result.Unreadable++; Issue(issues, directory + ": " + ex.Message); }
            }
            nextCancellationCheck = 0; check();
            result.ElapsedSeconds = watch.Elapsed.TotalSeconds;
            result.Issues = issues.ToArray();
            result.Complete = !result.Truncated && result.Unreadable == 0 && result.OtherLinks == 0;
            return result;
        }
    }
}
