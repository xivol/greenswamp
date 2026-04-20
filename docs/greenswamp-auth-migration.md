## The Correct Approach: Keep `users` + Extend `auth`

Your current schema:
- `users` – profile data (display_name, avatar_url, bio, is_active, created_at)
- `auth` – authentication data (password_hash, last_login, reset_token, token_expiry)  
- Foreign key: `auth.user_id` → `users.user_id` (so each auth record belongs to one user)

We will:
1. **Add Identity's required columns** to the `auth` table.
2. **Map `IdentityUser<int>`** to the `auth` table.
3. **Keep `users` table completely intact** – no changes, no drops.
4. **Configure a one-to-one relationship** between `AppUser` (auth) and your existing `User` entity (users table).

---

## Step 1: Create Entity Classes That Map to Both Tables

```csharp
// This maps to your existing "users" table – unchanged
[Table("users")]
public class UserProfile
{
    [Key]
    [Column("user_id")]
    public int UserId { get; set; }

    [Column("username")]
    public string Username { get; set; }

    [Column("display_name")]
    public string DisplayName { get; set; }

    [Column("avatar_url")]
    public string? AvatarUrl { get; set; }

    [Column("bio")]
    public string? Bio { get; set; }

    [Column("is_active")]
    public bool IsActive { get; set; }

    [Column("created_at")]
    public DateTime CreatedAt { get; set; }

    // Navigation to auth
    public AppUser Auth { get; set; }
}

// This maps to your "auth" table and inherits IdentityUser<int>
[Table("auth")]
public class AppUser : IdentityUser<int>
{
    // These columns already exist in your auth table
    [Column("password_hash")]
    public override string? PasswordHash { get; set; }

    [Column("last_login")]
    public DateTime? LastLogin { get; set; }

    // Navigation to profile
    public UserProfile Profile { get; set; }
}
```

**Note:** `IdentityUser<int>` already has properties like `UserName`, `Email`, `SecurityStamp`, etc. We'll add columns for them in the migration.

---

## Step 2: Create a Migration That **Only Adds Columns** to `auth`

Run:
```bash
dotnet ef migrations add ExtendAuthForIdentity
```

In the generated migration's `Up()` method, add columns **without dropping anything**:

```csharp
protected override void Up(MigrationBuilder migrationBuilder)
{
    // Add Identity-required columns to the existing "auth" table
    // (These are all nullable initially to allow existing rows to have NULL)
    migrationBuilder.AddColumn<string>("UserName", "auth", maxLength: 256, nullable: true);
    migrationBuilder.AddColumn<string>("NormalizedUserName", "auth", maxLength: 256, nullable: true);
    migrationBuilder.AddColumn<string>("Email", "auth", maxLength: 256, nullable: true);
    migrationBuilder.AddColumn<string>("NormalizedEmail", "auth", maxLength: 256, nullable: true);
    migrationBuilder.AddColumn<bool>("EmailConfirmed", "auth", nullable: false, defaultValue: false);
    migrationBuilder.AddColumn<string>("PhoneNumber", "auth", nullable: true);
    migrationBuilder.AddColumn<bool>("PhoneNumberConfirmed", "auth", nullable: false, defaultValue: false);
    migrationBuilder.AddColumn<bool>("TwoFactorEnabled", "auth", nullable: false, defaultValue: false);
    migrationBuilder.AddColumn<DateTimeOffset?>("LockoutEnd", "auth", nullable: true);
    migrationBuilder.AddColumn<bool>("LockoutEnabled", "auth", nullable: false, defaultValue: false);
    migrationBuilder.AddColumn<int>("AccessFailedCount", "auth", nullable: false, defaultValue: 0);
    migrationBuilder.AddColumn<string>("SecurityStamp", "auth", nullable: true);
    migrationBuilder.AddColumn<string>("ConcurrencyStamp", "auth", nullable: true);

    // Populate UserName from the related users table (same user_id)
    // This preserves your existing usernames
    migrationBuilder.Sql(@"
        UPDATE auth 
        SET UserName = u.username,
            NormalizedUserName = UPPER(u.username)
        FROM users u
        WHERE auth.user_id = u.user_id
    ");

    // Make UserName NOT NULL after populating
    migrationBuilder.AlterColumn<string>("UserName", "auth", nullable: false);
    migrationBuilder.AlterColumn<string>("NormalizedUserName", "auth", nullable: false);

    // Generate a SecurityStamp for existing users
    migrationBuilder.Sql("UPDATE auth SET SecurityStamp = NEWID()");
}
```

---

## Step 3: Configure Identity to Use `auth` Table

In your `DbContext`:

```csharp
public class AppDbContext : IdentityDbContext<AppUser, IdentityRole<int>, int>
{
    public DbSet<UserProfile> Users { get; set; }  // your original users table

    protected override void OnModelCreating(ModelBuilder builder)
    {
        base.OnModelCreating(builder);

        // Tell Identity to use your "auth" table (not AspNetUsers)
        builder.Entity<AppUser>().ToTable("auth");

        // Configure the one-to-one relationship between AppUser (auth) and UserProfile (users)
        builder.Entity<AppUser>()
            .HasOne(a => a.Profile)
            .WithOne(p => p.Auth)
            .HasForeignKey<AppUser>(a => a.Id)          // auth.user_id is the PK
            .HasPrincipalKey<UserProfile>(p => p.UserId); // users.user_id is referenced

        // Note: Your existing foreign key is auth.user_id -> users.user_id.
        // That means auth.user_id is both PK of auth and FK to users.
        // EF Core can handle this as a shared primary key one-to-one.

        // Rename other Identity tables to avoid conflicts (optional)
        builder.Entity<IdentityRole<int>>().ToTable("roles");
        builder.Entity<IdentityUserRole<int>>().ToTable("user_roles");
        // ... etc.
    }
}
```

**Important:** Because `auth.user_id` is both the primary key of `auth` and a foreign key to `users.user_id`, EF Core can map this as a **shared primary key one-to-one**. This means when you create a new `AppUser`, you must also create a corresponding `UserProfile` with the same `Id`.

---

## Step 4: Map Existing Auth Columns to IdentityUser

Your original `auth` columns are already mapped via the `[Column]` attributes in `AppUser`:

| Your column       | IdentityUser property   |
|------------------|-------------------------|
| `password_hash`  | `PasswordHash`          |
| `last_login`     | (custom – not in Identity, but kept) |

For `last_login`, you can add a custom property as shown. Identity doesn't track last login by default, but you can update it manually.

For `reset_token` and `token_expiry` – Identity has its own password reset tokens (stored in `AspNetUserTokens` table by default). If you want to keep using your columns, you can continue to do so, or migrate to Identity's built-in reset system later.

---

## Step 5: Handle Password Hashing Compatibility (Same as Before)

You'll still need a custom `IPasswordHasher<AppUser>` if your existing `password_hash` uses a different algorithm. The implementation from my previous answer works here too – just point it to your `AppUser` class.

---

## Step 6: Update Foreign Keys in Other Tables

Your `posts`, `interactions`, etc. tables have `user_id` that currently references `users.user_id`. Since `auth.user_id` is the same value (thanks to the foreign key), you **do not need to change anything**. The foreign key can stay pointing to `users.user_id`, and you can still navigate from a post to `AppUser` via the `UserProfile`.

To make navigation easier, you can add a `UserProfile` navigation to `Post` and then access `AppUser` via `post.User.Auth`. Or you can add a direct `AppUser` navigation using a custom join – but it's simpler to keep the existing FK.


---
### Step 7: Registration

To register a new user while keeping your `users` (profile) and `auth` (Identity) tables synchronized, you need to:

1. **Create the Identity user** (`AppUser`) in the `auth` table using `UserManager<AppUser>`.
2. **Create the corresponding profile record** in the `users` table with the same `Id` (since `auth.user_id` is both primary key and foreign key to `users.user_id`).

Because you have a **shared primary key one-to-one** relationship (`auth.user_id` = `users.user_id`), you must ensure the profile gets the exact same ID as the newly created `AppUser`.

---

## Example Registration Service

```csharp
public class RegistrationService
{
    private readonly UserManager<AppUser> _userManager;
    private readonly AppDbContext _context;

    public RegistrationService(UserManager<AppUser> userManager, AppDbContext context)
    {
        _userManager = userManager;
        _context = context;
    }

    public async Task<IdentityResult> RegisterUserAsync(RegisterModel model)
    {
        // 1. Create the Identity user (auth table)
        var appUser = new AppUser
        {
            UserName = model.Username,
            Email = model.Email,
            // Any other Identity fields (PhoneNumber, etc.)
            // Custom fields from auth table (LastLogin, ResetToken) can be left null initially
        };

        var result = await _userManager.CreateAsync(appUser, model.Password);
        if (!result.Succeeded)
            return result;

        // 2. Now create the corresponding profile (users table)
        //    The appUser.Id is the newly generated integer (from auth.user_id)
        var userProfile = new UserProfile
        {
            UserId = appUser.Id,          // Same ID as auth record
            Username = model.Username,    // Duplicate or reference – keep in sync
            DisplayName = model.DisplayName,
            AvatarUrl = model.AvatarUrl,
            Bio = model.Bio,
            IsActive = true,
            CreatedAt = DateTime.UtcNow
        };

        _context.Users.Add(userProfile);   // Your DbSet<UserProfile>
        await _context.SaveChangesAsync();

        return IdentityResult.Success;
    }
}
```

**Important:** You need to wrap both operations in a **transaction** to avoid an inconsistent state (Identity user created but profile creation fails). `UserManager.CreateAsync` internally uses its own transaction scope. To combine them, either:

- Use `DbContext.Database.BeginTransaction()` before calling `CreateAsync`, then commit after both succeed.
- Or rely on the fact that `UserManager` uses the same `DbContext` – you can start a transaction and pass the `DbContext` to the manager via `IdentityBuilder`. However, the simplest is to manually begin a transaction:

```csharp
using var transaction = await _context.Database.BeginTransactionAsync();
try
{
    var result = await _userManager.CreateAsync(appUser, model.Password);
    if (!result.Succeeded) return result;

    // Save profile (using the same context)
    _context.Users.Add(userProfile);
    await _context.SaveChangesAsync();

    await transaction.CommitAsync();
    return IdentityResult.Success;
}
catch
{
    await transaction.RollbackAsync();
    throw;
}
```

---

## Keeping `users.username` in Sync

Your `users` table has a `username` column, and the `auth` table (via Identity) also has `UserName`. They should remain equal. In the registration example, we set both to the same value. For updates, you must override `UserManager.UpdateAsync` to also update `users.username` – or better, **treat the Identity `UserName` as the source of truth** and use a database trigger or override `SaveChanges` to copy it.

A simpler approach: **remove `username` from `users`** and rely solely on `auth.UserName`. Since you already have a one-to-one relationship, you can always get the username from `auth` via navigation (`profile.Auth.UserName`). But if you must keep the column, add a method that synchronises on every update.

---

## Using the Built-in Identity Register Endpoint (Razor Pages / MVC)

If you're using the default Identity UI, you can override the `Register` handler to add your profile logic. Example with Razor Pages:

```csharp
// In Areas/Identity/Pages/Account/Register.cshtml.cs
public async Task<IActionResult> OnPostAsync(string returnUrl = null)
{
    // ... default validation and user creation

    var user = new AppUser { UserName = Input.Email, Email = Input.Email };
    var result = await _userManager.CreateAsync(user, Input.Password);
    if (result.Succeeded)
    {
        // Create profile
        var profile = new UserProfile
        {
            UserId = user.Id,
            Username = user.UserName,
            DisplayName = Input.DisplayName,  // add to RegisterModel
            // other fields
        };
        _context.Users.Add(profile);
        await _context.SaveChangesAsync();

        // Continue with sign-in, email confirmation, etc.
    }
}
```

---

## Summary

- **Use `UserManager.CreateAsync`** to create the Identity record (`auth` table).
- **Immediately after success**, create a `UserProfile` with the same `Id` and save it to `users` table.
- **Wrap both in a transaction** to ensure atomicity.
- **Synchronize `username`** between the two tables by setting them equal and keeping them consistent on updates (or remove `username` from `users`).

This way, your Identity authentication works, and your existing foreign keys (e.g., `posts.user_id` → `users.user_id`) remain valid because the profile record exists with the same ID as the auth record.
