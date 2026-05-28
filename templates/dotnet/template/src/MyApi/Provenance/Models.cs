using System.Text.Json.Serialization;

namespace MyApi.Provenance;

public record SignedResponse<T>(
    [property: JsonPropertyName("data")] T Data,
    [property: JsonPropertyName("provenance")] ProvenanceBlock Provenance
);

public record ProvenanceBlock(
    [property: JsonPropertyName("alg")] string Alg,
    [property: JsonPropertyName("kid")] string Kid,
    [property: JsonPropertyName("signature")] string Signature,
    [property: JsonPropertyName("signedAt")] string SignedAt,
    [property: JsonPropertyName("payloadHash")] PayloadHash PayloadHash
);

public record PayloadHash(
    [property: JsonPropertyName("alg")] string Alg,
    [property: JsonPropertyName("value")] string Value
);
