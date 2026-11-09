using System.Text.Json.Nodes;

namespace Pesto.Engine;

/// <summary>
/// Response builders. Keys are written exactly as the bridge contract declares them (camelCase) and an explicit
/// <c>null</c> is preserved so the page can distinguish "unknown" from "empty". The engine, not the transport, owns the shape.
/// </summary>
internal static class Resp
{
    public static JsonObject Obj() => new();

    public static JsonObject Obj(params (string Key, object? Value)[] members)
    {
        var obj = new JsonObject();
        foreach (var (key, value) in members) obj[key] = Node(value);
        return obj;
    }

    public static JsonArray Arr() => new();

    public static JsonArray Arr<T>(IEnumerable<T> items, Func<T, JsonNode?> project)
    {
        var array = new JsonArray();
        foreach (var item in items) array.Add(project(item));
        return array;
    }

    /// <summary>Wraps a CLR value; a null CLR value becomes an explicit JSON null (kept by the transport).</summary>
    public static JsonNode? Node(object? value) => value switch
    {
        null => null,
        JsonNode node => node,
        string text => JsonValue.Create(text),
        bool flag => JsonValue.Create(flag),
        int number => JsonValue.Create(number),
        long number => JsonValue.Create(number),
        _ => throw new InvalidOperationException("Type de réponse non pris en charge : " + value.GetType().Name),
    };
}
