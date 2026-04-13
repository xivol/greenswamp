# Two-Part Lecture Series: ASP.NET Core Identity & Access Control

## Part 1 – IAAA + EF Identity Core Features

**Duration:** 90 minutes  
**Target Audience:** Intermediate developers familiar with ASP.NET Core & EF Core basics

### Learning Objectives
- Understand the four pillars of access control (IAAA)
- Map each pillar to ASP.NET Core Identity features
- Know what Identity provides out-of-the-box and what requires custom code
- Implement basic Identity setup with roles, claims, and 2FA

### Lecture Outline

#### 1. The IAAA Model (20 min)
| Pillar | Question | Core Principle |
|--------|----------|----------------|
| **Identification** | Who are you? | Claim an identity (username, email) |
| **Authentication** | Prove it! | Verify credentials (password, MFA) |
| **Authorization** | What can you do? | Grant/deny access (roles, policies) |
| **Accounting** | What did you do? | Audit logs for accountability |

**Real‑world analogy:** Airport security  
- Identification: Show passport  
- Authentication: Face scan matches photo  
- Authorization: Boarding pass grants gate access  
- Accounting: Camera records your movements

#### 2. ASP.NET Core Identity Overview (15 min)
- What it is: Membership system for web apps
- Key components:
  - `UserManager<TUser>` – create, update, delete users
  - `SignInManager<TUser>` – login, logout, 2FA
  - `RoleManager<TRole>` – manage roles
  - EF Core storage provider (default schema)
- Default schema: `AspNetUsers`, `AspNetRoles`, `AspNetUserClaims`, `AspNetUserLogins`, `AspNetUserTokens`, `AspNetRoleClaims`

#### 3. Mapping IAAA to Identity (30 min)

| IAAA Pillar | Identity Feature | Demo / Code |
|-------------|------------------|--------------|
| **Identification** | `UserManager.FindByNameAsync` / `FindByEmailAsync` | Login form reads username/email |
| **Authentication** | `SignInManager.PasswordSignInAsync` + 2FA | Password verification, TOTP, SMS |
| **Authorization** | Roles (`IsInRoleAsync`), Claims (`User.HasClaim`), Policies (`[Authorize(Policy="...")]`) | Role‑based controller access |
| **Accounting** | ❌ Not built-in | Show how to add custom `AuditLog` table + interceptor |

**Live demo snippets:**
```csharp
// Authentication
var result = await _signInManager.PasswordSignInAsync(model.Email, model.Password, model.RememberMe, lockoutOnFailure: true);

// Authorization – Role check
[Authorize(Roles = "Admin")]
public IActionResult AdminPanel() { ... }

// Authorization – Policy (e.g., "RequireEventOrganizer")
services.AddAuthorization(options =>
{
    options.AddPolicy("RequireEventOrganizer", policy => policy.RequireClaim("EventOrganizer", "true"));
});
```

#### 4. Extending Identity for Real-World Needs (15 min)
- Custom `ApplicationUser` (add `FullName`, `AvatarUrl`, etc.)
- Two‑factor authentication setup (QR code + authenticator)
- External login providers (Google, Microsoft)
- Lockout & password complexity rules

#### 5. Q&A / Mini Exercise (10 min)
- **Task:** Create a new ASP.NET Core project with Individual Authentication. Add a claim "Department=IT" to a user and protect a controller with a policy that requires that claim.

---

## Part 2 – Migrating an Existing DbContext to Identity

**Duration:** 90 minutes  
**Prerequisites:** Part 1 or equivalent knowledge; existing database with custom user/auth tables (e.g., `users` + `auth`)

### Learning Objectives
- Assess an existing custom authentication schema
- Choose migration strategy: keep integer PKs (custom Identity) vs. switch to GUID
- Execute EF Core migrations to integrate Identity without data loss
- Update legacy code to use `SignInManager` / `UserManager`

### Lecture Outline

#### 1. Analyzing the Legacy Schema (15 min)
- Example legacy tables (provided earlier):
  ```sql
  users (user_id INTEGER PRIMARY KEY, username, display_name, ...)
  auth (user_id REFERENCES users, password_hash, ...)
  posts (user_id REFERENCES users, ...)
  ```
- **Pain points:** Separate auth table, no email/password fields in users, no Identity tables
- **Constraints:** Existing foreign keys (`posts.user_id`) must be preserved or carefully updated

#### 2. Two Migration Strategies (15 min)

| Strategy | Keep integer PK? | Effort | Best for |
|----------|------------------|--------|----------|
| **Custom Identity (int key)** | ✅ Yes | Medium | Preserve all foreign keys |
| **Default Identity (GUID)** | ❌ No | High | New projects or full rewrite |

**Recommendation:** Custom Identity with `ApplicationUser : IdentityUser<int>` to keep `user_id` as integer primary key.

#### 3. Step-by-Step Migration (Custom int key) (40 min)

##### 3.1 Create custom `ApplicationUser` class
```csharp
public class ApplicationUser : IdentityUser<int>
{
    // Map existing columns
    public string DisplayName { get; set; }
    public string AvatarUrl { get; set; }
    public string Bio { get; set; }
    public DateTime CreatedAt { get; set; }
    public bool IsActive { get; set; }
}
```

##### 3.2 Update DbContext to use Identity
```csharp
public class AppDbContext : IdentityDbContext<ApplicationUser, IdentityRole<int>, int>
{
    // Keep existing DbSets (Posts, Tags, Interactions, Events)
    // Remove old Users DbSet (now handled by Identity)
}
```

##### 3.3 Add migration to alter `users` table
```powershell
Add-Migration AddIdentityColumnsToUsers
```
**Generated migration will:**
- Add missing columns: `Email`, `NormalizedUserName`, `PasswordHash`, `SecurityStamp`, `ConcurrencyStamp`, `LockoutEnabled`, `AccessFailedCount`, etc.
- Rename `user_id` to `Id` (or keep as `user_id` using column mapping)

**Manual adjustments in `Up()`:**
```csharp
// Copy password_hash from old auth table to new PasswordHash column
migrationBuilder.Sql(@"
    UPDATE users 
    SET PasswordHash = (SELECT password_hash FROM auth WHERE auth.user_id = users.user_id)
    WHERE EXISTS (SELECT 1 FROM auth WHERE auth.user_id = users.user_id);
");
// Drop auth table
migrationBuilder.DropTable("auth");
```

##### 3.4 Create remaining Identity tables (roles, claims, etc.)
- Identity will automatically create them via `base.OnModelCreating`
- Run `Update-Database` to apply

##### 3.5 Update foreign key references (if needed)
- Because `user_id` remains an integer, `posts.user_id` continues to work without changes

#### 4. Updating Legacy Code (10 min)
- Replace custom login logic with `SignInManager.PasswordSignInAsync`
- Replace `User.Identity.Name` with `UserManager.GetUserName(User)`
- Update registration to use `UserManager.CreateAsync` with hashed password
- Modify any direct SQL queries that touched `users` or `auth`

**Before (custom):**
```csharp
var user = db.Users.FirstOrDefault(u => u.Username == username && u.Password == hash(password));
```

**After (Identity):**
```csharp
var user = await _userManager.FindByNameAsync(username);
var valid = await _signInManager.UserManager.CheckPasswordAsync(user, password);
```

#### 5. Handling Data Integrity (5 min)
- Ensure existing `username` values are unique (already true)
- Set `Email` column from existing data or leave null (mark as unconfirmed)
- Reset `SecurityStamp` for all users – forces re‑authentication after migration

#### 6. Live Demo / Walkthrough (5 min)
- Show a real migration from the provided schema to Identity
- Demonstrate that existing posts still show correct user names
