# Adding Tests, Project Structure, and CI/CD in ASP.NET

---

## 11. Adding Tests, Project Structure, and CI/CD

Testing is not only about writing test methods; it requires a solid project structure, test infrastructure, and integration into a continuous integration / continuous deployment (CI/CD) pipeline. This section covers how to integrate testing into the development lifecycle—from the layout of your solution to automated execution on every commit.

---

### 11.1 Setting Up a Test Project

In .NET, tests live in separate projects from the application code. A typical solution structure:

```
MyApp.sln
├── src/
│   ├── MyApp.Web/               (ASP.NET Core application)
│   ├── MyApp.Application/       (business logic)
│   └── MyApp.Infrastructure/    (data access, external services)
└── tests/
    ├── MyApp.UnitTests/         (unit tests)
    ├── MyApp.IntegrationTests/  (integration tests)
    └── MyApp.FunctionalTests/   (BDD / end-to-end tests)
```

To add a test project, use the CLI or IDE:

```bash
dotnet new xunit -n MyApp.UnitTests -o tests/MyApp.UnitTests
cd tests/MyApp.UnitTests
dotnet add reference ../../src/MyApp.Application/MyApp.Application.csproj
dotnet add package Moq
dotnet add package FluentAssertions
```

For integration tests, reference the web project (since `WebApplicationFactory` needs it) and add relevant packages:

```bash
dotnet new xunit -n MyApp.IntegrationTests -o tests/MyApp.IntegrationTests
cd tests/MyApp.IntegrationTests
dotnet add reference ../../src/MyApp.Web/MyApp.Web.csproj
dotnet add package Microsoft.AspNetCore.Mvc.Testing
dotnet add package Testcontainers
dotnet add package Respawn
```

The web project must have a public entry point for `WebApplicationFactory` to work. If using .NET 6+ with top-level statements, you can expose the `Program` class implicitly with a partial class or using `InternalsVisibleTo`. A common practice is to add a line to the web project’s `Program.cs`:

```csharp
public partial class Program { }
```

Then in the test project’s `csproj`, add:

```xml
<ItemGroup>
  <InternalsVisibleTo Include="MyApp.IntegrationTests" />
</ItemGroup>
```

---

### 11.2 Project Structure and Naming Conventions

- **Test project naming**: `<ProjectUnderTest>.<TestType>Tests` (e.g., `MyApp.Application.UnitTests`).
- **Folder structure**: Mirror the source project folders so it’s easy to locate tests. For `Services/OrderService.cs`, place `Services/OrderServiceTests.cs`.
- **One test file per class**: Avoid giant test files.
- **Fixtures and helpers**: Create a `Testing/` or `Shared/` folder for common setup, mocks, builders, and custom fixtures.

Example:

```
tests/MyApp.UnitTests/
├── Services/
│   ├── OrderServiceTests.cs
│   └── CustomerServiceTests.cs
├── Shared/
│   ├── TestData.cs
│   └── AutoFixtureCustomizations.cs
└── GlobalUsings.cs
```

In integration tests:

```
tests/MyApp.IntegrationTests/
├── Api/
│   ├── ProductsControllerTests.cs
│   └── OrdersControllerTests.cs
├── Middleware/
│   └── ExceptionHandlingTests.cs
├── Data/
│   └── OrderRepositoryTests.cs
├── Shared/
│   ├── IntegrationTestFixture.cs
│   ├── DatabaseFixture.cs
│   └── TestWebApplicationFactory.cs
```

---

### 11.3 Test Infrastructure

#### 11.3.1 Test Server with WebApplicationFactory

The `WebApplicationFactory` is the central piece for integration tests. You can customize the host builder to replace real services with mocks or change configuration.

```csharp
public class TestWebApplicationFactory<TProgram> : WebApplicationFactory<TProgram> where TProgram : class
{
    protected override void ConfigureWebHost(IWebHostBuilder builder)
    {
        builder.ConfigureServices(services =>
        {
            // Replace database context with a test container connection
            services.RemoveAll<DbContextOptions<AppDbContext>>();
            services.AddDbContext<AppDbContext>(options =>
                options.UseNpgsql(TestDatabase.ConnectionString));

            // Optionally replace an external service with a mock
            services.RemoveAll<IWeatherService>();
            services.AddScoped(_ => new Mock<IWeatherService>().Object);
        });
    }
}
```

Usage in tests with xUnit’s `IClassFixture`:

```csharp
public class ProductsControllerTests : IClassFixture<TestWebApplicationFactory<Program>>
{
    private readonly HttpClient _client;
    public ProductsControllerTests(TestWebApplicationFactory<Program> factory)
    {
        _client = factory.CreateClient();
    }

    [Fact]
    public async Task Get_ReturnsProducts() { ... }
}
```

#### 11.3.2 Database Management with Testcontainers and Respawn

**Testcontainers** spins up a disposable Docker container with your database engine. This guarantees parity with production.

```csharp
public sealed class PostgresFixture : IAsyncLifetime
{
    private readonly PostgreSqlContainer _container;
    public string ConnectionString => _container.GetConnectionString();

    public PostgresFixture()
    {
        _container = new PostgreSqlBuilder()
            .WithDatabase("testdb")
            .WithUsername("test")
            .WithPassword("test")
            .Build();
    }

    public async Task InitializeAsync()
    {
        await _container.StartAsync();
        // Apply migrations or ensure database schema
        using var scope = ServiceProvider.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
        await db.Database.EnsureCreatedAsync();
    }

    public async Task DisposeAsync()
    {
        await _container.DisposeAsync();
    }
}
```

Use this fixture as a `CollectionFixture` to share a single container across all test classes in the integration project.

**Respawn** resets database state between tests without dropping the schema, which is much faster than recreating the database.

```csharp
private static Respawner _respawner;
private static string _connectionString;

public async Task ResetDatabaseAsync()
{
    if (_respawner == null)
    {
        _respawner = await Respawner.CreateAsync(_connectionString,
            new RespawnerOptions { DbAdapter = DbAdapter.Postgres });
    }
    await _respawner.ResetAsync(_connectionString);
}
```

Call this in a test class’s constructor or in an `IAsyncLifetime` fixture.

#### 11.3.3 Mocking External APIs with WireMock.Net

For tests that make outgoing HTTP calls, use WireMock to run a fake server inside the test process.

```csharp
var wireMock = WireMockServer.Start();
wireMock.Given(
    Request.Create().WithPath("/external").UsingGet()
).RespondWith(
    Response.Create().WithStatusCode(200).WithBodyAsJson(new { result = "ok" })
);

// Override the external service URL in configuration
factory.WithWebHostBuilder(builder =>
{
    builder.ConfigureAppConfiguration((context, config) =>
    {
        config.AddInMemoryCollection(new Dictionary<string, string>
        {
            ["ExternalApi:BaseUrl"] = wireMock.Url!
        });
    });
});
```

---

### 11.4 CI/CD Pipeline Integration

Testing is only truly effective when it runs automatically on every change. Both GitHub Actions and Azure DevOps provide excellent support for .NET pipelines.

#### 11.4.1 GitHub Actions Workflow Example

Create `.github/workflows/dotnet-test.yml`:

```yaml
name: .NET Build & Test

on:
  push:
    branches: [ main ]
  pull_request:
    branches: [ main ]

jobs:
  test:
    runs-on: ubuntu-latest

    services:
      # If not using Testcontainers, you can spin up a service container
      postgres:
        image: postgres:15
        env:
          POSTGRES_PASSWORD: TestPassword
          POSTGRES_DB: testdb
        ports:
          - 5432:5432
        options: >-
          --health-cmd pg_isready
          --health-interval 10s
          --health-timeout 5s
          --health-retries 5

    steps:
    - uses: actions/checkout@v4

    - name: Setup .NET
      uses: actions/setup-dotnet@v4
      with:
        dotnet-version: '8.0.x'

    - name: Restore
      run: dotnet restore

    - name: Build
      run: dotnet build --no-restore --configuration Release

    - name: Run Unit Tests
      run: dotnet test tests/MyApp.UnitTests --configuration Release --no-build --logger "trx;LogFileName=unit_results.trx"

    - name: Run Integration Tests
      run: dotnet test tests/MyApp.IntegrationTests --configuration Release --no-build --logger "trx;LogFileName=integration_results.trx"
      env:
        ConnectionStrings__DefaultConnection: "Host=localhost;Database=testdb;Username=postgres;Password=TestPassword"

    - name: Upload Test Results
      if: always()
      uses: actions/upload-artifact@v4
      with:
        name: test-results
        path: '**/*.trx'
```

If you use **Testcontainers**, Docker must be available. GitHub Actions runners already include Docker; you don’t need the `services` block, but you must ensure the workflow can run containers (runs-on: ubuntu-latest works fine).

#### 11.4.2 Azure DevOps Pipeline (Simplified)

```yaml
trigger:
- main

pool:
  vmImage: 'ubuntu-latest'

steps:
- task: UseDotNet@2
  inputs:
    version: '8.x'

- script: dotnet restore
  displayName: Restore

- script: dotnet build --no-restore --configuration Release
  displayName: Build

- script: dotnet test tests/MyApp.UnitTests --configuration Release --no-build --logger trx
  displayName: Unit Tests

- script: dotnet test tests/MyApp.IntegrationTests --configuration Release --no-build --logger trx
  displayName: Integration Tests
  env:
    ConnectionStrings__DefaultConnection: $(TestDbConnectionString)

- task: PublishTestResults@2
  inputs:
    testResultsFormat: 'VSTest'
    testResultsFiles: '**/*.trx'
```

#### 11.4.3 Managing Secrets and Configuration

Use CI/CD secure variables for connection strings, API keys, etc. In GitHub Actions, use repository secrets and reference them as `${{ secrets.SECRET_NAME }}`. For local development, use the `dotnet user-secrets` tool.

---

### 11.5 Continuous Deployment with Testing Gates

A typical CI/CD pipeline goes:

**CI** (Continuous Integration):
1. Build
2. Run unit tests
3. Run integration tests (with database/containers)
4. Code quality analysis (SonarQube, linting)
5. (Optional) Run UI / smoke tests

**CD** (Continuous Deployment):
1. Deploy to staging environment
2. Run post-deployment smoke tests (API validation, synthetic transactions)
3. Manual approval or automatic promotion to production

By treating test suites as deployment gates, you ensure that only validated code reaches users. Integration tests that run against a real database in a container inside CI give high confidence without a full staging environment.

---

### 11.6 Best Practices for CI/CD and Test Infrastructure

- **Keep tests fast**: Unit tests should complete in seconds; integration tests in minutes. Use Respawn to avoid slow database rebuilds.
- **Isolate test data**: Each test should not depend on data from another test; use unique identifiers or wipe data.
- **Parallelize**: xUnit runs tests in parallel by default; structure integration tests in separate collections to avoid database conflicts.
- **Fail early**: Run unit tests before integration tests in CI.
- **Treat flaky tests as bugs**: Quarantine and fix them immediately.
- **Use artifacts**: Store test results and logs for debugging CI failures.
- **Version control test scripts**: Pipeline YAML files, Docker Compose files for test dependencies, and test data scripts should all be in source control.

---

### 11.7 Example: End-to-End Project Setup Summary

To add comprehensive testing to an ASP.NET solution:

1. Create `tests/` folder with separate projects for unit, integration, and functional tests.
2. In unit tests, reference the class library containing business logic; mock infrastructure.
3. In integration tests, reference the web project; use `WebApplicationFactory` + Testcontainers (PostgreSQL) + Respawn.
4. For UI tests (optional), add a project with Playwright.
5. Write a CI workflow (GitHub Actions) that:
   - Restores, builds, runs all test projects.
   - Uses a Docker service for the database (or relies on Testcontainers).
   - Uploads test results.
6. Add branch protection rules requiring tests to pass before merging.

By following this structure, you create a robust safety net that grows with your application and empowers your team to deliver with confidence.

## 11.8 Example: User Registration and Login (Step‑by‑Step)

This section turns the theory into practice by building a minimal ASP.NET Core web API for user registration/login and testing it with a full test suite and CI pipeline. The domain is deliberately simple – a single field (`Username`) – so we can focus on the testing infrastructure.

### 11.8.1 Solution Structure

```
UserLogin/
├── src/
│   └── UserLogin.Api/                 # ASP.NET Core Web API
│       ├── Program.cs
│       ├── Controllers/
│       │   └── AuthController.cs
│       ├── Services/
│       │   └── UserService.cs
│       ├── Data/
│       │   ├── AppDbContext.cs
│       │   └── UserRepository.cs
│       └── Models/
│           └── User.cs
└── tests/
    ├── UserLogin.UnitTests/           # Unit tests for UserService
    │   └── Services/
    │       └── UserServiceTests.cs
    └── UserLogin.IntegrationTests/    # Integration tests for API
        ├── Api/
        │   └── AuthControllerTests.cs
        ├── Fixtures/
        │   ├── TestWebApplicationFactory.cs
        │   └── DatabaseFixture.cs
        └── GlobalUsings.cs
```

### 11.8.2 Application Code (src/UserLogin.Api)

**User.cs**
```csharp
public class User
{
    public int Id { get; set; }
    public string Username { get; set; }
}
```

**AppDbContext.cs**
```csharp
public class AppDbContext : DbContext
{
    public AppDbContext(DbContextOptions<AppDbContext> options) : base(options) { }
    public DbSet<User> Users => Set<User>();

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        modelBuilder.Entity<User>()
            .HasIndex(u => u.Username)
            .IsUnique();
    }
}
```

**UserRepository.cs** (abstracts data access)
```csharp
public interface IUserRepository
{
    Task<User?> GetByUsernameAsync(string username);
    Task<bool> AddAsync(User user);
}

public class UserRepository : IUserRepository
{
    private readonly AppDbContext _db;
    public UserRepository(AppDbContext db) => _db = db;

    public async Task<User?> GetByUsernameAsync(string username)
        => await _db.Users.SingleOrDefaultAsync(u => u.Username == username);

    public async Task<bool> AddAsync(User user)
    {
        if (await GetByUsernameAsync(user.Username) != null) return false;
        _db.Users.Add(user);
        await _db.SaveChangesAsync();
        return true;
    }
}
```

**UserService.cs** (business logic – uses repository)
```csharp
public class UserService
{
    private readonly IUserRepository _repo;
    public UserService(IUserRepository repo) => _repo = repo;

    public async Task<bool> RegisterAsync(string username)
    {
        if (string.IsNullOrWhiteSpace(username)) return false;
        var user = new User { Username = username.Trim() };
        return await _repo.AddAsync(user);
    }

    public async Task<bool> LoginAsync(string username)
    {
        if (string.IsNullOrWhiteSpace(username)) return false;
        return await _repo.GetByUsernameAsync(username.Trim()) != null;
    }
}
```

**AuthController.cs**
```csharp
[ApiController]
[Route("api/[controller]")]
public class AuthController : ControllerBase
{
    private readonly UserService _userService;
    public AuthController(UserService userService) => _userService = userService;

    [HttpPost("register")]
    public async Task<IActionResult> Register([FromBody] string username)
    {
        if (string.IsNullOrWhiteSpace(username)) return BadRequest("Username required");
        var success = await _userService.RegisterAsync(username);
        return success ? Ok(new { message = "User registered" }) : Conflict("User already exists");
    }

    [HttpPost("login")]
    public async Task<IActionResult> Login([FromBody] string username)
    {
        var exists = await _userService.LoginAsync(username);
        return exists ? Ok(new { message = "Login successful" }) : Unauthorized("Invalid user");
    }
}
```

**Program.cs** (web application entry point)
```csharp
var builder = WebApplication.CreateBuilder(args);
builder.Services.AddControllers();
builder.Services.AddDbContext<AppDbContext>(options =>
    options.UseNpgsql(builder.Configuration.GetConnectionString("Default")));
builder.Services.AddScoped<IUserRepository, UserRepository>();
builder.Services.AddScoped<UserService>();

var app = builder.Build();
app.MapControllers();

// Expose Program for integration tests
public partial class Program { }

app.Run();
```

### 11.8.3 Unit Tests (tests/UserLogin.UnitTests)

Only the `UserService` needs unit testing; we mock the repository.

```csharp
public class UserServiceTests
{
    [Fact]
    public async Task Register_NewUsername_ReturnsTrue()
    {
        var mockRepo = new Mock<IUserRepository>();
        mockRepo.Setup(r => r.AddAsync(It.IsAny<User>())).ReturnsAsync(true);
        var service = new UserService(mockRepo.Object);

        var result = await service.RegisterAsync("alice");

        Assert.True(result);
        mockRepo.Verify(r => r.AddAsync(It.Is<User>(u => u.Username == "alice")), Times.Once);
    }

    [Fact]
    public async Task Register_DuplicateUsername_ReturnsFalse()
    {
        var mockRepo = new Mock<IUserRepository>();
        mockRepo.Setup(r => r.AddAsync(It.IsAny<User>())).ReturnsAsync(false);
        var service = new UserService(mockRepo.Object);

        var result = await service.RegisterAsync("alice");

        Assert.False(result);
    }

    [Fact]
    public async Task Login_ExistingUser_ReturnsTrue()
    {
        var mockRepo = new Mock<IUserRepository>();
        mockRepo.Setup(r => r.GetByUsernameAsync("bob")).ReturnsAsync(new User { Username = "bob" });
        var service = new UserService(mockRepo.Object);

        var result = await service.LoginAsync("bob");

        Assert.True(result);
    }

    [Fact]
    public async Task Login_NonExistentUser_ReturnsFalse()
    {
        var mockRepo = new Mock<IUserRepository>();
        mockRepo.Setup(r => r.GetByUsernameAsync(It.IsAny<string>())).ReturnsAsync((User?)null);
        var service = new UserService(mockRepo.Object);

        var result = await service.LoginAsync("ghost");

        Assert.False(result);
    }
}
```

### 11.8.4 Integration Tests (tests/UserLogin.IntegrationTests)

We use a real PostgreSQL database via **Testcontainers**, **WebApplicationFactory**, and **Respawn** to reset state between tests.

**DatabaseFixture.cs** – shared container and respawner.

```csharp
public class DatabaseFixture : IAsyncLifetime
{
    private readonly PostgreSqlContainer _container;
    public string ConnectionString => _container.GetConnectionString();
    private Respawner _respawner = null!;

    public DatabaseFixture()
    {
        _container = new PostgreSqlBuilder()
            .WithDatabase("userlogin")
            .WithUsername("test")
            .WithPassword("test")
            .Build();
    }

    public async Task InitializeAsync()
    {
        await _container.StartAsync();
        // Apply EF Core migrations on the test database
        var options = new DbContextOptionsBuilder<AppDbContext>()
            .UseNpgsql(ConnectionString)
            .Options;
        using var db = new AppDbContext(options);
        await db.Database.EnsureCreatedAsync();
    }

    public async Task ResetAsync()
    {
        _respawner ??= await Respawner.CreateAsync(ConnectionString,
            new RespawnerOptions { DbAdapter = DbAdapter.Postgres });
        await _respawner.ResetAsync(ConnectionString);
    }

    public async Task DisposeAsync() => await _container.DisposeAsync();
}
```

**TestWebApplicationFactory.cs** – configures the app to use the test database.

```csharp
public class TestWebApplicationFactory : WebApplicationFactory<Program>, IAsyncLifetime
{
    private readonly DatabaseFixture _dbFixture = new();
    public HttpClient Client { get; private set; } = null!;

    protected override void ConfigureWebHost(IWebHostBuilder builder)
    {
        builder.ConfigureServices(services =>
        {
            // Remove the real DbContext config and use the test container
            services.RemoveAll<DbContextOptions<AppDbContext>>();
            services.RemoveAll<AppDbContext>();
            services.AddDbContext<AppDbContext>(options =>
                options.UseNpgsql(_dbFixture.ConnectionString));
        });
    }

    public async Task InitializeAsync()
    {
        await _dbFixture.InitializeAsync();
        Client = CreateClient();
    }

    public async Task ResetDatabaseAsync() => await _dbFixture.ResetAsync();

    public new async Task DisposeAsync()
    {
        await _dbFixture.DisposeAsync();
        Client.Dispose();
    }
}
```

**AuthControllerTests.cs** – the actual integration tests.

```csharp
public class AuthControllerTests : IClassFixture<TestWebApplicationFactory>
{
    private readonly HttpClient _client;
    private readonly TestWebApplicationFactory _factory;

    public AuthControllerTests(TestWebApplicationFactory factory)
    {
        _factory = factory;
        _client = _factory.Client;
    }

    [Fact]
    public async Task Register_NewUsername_ReturnsOk()
    {
        await _factory.ResetDatabaseAsync();
        var content = new StringContent("\"alice\"", Encoding.UTF8, "application/json");

        var response = await _client.PostAsync("/api/auth/register", content);

        response.StatusCode.Should().Be(HttpStatusCode.OK);
        var body = await response.Content.ReadAsStringAsync();
        body.Should().Contain("User registered");
    }

    [Fact]
    public async Task Register_DuplicateUsername_ReturnsConflict()
    {
        await _factory.ResetDatabaseAsync();
        var content = new StringContent("\"bob\"", Encoding.UTF8, "application/json");
        await _client.PostAsync("/api/auth/register", content); // first registration

        var response = await _client.PostAsync("/api/auth/register", content);

        response.StatusCode.Should().Be(HttpStatusCode.Conflict);
    }

    [Fact]
    public async Task Login_RegisteredUser_ReturnsOk()
    {
        await _factory.ResetDatabaseAsync();
        var registerContent = new StringContent("\"charlie\"", Encoding.UTF8, "application/json");
        await _client.PostAsync("/api/auth/register", registerContent);
        var loginContent = new StringContent("\"charlie\"", Encoding.UTF8, "application/json");

        var response = await _client.PostAsync("/api/auth/login", loginContent);

        response.StatusCode.Should().Be(HttpStatusCode.OK);
        var body = await response.Content.ReadAsStringAsync();
        body.Should().Contain("Login successful");
    }

    [Fact]
    public async Task Login_UnregisteredUser_ReturnsUnauthorized()
    {
        await _factory.ResetDatabaseAsync();
        var content = new StringContent("\"unknown\"", Encoding.UTF8, "application/json");

        var response = await _client.PostAsync("/api/auth/login", content);

        response.StatusCode.Should().Be(HttpStatusCode.Unauthorized);
    }
}
```

> **Note**: In a real project you’d also test empty input, very long strings, etc. They are omitted for brevity.

### 11.8.5 BDD Tools in .NET

Behavior-Driven Development (BDD) is a software development approach that bridges the gap between business stakeholders, developers, and testers by using a shared, plain‑language format to describe how the system should behave. It is not a testing technique, but a collaborative way to define requirements that can be automatically executed as tests.

We’ll add BDD scenarios to our existing UserLogin solution and connect them to the same TestWebApplicationFactory used by the integration tests.

#### 11.8.5.1 Add the BDD Test Project

Create a new xUnit test project (or add to existing functional tests project):

```bash
dotnet new xunit -n UserLogin.BddTests -o tests/UserLogin.BddTests
cd tests/UserLogin.BddTests
dotnet add reference ../../src/UserLogin.Api/UserLogin.Api.csproj
dotnet add package Reqnroll.xUnit
dotnet add package Reqnroll
dotnet add package Microsoft.AspNetCore.Mvc.Testing
# (Re-use the same TestWebApplicationFactory from IntegrationTests or copy it)
```

Add the `Reqnroll.json` configuration file to the project root with:

```json
{
  "language": {
    "feature": "en-US"
  },
  "generator": {
    "allowDebugGeneratedFiles": true
  }
}
```

This tells Reqnroll to generate C# code from the `.feature` files.

#### 11.8.5.2 Create a Feature File

Add `Features/UserRegistration.feature`:

```gherkin
Feature: User Registration and Login
  As a visitor
  I want to register and login
  So that I can access the system

Scenario: Register a new user
  Given a user with username "alice" does not exist
  When I register the username "alice"
  Then the registration should succeed with status "OK"

Scenario: Duplicate registration fails
  Given a user with username "bob" already exists
  When I register the username "bob"
  Then the registration should fail with status "Conflict"

Scenario: Login with registered user
  Given a user with username "charlie" is registered
  When I login with username "charlie"
  Then the login should succeed with status "OK"

Scenario: Login with unknown user
  Given a user with username "ghost" does not exist
  When I login with username "ghost"
  Then the login should fail with status "Unauthorized"
```

####  11.8.5.3  Generate Step Definitions

Building the project will auto‑generate a stub step definition class (or you can create it manually). Create `StepDefinitions/UserRegistrationSteps.cs`:

```csharp
using System.Net;
using System.Net.Http;
using System.Text;
using System.Threading.Tasks;
using Microsoft.AspNetCore.Mvc.Testing;
using Reqnroll;
using UserLogin.Api;
using Xunit;

[Binding]
public sealed class UserRegistrationSteps
{
    private readonly HttpClient _client;
    private HttpResponseMessage _response;

    // Reuse the TestWebApplicationFactory (shared via a hook)
    public UserRegistrationSteps(TestWebApplicationFactory factory)
    {
        _client = factory.CreateClient();
    }

    [Given(@"a user with username ""(.*)"" does not exist")]
    public async Task GivenAUserWithUsernameDoesNotExist(string username)
    {
        // Nothing to do; the test database will be empty after reset.
    }

    [Given(@"a user with username ""(.*)"" already exists")]
    [Given(@"a user with username ""(.*)"" is registered")]
    public async Task GivenAUserWithUsernameIsRegistered(string username)
    {
        var content = new StringContent($"\"{username}\"", Encoding.UTF8, "application/json");
        await _client.PostAsync("/api/auth/register", content);
    }

    [When(@"I register the username ""(.*)""")]
    public async Task WhenIRegisterTheUsername(string username)
    {
        var content = new StringContent($"\"{username}\"", Encoding.UTF8, "application/json");
        _response = await _client.PostAsync("/api/auth/register", content);
    }

    [When(@"I login with username ""(.*)""")]
    public async Task WhenILoginWithUsername(string username)
    {
        var content = new StringContent($"\"{username}\"", Encoding.UTF8, "application/json");
        _response = await _client.PostAsync("/api/auth/login", content);
    }

    [Then(@"the registration should succeed with status ""(.*)""")]
    [Then(@"the registration should fail with status ""(.*)""")]
    [Then(@"the login should succeed with status ""(.*)""")]
    [Then(@"the login should fail with status ""(.*)""")]
    public void ThenTheOutcomeShouldBeWithStatus(string status)
    {
        Assert.Equal(Enum.Parse<HttpStatusCode>(status), _response.StatusCode);
    }
}
```

####  11.8.5.4 Hooks (Setup / Teardown)

Use `[BeforeScenario]` and `[AfterScenario]` hooks to reset the database and ensure isolation.

```csharp
[Binding]
public class Hooks
{
    private readonly TestWebApplicationFactory _factory;

    public Hooks(TestWebApplicationFactory factory)
    {
        _factory = factory;
    }

    [BeforeScenario]
    public async Task BeforeScenario()
    {
        await _factory.ResetDatabaseAsync();
    }
}
```

Register the factory as a context‑injection dependency. Reqnroll’s built‑in DI (BoDi) can be configured in a `Startup` class or via a `[Binding]` class with `[BeforeTestRun]`:

```csharp
[Binding]
public static class DependencyRegistration
{
    [BeforeTestRun]
    public static async Task RegisterDependencies(IObjectContainer container)
    {
        var factory = new TestWebApplicationFactory();
        await factory.InitializeAsync();
        container.RegisterInstanceAs(factory, typeof(TestWebApplicationFactory), dispose: true);
    }

    [AfterTestRun]
    public static async Task Cleanup(IObjectContainer container)
    {
        var factory = container.Resolve<TestWebApplicationFactory>();
        await factory.DisposeAsync();
    }
}
```

Now all scenarios share the same `TestWebApplicationFactory` and have a clean database before each.

####  11.8.5.5 Run the BDD Tests

```bash
dotnet test tests/UserLogin.BddTests
```

The test runner will discover Reqnroll scenarios as individual tests, each displayed with its Gherkin title.

###  11.8.6 Living Documentation Output (Optional)

Reqnroll can produce an HTML or JSON report of the feature files with pass/fail status using plugins like `Reqnroll.Tools.LivingDoc`. After execution, you can generate a living documentation site:

```bash
dotnet tool install --global Reqnroll.Tools.LivingDoc.CLI
livingdoc test-assembly tests/UserLogin.BddTests/bin/Release/net8.0/UserLogin.BddTests.dll --output livingdoc.html
```


### 11.8.7 CI/CD Pipeline (GitHub Actions)

`.github/workflows/dotnet-test.yml`:

```yaml
name: UserLogin CI

on:
  push:
    branches: [ main ]
  pull_request:

jobs:
  test:
    runs-on: ubuntu-latest

    steps:
    - uses: actions/checkout@v4
    - uses: actions/setup-dotnet@v4
      with:
        dotnet-version: '8.0.x'

    - name: Restore
      run: dotnet restore

    - name: Build
      run: dotnet build --no-restore -c Release

    - name: Unit Tests
      run: dotnet test tests/UserLogin.UnitTests -c Release --no-build --logger trx

    - name: Integration Tests
      run: dotnet test tests/UserLogin.IntegrationTests -c Release --no-build --logger trx
      env:
        # Testcontainers will use Docker, no extra setup needed on GitHub runners
        # (Docker is pre-installed)
        TEST_RESPAWN_ENABLED: true

    - name: Upload Test Results
      if: always()
      uses: actions/upload-artifact@v4
      with:
        name: test-results
        path: '**/*.trx'
```

Because integration tests use **Testcontainers**, the pipeline automatically starts a PostgreSQL container. No service definition needed. The runner must have Docker (GitHub’s `ubuntu-latest` does). If you wanted to avoid Docker, you could fall back to EF Core InMemory, but Testcontainers is far more reliable.

### 11.8.8 Key Takeaways from This Example

- **Project separation**: `src` and `tests` folders with clear naming conventions.
- **Unit tests** are fast, mock the repository, and verify service logic.
- **Integration tests** use `WebApplicationFactory`, a real database container, and Respawn for data isolation.
- **BDD scenarios** can be added later and reuse the same factory.
- **CI pipeline** runs all tests automatically on every push; integration tests run inside Docker without extra configuration.
- This setup gives high confidence that the registration/login flow works end‑to‑end, from the HTTP layer down to the database.

Repeat this pattern for any feature in your ASP.NET applications to build a robust, maintainable test suite that lives at the heart of your development process.
