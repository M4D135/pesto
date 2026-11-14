namespace Pesto.Engine;

/// <summary>
/// Whether this Windows computer is a domain member, read locally by Windows without any directory call.
/// Null means it could not be read. It says nothing about the computer account in AD.
/// </summary>
public interface ILocalDomainMembership
{
    bool? LocalComputerJoined { get; }
}
