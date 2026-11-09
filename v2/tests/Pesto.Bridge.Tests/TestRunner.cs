using System.Reflection;

namespace Pesto.Bridge.Tests;

/// <summary>Marks a test method: public or internal, static or instance, no parameters, returns void or Task.</summary>
[AttributeUsage(AttributeTargets.Method)]
internal sealed class TestAttribute : Attribute
{
}

internal sealed class TestFailureException(string message) : Exception(message)
{
}

internal static class Check
{
    public static void True(bool condition, string message)
    {
        if (!condition) throw new TestFailureException(message);
    }

    public static void Equal<T>(T expected, T actual, string message)
    {
        if (!EqualityComparer<T>.Default.Equals(expected, actual)) throw new TestFailureException($"{message} (attendu {expected}, obtenu {actual})");
    }

    public static void False(bool condition, string message) => True(!condition, message);
}

/// <summary>Minimal dependency-free test runner: finds [Test] methods by reflection, runs them, prints a summary.</summary>
internal static class TestRunner
{
    private static async Task<int> Main(string[] args)
    {
        var filter = args.Length > 0 ? args[0] : null;
        var tests = typeof(TestRunner).Assembly.GetTypes()
            .SelectMany(t => t.GetMethods(BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Static | BindingFlags.Instance)
                .Where(m => m.GetCustomAttribute<TestAttribute>() is not null)
                .Select(m => (Type: t, Method: m)))
            .Where(x => filter is null || $"{x.Type.Name}.{x.Method.Name}".Contains(filter, StringComparison.OrdinalIgnoreCase))
            .OrderBy(x => x.Type.Name).ThenBy(x => x.Method.Name).ToList();
        int passed = 0, failed = 0;
        foreach (var (type, method) in tests)
        {
            var name = $"{type.Name}.{method.Name}";
            try
            {
                var instance = method.IsStatic ? null : Activator.CreateInstance(type);
                if (method.Invoke(instance, null) is Task task) await task.ConfigureAwait(false);
                passed++;
                Console.WriteLine($"OK    {name}");
            }
            catch (Exception ex)
            {
                failed++;
                var inner = ex is TargetInvocationException tie && tie.InnerException is not null ? tie.InnerException : ex;
                Console.WriteLine($"ECHEC {name} : {inner.Message}");
            }
        }
        Console.WriteLine($"{passed} réussis, {failed} en échec, {tests.Count} au total.");
        // Un filtre qui ne sélectionne aucun test est un échec, jamais un vert vide.
        if (tests.Count == 0)
        {
            Console.WriteLine("AUCUN test sélectionné : vérifier le filtre et les arguments passés après « -- ».");
            return 1;
        }
        return failed == 0 ? 0 : 1;
    }
}
