# Ubuntu vs Alpine Linux for .NET Docker Images (.NET 10)

---

## The Images at a Glance

```bash
# Microsoft's official .NET images — Ubuntu (Noble = 24.04 LTS in .NET 10)
mcr.microsoft.com/dotnet/aspnet:10.0-noble
mcr.microsoft.com/dotnet/aspnet:10.0-noble-chiseled        # minimal Ubuntu
mcr.microsoft.com/dotnet/aspnet:10.0-noble-chiseled-extra  # chiseled + extra libs

# Microsoft's official .NET images — Alpine
mcr.microsoft.com/dotnet/aspnet:10.0-alpine
mcr.microsoft.com/dotnet/aspnet:10.0-alpine3.21
```

---

## Image Size Comparison (approx. .NET 10 ASP.NET runtime)

| Image | Compressed | Uncompressed |
|---|---|---|
| `10.0-noble` (full Ubuntu) | ~90 MB | ~220 MB |
| `10.0-noble-chiseled` | ~40 MB | ~105 MB |
| `10.0-alpine` | ~45 MB | ~115 MB |
| `10.0-alpine-composite` | ~38 MB | ~98 MB |

> Chiseled Ubuntu and Alpine remain very close in size — size alone is not a strong differentiator.

---

## Strategy 1 — Ubuntu Noble / Chiseled

### Standard Ubuntu Noble

```dockerfile
FROM mcr.microsoft.com/dotnet/sdk:10.0-noble AS build
WORKDIR /src
COPY . .
RUN dotnet publish -c Release -o /app

FROM mcr.microsoft.com/dotnet/aspnet:10.0-noble AS runtime
WORKDIR /app
COPY --from=build /app .
ENTRYPOINT ["dotnet", "MyApp.dll"]
```

### Chiseled Ubuntu (minimal — no shell, no package manager)

```dockerfile
FROM mcr.microsoft.com/dotnet/sdk:10.0-noble AS build
WORKDIR /src
COPY . .
RUN dotnet publish -c Release -o /app

FROM mcr.microsoft.com/dotnet/aspnet:10.0-noble-chiseled AS runtime
WORKDIR /app
COPY --from=build /app .
ENTRYPOINT ["dotnet", "MyApp.dll"]
```

### Chiseled Extra (chiseled + ICU + tzdata)

```dockerfile
# Use when you need globalization/timezone support but still want minimal image
FROM mcr.microsoft.com/dotnet/aspnet:10.0-noble-chiseled-extra AS runtime
WORKDIR /app
COPY --from=build /app .
ENTRYPOINT ["dotnet", "MyApp.dll"]
```

### ✅ Pros
- **glibc** — full GNU C Library, maximum .NET native library compatibility
- Standard `apt` tooling — easy to install dependencies (`libgdiplus`, `icu-libs`, etc.)
- Best compatibility with NuGet packages that have native dependencies
- `noble-chiseled` gives Ubuntu familiarity with near-Alpine size
- Chiseled removes shell + package manager — improved security surface
- `noble-chiseled-extra` adds ICU + tzdata — globalization without full image
- Non-root by default on chiseled images
- Microsoft's **recommended** base image for production .NET workloads
- Better support for `SkiaSharp`, `ImageSharp`, OpenSSL bindings
- Ubuntu 24.04 Noble LTS — long-term Canonical support until 2029

### ❌ Cons
- Full `noble` image is significantly larger than Alpine
- More packages = larger attack surface (full image)
- Chiseled has no shell — harder to `docker exec` in for debugging
- Chiseled has no `apt` — can't install tools at runtime

---

## Strategy 2 — Alpine Linux

### ✅ Pros
- Small image size — fast pulls, less registry storage
- Minimal attack surface — fewer installed packages by default
- `apk` package manager still available (unlike chiseled)
- Shell present — `docker exec` debugging works
- Works well for simple REST APIs / gRPC services with no native deps
- Cost savings at scale — less bandwidth, faster CI pipelines
- Good for Kubernetes where pod startup speed matters

### ❌ Cons
- Uses **musl libc** instead of glibc — root cause of most Alpine .NET pain
- Many NuGet packages with native components **don't support musl**
- `SkiaSharp`, `libgdiplus` require extra work or fail silently
- ICU / globalization issues — must explicitly configure
- `--runtime linux-musl-x64` required for self-contained — easy to miss
- Some `PInvoke` / interop scenarios break under musl
- Less alignment with dev machines — "works locally, fails in Alpine"
- Microsoft does **not** recommend Alpine for production .NET in most scenarios

---

## Side-by-Side Comparison

| Factor | Ubuntu Noble | Ubuntu Chiseled | Alpine |
|---|---|---|---|
| **Base C library** | glibc | glibc | musl libc |
| **Image size** | Large (~220MB) | Small (~105MB) | Small (~115MB) |
| **Native lib compatibility** | ✅ Excellent | ✅ Excellent | ⚠️ musl issues |
| **NuGet native deps** | ✅ Full support | ✅ Full support | ⚠️ Hit or miss |
| **Globalization / ICU** | ✅ Out of box | ✅ via `-extra` tag | ❌ Extra config needed |
| **Shell access (debug)** | ✅ Yes | ❌ No | ✅ Yes |
| **Package manager** | ✅ apt | ❌ None | ✅ apk |
| **Security surface** | Medium | ✅ Minimal | ✅ Minimal |
| **Non-root by default** | ❌ | ✅ | ❌ |
| **Microsoft recommended** | ✅ Yes | ✅ Yes | ⚠️ Conditional |
| **SkiaSharp / Drawing** | ✅ | ✅ | ❌ Needs extra libs |
| **Self-contained publish** | ✅ linux-x64 | ✅ linux-x64 | ⚠️ linux-musl-x64 |
| **Kubernetes pod startup** | Medium | ✅ Fast | ✅ Fast |
| **Ubuntu LTS support** | 2029 (Noble) | 2029 (Noble) | N/A |
| **Best for** | General purpose | Production secure | Simple APIs, no native deps |

---

## The musl vs glibc Problem in Practice

```bash
# Common Alpine runtime failure — native lib not found
System.DllNotFoundException: Unable to load shared library 'libgdiplus'

# Common Alpine globalization failure
Unhandled exception: System.Globalization.CultureNotFoundException:
Only the invariant culture is supported in globalization-invariant mode.

# Fix 1 — install missing libs in Alpine Dockerfile
RUN apk add --no-cache \
    icu-libs \
    libgdiplus \
    krb5-libs \
    libintl \
    libssl3

# Fix 2 — invariant globalization mode (loss of culture support)
ENV DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=1

# Fix 3 — use noble-chiseled-extra instead (globalization included)
FROM mcr.microsoft.com/dotnet/aspnet:10.0-noble-chiseled-extra
```

---

## GitHub Actions — Multi-stage with .NET 10

```yaml
- name: Build and push Docker image
  run: |
    docker build \
      --build-arg DOTNET_VERSION=10.0 \
      -t myapp:${{ github.ref_name }} .
    docker push myapp:${{ github.ref_name }}
```

```dockerfile
ARG DOTNET_VERSION=10.0

FROM mcr.microsoft.com/dotnet/sdk:${DOTNET_VERSION}-noble AS build
WORKDIR /src
COPY ["MyApp.csproj", "."]
RUN dotnet restore
COPY . .
RUN dotnet publish -c Release -o /app --no-restore

FROM mcr.microsoft.com/dotnet/aspnet:${DOTNET_VERSION}-noble-chiseled AS runtime
WORKDIR /app
COPY --from=build /app .
EXPOSE 8080
ENTRYPOINT ["dotnet", "MyApp.dll"]
```

---

## Recommended Approach by Use Case

```
General-purpose ASP.NET Core API?
    └── noble-chiseled — best balance of size, security, compatibility

Needs SkiaSharp, ImageSharp, System.Drawing, PDF libs?
    └── noble (full) or noble-chiseled-extra — Alpine will cause pain

Needs globalization / timezone but wants small image?
    └── noble-chiseled-extra — ICU + tzdata included

Simple gRPC / REST service, no native deps?
    └── Alpine is fine — small, fast, works well

Need to docker exec in for debugging?
    └── noble (full) or Alpine — chiseled has no shell

Production, security-hardened, non-root?
    └── noble-chiseled — Microsoft's recommended production image

Self-contained single binary?
    └── Alpine with linux-musl-x64 or chiseled with linux-x64
```
