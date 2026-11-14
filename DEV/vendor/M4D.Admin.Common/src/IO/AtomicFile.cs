using System;
using System.IO;

namespace M4D.Admin.Common.IO
{
    public static class AtomicFile
    {
        private static void RejectLinks(string path)
        {
            var current = Path.GetFullPath(path);
            while (!String.IsNullOrEmpty(current))
            {
                // GetAttributes observes dangling links too; Exists() would hide them.
                try { if ((File.GetAttributes(current) & FileAttributes.ReparsePoint) != 0) throw new IOException("Linked path refused."); }
                catch (FileNotFoundException) { }
                catch (DirectoryNotFoundException) { }
                current = Path.GetDirectoryName(current);
            }
        }
        // Existing target uses File.Replace: never delete it as a fallback when ACL/replace fails.
        public static string WriteWithBackup(string path, byte[] bytes)
        {
            if (bytes == null) throw new ArgumentNullException("bytes");
            path = Path.GetFullPath(path); RejectLinks(path);
            var parent = Path.GetDirectoryName(path);
            if (!Directory.Exists(parent)) throw new DirectoryNotFoundException(parent);
            var stage = Path.Combine(parent, ".m4d-" + Guid.NewGuid().ToString("N") + ".tmp");
            var backup = path + "." + Guid.NewGuid().ToString("N") + ".bak";
            try
            {
                using (var stream = new FileStream(stage, FileMode.CreateNew, FileAccess.Write, FileShare.None)) { stream.Write(bytes, 0, bytes.Length); stream.Flush(true); }
                RejectLinks(path);
                if (File.Exists(path)) { File.Replace(stage, path, backup, false); return backup; }
                File.Move(stage, path); return null;
            }
            finally { if (File.Exists(stage)) File.Delete(stage); }
        }
    }
}
