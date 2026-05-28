namespace MyApi.Models;

public record ApiError(string Code, string Message, string? Details = null);
