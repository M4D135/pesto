namespace Pesto.Engine;

/// <summary>
/// Account selected for directory requests. This is an identity label, never a credential or evidence that
/// authentication succeeded. Null means that the reader uses the current Windows process identity.
/// </summary>
public interface IDirectoryAccountDisclosure
{
    string? SelectedAccount { get; }
}
