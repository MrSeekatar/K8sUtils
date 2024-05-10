ARG aspNetVersion=8.0.0-jammy-chiseled
# ARG aspNetVersion=8.0.0-jammy
ARG sdkVersion=8.0.100

FROM mcr.microsoft.com/dotnet/aspnet:${aspNetVersion} AS runtime

FROM mcr.microsoft.com/dotnet/sdk:${sdkVersion} AS build

WORKDIR /src/minimal-api
COPY ["minimal-api.csproj", "./"]
RUN dotnet restore "minimal-api.csproj"
COPY . .
RUN dotnet build "minimal-api.csproj" -c Release -o /app/build

FROM build AS publish
RUN dotnet publish "minimal-api.csproj" -c Release -o /app/publish /p:UseAppHost=false

FROM runtime AS final
ARG buildTime

WORKDIR /app

EXPOSE 5095

ENV ASPNETCORE_URLS=http://+:5095
ENV BUILD_TIME=$buildTime

COPY --from=publish /app/publish .
COPY ./Scripts /Scripts

ENTRYPOINT ["dotnet", "minimal-api.dll"]
