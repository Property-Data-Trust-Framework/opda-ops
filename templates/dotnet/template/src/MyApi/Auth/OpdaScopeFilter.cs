using System.Security.Claims;
using System.Text;
using System.Text.Json;
using MyApi.Models;

namespace MyApi.Auth;

public static class OpdaScopeFilter
{
    public static RouteHandlerBuilder RequireOpdaScopes(this RouteHandlerBuilder builder, params string[] required)
        => builder.AddEndpointFilter(async (ctx, next) =>
        {
            var http = ctx.HttpContext;
            var scopes = ScopesFromClaims(http) ?? ScopesFromBearerToken(http);

            if (scopes is null)
                return Results.Json(
                    new ApiError("missing_authorization", "Authorization: Bearer token is required"),
                    statusCode: StatusCodes.Status401Unauthorized);

            if (!required.All(scopes.Contains))
                return Results.Json(
                    new ApiError("insufficient_scope", $"Token does not contain required scope(s): {string.Join(", ", required)}"),
                    statusCode: StatusCodes.Status403Forbidden);

            return await next(ctx);
        });

    // Amazon.Lambda.AspNetCoreServer marshals the API Gateway authorizer context into HttpContext.User claims.
    // The Lambda authorizer puts the scope as a space-delimited string under the "scope" key, which becomes
    // a single claim of type "scope".
    private static HashSet<string>? ScopesFromClaims(HttpContext http)
    {
        var scopeClaim = http.User.FindFirst("scope")?.Value;
        if (string.IsNullOrWhiteSpace(scopeClaim)) return null;
        return scopeClaim.Split(' ', StringSplitOptions.RemoveEmptyEntries).ToHashSet();
    }

    private static HashSet<string>? ScopesFromBearerToken(HttpContext http)
    {
        var auth = http.Request.Headers.Authorization.FirstOrDefault();
        if (auth is null || !auth.StartsWith("Bearer ", StringComparison.OrdinalIgnoreCase))
            return null;

        var token = auth["Bearer ".Length..].Trim();
        return ParseScopes(TryParseAsJson(token) ?? TryDecodeJwtPayload(token));
    }

    private static HashSet<string>? ParseScopes(JsonElement? json)
    {
        if (json is null) return null;
        var el = json.Value;

        if (el.TryGetProperty("scope", out var scope) && scope.ValueKind == JsonValueKind.String)
            return scope.GetString()!.Split(' ', StringSplitOptions.RemoveEmptyEntries).ToHashSet();

        if (el.TryGetProperty("scopes", out var scopes) && scopes.ValueKind == JsonValueKind.Array)
            return scopes.EnumerateArray().Select(e => e.GetString()!).ToHashSet();

        return null;
    }

    private static JsonElement? TryParseAsJson(string s)
    {
        try { return JsonDocument.Parse(s).RootElement; }
        catch { return null; }
    }

    private static JsonElement? TryDecodeJwtPayload(string token)
    {
        var parts = token.Split('.');
        if (parts.Length != 3) return null;
        try
        {
            var payload = parts[1].Replace('-', '+').Replace('_', '/');
            payload = payload.PadRight(payload.Length + (4 - payload.Length % 4) % 4, '=');
            return JsonDocument.Parse(Encoding.UTF8.GetString(Convert.FromBase64String(payload))).RootElement;
        }
        catch { return null; }
    }
}
