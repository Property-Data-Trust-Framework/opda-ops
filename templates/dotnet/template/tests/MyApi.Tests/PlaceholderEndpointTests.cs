// TEMPLATE PLACEHOLDER — delete this file and replace with your API's endpoint tests.
// These tests cover the scaffold UPRN validation stub in Program.cs. Once you replace
// that stub with your real endpoint, these tests will fail with 404 and should be removed.

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

    [Theory]
    [InlineData("123456789012", true)]
    [InlineData("000000000000", true)]
    [InlineData("12345678901",  false)] // 11 digits
    [InlineData("1234567890123", false)] // 13 digits
    [InlineData("12345678901a", false)] // non-numeric
    [InlineData("abcdefghijkl", false)] // all letters
    public async Task Validate_ReturnsExpectedResult(string uprn, bool expectedValid)
    {
        var response = await _client.GetAsync($"/uprn/validate/{uprn}");
        Assert.Equal(HttpStatusCode.OK, response.StatusCode);

        var body = JsonSerializer.Deserialize<JsonElement>(await response.Content.ReadAsStringAsync());
        Assert.Equal(expectedValid, body.GetProperty("valid").GetBoolean());
    }

    [Fact]
    public async Task NoAuthorization_Returns401()
    {
        _client.DefaultRequestHeaders.Authorization = null;
        var response = await _client.GetAsync("/uprn/validate/123456789012");
        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
    }

    [Fact]
    public async Task WrongScope_Returns403()
    {
        _client.DefaultRequestHeaders.Authorization =
            new AuthenticationHeaderValue("Bearer", JsonToken(scope: "other:scope"));
        var response = await _client.GetAsync("/uprn/validate/123456789012");
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
