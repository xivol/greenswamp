# Deploying ASP.NET Applications with Docker and CI/CD
---

### 0. Introduction to Docker (Lecture Notes)

**Goal:** Ensure everyone understands what Docker is at a conceptual level, why it exists, and how it differs from traditional deployment models. No ASP.NET yet – just pure Docker fundamentals.

**Key Concepts to Cover:**

- **What is Docker?**
  - Docker is an open platform for developing, shipping, and running applications. It lets you package an application with all its dependencies into a standardized unit called a *container*.
  - A container is a lightweight, standalone, executable package that includes everything needed to run the software: code, runtime, system tools, libraries, settings.

- **Containers vs Virtual Machines**
  - **Virtual Machines (VMs):** each VM includes a full guest OS, virtualized hardware, and the application. Heavyweight, slow to boot, consume significant resources.
  - **Containers:** share the host OS kernel, isolate user space. They start in milliseconds, use much less RAM and disk, and achieve near-native performance.
  - Analogy: VM = a house, container = an apartment in a building. Apartments share core infrastructure but are isolated.

- **Core Docker Components**
  - **Docker Engine:** the runtime that builds and runs containers. Consists of a daemon (`dockerd`) and a CLI (`docker`).
  - **Image:** a read‑only template with instructions to create a container. Think of it as a snapshot or a class definition. Images are built in layers.
  - **Container:** a runnable instance of an image. You can run many containers from the same image.
  - **Dockerfile:** a text file containing commands to assemble an image. Each command creates a new layer.
  - **Registry:** a service for storing and distributing images. Docker Hub is the default public registry; cloud providers offer private registries (ACR, ECR, GCR).

- **Basic Workflow Demo (Live or Screenshots)**
  1. `docker pull hello-world` – Pull a test image from Docker Hub.
  2. `docker run hello-world` – Run the container; it prints a message and exits.
  3. `docker run -it ubuntu bash` – Run an interactive Ubuntu container.
  4. Show `docker ps` (list running containers), `docker ps -a` (all containers), `docker stop <id>`.
  5. `docker images` – List locally cached images; `docker rmi <image>` to remove.
  6. Emphasise that the container's file system is ephemeral – changes lost when container is removed, unless volumes are used.

- **Why Containers?**
  - **Consistency:** “It works on my machine” problem solved. The same image runs in development, staging, and production.
  - **Isolation:** Apps and their dependencies are sandboxed. No conflicts between different versions of .NET or Node.js on the same host.
  - **Portability:** A container that runs on your laptop will run on any cloud, on‑premises, or in Kubernetes.
  - **Efficiency:** Share kernel, less overhead than VMs; higher server density.
  - **DevOps and CI/CD:** Immutable artifacts make deployments predictable and rollbacks trivial.

- **Important Distinctions**
  - Docker is not a hypervisor; it uses OS‑level virtualisation (namespaces, cgroups).
  - Containers are not magical VMs – they run the host’s kernel, so a Linux container won’t run natively on Windows without a VM (but Docker Desktop handles this transparently).

**Summary Slide:**
- Docker packages apps and dependencies into lightweight containers.
- It provides portability, speed, and isolation.
- Key building blocks: image, container, Dockerfile, registry.

---

### 1. Introduction & Motivation for Docker + ASP.NET (Lecture Notes)

**Goal:** Bridge the gap between generic Docker knowledge and the specific benefits for ASP.NET Core developers. Motivate the rest of the lecture.

**Why Docker for ASP.NET?**
- **Consistent Runtime Across Environments:**
  - In traditional .NET deployment, you might develop on Windows, test on a Windows Server, and deploy to IIS. With Docker, the exact same Linux (or Windows) container image runs everywhere. No more “but it worked on my machine”.
  - ASP.NET Core runs great on Linux. Using the official `mcr.microsoft.com/dotnet/aspnet` images guarantees that the right .NET runtime and dependencies are included.
- **Simplified Dependencies:**
  - The target server doesn’t need .NET SDK or runtime installed. The image contains everything. You can even run multiple apps with different .NET versions on the same host without conflicts.
- **Immutable Artifacts:**
  - The image you build and test is the exact same image pushed to production. There is no configuration drift between staging and live servers.
- **Designed for Orchestration:**
  - Modern ASP.NET apps often consist of multiple services (microservices). Docker Compose for local development; Kubernetes for production. Containers make scaling, service discovery, and load balancing straightforward.
- **Fast, Reliable Deployments:**
  - Pulling a new image and restarting a container is much faster than traditional `msdeploy` or FTP-based copy. Rollback = just deploy the previous image tag.
- **Developer Onboarding:**
  - A new developer clones the repo, runs `docker compose up`, and has the full app stack (ASP.NET + database + Redis) running in minutes, without installing SDKs or tools globally.

**Traditional IIS Deployment vs Containerized Deployment**
- *IIS Deployment:* Install .NET runtime on Windows Server, configure IIS, copy files, manage app pools, deal with shared hosting limits.
- *Containerized Deployment:* Build image (once), push to registry, pull and run on any orchestrator. The container image is the deployable unit.

**Agenda Preview:**
- We’ll start with Dockerfile anatomy and image optimization.
- Then push images to a registry.
- Next, look at various ways to run containerized ASP.NET apps in production (serverless containers, PaaS, Kubernetes).
- Finally, dive into CI/CD pipelines that automate the whole process.

**Visual Idea:**
Show a diagram: Developer laptop → `docker build` → container registry → cloud environment (App Service, AKS, Container Apps). The same image moves right with no changes.

---

### 2. Foundations: Docker Imaging for ASP.NET (Lecture Notes)

**Goal:** Teach how to write a production‑grade Dockerfile for an ASP.NET Core application, focusing on multi‑stage builds, layer caching, and security.

#### 2.1 Anatomy of a Dockerfile
- **Base Images for .NET:**
  - Microsoft publishes several official images:
    - `mcr.microsoft.com/dotnet/sdk:8.0`: includes .NET SDK, MSBuild, NuGet, etc. Used for building and publishing.
    - `mcr.microsoft.com/dotnet/aspnet:8.0`: contains only the ASP.NET Core runtime and dependencies. Much smaller (around 100 MB compressed). Used for running the app in production.
  - Tag variants: `8.0`, `8.0-bookworm-slim` (Debian slim), `8.0-alpine` (Alpine Linux, smaller but may have compatibility issues with some native libraries). Default Debian-based is a safe choice.
- **Multi‑stage Build Concept:**
  - Single Dockerfile, multiple `FROM` statements. Each `FROM` begins a new stage.
  - First stage (named `build`): uses SDK image, copies source, restores NuGet packages, compiles, publishes.
  - Second stage (final image): uses runtime image, copies *only the published output* from the build stage.
  - **Benefits:**
    - Final image does not contain SDK, source code, or intermediate build artifacts.
    - Drastically reduces image size (often from ~1.5 GB to ~200 MB).
    - Improves security (fewer tools for an attacker to exploit).
- **Step-by-step Dockerfile Explanation:**
  ```dockerfile
  # Stage 1: Build
  FROM mcr.microsoft.com/dotnet/sdk:8.0 AS build
  WORKDIR /src
  COPY *.csproj .                    # Copy only project file first
  RUN dotnet restore                 # Restore dependencies (cached if csproj unchanged)
  COPY . .                           # Copy remaining source code
  RUN dotnet publish -c Release -o /app

  # Stage 2: Runtime
  FROM mcr.microsoft.com/dotnet/aspnet:8.0
  WORKDIR /app
  COPY --from=build /app .           # Copy published output from build stage
  ENTRYPOINT ["dotnet", "MyApp.dll"]
  ```
  - **Line-by-line:**
    - `FROM ... AS build`: names the stage so we can reference it later.
    - `COPY *.csproj .` then `RUN dotnet restore`: restores packages. Docker caches this layer; if `*.csproj` files don’t change, the cache is reused, dramatically speeding up rebuilds.
    - `COPY . .`: after restore, copy all source. Code changes invalidate only this layer and subsequent ones.
    - `RUN dotnet publish -c Release -o /app`: builds and publishes the app to `/app`.
    - Second `FROM`: starts from clean runtime image.
    - `COPY --from=build /app .`: copies the entire `/app` folder from the build stage into the current working directory.
    - `ENTRYPOINT`: defines the command to run when the container starts.

#### 2.2 Building and Tagging Images
- **Building:**
  ```bash
  docker build -t myapp:1.0 .
  docker build -t myapp:1.0 -t myapp:latest .
  ```
  The `-t` flag applies a tag. You can apply multiple tags to the same image.
- **Tagging Strategies:**
  - **Semantic versioning:** `1.0.0`, `1.0`, `1`. Allows easy rollback.
  - **Git commit hash:** `git rev-parse --short HEAD` → `myapp:abc1234`. Guarantees traceability to source.
  - **Branch + build number:** `develop-42`, `main-10`.
  - **`latest`:** points to the most recent stable build. Useful for development but risky for production because it’s mutable.
- **Image Size Comparison:**
  - Build the same app with single-stage (SDK) vs multi‑stage. The multi‑stage image will be ~10x smaller. Show `docker images` output to emphasise the difference.

#### 2.3 Running and Debugging Locally
- **Basic run command:**
  ```bash
  docker run -p 8080:8080 myapp:1.0
  ```
  This maps host port 8080 to container port 8080 (ASP.NET default since .NET 8). Older templates used port 80.
- **Environment Variables:**
  - Set via `-e` or `--env-file`:
    ```bash
    docker run -e ASPNETCORE_ENVIRONMENT=Development -e ConnectionStrings__Default="Server=..." myapp
    ```
  - ASP.NET Core reads these automatically; they override `appsettings.json`.
- **Development Hot‑Reload (Optional):**
  - Mount source code as a volume and use `dotnet watch` inside a container. Typically done with Docker Compose. Example snippet:
    ```bash
    docker run -v $(pwd):/src -p 8080:8080 -e ASPNETCORE_ENVIRONMENT=Development myapp-dev
    ```
  - This is not a production pattern but helpful for inner loop.

#### 2.4 Image Security and Best Practices
- **Run as non‑root user:**
  - The official .NET 8 images define a `app` user (uid 1654). In the runtime stage, add `USER app` before ENTRYPOINT.
    ```dockerfile
    USER app
    ENTRYPOINT ["dotnet", "MyApp.dll"]
    ```
  - This limits the blast radius if the app is compromised.
- **Image Scanning:**
  - Use tools to check for known vulnerabilities in OS packages and NuGet dependencies.
  - `docker scout quickview myapp:1.0` (built into Docker Desktop).
  - Trivy, Snyk, Aqua are popular third‑party scanners.
  - Scanning should be part of the CI/CD pipeline.
- **Minimal Images:**
  - **Distroless images:** Google’s Distroless images or Chainguard’s Wolfi‑based images contain only your app and its runtime dependencies, no shell, package manager, etc. Attack surface is drastically reduced.
  - For .NET, there are `wolfi‑based` images (e.g., `cgr.dev/chainguard/aspnet:latest`). They are even smaller and more secure but require testing because of missing debugging tools.
- **Secrets Management:**
  - Never hardcode secrets (connection strings, API keys) in the Dockerfile. They become embedded in the image layers.
  - Pass secrets at runtime via environment variables, mounted secret files, or a secret store (Azure Key Vault, HashiCorp Vault).
  - Docker BuildKit supports secret mounts (`--secret`) for build‑time secrets (e.g., private NuGet feeds), but these are not stored in the final image.

**Summary of Section 2:**
- Multi‑stage Dockerfiles dramatically reduce image size and improve security.
- Order commands to maximise layer caching (restore before copying full source).
- Always run the final image as a non‑root user and scan for vulnerabilities.
- Use environment variables for configuration, not baked‑in settings.

---

### 3. Pushing to a Container Registry (Lecture Notes)

**Goal:** Explain how to store and share your Docker images using a registry, and set up authentication.

**Container Registry Options**
- **Public Registries:** Docker Hub (most popular), GitHub Container Registry (ghcr.io). Good for open‑source or internal sharing.
- **Private Registries (Cloud):**
  - Azure Container Registry (ACR): integrated with Azure AD, geo‑replication, tasks.
  - Amazon Elastic Container Registry (ECR): IAM authentication, integrated with ECS/EKS.
  - Google Container Registry / Artifact Registry: GCP integration.
- **On‑Premises:** Harbor, GitLab Container Registry, Docker Trusted Registry.

**Pushing an Image (Step‑by‑step)**
1. **Login:**
   - Docker Hub: `docker login` (prompts for username/password or access token).
   - ACR: `az acr login --name myregistry` (uses Azure CLI credentials).
   - ECR: `aws ecr get-login-password | docker login ...`
   - GitHub: `docker login ghcr.io -u USERNAME -p $CR_PAT` (Personal Access Token).
2. **Tag the image with the registry hostname and repository:**
   ```bash
   docker tag myapp:1.0 myregistry.azurecr.io/myapp:1.0
   ```
   The format is `<registry>/<repository>:<tag>`. For Docker Hub, you can omit the registry if pushing to your user namespace.
3. **Push:**
   ```bash
   docker push myregistry.azurecr.io/myapp:1.0
   ```
4. **Verify:** The image appears in the registry’s UI or via `docker pull`.

**Automation and CI/CD Integration:**
- In a pipeline, you’ll log in using a service principal or pre‑configured secret, then build and push in one step (we’ll see this in section 5).
- Always push after build success; never push images that haven’t passed tests.

**Best Practices for Registries**
- Use a private registry for proprietary code.
- Enable vulnerability scanning provided by the registry (ACR has built‑in Qualys scanning, ECR has enhanced scanning).
- Use image retention policies to clean up old, unused tags.
- Consider enabling immutable tags for production‑ready versions (`1.0.0`) to prevent overwriting.

**Key Takeaway:** The registry is the bridge between the build pipeline and the deployment target. Always push a uniquely tagged, scanned image.

---

### 4. Deployment Patterns for Dockerized ASP.NET Apps (Lecture Notes)

**Goal:** Survey the main ways to run containerized ASP.NET Core applications in production, from simple to complex.

**1. Serverless Containers**
- **Azure Container Apps:** Fully managed, serverless container platform. Autoscales based on HTTP requests, events, or KEDA scalers. Supports Dapr for microservices. You bring your image and set CPU/memory limits, scaling rules.
  - *Pros:* No infrastructure management, built‑in HTTPS, easy revision control, cheap for low‑traffic apps.
  - *Demo idea:* `az containerapp create --image myapp:1.0 ...` and get a public URL in seconds.
- **AWS App Runner:** Similar service, build from source or container image, automatic scaling.
- **Google Cloud Run:** Great for stateless HTTP workloads, pay‑per‑request.

**2. Platform as a Service (PaaS)**
- **Azure App Service (Web App for Containers):** A fully managed platform that can run Docker containers. Supports both Linux and Windows containers. You configure the image and tag in the App Service settings; it pulls and runs it.
  - *Features:* automatic OS patching, custom domains, SSL, deployment slots (blue‑green), built‑in CI/CD integration.
  - *Limitations:* some ports restrictions, not as flexible as a full orchestrator.
- **AWS Elastic Beanstalk (Docker):** Deploy your Docker image and let Beanstalk handle load balancing, scaling, and monitoring.

**3. Orchestrators (Kubernetes)**
- **Kubernetes (K8s):** The de‑facto container orchestrator. Manages deployment, scaling, networking, and self‑healing of containers across a cluster.
  - *Managed options:* Azure Kubernetes Service (AKS), Amazon EKS, Google GKE.
  - *When to use:* Microservices architectures, need for advanced scheduling, service mesh, custom networking, or when you want a standard multi‑cloud abstraction.
- **Docker Swarm:** Simpler orchestrator built into Docker Engine. Rarely used for new projects now; Kubernetes has become standard.

**4. Hybrid / On‑Premises**
- **Docker Compose:** Ideal for local development and small‑scale production on a single VM. You define multi‑container apps (app + database + cache) in a YAML file.
- **Self‑hosted orchestrators:** K3s, MicroK8s for edge/on‑premises. Use private registries.

**Deployment Decision Factors:**
- **Complexity:** Container Apps/Cloud Run < PaaS < Kubernetes.
- **Control:** Kubernetes gives you full control, but you manage the cluster. Serverless limits are by design.
- **Cost:** Serverless scales to zero; Kubernetes has baseline cluster costs.
- **Team skills:** Kubernetes requires more operations expertise.

**Quick Demo: Azure Container Apps Deployment**
1. Build and push image to ACR.
2. Create a Container App environment: `az containerapp env create ...`
3. Deploy: `az containerapp create -n myapp --image myregistry.azurecr.io/myapp:1.0 --target-port 8080 --ingress external`
4. The command returns a URL. The app is live.

**Key Takeaway:** For most ASP.NET core web apps, serverless containers or PaaS provide the best balance of simplicity and reliability. Kubernetes is warranted when you need multi‑service orchestration.

---

### 5. CI/CD Tools and Pipelines (Lecture Notes)

**Goal:** Design automated pipelines that build, test, containerize, and deploy an ASP.NET application. Compare popular CI/CD systems.

#### 5.1 Core Pipeline Stages
A typical CI/CD pipeline for a Dockerized ASP.NET app has these phases:
1. **Source Trigger:** Push to a Git branch (main or feature branch) triggers the pipeline.
2. **Build & Test:**
   - Restore NuGet packages, compile, run unit tests (`dotnet test`).
   - Run static code analysis, linting.
3. **Integration / Container Structure Tests:**
   - Spin up a container from the newly built image, run integration tests against it (using Testcontainers for .NET).
   - Validate the container’s file structure, environment variables, etc.
4. **Package (Docker Build):**
   - Build Docker image with appropriate tags (commit SHA, build number).
   - Scan image for vulnerabilities (fail pipeline on critical findings).
5. **Push:** Push the image to your registry.
6. **Deploy:** Update the target environment:
   - For PaaS: update the App Service to use the new image tag.
   - For Kubernetes: `kubectl set image deployment/myapp` or apply updated manifest.
   - Use strategies: rolling update (default), blue‑green, canary.

**Pipeline as Code:** All modern tools use YAML files stored in the repository (`azure-pipelines.yml`, `.github/workflows/deploy.yml`, `.gitlab-ci.yml`). This makes pipelines versioned, reviewed, and reproducible.

#### 5.2 GitHub Actions
- **Workflow definition:** `.github/workflows/deploy.yml`
- **Triggers:** `on: push: branches: [main]` or `pull_request`.
- **Jobs and Steps:** A job runs on a runner (Ubuntu, Windows, macOS). Steps are individual tasks.
- **Key Actions:**
  - `actions/checkout@v4`: checks out source code.
  - `docker/login-action@v3`: authenticates to a container registry using secrets.
  - `docker/build-push-action@v5`: builds image with caching, tags, and can push in one step. Supports multi‑arch builds, GitHub Actions cache.
  - `azure/login@v1` (for Azure): logs in to Azure using service principal credentials.
  - `Azure/container-apps-deploy-action@v1`: deploys to Azure Container Apps.
- **Secrets:** Store credentials (registry password, Azure SP, SSH keys) in GitHub Secrets; refer to them as `${{ secrets.SECRET_NAME }}`.
- **Example Snippet:**
  ```yaml
  name: Build and Deploy
  on:
    push:
      branches: [main]
  jobs:
    build-and-deploy:
      runs-on: ubuntu-latest
      steps:
        - uses: actions/checkout@v4
        - uses: docker/login-action@v3
          with:
            registry: ghcr.io
            username: ${{ github.actor }}
            password: ${{ secrets.GITHUB_TOKEN }}
        - uses: docker/build-push-action@v5
          with:
            context: .
            push: true
            tags: ghcr.io/${{ github.repository }}:${{ github.sha }}
            cache-from: type=gha
            cache-to: type=gha,mode=max
        # Deploy step (example for Azure Container Apps)
        - uses: azure/login@v1
          with:
            creds: ${{ secrets.AZURE_CREDENTIALS }}
        - uses: azure/container-apps-deploy-action@v1
          with:
            imageToDeploy: ghcr.io/${{ github.repository }}:${{ github.sha }}
            ...
  ```
- **Benefits:** Native integration with GitHub, free minutes for public repositories, huge marketplace.

#### 5.3 Azure Pipelines (YAML)
- **Pipeline Definition:** `azure-pipelines.yml` in the repo root.
- **Triggers:** `trigger: - main`; optionally `pr:` for PR validation.
- **Agent Pools:** `vmImage: 'ubuntu-latest'` (Microsoft‑hosted agent with Docker pre‑installed).
- **Typical Tasks:**
  - `DotNetCoreCLI@2`: `restore`, `build`, `test`, `publish`. Often you can skip the `publish` step if Docker build does it.
  - `Docker@2`: builds and pushes image. It can use service connections for registry authentication.
  - `AzureWebAppContainer@1`: deploys to Azure App Service (Web App for Containers). Requires a service connection to the Azure subscription and the container registry.
- **Service Connections:** Pre‑configured connections to Azure and external services that abstract away credentials. They are managed in the Azure DevOps project settings.
- **Multi‑stage Pipelines:**
  - You can define separate stages (Build, Staging, Production) with environments and approvals. For example, a “Deploy to Production” stage might require manual approval.
  - Example structure:
    ```yaml
    stages:
      - stage: Build
        jobs: ...
      - stage: DeployStaging
        jobs: ...
      - stage: DeployProduction
        jobs: ...
        dependsOn: DeployStaging
        environment: 'production'   # With approval gates
    ```
- **Benefits:** Deep integration with Azure services, robust secret management, excellent for teams already using Azure DevOps Boards and Repos.

#### 5.4 Other Tools (Overview)
- **Jenkins:** The veteran CI/CD server. Use a `Jenkinsfile` with the Docker Pipeline plugin to build and push. Highly customisable but requires more maintenance (master/agent setup). Good for on‑premises scenarios.
- **GitLab CI:** Uses `.gitlab-ci.yml`. GitLab has a built‑in container registry per project. Very convenient. Auto DevOps can automatically build and deploy Dockerized apps with minimal configuration.
- **CircleCI, Bitbucket Pipelines, AWS CodePipeline:** Similar concepts, each with their own syntax and integrations. The same pattern applies: checkout → build → test → Docker build & push → deploy.

#### 5.5 Advanced Pipeline Features
- **Image Signing and Verification:**
  - Tools like Cosign (Sigstore) allow you to sign container images cryptographically. In the pipeline, after pushing, you run `cosign sign myimage:tag`. Deployment policies can require valid signatures. Increases supply chain security.
- **Progressive Delivery (Canary, Blue‑Green):**
  - **Argo Rollouts** (Kubernetes): Replaces the standard Deployment resource with a Rollout that can do canary deployments, automatic analysis, and rollbacks.
  - **Flagger:** Similar, works with service meshes (Istio, Linkerd). Can gradually shift traffic to a new version and automatically rollback if metrics degrade.
  - These are advanced deployment patterns you can plug into your pipeline after the image is pushed.
- **Integration Testing with Testcontainers:**
  - In the pipeline, you can start a container of your app and run integration tests against it. Using .NET’s Testcontainers library, you can define an `MsSqlContainer`, a `RedisContainer`, and your ASP.NET app container. This happens inside the CI job, ensuring your image actually serves traffic correctly before deployment.
- **Caching for Speed:**
  - Docker layer caching: use `cache-from` and `cache-to` in build-push-action to save layers in a remote cache (e.g., GitHub Actions cache, ACR, S3). This avoids rebuilding unchanged layers.
  - NuGet package caching: in `DotNetCoreCLI@2`, there’s a built‑in cache task or you can use `actions/cache`.
  - Parallel jobs: split the pipeline into independent jobs (e.g., unit tests in one, integration tests in another) that run concurrently.

**Summary of Section 5:**
- A robust CI/CD pipeline builds, tests, and pushes a versioned Docker image automatically.
- GitHub Actions and Azure Pipelines are both excellent choices, with native Docker and cloud integrations.
- Extend pipelines with security scanning, image signing, and progressive delivery for production readiness.
- The pipeline is the backbone of a DevOps workflow for containerized ASP.NET applications.

---
