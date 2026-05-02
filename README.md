# DevOps Base Images for .NET


This repository is primarily **documentation**: it explains how to choose Microsoft’s official .NET 10 runtime bases (Ubuntu Noble, Chiseled, Alpine) and how this repo’s optional **Imeritas wrapper images** fit in. Treat it as **ideas and guidelines**—a starting point for **brainstorming** and for picking what **fits best** on future projects—not a fixed rulebook or org-wide mandate. Always align with your team’s standards, risk posture, and registry policies.

Read the sections below first; then use **The Images at a Glance** and the strategy sections for detail.

### For application developers

- **Your main decision:** full Ubuntu (`noble`), Chiseled (`noble-chiseled` / `noble-chiseled-extra`), or Alpine — see **Strategy 1 — Standard Ubuntu (Noble)**, **Strategy 2 — Ubuntu Chiseled**, **Strategy 3 — Alpine Linux**, and [Recommended Approach by Use Case](#recommended-approach-by-use-case) below.
- **Default bias for production .NET:** prefer **noble-chiseled** (or **noble-chiseled-extra** if you need globalization/ICU without the full image); use **full noble** when you need `apt`, a shell in the image, or heavy native stacks (e.g. some drawing/PDF scenarios).
- **If you use Alpine:** you own **musl** caveats (native NuGet deps, `linux-musl-x64` for self-contained) — see [The musl vs glibc Problem in Practice](#the-musl-vs-glibc-problem-in-practice) and the comparison table in [Side-by-Side Comparison](#side-by-side-comparison).

### For platform and DevOps

- **Image catalog:** [The Images at a Glance](#the-images-at-a-glance), [Image Size Comparison](#image-size-comparison-approx-net-10-aspnet-runtime), and [Published images (GHCR)](#published-images-ghcr).
- **CI patterns:** **GitHub Actions — Multi-stage with .NET 10** (section below).
- **Building this repo’s base images locally:** [Getting Started With This Repository](#getting-started-with-this-repository) (paths under `dockerfiles/`, build commands, smoke check).

### For security and compliance

- **Chiseled** reduces surface area (no shell, no package manager in the runtime image) but complicates break-glass debugging — trade off with operational runbooks; see Chiseled cons under **Strategy 2 — Ubuntu Chiseled** below.
- **Alpine vs glibc** affects supply chain and compatibility, not just size — [Side-by-Side Comparison](#side-by-side-comparison) and [The musl vs glibc Problem in Practice](#the-musl-vs-glibc-problem-in-practice) summarize common failure modes.
- **Patching** follows the lifecycles of the **upstream Microsoft** and **distro** images you pin; document your tag/digest policy in your own org — this README does not replace a formal image-allowed list.

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
| --- | --- | --- |
| `10.0-noble` (full Ubuntu) | ~90 MB | ~220 MB |
| `10.0-noble-chiseled` | ~40 MB | ~105 MB |
| `10.0-alpine` | ~45 MB | ~115 MB |
| `10.0-alpine-composite` | ~38 MB | ~98 MB |

> Chiseled Ubuntu and Alpine remain very close in size.
> Size alone is not a strong differentiator.

---

### Multi-stage: Noble SDK vs Imeritas `ubuntu-net-10` runtime

Publish with `mcr.microsoft.com/dotnet/sdk:10.0-noble`, then run the published output on `ghcr.io/imeritas-org/ubuntu-net-10` — the image this repository **builds and publishes** from [`dockerfiles/ubuntu/10/dockerfile`](dockerfiles/ubuntu/10/dockerfile) (not a second arbitrary tag). It layers **security-oriented maintenance and hardening** on top of Microsoft’s ASP.NET Noble base: `apt` **update/upgrade**, pinned packages (**curl**, **libicu74**, **tzdata**, **ca-certificates**), production-oriented **environment** (**`ASPNETCORE_URLS`** on 8080/8443, **`DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=false`**, **server GC** and **`DOTNET_GCHeapHardLimit`**), a dedicated **`imeritas`** account (UID/GID **7777**, home **`/app`**) for non-root-oriented layouts, **`chown`**/`chmod` on **`/app`**, and **`WORKDIR /app`**. That is what you pull from GHCR; see [Published images (GHCR)](#published-images-ghcr).

**Upstream Microsoft runtime only** — `mcr.microsoft.com/dotnet/aspnet:10.0-noble` is Microsoft’s **stock** ASP.NET image. It does **not** include the Dockerfile steps above: no Imeritas package set, env tuning, heap cap, or `imeritas` user from [`dockerfiles/ubuntu/10/dockerfile`](dockerfiles/ubuntu/10/dockerfile).

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

**Imeritas-built runtime (`ubuntu-net-10`)** — final stage only (reuse the same `build` stage). **`FROM ghcr.io/imeritas-org/ubuntu-net-10`** matches the **published artifact** of [`dockerfiles/ubuntu/10/dockerfile`](dockerfiles/ubuntu/10/dockerfile), so local and CI runs use the **same** updated packages, env, GC/memory ceiling, listening ports, ICU, and `/app` layout as production. The stock **`aspnet:10.0-noble`** snippet above cannot surface regressions tied to those layers because **they are not present** in the upstream image.

```dockerfile
# Runtime image = build output of dockerfiles/ubuntu/10/dockerfile (see README prose above).
FROM ghcr.io/imeritas-org/ubuntu-net-10 AS runtime
WORKDIR /app
COPY --from=build /app .
ENTRYPOINT ["dotnet", "MyApp.dll"]
```

## Strategy 1 — Standard Ubuntu (Noble)

Microsoft’s **full** Ubuntu 24.04 **Noble** images (`mcr.microsoft.com/dotnet/*:10.0-noble`) are a **normal Linux container**: a **shell**, **`apt`**, and a broad set of packages on the base image. You get **maximum flexibility** for adding native libraries, using `docker exec` for break-glass debugging, and matching many developers’ “full Linux” expectations. The tradeoff is **size and attack surface** — the stock ASP.NET runtime image is much **larger** than the Chiseled variant for the same .NET version (see Microsoft’s [sample image size report](https://github.com/dotnet/dotnet-docker/blob/main/documentation/sample-image-size-report.md) for relative numbers; sizes move with releases).

**vs Chiseled (summary):** Standard Noble is the choice when you need **apt + shell +** the widest **runtime installability**; Chiseled is the choice when you accept **no apt/shell** in the runtime image in exchange for a **smaller, slimmer** footprint ([Strategy 2 — Ubuntu Chiseled](#strategy-2-ubuntu-chiseled)).

### ✅ Pros

- **glibc** — same C library as most Linux desktops and servers; strongest compatibility for NuGet packages with native `.so` dependencies
- **`apt` + shell** — install or troubleshoot packages (`libgdiplus`, `icu-libs`, debugging tools) in the image when policy allows
- **Default globalization** — typical `aspnet` runtime images include ICU-backed culture support without extra variants
- **Operational familiarity** — behaves like a conventional Ubuntu container for teams used to full distros
- Strong fit for **SkiaSharp**, **ImageSharp**, OpenSSL-heavy workloads, and “install another deb” scenarios
- **Ubuntu 24.04 Noble LTS** — long-term Canonical support until 2029

### ❌ Cons

- **Larger pull and disk use** than Chiseled (and often larger than Alpine) for the same app — see [Image Size Comparison](#image-size-comparison-approx-net-10-aspnet-runtime)
- **More installed packages** than Chiseled → broader patch surface (still bounded by what Microsoft ships in the image)
- **Not “distroless”** — more tooling in the image than minimal/runtime-only layouts

---

## Strategy 2 — Ubuntu Chiseled

**.NET’s Ubuntu Chiseled** images (`*-noble-chiseled`, `*-noble-chiseled-extra`) are **distroless-style**: only the **minimal slice** of Ubuntu required to run .NET, produced with Canonical **Chisel**. Microsoft documents **no package manager**, **no shell**, **non-root by default**, and **far fewer moving parts** than full Noble — which shrinks images and the attack surface compared to standard Ubuntu bases ([official overview](https://github.com/dotnet/dotnet-docker/blob/main/documentation/ubuntu-chiseled.md)). There is **no Chiseled SDK**; you **publish** with `mcr.microsoft.com/dotnet/sdk:*-noble` and run on Chiseled **runtime** tags.

**Main differences from standard Noble:** **smaller** runtime image; **no `apt`/`bash`** in the final stage; **tighter** supply chain; use **`10.0-noble-chiseled-extra`** when you need **ICU + tzdata**-style globalization without switching to the full Ubuntu image (baseline Chiseled ASP.NET tags are **distroless +** different globalization defaults than full Noble — see Microsoft’s variant table in the [sample image size report](https://github.com/dotnet/dotnet-docker/blob/main/documentation/sample-image-size-report.md)).

### ✅ Pros

- **Smaller compressed/uncompressed size** than full Noble for framework-dependent deployments (same report as above)
- **Minimal packages** — only what Chisel includes for that tag
- **No `apt` / no shell** in the runtime image — fewer tools for attackers; aligns with hardened production posture
- **`noble-chiseled-extra`** — ICU/timezone-oriented extras **without** the full Noble image
- **Non-root by default** on these container variants (per Microsoft’s Chiseled documentation)
- **Same glibc / Ubuntu lineage** as Noble — native library behavior matches full Ubuntu better than Alpine **musl**

### ❌ Cons

- **No shell** — `docker exec` into a shell **won’t work** like on full Noble; plan **sidecars**, **ephemeral debug pods**, or CI-driven diagnostics
- **No package manager** — you **cannot** `apt install` at runtime; changes require a **new image** (or advanced Chisel/slice workflows for .NET 10+ per upstream docs)
- **Variant choice** — pick **`chiseled-extra`** explicitly when you need globalization parity closer to full images; otherwise behavior differs from stock `aspnet:noble`
- **Build stage** still uses a **full Ubuntu SDK** image — only the **runtime** stage is Chiseled

---

## Strategy 3 — Alpine Linux

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
| --- | --- | --- | --- |
| **Base C library** | glibc | glibc | musl libc |
| **Image size** | Large (~220MB) | Small (~105MB) | Small (~115MB) |
| **Native lib compatibility** | ✅ Excellent | ✅ Excellent | ⚠️ musl issues |
| **NuGet native deps** | ✅ Full support | ✅ Full support | ⚠️ Hit or miss |
| **Globalization / ICU** | ✅ Out of box | ✅ via `-extra` tag | ❌ Extra config |
| **Shell access (debug)** | ✅ Yes | ❌ No | ✅ Yes |
| **Package manager** | ✅ apt | ❌ None | ✅ apk |
| **Security surface** | Medium | ✅ Minimal | ✅ Minimal |
| **Non-root by default** | ❌ | ✅ | ❌ |
| **Microsoft recommended** | ✅ Yes | ✅ Yes | ⚠️ Conditional |
| **SkiaSharp / Drawing** | ✅ | ✅ | ❌ Needs extra libs |
| **Self-contained publish** | ✅ linux-x64 | ✅ linux-x64 | ⚠️ linux-musl-x64 |
| **Kubernetes pod startup** | Medium | ✅ Fast | ✅ Fast |
| **Ubuntu LTS support** | 2029 (Noble) | 2029 (Noble) | N/A |
| **Best for** | General purpose | Production secure | Simple APIs |

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

## Recommended Approach by Use Case

```text
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

---

## Getting Started With This Repository

This repository builds and publishes .NET 10 ASP.NET Docker base images
(Alpine, Ubuntu Noble, and Ubuntu Noble Chiseled) for downstream applications.

### Prerequisites

- Docker Engine with BuildKit support (`docker buildx` available)
- Git
- A GitHub account/token only if you plan to push images to GHCR (`ghcr.io`)

### Local Setup

```bash
git clone <your-repo-url>
cd Imeritas.DevOps.BaseImages
```

### Published images (GHCR)

Workflows push to **GitHub Container Registry** at `ghcr.io/<lowercase-org>/<image-name>`. The org segment is the GitHub **owner** of this repository (not the repo name). For the `imeritas-org` org, images are:

```bash
docker pull ghcr.io/imeritas-org/alpine-net-10
docker pull ghcr.io/imeritas-org/ubuntu-net-10
docker pull ghcr.io/imeritas-org/ubuntu-chiseled-net-10
```

The same commands work from **PowerShell**, Command Prompt, and bash. Each image is tagged `latest` and with a UTC publish stamp `yyyyMMdd-HHmm` (see `.github/workflows/docker-*.yml`). Use `:latest`, a specific stamp tag, or a digest pin for reproducible builds. Public packages can be pulled without logging in; private packages require `docker login ghcr.io`.

### Local Build Commands

Local tags below are for development only; published names are the `ghcr.io/imeritas-org/...` paths above.

```bash
# Alpine .NET 10 base image
docker build -f dockerfiles/alpine/10/dockerfile -t imeritas/alpine-net-10:local dockerfiles/alpine/10

# Ubuntu Noble .NET 10 base image
docker build -f dockerfiles/ubuntu/10/dockerfile -t imeritas/ubuntu-net-10:local dockerfiles/ubuntu/10

# Ubuntu Noble Chiseled .NET 10 base image
docker build -f dockerfiles/ubuntu-chiseled/10/dockerfile -t imeritas/ubuntu-chiseled-net-10:local dockerfiles/ubuntu-chiseled/10
```

### Smoke Check

```bash
docker run --rm imeritas/ubuntu-net-10:local --info
```

Use the same command with the Alpine and Chiseled tags to verify those images.

### Quick Validation

```bash
docker build -f dockerfiles/alpine/10/dockerfile dockerfiles/alpine/10
docker build -f dockerfiles/ubuntu/10/dockerfile dockerfiles/ubuntu/10
docker build -f dockerfiles/ubuntu-chiseled/10/dockerfile dockerfiles/ubuntu-chiseled/10
```

### Common Setup Issues

1. **Buildx not available**
   - Symptom: `docker buildx` commands fail
   - Fix: install/enable Docker Buildx in your Docker installation
2. **Permission errors pulling base images**
   - Symptom: cannot pull `mcr.microsoft.com/dotnet/aspnet:10.0-*`
   - Fix: verify outbound network access and Docker daemon connectivity
3. **GHCR push/auth problems**
   - Symptom: push fails to `ghcr.io`
   - Fix: authenticate Docker to GHCR and ensure package write permissions
