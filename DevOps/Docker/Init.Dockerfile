ARG aspNetVersion=8.0.0-jammy-chiseled
ARG sdkVersion=8.0.100

FROM mcr.microsoft.com/dotnet/aspnet:${aspNetVersion} AS runtime

FROM mcr.microsoft.com/dotnet/sdk:${sdkVersion} AS build

WORKDIR /src/init-app
COPY ["init-app.csproj", "./"]
RUN dotnet restore "init-app.csproj"
COPY . .
RUN dotnet build "init-app.csproj" -c Release -o /app/build

FROM build AS publish
RUN dotnet publish "init-app.csproj" -c Release -o /app/publish /p:UseAppHost=false

FROM runtime AS final

WORKDIR /app
COPY --from=publish /app/publish .

ENTRYPOINT ["dotnet", "init-app.dll"]
