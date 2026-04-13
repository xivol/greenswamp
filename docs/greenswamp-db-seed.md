## Slides and Lecture Notes: Database Seeding Hosted Service with EF Core Raw SQL

---

### Slide 1: Title

**Database Seeding Hosted Service**  
Using EF Core Raw SQL + Faker.Net in ASP.NET Core

*Lecture Notes*:  
This session presents a robust, production‑ready solution for populating a relational database with realistic test data. It runs automatically as a background service in an ASP.NET Core application, using Entity Framework Core only for its raw SQL execution capabilities – no entity mappings required. All data generation leverages the Faker.Net library.

---

### Slide 2: Problem Statement

**Why a Seeding Service?**  
- Need consistent, repeatable test data for development and testing.  
- Data must respect complex foreign key relationships (users → posts → interactions → events).  
- Should run automatically on application startup.  
- Must be maintainable and configurable.  

*Lecture Notes*:  
Manual data insertion is error‑prone and time‑consuming. Our schema has multiple interrelated tables (users, posts of three types, tags, comments, reposts, likes, RSVPs, events). A seeded service ensures that every developer or test environment starts with the same rich dataset, while the code remains easy to adjust (e.g., change the number of users/posts).

---

### Slide 3: Solution Overview

**Architecture**  
- `BackgroundService` derived hosted service.  
- Uses `DbContext` only for `ExecuteSqlRawAsync` and `SqlQueryRaw<T>`.  
- No entity classes – all operations are raw SQL strings.  
- Faker.Net generates random but realistic values.  
- All inserts are wrapped in a single transaction.  

*Lecture Notes*:  
We deliberately avoid Entity Framework’s change tracker and entity mappings. This gives us full control over the SQL and eliminates the overhead of mapping complex relationships. The service is registered in DI and automatically started by the ASP.NET Core host. A short delay (`Task.Delay`) ensures the database is ready before seeding begins.

---

### Slide 4: Minimal DbContext

```csharp
public class GreenswampDbContext : DbContext
{
    public GreenswampDbContext(DbContextOptions<GreenswampDbContext> options)
        : base(options) { }
    // No DbSet properties
}
```

*Lecture Notes*:  
This is intentionally empty. It only serves as a conduit to the database connection and transaction management. EF Core will still create the database and apply migrations if you later add them, but for seeding we rely entirely on raw SQL.

---

### Slide 5: Registering the Service (Program.cs)

```csharp
builder.Services.AddDbContext<GreenswampDbContext>(options =>
    options.UseSqlite(builder.Configuration.GetConnectionString("DefaultConnection")));

builder.Services.AddHostedService<DatabaseSeedingHostedService>();
```

*Lecture Notes*:  
The DbContext is registered with the DI container using the connection string from `appsettings.json`. The hosted service is added as a singleton background service. Both are resolved later inside the service’s `ExecuteAsync` method via a scope.

---

### Slide 6: Hosted Service – ExecuteAsync

```csharp
protected override async Task ExecuteAsync(CancellationToken stoppingToken)
{
    await Task.Delay(5000, stoppingToken);
    using var scope = _serviceProvider.CreateScope();
    var context = scope.ServiceProvider.GetRequiredService<GreenswampDbContext>();
    await SeedDatabaseAsync(context, stoppingToken);
}
```

*Lecture Notes*:  
The 5‑second delay gives the application time to finish any startup tasks. A new DI scope is created to resolve the DbContext – this ensures proper disposal and avoids captive dependencies. All seeding logic is inside `SeedDatabaseAsync`, which uses a transaction.

---

### Slide 7: Core Seeding Pattern – Insert and Get ID

```csharp
// Insert the row
await context.Database.ExecuteSqlRawAsync(
    @"INSERT INTO users (username, display_name, avatar_url, bio, is_active)
      VALUES ({0}, {1}, {2}, {3}, {4})",
    username, displayName, avatarUrl, bio, isActive);

// Retrieve the auto‑generated ID
var userId = await context.Database
    .SqlQueryRaw<long>("SELECT last_insert_rowid()")
    .FirstAsync(ct);
```

*Lecture Notes*:  
SQLite’s `last_insert_rowid()` returns the ID of the last inserted row in the same connection. We combine an `ExecuteSqlRawAsync` call with a `SqlQueryRaw<long>` query. This works perfectly inside the same transaction and does not require any manual ADO.NET code.

---

### Slide 8: Handling Foreign Keys – Adding Tags to a Post

```csharp
private async Task AddTagsToPostAsync(DbContext context, long postId, 
    List<long> tagIds, bool forceAtLeastOne, CancellationToken ct)
{
    int numTags = forceAtLeastOne 
        ? Random.Shared.Next(1, MaxTagsPerPost + 1)
        : Random.Shared.Next(0, MaxTagsPerPost + 1);
    var selected = tagIds.OrderBy(x => Guid.NewGuid()).Take(numTags);
    foreach (var tagId in selected)
    {
        await context.Database.ExecuteSqlRawAsync(
            "INSERT INTO post_tags (post_id, tag_id) VALUES ({0}, {1})",
            postId, tagId, ct);
        await context.Database.ExecuteSqlRawAsync(
            "UPDATE tags SET usage_count = usage_count + 1 WHERE tag_id = {0}",
            tagId, ct);
    }
}
```

*Lecture Notes*:  
This method ensures that every post gets a random set of tags (or none for text posts). The junction table `post_tags` is populated and the `usage_count` on tags is incremented. The use of `OrderBy(x => Guid.NewGuid())` gives a random selection without repetition.

---

### Slide 9: Generating Interacting Data – Comments

```csharp
var sql = @"INSERT INTO interactions (user_id, post_id, interaction_type, content, created_at)
            VALUES ({0}, {1}, 'comment', {2}, {3})";
try
{
    await context.Database.ExecuteSqlRawAsync(sql, 
        commenterId, postId, content, createdAt.ToString("yyyy-MM-dd HH:mm:ss"), ct);
}
catch (DbUpdateException) { /* duplicate unique constraint */ }
```

*Lecture Notes*:  
The `interactions` table has a `UNIQUE(user_id, post_id, interaction_type)` constraint. Because we generate random combinations, duplicates are possible. We simply catch the `DbUpdateException` and skip – this is acceptable for seeding. For comments, reposts, and likes the same pattern is used.

---

### Slide 10: Events with RSVPs

```csharp
// Create the event row
await context.Database.ExecuteSqlRawAsync(
    @"INSERT INTO events (post_id, event_time, location, host_org, rsvp_count, max_capacity)
      VALUES ({0}, {1}, {2}, {3}, {4}, {5})",
    postId, eventTime, location, hostOrg, rsvpCount, 
    maxCapacity == 0 ? DBNull.Value : (object)maxCapacity);

// Add RSVP interactions
foreach (var userId in rsvpUsers)
{
    try
    {
        await context.Database.ExecuteSqlRawAsync(
            "INSERT INTO interactions (user_id, post_id, interaction_type) VALUES ({0}, {1}, 'rsvp')",
            userId, postId, ct);
    }
    catch (DbUpdateException) { }
}
```

*Lecture Notes*:  
Events are linked to a post (one‑to‑one). The `rsvp_count` is set to a realistic number, and we then create that many RSVP entries in the `interactions` table. The try‑catch again handles potential duplicates (a user could RSVP only once per event).

---

### Slide 11: Running the Service

- Build and run the ASP.NET Core application.  
- The service logs progress via `ILogger`.  
- After seeding completes, you can query the database:  
  ```sql
  SELECT COUNT(*) FROM users;   -- 50
  SELECT COUNT(*) FROM posts;    -- 350
  SELECT COUNT(*) FROM interactions; -- several hundred
  ```

*Lecture Notes*:  
No manual action is required after configuration. The seeding runs once per application start (you could add a flag to prevent re‑seeding on every restart, e.g., check if users table already has data). All logged messages appear in the console or configured logger.

---

### Slide 12: Benefits of This Approach

- **No entity mapping overhead** – you write exactly the SQL you need.  
- **Full transaction support** – all inserts succeed or fail together.  
- **Easy to adjust data volume** – constants at the top of the service.  
- **DI friendly** – DbContext lifetime is managed by the container.  
- **Works with any database provider** (SQLite shown, but same pattern works for SQL Server, PostgreSQL, etc.).  

*Lecture Notes*:  
This pattern is especially useful when you have a legacy or external schema that you cannot change, or when you want to avoid the complexity of configuring entity relationships purely for seeding. Because we use `ExecuteSqlRawAsync`, the SQL is database‑agnostic – only `last_insert_rowid()` is SQLite‑specific; for other databases you would use `SCOPE_IDENTITY()` or `RETURNING`.

