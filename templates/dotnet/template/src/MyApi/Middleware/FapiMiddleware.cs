using System.Text.RegularExpressions;
using MyApi.Models;

namespace MyApi.Middleware;

public class FapiMiddleware(RequestDelegate next)
{
    private const string Header = "x-fapi-interaction-id";

    private static readonly Regex UuidV4 = new(
        @"^[a-fA-F0-9]{8}-[a-fA-F0-9]{4}-4[a-fA-F0-9]{3}-[89abAB][a-fA-F0-9]{3}-[a-fA-F0-9]{12}$",
        RegexOptions.Compiled);

    public async Task InvokeAsync(HttpContext context)
    {
        var interactionId = context.Request.Headers[Header].FirstOrDefault();

        if (interactionId is not null)
        {
            if (!UuidV4.IsMatch(interactionId.Trim()))
            {
                context.Response.StatusCode = StatusCodes.Status400BadRequest;
                context.Response.ContentType = "application/json";
                await context.Response.WriteAsJsonAsync(
                    new ApiError("invalid_fapi_interaction_id", "x-fapi-interaction-id must be a UUIDv4"));
                return;
            }
            context.Response.Headers[Header] = interactionId;
        }
        else
        {
            context.Response.Headers[Header] = Guid.NewGuid().ToString();
        }

        await next(context);
    }
}
