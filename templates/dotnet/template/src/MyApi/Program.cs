using System.Text.RegularExpressions;
using Amazon.SimpleSystemsManagement;
using Amazon.SimpleSystemsManagement.Model;
using MyApi.Auth;
using MyApi.Middleware;
using MyApi.Provenance;

var builder = WebApplication.CreateBuilder(args);
builder.Services.AddAWSLambdaHosting(LambdaEventSource.RestApi);
builder.Logging.ClearProviders();
builder.Logging.AddJsonConsole(o => o.TimestampFormat = "yyyy-MM-ddTHH:mm:ssZ");

// Load provenance signing config. Both vars must be set to enable signing;
// absent either means responses are returned unsigned (same opt-in as the Go facade).
var kid = Environment.GetEnvironmentVariable("PROVENANCE_SIGNING_KID");
var keyPath = Environment.GetEnvironmentVariable("PROVENANCE_SIGNING_KEY_PATH");
IProvenanceSigner? provenanceSigner = null;

if (!string.IsNullOrWhiteSpace(kid) && !string.IsNullOrWhiteSpace(keyPath))
{
    using var ssm = new AmazonSimpleSystemsManagementClient();
    var param = await ssm.GetParameterAsync(new GetParameterRequest
    {
        Name = keyPath,
        WithDecryption = true
    });
    provenanceSigner = new ProvenanceSigner(param.Parameter.Value, kid);
}

var app = builder.Build();

app.UseMiddleware<FapiMiddleware>();

app.MapGet("/health", () => Results.Ok(new { status = "healthy" }));

app.MapGet("/uprn/validate/{uprn}", (string uprn) =>
{
    var data = new { valid = Regex.IsMatch(uprn, @"^\d{12}$") };
    return provenanceSigner is not null
        ? Results.Ok(provenanceSigner.Sign(data))
        : Results.Ok(data);
})
.RequireOpdaScopes("land-registry");

// Test-only route used by ScopeFilterTests — not reachable in production (Lambda runs as Production).
if (app.Environment.IsEnvironment("Testing"))
    app.MapGet("/_test/scoped", () => Results.Ok(new { ok = true }))
       .RequireOpdaScopes("test:read");

app.Run();

public partial class Program { }
