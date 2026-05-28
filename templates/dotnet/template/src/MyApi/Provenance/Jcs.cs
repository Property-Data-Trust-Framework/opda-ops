using System.Text;
using System.Text.Json;

namespace MyApi.Provenance;

/// <summary>
/// RFC 8785 JSON Canonicalization Scheme (JCS).
/// Produces deterministic JSON: objects with keys sorted by Unicode code point,
/// no insignificant whitespace. Compatible with the Go ucarion/jcs library used
/// by opda-lr-facade, enabling cross-language signature verification.
/// </summary>
public static class Jcs
{
    public static string Serialize(object value)
    {
        var json = JsonSerializer.Serialize(value);
        using var doc = JsonDocument.Parse(json);
        var sb = new StringBuilder();
        AppendElement(doc.RootElement, sb);
        return sb.ToString();
    }

    private static void AppendElement(JsonElement el, StringBuilder sb)
    {
        switch (el.ValueKind)
        {
            case JsonValueKind.Object:
                sb.Append('{');
                var props = el.EnumerateObject()
                    .OrderBy(p => p.Name, StringComparer.Ordinal)
                    .ToList();
                for (var i = 0; i < props.Count; i++)
                {
                    if (i > 0) sb.Append(',');
                    sb.Append('"');
                    AppendEscaped(props[i].Name, sb);
                    sb.Append("\":");
                    AppendElement(props[i].Value, sb);
                }
                sb.Append('}');
                break;

            case JsonValueKind.Array:
                sb.Append('[');
                var items = el.EnumerateArray().ToList();
                for (var i = 0; i < items.Count; i++)
                {
                    if (i > 0) sb.Append(',');
                    AppendElement(items[i], sb);
                }
                sb.Append(']');
                break;

            case JsonValueKind.String:
                sb.Append('"');
                AppendEscaped(el.GetString()!, sb);
                sb.Append('"');
                break;

            case JsonValueKind.Number:
                sb.Append(el.GetRawText());
                break;

            case JsonValueKind.True:
                sb.Append("true");
                break;

            case JsonValueKind.False:
                sb.Append("false");
                break;

            case JsonValueKind.Null:
                sb.Append("null");
                break;
        }
    }

    private static void AppendEscaped(string s, StringBuilder sb)
    {
        foreach (var c in s)
        {
            switch (c)
            {
                case '"':  sb.Append("\\\""); break;
                case '\\': sb.Append("\\\\"); break;
                case '\b': sb.Append("\\b");  break;
                case '\f': sb.Append("\\f");  break;
                case '\n': sb.Append("\\n");  break;
                case '\r': sb.Append("\\r");  break;
                case '\t': sb.Append("\\t");  break;
                default:
                    if (c < 0x20)
                        sb.Append($"\\u{(int)c:x4}");
                    else
                        sb.Append(c);
                    break;
            }
        }
    }
}
