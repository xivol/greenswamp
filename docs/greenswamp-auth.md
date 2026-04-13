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


# Part 3 – Razor Pages & Conditional UI Templates with Identity

**Duration:** 90 minutes  
**Prerequisites:** Parts 1 & 2; basic Razor Pages syntax; ASP.NET Core Identity configured

## Learning Objectives
- Integrate Identity into Razor Pages applications
- Use conditional logic in Razor templates based on authentication state, roles, and claims
- Customize Identity’s default UI pages (login, register, manage account)
- Securely handle post-authentication redirections and access control

---

### 1.Part 3 -- Identity + Razor Pages Integration (15 min)

#### 1.1 Default Identity UI
- Add Identity UI package:  
  `dotnet add package Microsoft.AspNetCore.Identity.UI`
- Register in `Program.cs`:
  ```csharp
  builder.Services.AddDefaultIdentity<ApplicationUser>()
      .AddEntityFrameworkStores<AppDbContext>()
      .AddDefaultTokenProviders();
  ```
- Map Razor Pages and Identity endpoints:
  ```csharp
  app.MapRazorPages();
  app.MapControllers(); // if needed
  ```

#### 1.2 Default Endpoints Provided
| Page | Route | Purpose |
|------|-------|---------|
| Login | `/Identity/Account/Login` | Sign in |
| Register | `/Identity/Account/Register` | Create account |
| Manage | `/Identity/Account/Manage` | Change password, 2FA, personal data |
| Logout | `/Identity/Account/Logout` | Sign out |
| Forgot password | `/Identity/Account/ForgotPassword` | Reset flow |

**Demo:** Scaffold Identity pages to customize them:
```powershell
dotnet aspnet-codegenerator identity -dc AppDbContext -f --useDefaultUI
```

---

### 2. Conditional UI in Razor Templates (30 min)

#### 2.1 Check Authentication State
```cshtml
@using Microsoft.AspNetCore.Identity
@inject SignInManager<ApplicationUser> SignInManager

@if (SignInManager.IsSignedIn(User))
{
    <p>Hello @User.Identity.Name!</p>
    <a asp-page="/Account/Logout">Logout</a>
}
else
{
    <a asp-page="/Account/Login">Login</a>
    <a asp-page="/Account/Register">Register</a>
}
```

#### 2.2 Role‑Based Conditional Content
```cshtml
@if (User.IsInRole("Admin"))
{
    <a href="/admin">Admin Panel</a>
    <button class="delete-post">Delete (Admin only)</button>
}
```

#### 2.3 Claim‑Based Conditions
```cshtml
@foreach (var claim in User.Claims)
{
    if (claim.Type == "EventOrganizer" && claim.Value == "true")
    {
        <a href="/events/create">Create New Event</a>
    }
}
```

Or using policy evaluation in view:
```cshtml
@if ((await AuthorizationService.AuthorizeAsync(User, "RequireEventOrganizer")).Succeeded)
{
    <div>You can organize events.</div>
}
```
Requires `@inject IAuthorizationService AuthorizationService`

#### 2.4 Showing/Hiding Page Sections
- Entire sections of a layout
- Edit/delete buttons on list items
- Custom dashboard widgets

**Example: Post list with conditional actions**
```cshtml
@foreach (var post in Model.Posts)
{
    <div class="post">
        <h3>@post.Title</h3>
        <p>@post.Content</p>
        @if (User.FindFirstValue(ClaimTypes.NameIdentifier) == post.UserId.ToString() || User.IsInRole("Admin"))
        {
            <a href="/posts/edit/@post.Id">Edit</a>
            <button class="delete" data-id="@post.Id">Delete</button>
        }
    </div>
}
```

#### 2.5 Using `ViewBag` / `ViewData` for Precomputed Conditions
In PageModel:
```csharp
public void OnGet()
{
    ViewData["IsAdmin"] = User.IsInRole("Admin");
    ViewData["CanEditPost"] = User.FindFirstValue(ClaimTypes.NameIdentifier) == post.UserId.ToString();
}
```
In Razor:
```cshtml
@if ((bool)ViewData["CanEditPost"]) { ... }
```

---

### 3. Customizing Identity UI Pages (25 min)

#### 3.1 Scaffolding Identity Pages
- Override only the pages you need to customize
- Files appear in `Areas/Identity/Pages/Account/`

**Scaffold command (Visual Studio):** Right‑click project → Add → New Scaffolded Item → Identity  
**CLI:**
```powershell
dotnet aspnet-codegenerator identity -dc AppDbContext -f -outDir Areas/Identity/Pages
```

#### 3.2 Common Customizations

| Page | Typical Changes |
|------|------------------|
| `Login.cshtml` | Add custom CSS, redirect URL logic, external login buttons |
| `Register.cshtml` | Add extra fields (e.g., `DisplayName`, `AvatarUrl`) |
| `Manage/Index.cshtml` | Show additional profile data |
| `Manage/ChangePassword.cshtml` | Add password strength meter |

#### 3.3 Adding Custom Fields to Registration
- Extend `InputModel` in `Register.cshtml.cs`
- Update `OnPostAsync` to save extra properties:
```csharp
var user = new ApplicationUser 
{
    UserName = Input.Email,
    Email = Input.Email,
    DisplayName = Input.DisplayName,
    Bio = Input.Bio
};
await _userManager.CreateAsync(user, Input.Password);
```

#### 3.4 Post‑Login Redirection Logic
Override `LoginModel.OnPostAsync` or set:
```csharp
options.LoginPath = "/Account/Login";
options.ReturnUrlParameter = "returnUrl";
```
In `Login.cshtml.cs`:
```csharp
if (result.Succeeded)
{
    var returnUrl = Request.Query["returnUrl"].ToString();
    if (!string.IsNullOrEmpty(returnUrl) && Url.IsLocalUrl(returnUrl))
        return LocalRedirect(returnUrl);
    else
        return RedirectToPage("/Index");
}
```

#### 3.5 Customizing Layout for Identity Pages
- Identity pages use `~/Areas/Identity/Pages/_ViewStart.cshtml`
- Change its layout:
```cshtml
@{
    Layout = "/Pages/Shared/_Layout.cshtml";
}
```
- Or create a separate layout for Identity pages (`_IdentityLayout.cshtml`)

---

### 4. Protecting Razor Pages with Authorization (10 min)

#### 4.1 Page‑Level Authorization
```csharp
[Authorize(Roles = "Admin")]
public class AdminDashboardModel : PageModel { ... }
```

#### 4.2 Folder‑Level Authorization
Create `_ViewStart.cshtml` or `_ViewImports.cshtml` in folder and use:
```csharp
@using Microsoft.AspNetCore.Authorization
@attribute [Authorize]
```

Or configure in `Program.cs`:
```csharp
services.AddAuthorization(options =>
{
    options.AddPolicy("AdminOnly", policy => policy.RequireRole("Admin"));
});
builder.Services.Configure<RazorPagesOptions>(options =>
{
    options.Conventions.AuthorizeFolder("/Admin", "AdminOnly");
    options.Conventions.AllowAnonymousToPage("/Admin/Login");
});
```

#### 4.3 Handler‑Level Authorization (e.g., `OnPostDelete`)
```csharp
public async Task<IActionResult> OnPostDeleteAsync(int id)
{
    if (!User.IsInRole("Admin") && User.FindFirstValue(ClaimTypes.NameIdentifier) != post.UserId.ToString())
        return Forbid();

    // delete logic
}
```

---

### 5. Real‑World Example: Dynamic Navigation Menu (10 min)

Create `_NavMenu.cshtml` partial:
```cshtml
@inject SignInManager<ApplicationUser> SignInManager
@inject UserManager<ApplicationUser> UserManager

@if (SignInManager.IsSignedIn(User))
{
    var user = await UserManager.GetUserAsync(User);
    <div class="user-info">
        <img src="@user.AvatarUrl" width="32" />
        <span>@user.DisplayName</span>
    </div>
    <ul>
        <li><a href="/">Home</a></li>
        <li><a href="/my-posts">My Posts</a></li>
        @if (User.IsInRole("Admin"))
        {
            <li><a href="/admin/users">Manage Users</a></li>
        }
        @if (User.HasClaim("EventOrganizer", "true"))
        {
            <li><a href="/events/create">Create Event</a></li>
        }
    </ul>
    <form asp-page="/Account/Logout" method="post">
        <button type="submit">Logout</button>
    </form>
}
else
{
    <a asp-page="/Account/Login">Login</a>
    <a asp-page="/Account/Register">Register</a>
}
```

Include in layout:
```cshtml
<partial name="_NavMenu" />
```

---

## Hands‑On Exercises (20 min)

### Exercise 1: Customize Login Page
- Scaffold the Login page
- Add a "Remember Me" checkbox (already there – style it)
- Add a custom CSS class to the form
- Change the title to "Welcome Back"

### Exercise 2: Role‑Based Dashboard
- Create a Razor Page `Dashboard.cshtml`
- Show different content for:
  - Anonymous users (redirect to login)
  - Regular users (show their recent posts)
  - Admins (show user list and system stats)

### Exercise 3: Conditional Buttons on Post List
- Display a list of posts from the database
- Show an "Edit" button only if current user is the author or has the "Editor" role
- Show a "Delete" button only for admins

### Exercise 4: Register with Profile Picture
- Extend `Register.cshtml` to accept an avatar URL (or file upload)
- Save it to `ApplicationUser.AvatarUrl`
- Display the avatar in the navigation menu after login

---

## Summary & Best Practices

| Scenario | Recommended Approach |
|----------|----------------------|
| Simple auth‑dependent UI | `SignInManager.IsSignedIn(User)` + `User.IsInRole()` |
| Complex policies | Use `IAuthorizationService` in views |
| Reusable logic | Create custom view components or partials with injection |
| Protecting pages | `[Authorize]` attributes + conventions in `Program.cs` |
| Customizing Identity UI | Scaffold only pages you need to change |
| Security | Always re‑authorize on POST handlers, never trust client‑side hiding |

---

## Next Steps / Further Reading
- [Customize Identity UI](https://learn.microsoft.com/en-us/aspnet/core/security/authentication/scaffold-identity)
- [Policy-based authorization in Razor Pages](https://learn.microsoft.com/en-us/aspnet/core/security/authorization/razor-pages-authorization)
- [Using claims to drive UI](https://learn.microsoft.com/en-us/aspnet/core/security/authorization/claims)

