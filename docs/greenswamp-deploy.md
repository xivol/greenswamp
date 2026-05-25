# Lecture Outline: Deploying ASP.NET Applications with Docker and CI/CD

**Audience:** Developers with basic knowledge of ASP.NET Core; no prior Docker experience required.  
**Duration:** ~105 minutes (including demos)  
**Learning Objectives:**
- Understand fundamental Docker concepts and why containers matter.
- Learn how to containerize and optimize an ASP.NET application.
- Build, tag, and push Docker images to a registry.
- Explore deployment patterns for containerized ASP.NET apps.
- Design CI/CD pipelines that automate build, test, and deployment.
- Compare popular CI/CD tools (GitHub Actions, Azure Pipelines, etc.)

---

## 0. Introduction to Docker (15 min)
- **What is Docker?**
  - Platform for packaging, distributing, and running applications in lightweight, isolated environments called *containers*.
- **Containers vs. Virtual Machines**
  - VMs include a full OS; containers share the host kernel and isolate user space.
  - Faster startup, smaller footprint, higher density.
- **Key Docker concepts**
  - **Image** – read‑only template with application code, runtime, libraries, and dependencies.
  - **Container** – a running instance of an image.
  - **Registry** – a repository for storing and sharing images (Docker Hub, Azure Container Registry, etc.).
  - **Dockerfile** – a script of instructions to build an image.
  - **Docker Engine** – the runtime that builds and runs containers.
- **Basic commands demo** (live or recorded)
  - `docker pull`, `docker run`, `docker ps`, `docker stop`, `docker images`, `docker rmi`
- **Why containers?**
  - Portability across environments (dev, test, prod).
  - Immutable infrastructure – deploy the exact same artifact everywhere.
  - Dependency isolation – no “works on my machine” issues.
  - Ecosystem integration (orchestration, CI/CD, service meshes).
- **Transition:** Now that we understand containers, let’s apply Docker specifically to ASP.NET applications.

---

## 1. Introduction & Motivation for Docker + ASP.NET (5 min)
- **Why Docker for ASP.NET?** (recap with .NET context)
  - Consistent runtime environment (e.g., .NET 8 on Linux across all stages).
  - Simplified dependency management – no need to install .NET on the host.
  - Seamless scaling and orchestration (Kubernetes, AKS, etc.).
  - Fast, reliable deployments with immutable artifacts.
- **Traditional IIS deployment vs. containerized deployment.**
- **Agenda overview and demo preview.**

---

## 2. Foundations: Docker Imaging for ASP.NET (20 min)
### 2.1 Anatomy of a Dockerfile
- **Base images:**
  - `mcr.microsoft.com/dotnet/aspnet:8.0` (runtime only).
  - `mcr.microsoft.com/dotnet/sdk:8.0` (build tools + runtime).
- **Multi‑stage builds explained:**
  - Stage 1: restore, build, publish (uses SDK image).
  - Stage 2: copy published output into runtime‑only image.
  - Benefits: smaller final image, no build tools in production.
- **Example Dockerfile walkthrough:**
  ```dockerfile
  FROM mcr.microsoft.com/dotnet/sdk:8.0 AS build
  WORKDIR /src
  COPY *.csproj .
  RUN dotnet restore
  COPY . .
  RUN dotnet publish -c Release -o /app

  FROM mcr.microsoft.com/dotnet/aspnet:8.0
  WORKDIR /app
  COPY --from=build /app .
  ENTRYPOINT ["dotnet", "MyApp.dll"]
  ```
- **Optimizing layer caching:** Copy `csproj` first, then restore, then copy remaining source.

### 2.2 Building and Tagging Images
- `docker build -t myapp:1.0 .`
- Tags for versioning: semantic (`1.0.0`), Git commit hash, `latest`.
- Image size comparison (SDK image vs. runtime image vs. optimized).

### 2.3 Running and Debugging Locally
- `docker run -p 8080:80 myapp:1.0`
- Environment variables: `ASPNETCORE_ENVIRONMENT`, connection strings.
- Volume mounts for development hot‑reload (optional).

### 2.4 Image Security and Best Practices
- **Don’t run as root:** Use `USER app` (or `$APP_UID` in .NET 8+ images).
- **Scan for vulnerabilities:** tools like `docker scout`, Trivy.
- **Use distroless images** or Chainguard images for minimal attack surface.
- **Avoid secrets in layers:** `Dockerfile` → build args only for non‑sensitive data.

---

## 3. Pushing to a Container Registry (5 min)
- **Registries:** Docker Hub, Azure Container Registry (ACR), Amazon ECR, GitHub Container Registry.
- **Authentication:** `docker login`, service principals, GitHub secrets.
- **Pushing an image:**
  ```bash
  docker tag myapp:1.0 myregistry.azurecr.io/myapp:1.0
  docker push myregistry.azurecr.io/myapp:1.0
  ```

---

## 4. Deployment Patterns for Dockerized ASP.NET Apps (10 min)
- **Serverless containers:** Azure Container Apps, AWS App Runner.
- **PaaS:** Azure App Service (Web App for Containers), AWS Elastic Beanstalk (Docker).
- **Orchestrators:** Kubernetes (AKS, EKS, GKE), Docker Swarm (legacy).
- **Hybrid / On‑premises:** Docker Compose, local registry.
- **Quick demo:** Deploy to Azure Container Apps using a single CLI command or portal.

---

## 5. CI/CD Tools and Pipelines (30 min)
### 5.1 Core Pipeline Stages
1. **Source** – Git push triggers pipeline.
2. **Build** – Restore, compile, run unit tests.
3. **Test** – Integration tests, container structure tests.
4. **Package** – Build Docker image, scan it.
5. **Push** – Publish to registry.
6. **Deploy** – Update target environment (rolling update, blue‑green, canary).

### 5.2 GitHub Actions
- **Workflow file:** `.github/workflows/deploy.yml`
- Key actions:
  - `actions/checkout`
  - `docker/login-action`
  - `docker/build-push-action` (multi‑arch, cache support).
- **Environment‑specific secrets** (`secrets.AZURE_CREDENTIALS`, `secrets.REGISTRY_PASSWORD`).
- **Deploy step:** Azure Container Apps Deploy action, or `kubectl` for AKS.
- **Demo snippet:** Build, push to GHCR, deploy to Azure App Service.

### 5.3 Azure Pipelines (YAML)
- **Pipeline structure:** `azure-pipelines.yml`
- Tasks: `DotNetCoreCLI@2` (build, test, publish), `Docker@2` (build and push), `AzureWebAppContainer@1` (deploy).
- Service connections for ACR and Azure subscription.
- **Multi‑stage pipelines** with environment approvals.

### 5.4 Other Tools (Overview)
- **Jenkins:** `Jenkinsfile` with Docker pipeline plugin.
- **GitLab CI:** `.gitlab-ci.yml`, built‑in container registry, Auto DevOps.
- **CircleCI, Bitbucket Pipelines:** Similar patterns.

### 5.5 Advanced Pipeline Features
- **Image signing:** Notary, Cosign.
- **Progressive delivery:** Argo Rollouts, Flagger (canary deployments).
- **Running integration tests inside containers** (Testcontainers for .NET).
- **Caching and parallel jobs** to speed up pipelines.

---

## 6. Monitoring and Observability (5 min)
- Container logs → stdout/stderr → log aggregation (e.g., ELK, Azure Log Analytics).
- Health checks: ASP.NET health endpoints + Docker `HEALTHCHECK`.
- Metrics: Prometheus, Application Insights SDK.

---

## 7. Q&A and Recap (5 min)
- Key takeaways:
  1. Docker provides consistent, portable environments for ASP.NET apps.
  2. Multi‑stage Dockerfiles produce lean, secure images.
  3. CI/CD automates the full path from code commit to production deployment.
  4. Tool choice (GitHub Actions, Azure Pipelines, etc.) depends on existing ecosystem and requirements.
- Common pitfalls:
  - Committing environment‑specific config into images.
  - Neglecting image scanning.
  - Overlooking layer caching → slow builds.

---

## 8. Resources & Further Reading
- Microsoft Learn: “Build and deploy ASP.NET Core in containers”
- Docker official documentation: Multi‑stage builds, Dockerfile reference
- GitHub Actions: `docker/build-push-action` examples
- Azure Pipelines: Deploy to Azure App Service container
- Sample repository on GitHub (to be shared)
