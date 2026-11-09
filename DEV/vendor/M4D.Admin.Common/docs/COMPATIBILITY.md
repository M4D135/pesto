# Common 0.2.0 Compatibility contract

The public 0.1.1 APIs remain available. AssemblyVersion remains 0.1.1.0 so existing compiled consumers can bind; FileVersion and informational version are 0.2.0. Every consumer must still verify its explicitly pinned DLL hashes. This does not authorize substituting a DLL under an existing lock.

Core adds bounded text validation, OperationResult and DataContract JSON transport. ResultKind describes a result; it grants no execution permission. The application retains domain identities, lifecycle rules and credential handling.

Diagnostics is optional. Its bounded buffers expose discarded/rejected events. AsyncJournal uses an exclusive new file, a bounded queue and explicit completion/error reporting. Use approved fields only; the redactor is defence in depth, not a credential serializer. A false TryWrite or failed completion must not be interpreted as a persisted audit event.

IO.WriteWithBackup creates a temporary file in the same parent, flushes it, then uses File.Replace with a unique backup. It never deletes the target as a fallback. Use a trusted parent directory; this helper does not claim protection against every concurrent parent-directory replacement or validation of NTFS/SMB semantics on another platform.

Wpf is a separate assembly and dependency. Core, Query, IO and Diagnostics do not depend on it. DispatcherCoalescer is owned/disposed by the view, runs on its dispatcher and coalesces pending requests. RefreshExistingPeer does not create automation peers or move focus. The WPF test requires Windows STA and is not executed on macOS.

## Qualification and release

```text
python3 tools/bootstrap.py
pwsh -NoProfile -File tools/build.ps1 -Tests
pwsh -NoProfile -File tools/test.ps1
python3 -m unittest discover -s tests -p test_*.py
python3 tools/release.py --source dist --output NEW_DIRECTORY --consumer Pesto:Core,Query --consumer Domenia:Core,Query --consumer Filpro:Core,IO --minimum-version 0.1.1
```

The bootstrap alone downloads the Microsoft reference pack, pins its version and SHA512, and does not install a runtime. The build uses C#5 and net472 references. Runtime consumers download nothing. The release helper verifies every binary before copying and emits separate consumer locks; it does not modify any consumer or ship test assemblies.

`tools/public_api.ps1` exports the public API for a baseline comparison. The 0.1.1 test assemblies were also executed against 0.2.0 to test binary compatibility on the local .NET host. These are distinct from a complete Pesto/Domenia/Filpro application test under Windows. Windows qualification remains necessary after consumers update their explicit locks.

The release source commit and dirty state are recorded separately from the source hash. A dirty source is refused by default; --allow-dirty is reserved for an explicitly identified development bundle. A lower version is refused against the supplied minimum. Any breaking API change requires a new compatibility decision, not an automatic lock refresh.
