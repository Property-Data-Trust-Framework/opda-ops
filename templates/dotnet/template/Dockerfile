FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build
WORKDIR /src
COPY src/MyApi/MyApi.csproj src/MyApi/
RUN dotnet restore src/MyApi/MyApi.csproj -r linux-x64
COPY src/MyApi/ src/MyApi/
RUN dotnet publish src/MyApi/MyApi.csproj \
    -c Release -o /app/publish --no-restore \
    -r linux-x64 --self-contained true -p:PublishSingleFile=true -p:InvariantGlobalization=true

FROM public.ecr.aws/lambda/provided:al2023
WORKDIR /var/task
COPY --from=build /app/publish/MyApi ./bootstrap
COPY --from=build /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/ca-certificates.crt
ENTRYPOINT ["/var/task/bootstrap"]
