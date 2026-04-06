# Entity Framework Core with ASP.NET Core – Complete Slide Deck with Lecture Notes

Below is a **ready‑to‑use slide deck** in Markdown format (compatible with [Marp](https://marp.app/) or easily copy‑pasted into PowerPoint/Google Slides).  
Each slide includes:

- Slide title & content (bullets, code, tables)
- **🎤 Lecture Notes** – what the instructor says

The final slide contains a **textual flowchart** describing the Entity Framework configuration decision process.

---

## Slide 1: Title Slide

# Entity Framework Core with ASP.NET Core  
## Data Access Made Easy

**🎤 Notes:**  
Welcome. Today we’ll learn how to connect an ASP.NET Core application to a database using Entity Framework Core. We’ll cover both theory and hands‑on demos, from choosing a workflow to advanced startup initialization.

---

## Slide 2: What is an ORM? Why EF Core?

- **ORM** = Object‑Relational Mapper – maps database tables to C# objects  
- EF Core: Microsoft’s lightweight, cross‑platform ORM  
- **Benefits**  
  - Write LINQ queries instead of SQL  
  - Automatic change tracking  
  - Migrations – version control for DB schema  
  - Works with SQL Server, PostgreSQL, SQLite, MySQL, etc.

**🎤 Notes:**  
“An ORM reduces the impedance mismatch between relational databases and object‑oriented code. EF Core is the modern version of Entity Framework, designed for .NET Core/.NET 5+. We’ll use it in every data‑centric ASP.NET Core app.”

---

## Slide 3: Code First vs. Database First

| **Code First** | **Database First** |
|----------------|---------------------|
| Write C# classes → EF creates DB | Existing DB → scaffold C# models |
| Full control via code | Use `dotnet ef dbcontext scaffold` |
| Best for new projects | Best for legacy or DBA‑driven schemas |
| Version control friendly | Regenerate when schema changes |

**🎤 Notes:**  
“We’ll focus on **Code First** because it’s the recommended approach for most new applications. Database First is available via scaffolding for when you already have a database.”

**Demo:** Create a simple `Product` class and an empty DbContext.

---

## Slide 4: DbContext and DbSets

- **DbContext** – session with the database, manages connections and change tracking  
- Register in `Program.cs`:

```csharp
builder.Services.AddDbContext<AppDbContext>(options =>
    options.UseSqlServer(builder.Configuration.GetConnectionString("Default")));
```

- **DbSet<T>** – represents a table:

```csharp
public class AppDbContext : DbContext
{
    public DbSet<Product> Products { get; set; }
    public DbSet<Category> Categories { get; set; }
}
```

**🎤 Notes:**  
“The DbContext is the heart of EF Core. We register it in DI so controllers can request it. DbSet properties tell EF Core which entity classes map to which tables.”

---

## Slide 5: Connection Strings

- Store in `appsettings.json`:

```json
{
  "ConnectionStrings": {
    "Default": "Server=(localdb)\\mssqllocaldb;Database=MyStoreDb;Trusted_Connection=True;"
  }
}
```

- **Security**  
  - Dev: User Secrets  
  - Prod: Environment variables, Azure Key Vault  
- Test connection:

```csharp
await context.Database.CanConnectAsync();
```

**🎤 Notes:**  
“Connection strings are read from configuration – that’s why we call `GetConnectionString`. Never hard‑code them. For local development, use `(localdb)` or SQLite.”

---

## Slide 6: Fluent API vs. Data Annotations

**Data Annotations** (inside entity class)

```csharp
[Key]
public int Id { get; set; }
[Required, MaxLength(100)]
public string Name { get; set; }
```

**Fluent API** (inside `OnModelCreating`)

```csharp
modelBuilder.Entity<Product>(e => {
    e.HasKey(p => p.Id);
    e.Property(p => p.Name).IsRequired().HasMaxLength(100);
    e.Property(p => p.Price).HasPrecision(18,2);
});
```

**🎤 Notes:**  
“Fluent API is more powerful (composite keys, indexes, cascading deletes). I recommend keeping entities clean and putting all mapping in `OnModelCreating`.”

---

## Slide 7: Migrations with EF Tools

- **What are migrations?** – version control for database schema  
- Install tools:

```bash
dotnet tool install --global dotnet-ef
dotnet add package Microsoft.EntityFrameworkCore.Design
```

- Basic commands:

| Command | Purpose |
|---------|---------|
| `dotnet ef migrations add InitialCreate` | Create migration |
| `dotnet ef database update` | Apply pending migrations |
| `dotnet ef migrations remove` | Remove last (not applied) |
| `dotnet ef database update 0` | Revert all migrations |

**🎤 Notes:**  
“Migrations are like Git for your database schema. You commit migration files; teammates run `database update`. Never manually alter the database.”

**Demo:** Add migration, inspect `Up()`/`Down()`, apply, show `__EFMigrationsHistory`.

---

## Slide 8: Dropping and Seeding in Development

- **Drop database**:

```bash
dotnet ef database drop --force
```

- **Recreate & reseed** (clean slate):

```bash
dotnet ef database update
# then run seeding logic
```

- **Static seeding** (in `OnModelCreating`):

```csharp
modelBuilder.Entity<Product>().HasData(
    new Product { Id = 1, Name = "Laptop", Price = 999.99m }
);
```

- **Dynamic seeding** (custom initializer called in `Program.cs`)

**🎤 Notes:**  
“Dropping and recreating is safe only in development. `HasData` is great for reference data. For dynamic test data, write a custom seeder.”

**Demo:** Drop DB, migrate, run seeder, verify data via API.

---

## Slide 9: Initializing Database from a Pure SQL Script (New!)

**Why?** – DBA provides `.sql` schema, legacy system, full control.

### ✅ Approach 1: `IHostedService` (Recommended)

```csharp
public class DatabaseInitializer : IHostedService
{
    public async Task StartAsync(CancellationToken ct)
    {
        using var scope = _serviceProvider.CreateScope();
        var context = scope.ServiceProvider.GetRequiredService<YourDbContext>();
        var sql = await File.ReadAllTextAsync("Schema/database.sql", ct);
        await context.Database.ExecuteSqlRawAsync(sql, ct);
    }
}
```

Register: `builder.Services.AddHostedService<DatabaseInitializer>();`

### 🔁 Approach 2: Direct in `Program.cs` (Blocking)

```csharp
using (var scope = app.Services.CreateScope())
{
    var context = scope.ServiceProvider.GetRequiredService<YourDbContext>();
    var sql = File.ReadAllText("Schema/database.sql");
    context.Database.ExecuteSqlRaw(sql);
}
```

**🎤 Notes:**  
“`IHostedService` runs **before** the server accepts requests – async, non‑blocking, production‑ready. Use the blocking version only for development.”

---

## Slide 10: Handling `GO` Statements in SQL Scripts

- EF Core’s `ExecuteSqlRaw` does **not** understand `GO` batch separators.  
- Use a helper to split and execute:

```csharp
private async Task ExecuteBatchScriptAsync(DbContext context, string script)
{
    var batches = script.Split(new[] { "GO" }, StringSplitOptions.RemoveEmptyEntries);
    foreach (var batch in batches)
    {
        if (!string.IsNullOrWhiteSpace(batch))
            await context.Database.ExecuteSqlRawAsync(batch);
    }
}
```

**🎤 Notes:**  
“Many SQL Server scripts use `GO`. This helper splits the script on `GO` and runs each batch separately. Call this instead of `ExecuteSqlRawAsync` directly.”

---

## Slide 11: Basic CRUD Controller

- Inject `AppDbContext`:

```csharp
[ApiController]
[Route("api/[controller]")]
public class ProductsController : ControllerBase
{
    private readonly AppDbContext _context;
    public ProductsController(AppDbContext context) => _context = context;
}
```

- **GET** all:

```csharp
[HttpGet]
public async Task<IActionResult> GetAll() =>
    Ok(await _context.Products.ToListAsync());
```

- **POST**:

```csharp
[HttpPost]
public async Task<IActionResult> Create(Product product)
{
    _context.Products.Add(product);
    await _context.SaveChangesAsync();
    return CreatedAtAction(nameof(GetById), new { id = product.Id }, product);
}
```

**🎤 Notes:**  
“Always use `async/await`. For `PUT` we set entity state to `Modified`. Use DTOs in real apps to avoid over‑posting.”

**Demo:** Build full CRUD, test with Swagger.

---

## Slide 12: Development Best Practices

| Do | Don't |
|----|-------|
| Use `AsNoTracking()` for read‑only queries | Use `EnsureDeleted()` in production |
| Batch `SaveChangesAsync` (one per many ops) | Call `SaveChanges` inside loops |
| Enable sensitive logging only in dev | Log passwords or secrets |
| Use connection resiliency (retries) | Ignore transient faults |

**🎤 Notes:**  
“`AsNoTracking()` dramatically improves performance. Always batch your changes. Turn off sensitive logging in production – it can leak data.”

---

## Slide 13: Final Flowchart – Entity Framework Configuration Decision Process

Below is a **textual flowchart** describing the steps to configure EF Core in an ASP.NET Core project.

```
Start: New ASP.NET Core Project?
 │
 ▼
Do you have an existing database?
 │
 ├── Yes ──► Use Database First: scaffold with `dotnet ef dbcontext scaffold`
 │            (then go to "Configure DbContext and connection string")
 │
 └── No ───► Use Code First: write entity classes and DbContext
              │
              ▼
         Configure connection string in appsettings.json
              │
              ▼
         Register DbContext in Program.cs with AddDbContext<T>
              │
              ▼
         Choose mapping style: Fluent API (OnModelCreating) or Data Annotations
              │
              ▼
         Do you need to create/update database schema?
              │
              ├── Yes ──► Use migrations: `dotnet ef migrations add` then `database update`
              │            (or run a raw SQL script via IHostedService)
              │
              └── No ───► Database already exists? EnsureCreated() or run script once
              │
              ▼
         Seed data? (HasData in OnModelCreating or custom initializer)
              │
              ▼
         Build CRUD controllers using injected DbContext
              │
              ▼
         Apply best practices: AsNoTracking(), batching, resiliency
              │
              ▼
         Done – ready for development/production
```

**🎤 Notes:**  
“This flowchart summarises the entire decision process. Use it as a quick reference when starting a new project. Start with ‘Do you have an existing database?’ and follow the branches. It covers everything we discussed today.”

---

# Part 1: Development & Experimentation – Running SQL Scripts and Quick Prototyping

**Goal:** Learn how to execute raw SQL scripts, initialize a database at startup, and reverse‑engineer an existing database – perfect for demos, prototypes, or when you have a DBA‑provided `.sql` file.

---

## Slide 1.1 – Title Slide (Part 1)

# Entity Framework Core – Part 1  
## Development & Experimentation: SQL Scripts, Startup Initialization, and Scaffolding

**🎤 Notes:**  
“This first part focuses on getting a database up and running quickly from an existing SQL script or an existing database. We’ll use raw SQL execution and `IHostedService` – ideal for development, testing, and scenarios where you don’t control the schema creation.”

---

## Slide 1.2 – When to Use Raw SQL in EF Core

- You have an existing `.sql` schema file (provided by a DBA or from a legacy system).  
- You need to run stored procedures or complex commands not easily expressed in LINQ.  
- You are prototyping and want to reuse an existing database definition.

**Note:** For new projects with full control, migrations (Part 2) are usually better.

**🎤 Notes:**  
“Raw SQL execution gives you ultimate flexibility. It’s not the default way to use EF Core, but it’s a lifesaver in certain situations – especially when you’re given a SQL script and told ‘make this work’.”

---

## Slide 1.3 – Executing Raw SQL in EF Core

| Method | Purpose |
|--------|---------|
| `ExecuteSqlRawAsync` | Non‑query commands (`CREATE`, `INSERT`, `UPDATE`, `DELETE`) |
| `SqlQuery<T>` | Queries that return entity or non‑entity types (`.FromSqlRaw()`) |

**Example – running a script from a file:**

```csharp
string sql = await File.ReadAllTextAsync("Schema/database.sql");
await context.Database.ExecuteSqlRawAsync(sql);
```

**Handling `GO` statements** – split on `"GO"` and execute batches separately.

**🎤 Notes:**  
“`ExecuteSqlRawAsync` sends the entire script as one command. Many SQL Server scripts contain `GO` – EF Core doesn’t understand it, so we split manually. I’ll show you a helper later.”

---

## Slide 1.4 – Running SQL at Application Startup (IHostedService)

**Why?** Ensure the database is ready **before** the app starts serving requests.

### Create a background service:

```csharp
public class DatabaseInitializer : IHostedService
{
    private readonly IServiceProvider _serviceProvider;
    private readonly IWebHostEnvironment _env;

    public DatabaseInitializer(IServiceProvider sp, IWebHostEnvironment env)
    {
        _serviceProvider = sp;
        _env = env;
    }

    public async Task StartAsync(CancellationToken ct)
    {
        using var scope = _serviceProvider.CreateScope();
        var context = scope.ServiceProvider.GetRequiredService<AppDbContext>();
        var sqlPath = Path.Combine(_env.ContentRootPath, "Schema", "database.sql");
        var sql = await File.ReadAllTextAsync(sqlPath, ct);
        await context.Database.ExecuteSqlRawAsync(sql, ct);
    }

    public Task StopAsync(CancellationToken ct) => Task.CompletedTask;
}
```

**Register in `Program.cs`:**

```csharp
builder.Services.AddHostedService<DatabaseInitializer>();
```

**🎤 Notes:**  
“This runs once when the app starts, before the web server listens. It’s asynchronous and non‑blocking. Perfect for development environments where you want a clean database on every run.”

---

## Slide 1.5 – Alternative: Blocking Startup in Program.cs (Simpler)

```csharp
var app = builder.Build();

using (var scope = app.Services.CreateScope())
{
    var context = scope.ServiceProvider.GetRequiredService<AppDbContext>();
    var sql = File.ReadAllText("Schema/database.sql");
    context.Database.ExecuteSqlRaw(sql);
}

app.Run();
```

⚠️ **Blocks startup** – only for local development or very small apps.

**🎤 Notes:**  
“This is easier to understand but blocks the main thread. I recommend the `IHostedService` approach for anything beyond a quick test.”

---

## Slide 1.6 – Important EF Core Tools for Development

| Command | Use |
|---------|-----|
| `dotnet ef dbcontext scaffold` | Reverse engineer an existing database into C# models and DbContext (Database First) |
| `dotnet ef database drop` | Quickly delete the entire database (use `--force` to skip prompt) |
| `dotnet ef migrations add` (optional) | You might still use migrations even in a script‑based workflow |

**Example scaffold command:**

```bash
dotnet ef dbcontext scaffold "Server=.;Database=ExistingDb;Trusted_Connection=True" Microsoft.EntityFrameworkCore.SqlServer
```

**🎤 Notes:**  
“These tools help you when you already have a database. Scaffolding generates your entity classes automatically – a huge time saver. And `database drop` lets you reset your environment instantly.”

---

## Slide 1.7 – Hands‑on Demo for Part 1

**Scenario:** You are given a `init.sql` file that creates a `Products` table.

1. Create a new ASP.NET Core Web API project.  
2. Add EF Core packages:  
   `dotnet add package Microsoft.EntityFrameworkCore.SqlServer`  
   `dotnet add package Microsoft.EntityFrameworkCore.Design`  
3. Create an empty `AppDbContext` (no DbSets initially – the script will create the table).  
4. Implement `DatabaseInitializer` (IHostedService) to read and execute `init.sql`.  
5. Run the app, then query the database to verify the table exists.

**🎤 Notes:**  
“Let’s do this live. You’ll see how easy it is to turn any SQL script into a working database – no manual creation in SSMS required.”

---

# Part 2: Production Workflow – Migrations and Safe Deployment

**Goal:** Use EF Core migrations to evolve your database schema incrementally, generate SQL scripts, and apply changes safely in production environments.

---

## Slide 2.1 – Title Slide (Part 2)

# Entity Framework Core – Part 2  
## Production Workflow: Migrations, Scripting, and Safe Deployment

**🎤 Notes:**  
“In production, we cannot drop and recreate the database. We need incremental, reversible, and auditable schema changes. Migrations give us that.”

---

## Slide 2.2 – What Are Migrations?

- A migration is a C# class with `Up()` and `Down()` methods.  
- `Up()` applies the schema change, `Down()` reverts it.  
- The `__EFMigrationsHistory` table tracks which migrations have been applied.  
- Migrations are stored in the `Migrations` folder and committed to source control.

**🎤 Notes:**  
“Think of migrations as version control for your database schema. Each migration is a checkpoint. You can move forward (`Up`) or backward (`Down`) between checkpoints.”

---

## Slide 2.3 – Installing EF Core Tools (Recap)

**CLI (cross‑platform):**
```bash
dotnet tool install --global dotnet-ef
dotnet add package Microsoft.EntityFrameworkCore.Design
```

**PMC (Visual Studio):**
```powershell
Install-Package Microsoft.EntityFrameworkCore.Tools
```

**Add a database provider** (e.g., SQL Server):
```bash
dotnet add package Microsoft.EntityFrameworkCore.SqlServer
```

**🎤 Notes:**  
“You only need to install the tools once per machine. The Design package is required for migrations.”

---

## Slide 2.4 – Essential Migration Commands

| Command | Purpose |
|---------|---------|
| `dotnet ef migrations add <Name>` | Create a new migration after model changes |
| `dotnet ef database update` | Apply all pending migrations to the database |
| `dotnet ef migrations remove` | Delete the last migration (only if not applied) |
| `dotnet ef migrations list` | List all migrations and their status |
| `dotnet ef migrations script` | Generate a SQL script from migrations |

**🎤 Notes:**  
“These five commands are the core of the migration workflow. We’ll focus on `add`, `update`, and especially `script` – the most important for production.”

---

## Slide 2.5 – Creating and Applying a Migration (Demo)

**Step 1 – Change your model** (add a `Description` property to `Product`):

```csharp
public class Product
{
    public int Id { get; set; }
    public string Name { get; set; }
    public decimal Price { get; set; }
    public string Description { get; set; }  // new
}
```

**Step 2 – Create migration:**
```bash
dotnet ef migrations add AddProductDescription
```

**Step 3 – Review generated code** (in `Migrations/..._AddProductDescription.cs`)

**Step 4 – Apply to database:**
```bash
dotnet ef database update
```

**🎤 Notes:**  
“Always review the migration code before applying. EF Core is smart, but it’s not perfect – you might want to customise the `Up` method (e.g., add a default value for existing rows).”

---

## Slide 2.6 – Using IHostedService for Migrations (Development Only)

For **development or test environments**, you can run migrations automatically on startup:

```csharp
public class MigratorHostedService : IHostedService
{
    private readonly IServiceScopeFactory _scopeFactory;
    public MigratorHostedService(IServiceScopeFactory scopeFactory) => _scopeFactory = scopeFactory;

    public async Task StartAsync(CancellationToken ct)
    {
        using var scope = _scopeFactory.CreateScope();
        var context = scope.ServiceProvider.GetRequiredService<AppDbContext>();
        await context.Database.MigrateAsync(ct);
    }

    public Task StopAsync(CancellationToken ct) => Task.CompletedTask;
}
```

**Register:** `builder.Services.AddHostedService<MigratorHostedService>();`

⚠️ **Not recommended for production** – multiple instances could conflict, and you lose control over when changes happen.

**🎤 Notes:**  
“Auto‑migration is convenient for local development but dangerous in production. Use it only on your dev machine.”

---

## Slide 2.7 – Production‑Grade Migration Strategy

**The safe way:**

1. **Generate a SQL script** from your migrations:
   ```bash
   dotnet ef migrations script --output update.sql
   ```

2. **Review the script** (check for destructive changes, performance issues).

3. **Apply the script** as part of your CI/CD pipeline (e.g., with `sqlcmd`, Azure Pipelines, GitHub Actions).

4. **Rollback plan** – keep a previous script or use `dotnet ef migrations script 0` to generate a full rollback.

**Advantages:**  
- Single execution (no race conditions)  
- Auditable and reviewable  
- Works with any deployment model (blue/green, canary)  
- No need for EF Core tools on the production server

**🎤 Notes:**  
“This is the gold standard. The SQL script is a plain text file you can check into version control, review in a pull request, and run with standard database tools. Your production environment doesn’t even need the .NET SDK.”

---

## Slide 2.8 – Important EF Tools for Production

| Command | Why it matters |
|---------|----------------|
| `dotnet ef migrations script` | Generates the deployment artifact. Use `-o` to save to a file. |
| `dotnet ef migrations list` | Check which migrations are already applied (useful for debugging). |
| `dotnet ef database update` | Only for emergency fixes or test environments – never run automatically in production. |

**Example – script from initial to latest:**
```bash
dotnet ef migrations script 0 --output full_schema.sql
```

**Example – script only the last two migrations:**
```bash
dotnet ef migrations script MigrationA MigrationB --output incremental.sql
```

**🎤 Notes:**  
“You can script a range of migrations. This allows you to create incremental update scripts for each release – very useful when you have many environments.”

---

## Slide 2.9 – Final Flowchart: Entity Framework Configuration Decision Process

Below is a **textual flowchart** that guides you from the start of a project to a production‑ready EF Core setup, including both Part 1 and Part 2 workflows.

```
Start: New ASP.NET Core Project?
 │
 ▼
Do you have an existing database or SQL script?
 │
 ├── Yes ──► (Part 1 approach)
 │            │
 │            ├── Existing .sql script? ──► Use IHostedService + ExecuteSqlRaw
 │            │                              (development / prototyping)
 │            │
 │            └── Existing database? ────► Use `dotnet ef dbcontext scaffold`
 │                                          to generate models (Database First)
 │                                          Then decide: continue with raw SQL or
 │                                          switch to migrations?
 │
 └── No ────► (Part 2 approach) Code First
              │
              ▼
         Write entity classes and DbContext
              │
              ▼
         Install EF Core tools and design package
         Add database provider
              │
              ▼
         Configure connection string in appsettings.json
         Register DbContext in Program.cs
              │
              ▼
         Choose mapping style: Fluent API or Data Annotations
              │
              ▼
         Need to evolve schema over time?
              │
              ├── Yes (production) ──► Use migrations:
              │                        1. `dotnet ef migrations add <Name>`
              │                        2. Review migration code
              │                        3. Generate SQL script: `dotnet ef migrations script -o update.sql`
              │                        4. Apply script via CI/CD pipeline
              │
              └── No (prototyping) ───► Use `EnsureCreated()` or run raw SQL script on startup
              │
              ▼
         Seed data? (HasData or custom initializer)
              │
              ▼
         Build CRUD controllers using injected DbContext
              │
              ▼
         Apply best practices: AsNoTracking(), batching, resiliency
              │
              ▼
         Done – ready for production
```

**🎤 Notes:**  
“This flowchart combines both parts. Start by asking: do I already have a database or script? If yes, use Part 1 techniques. If you’re building from scratch and need production‑grade schema evolution, follow the Code First branch with migrations. The most important production decision is to always generate a SQL script – never let your app apply migrations automatically.”

---

## Slide 2.10 – Comparison: Part 1 vs. Part 2

| Aspect | Part 1 (Dev/Experimentation) | Part 2 (Production) |
|--------|-------------------------------|----------------------|
| **SQL execution** | Run entire `.sql` script via `ExecuteSqlRaw` | Run only migration scripts generated by EF |
| **Startup behaviour** | `IHostedService` runs script every time | No automatic execution; script applied by CI/CD |
| **Schema changes** | Recreate database from scratch (destructive) | Incremental migrations (preserve data) |
| **Risk** | Low – local environment only | High – requires review, backup, rollback |
| **Key EF command** | `dotnet ef dbcontext scaffold` | `dotnet ef migrations script` |
| **Best for** | Prototypes, demos, DBA‑provided scripts | Real applications with multiple environments |

**🎤 Notes:**  
“There’s no ‘right’ or ‘wrong’ – it depends on your scenario. For a throwaway prototype, Part 1 is faster. For a system that will live for years, Part 2 is mandatory.”

---

## Slide 2.11 – Hands‑on Lab for Part 2

**Scenario:** You have an existing database (from Part 1 lab) and need to add a new column safely.

1. Add a `CategoryId` column to the `Products` table using migrations.  
2. Create the migration: `dotnet ef migrations add AddCategoryId`.  
3. Generate a SQL script: `dotnet ef migrations script -o deploy.sql`.  
4. Review `deploy.sql` – find the `ALTER TABLE` statement.  
5. Manually execute the script on a separate “production” database.  
6. Verify that the schema change was applied without data loss.

**Bonus:** Roll back the change using the `Down` method (generate a rollback script with `dotnet ef migrations script AddCategoryId 0`).

**🎤 Notes:**  
“This lab simulates a real deployment. You’ll see how safe and controlled the migration script approach is – no surprises, no downtime if done correctly.”

---

## End of Two‑Part Lecture Series

**Total estimated time:**  
- Part 1: 1 – 1.5 hours  
- Part 2: 1.5 – 2 hours  
- Labs: optional extra time

**Materials:** .NET 6+ SDK, SQL Server LocalDB or SQLite, Postman/Swagger, a simple `.sql` file for Part 1.

---

Would you like me to export this as a **PDF**, a **PowerPoint‑ready Markdown** (Marp), or a **printable handout**? Just let me know.