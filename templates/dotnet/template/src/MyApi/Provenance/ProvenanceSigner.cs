using System.Security.Cryptography;
using System.Text;

namespace MyApi.Provenance;

public sealed class ProvenanceSigner : IProvenanceSigner, IDisposable
{
    private readonly RSA _rsa;
    private readonly string _kid;

    public ProvenanceSigner(string privateKeyPem, string kid)
    {
        _kid = kid;
        _rsa = RSA.Create();
        _rsa.ImportFromPem(privateKeyPem);
    }

    public SignedResponse<T> Sign<T>(T data)
    {
        var canonical = Jcs.Serialize(data!);
        var canonicalBytes = Encoding.UTF8.GetBytes(canonical);

        var hash = SHA256.HashData(canonicalBytes);
        var signature = _rsa.SignHash(hash, HashAlgorithmName.SHA256, RSASignaturePadding.Pkcs1);

        return new SignedResponse<T>(
            data,
            new ProvenanceBlock(
                Alg: "RS256",
                Kid: _kid,
                Signature: Base64UrlEncode(signature),
                SignedAt: DateTime.UtcNow.ToString("O"),
                PayloadHash: new PayloadHash(
                    Alg: "SHA-256",
                    Value: Base64UrlEncode(hash)
                )
            )
        );
    }

    private static string Base64UrlEncode(byte[] bytes)
        => Convert.ToBase64String(bytes)
            .TrimEnd('=')
            .Replace('+', '-')
            .Replace('/', '_');

    public void Dispose() => _rsa.Dispose();
}
