namespace MyApi.Provenance;

public interface IProvenanceSigner
{
    SignedResponse<T> Sign<T>(T data);
}
