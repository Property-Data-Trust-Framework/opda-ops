using System.Net;
using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Xunit;

namespace MyApi.Tests;

public class ScopeFilterTests : IClassFixture<ScopeFilterTests.TestingFactory>
{
    private readonly HttpClient _client;

    public ScopeFilterTests(TestingFactory factory) =>
        _client = factory.CreateClient();

    [Fact]
    public async Task NoAuthorization_Returns401()
    {
        var response = await _client.GetAsync("/_test/scoped");
        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
    }

    [Fact]
    public async Task WrongScope_Returns403()
    {
        _client.DefaultRequestHeaders.Authorization =
            new AuthenticationHeaderValue("Bearer", JsonToken(scope: "other:scope"));

        var response = await _client.GetAsync("/_test/scoped");
        Assert.Equal(HttpStatusCode.Forbidden, response.StatusCode);
    }

    [Fact]
    public async Task CorrectScope_Returns200()
    {
        _client.DefaultRequestHeaders.Authorization =
            new AuthenticationHeaderValue("Bearer", JsonToken(scope: "test:read"));

        var response = await _client.GetAsync("/_test/scoped");
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
    }

    [Fact]
    public async Task JwtWithCorrectScope_Returns200()
    {
        _client.DefaultRequestHeaders.Authorization =
            new AuthenticationHeaderValue("Bearer", JwtToken(scope: "test:read"));

        var response = await _client.GetAsync("/_test/scoped");
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
    }

    // Raw JSON bearer token — matches the facade's local dev fallback.
    private static string JsonToken(string scope) =>
        JsonSerializer.Serialize(new { scope });

    // Minimal JWT (unsigned) — header.payload.sig with base64url-encoded payload.
    private static string JwtToken(string scope)
    {
        var header  = Base64UrlEncode("{\"alg\":\"none\"}");
        var payload = Base64UrlEncode(JsonSerializer.Serialize(new { scope }));
        return $"{header}.{payload}.";
    }

    private static string Base64UrlEncode(string s) =>
        Convert.ToBase64String(Encoding.UTF8.GetBytes(s))
               .TrimEnd('=').Replace('+', '-').Replace('/', '_');

    public class TestingFactory : WebApplicationFactory<Program>
    {
        protected override void ConfigureWebHost(IWebHostBuilder builder) =>
            builder.UseEnvironment("Testing");
    }
}
