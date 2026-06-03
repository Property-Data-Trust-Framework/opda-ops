// TEMPLATE PLACEHOLDER — delete this file and replace with your API's endpoint tests.
// These tests cover the scaffold placeholder endpoint in Program.cs. Once you replace
// that placeholder with your real endpoint, these tests will fail with 404 and should be removed.

using System.Net;
using System.Net.Http.Headers;
using System.Text.Json;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Xunit;

namespace MyApi.Tests;

public class PlaceholderEndpointTests : IClassFixture<PlaceholderEndpointTests.TestingFactory>
{
    private readonly HttpClient _client;

    public PlaceholderEndpointTests(TestingFactory factory)
    {
        _client = factory.CreateClient();
        _client.DefaultRequestHeaders.Authorization =
            new AuthenticationHeaderValue("Bearer", JsonToken(scope: "land-registry"));
    }

    [Fact]
    public async Task GetPlaceholder_Returns200()
    {
        var response = await _client.GetAsync("/v1/placeholder");
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);

        var body = JsonSerializer.Deserialize<JsonElement>(await response.Content.ReadAsStringAsync());
        Assert.Equal("placeholder", body.GetProperty("message").GetString());
    }

    [Fact]
    public async Task NoAuthorization_Returns401()
    {
        _client.DefaultRequestHeaders.Authorization = null;
        var response = await _client.GetAsync("/v1/placeholder");
        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
    }

    [Fact]
    public async Task WrongScope_Returns403()
    {
        _client.DefaultRequestHeaders.Authorization =
            new AuthenticationHeaderValue("Bearer", JsonToken(scope: "other:scope"));
        var response = await _client.GetAsync("/v1/placeholder");
        Assert.Equal(HttpStatusCode.Forbidden, response.StatusCode);
    }

    private static string JsonToken(string scope) =>
        JsonSerializer.Serialize(new { scope });

    public class TestingFactory : WebApplicationFactory<Program>
    {
        protected override void ConfigureWebHost(IWebHostBuilder builder) =>
            builder.UseEnvironment("Testing");
    }
}
