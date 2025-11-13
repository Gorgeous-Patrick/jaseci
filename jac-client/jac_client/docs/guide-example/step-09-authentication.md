# Step 9: Adding Authentication

In this step, you'll learn how to add user authentication (signup and login) to your todo app.

## Why Authentication?

Without authentication:
- Anyone can see anyone's todos
- No way to identify users
- Can't have private data

With authentication:
- Each user has their own account
- Users only see their own todos
- Secure and private

**Python analogy:**

```python
# Without auth
@app.route("/todos")
def get_todos():
    return all_todos  # Everyone sees everything!

# With auth
@app.route("/todos")
@login_required
def get_todos():
    user = get_current_user()
    return user.todos  # Only your todos!
```

## Jac's Built-in Authentication

Jac provides authentication utilities out of the box:

```jac
cl import from "@jac-client/utils" {
    jacLogin,        # Log user in
    jacSignup,       # Create new account
    jacLogout,       # Log user out
    jacIsLoggedIn    # Check if logged in
}
```

No need to:
- Set up JWT tokens
- Create user tables
- Hash passwords
- Manage sessions

**Jac handles it all!**

## Using Authentication Directly

Jac makes authentication simple with these built-in functions:

```jac
cl import from "@jac-client/utils" {
    jacLogin,        # Log user in
    jacSignup,       # Create new account
    jacLogout,       # Log user out
    jacIsLoggedIn    # Check if logged in
}
```

Let's see how to use them directly in your components (no custom hooks needed!):

**Python analogy:**

```python
class AuthService:
    def login(self, username, password):
        # Handle login
        pass

    def signup(self, username, password):
        # Handle signup
        pass

    def logout(self):
        # Handle logout
        pass

    def is_authenticated(self):
        # Check if logged in
        pass
```

## Creating the Login Page

Let's build a simple, clean login form:

```jac
cl import from react {useState}
cl import from "@jac-client/utils" {jacLogin, useNavigate}

cl {
    def LoginPage() -> any {
        let [username, setUsername] = useState("");
        let [password, setPassword] = useState("");
        let [error, setError] = useState("");
        let navigate = useNavigate();

        async def handleLogin(e: any) -> None {
            e.preventDefault();
            setError("");

            # Validate inputs
            if not username or not password {
                setError("Please fill in all fields");
                return;
            }

            # Attempt login
            success = await jacLogin(username, password);
            if success {
                # Redirect to todos page
                navigate("/todos");
            } else {
                setError("Invalid credentials");
            }
        }

        return <div style={{
            "minHeight": "calc(100vh - 48px)",
            "display": "flex",
            "alignItems": "center",
            "justifyContent": "center",
            "background": "#f5f5f5"
        }}>
            <div style={{
                "background": "#ffffff",
                "padding": "30px",
                "borderRadius": "8px",
                "width": "280px",
                "boxShadow": "0 2px 4px rgba(0,0,0,0.1)"
            }}>
                <h2 style={{"marginBottom": "20px"}}>Login</h2>
                <form onSubmit={handleLogin}>
                    <input
                        type="text"
                        value={username}
                        onChange={lambda e: any -> None { setUsername(e.target.value); }}
                        placeholder="Username"
                        style={{
                            "width": "100%",
                            "padding": "8px",
                            "marginBottom": "10px",
                            "border": "1px solid #ddd",
                            "borderRadius": "4px",
                            "boxSizing": "border-box"
                        }}
                    />
                    <input
                        type="password"
                        value={password}
                        onChange={lambda e: any -> None { setPassword(e.target.value); }}
                        placeholder="Password"
                        style={{
                            "width": "100%",
                            "padding": "8px",
                            "marginBottom": "10px",
                            "border": "1px solid #ddd",
                            "borderRadius": "4px",
                            "boxSizing": "border-box"
                        }}
                    />
                    {(<div style={{"color": "#dc2626", "fontSize": "14px", "marginBottom": "10px"}}>{error}</div>) if error else None}
                    <button
                        type="submit"
                        style={{
                            "width": "100%",
                            "padding": "8px",
                            "background": "#3b82f6",
                            "color": "#ffffff",
                            "border": "none",
                            "borderRadius": "4px",
                            "cursor": "pointer",
                            "fontWeight": "600"
                        }}
                    >Login</button>
                </form>
                <p style={{"textAlign": "center", "marginTop": "12px", "fontSize": "14px"}}>
                    Need an account? <Link to="/signup">Sign up</Link>
                </p>
            </div>
        </div>;
    }
}
```

**Key Features:**
- Simple state with `useState` for username, password, and error
- Direct call to `jacLogin()` - no wrapper needed
- Redirects to `/todos` on success using `navigate()` from `useNavigate()`
- Clean error handling

## Creating the Signup Page

Similarly, the signup page is straightforward:

```jac
cl {
    def SignupPage() -> any {
        let [username, setUsername] = useState("");
        let [password, setPassword] = useState("");
        let [error, setError] = useState("");
        let navigate = useNavigate();

        async def handleSignup(e: any) -> None {
            e.preventDefault();
            setError("");

            # Validate inputs
            if not username or not password {
                setError("Please fill in all fields");
                return;
            }

            # Attempt signup
            result = await jacSignup(username, password);
            if result["success"] {
                # Redirect to todos page
                navigate("/todos");
            } else {
                setError(result["error"] if result["error"] else "Signup failed");
            }
        }

        return <div style={{
            "maxWidth": "420px",
            "margin": "48px auto",
            "padding": "32px",
            "backgroundColor": "#ffffff",
            "borderRadius": "16px",
            "boxShadow": "0 20px 55px rgba(15,23,42,0.12)"
        }}>
            <h2 style={{
                "margin": "0 0 12px",
                "fontSize": "26px",
                "color": "#1e293b"
            }}>
                Create Account
            </h2>
            <p style={{
                "margin": "0 0 20px",
                "color": "#64748b"
            }}>
                Join us to start managing your todos
            </p>

            {/* Error */}
            {(state["error"] != "") ? (
                <div style={{
                    "marginBottom": "16px",
                    "padding": "12px",
                    "borderRadius": "8px",
                    "backgroundColor": "#fee2e2",
                    "color": "#b91c1c"
                }}>
                    {state["error"]}
                </div>
            ) : <span></span>}

            <form onSubmit={handleSubmit} style={{
                "display": "grid",
                "gap": "16px"
            }}>
                {/* Username */}
                <label>
                    <span style={{"fontSize": "14px", "fontWeight": "600"}}>
                        Username
                    </span>
                    <input
                        type="text"
                        value={state["username"]}
                        onChange={lambda e: any -> None {
                            setState({
                                "username": e.target.value,
                                "password": state["password"],
                                "confirmPassword": state["confirmPassword"],
                                "loading": state["loading"],
                                "error": ""
                            });
                        }}
                        placeholder="Choose a username"
                        style={{
                            "width": "100%",
                            "padding": "12px",
                            "borderRadius": "8px",
                            "border": "1px solid #e2e8f0"
                        }}
                        required={True}
                    />
                </label>

                {/* Password */}
                <label>
                    <span style={{"fontSize": "14px", "fontWeight": "600"}}>
                        Password
                    </span>
                    <input
                        type="password"
                        value={state["password"]}
                        onChange={lambda e: any -> None {
                            setState({
                                "username": state["username"],
                                "password": e.target.value,
                                "confirmPassword": state["confirmPassword"],
                                "loading": state["loading"],
                                "error": ""
                            });
                        }}
                        placeholder="Create a password"
                        style={{
                            "width": "100%",
                            "padding": "12px",
                            "borderRadius": "8px",
                            "border": "1px solid #e2e8f0"
                        }}
                        required={True}
                    />
                </label>

                {/* Confirm Password */}
                <label>
                    <span style={{"fontSize": "14px", "fontWeight": "600"}}>
                        Confirm Password
                    </span>
                    <input
                        type="password"
                        value={state["confirmPassword"]}
                        onChange={lambda e: any -> None {
                            setState({
                                "username": state["username"],
                                "password": state["password"],
                                "confirmPassword": e.target.value,
                                "loading": state["loading"],
                                "error": ""
                            });
                        }}
                        placeholder="Confirm your password"
                        style={{
                            "width": "100%",
                            "padding": "12px",
                            "borderRadius": "8px",
                            "border": "1px solid #e2e8f0"
                        }}
                        required={True}
                    />
                </label>

                <button
                    type="submit"
                    disabled={state["loading"]}
                    style={{
                        "padding": "12px",
                        "borderRadius": "8px",
                        "backgroundColor": "#22c55e",
                        "color": "#ffffff",
                        "fontWeight": "600",
                        "border": "none",
                        "cursor": (("not-allowed" if state["loading"] else "pointer")),
                        "opacity": ((0.6 if state["loading"] else 1))
                    }}
                >
                    {(("Creating account..." if state["loading"] else "Create Account"))}
                </button>
            </form>

            <p style={{
                "marginTop": "16px",
                "textAlign": "center",
                "color": "#64748b"
            }}>
                Already have an account?{" "}
                <Link to="/login" style={{
                    "color": "#6366f1",
                    "textDecoration": "none",
                    "fontWeight": "600"
                }}>
                    Sign in
                </Link>
            </p>
        </div>;
    }
}
```

## Protected Dashboard

Now let's update the dashboard to require authentication:

```jac
cl import from "@jac-client/utils" {Router, Routes, Route, jacIsLoggedIn}

cl {
    def DashboardPage() -> any {
        # Your todo app logic here...
        return <div>
            <h1>My Todos</h1>
            {/* Todo app UI */}
        </div>;
    }

    # Protected Dashboard Component
    def DashboardPage() -> any {
        # Check authentication
        if not jacIsLoggedIn() {
            return <Navigate to="/login" />;
        }

        # Your todo app logic here...
        return <div>
            <h1>My Todos</h1>
            {/* Todo app UI */}
        </div>;
    }

    def app() -> any {
        return <Router>
            <Routes>
                <Route path="/login" element={<LoginPage />} />
                <Route path="/signup" element={<SignupPage />} />

                {/* Protected route - checks auth inside component */}
                <Route path="/dashboard" element={<DashboardPage />} />
            </Routes>
        </Router>;
    }
}
```

**What happens:**
- If not logged in → `<Navigate>` redirects to `/login`
- If logged in → Dashboard shows

## Adding Logout

Let's add a logout button in the header:

```jac
cl {
    def AppHeader() -> any {
        let navigate = useNavigate();
        let isLoggedIn = jacIsLoggedIn();

        def handleLogout() -> None {
            jacLogout();
            navigate("/login");
        }

        return <header style={{
            "backgroundColor": "#ffffff",
            "borderBottom": "1px solid #e5e7eb",
            "padding": "16px 24px"
        }}>
            <div style={{
                "maxWidth": "1080px",
                "margin": "0 auto",
                "display": "flex",
                "justifyContent": "space-between",
                "alignItems": "center"
            }}>
                <h1>Todo App</h1>

                {(
                    <button onClick={lambda -> None { handleLogout(); }} style={{
                        "padding": "8px 16px",
                        "backgroundColor": "#ef4444",
                        "color": "white",
                        "border": "none",
                        "borderRadius": "6px",
                        "cursor": "pointer"
                    }}>
                        Logout
                    </button>
                ) if isLoggedIn else (
                    <Link to="/login" style={{
                        "padding": "8px 16px",
                        "backgroundColor": "#3b82f6",
                        "color": "white",
                        "textDecoration": "none",
                        "borderRadius": "6px"
                    }}>
                        Login
                    </Link>
                )}
            </div>
        </header>;
    }
}
```

## Testing Authentication

1. **Start your app:**
   ```bash
   jac serve app.jac
   ```

2. **Create an account:**
   - Go to `/signup`
   - Enter username and password
   - Click "Create Account"
   - Should redirect to dashboard

3. **Test protected route:**
   - Logout
   - Try to visit `/dashboard`
   - Should redirect to `/login`

4. **Login:**
   - Enter credentials
   - Should redirect to dashboard

## User Isolation

The magic: **Each user only sees their own todos!**

```jac
walker read_todos {
    class __specs__ {
        has auth: bool = True;  # This ensures isolation!
    }

    can read with `root entry {
        visit [-->(`?Todo)];
    }

    can report_todos with exit {
        report here;
    }
}
```

When `auth: bool = True`:
- Jac automatically uses the logged-in user's root node
- User A can't see User B's todos
- No extra code needed!

## Common Authentication Patterns

### Pattern 1: Conditional UI

```jac
def HomePage() -> any {
    let isLoggedIn = jacIsLoggedIn();

    return <div>
        {(
            <Link to="/dashboard">Go to Dashboard</Link>
        ) if isLoggedIn else (
            <Link to="/login">Login to Continue</Link>
        )}
    </div>;
}
```

### Pattern 2: Auto-Redirect After Signup

```jac
async def handleSignup() -> None {
    let result = await auth["signup"](username, password, confirm);
    if result["success"] {
        # Auto-login and redirect
        await auth["login"](username, password);
        navigate("/dashboard");
    }
}
```

### Pattern 3: Remember Me (Session Persistence)

Jac automatically handles session persistence - users stay logged in across page refreshes!

## Common Issues

### Issue: Can't login after signup
**Solution**: Make sure signup returns success correctly. Check the response structure.

### Issue: Redirected to login immediately
**Check**: Is `jacIsLoggedIn()` returning `True`? Check browser console for errors.

### Issue: Can access protected route without login
**Check**: Did you add the auth check `if not jacIsLoggedIn() { return <Navigate to="/login" />; }` at the top of your protected component?

### Issue: Logout doesn't work
**Solution**: Call `jacLogout()` and then navigate to login page.

## What You Learned

- ✅ Jac's built-in authentication system
- ✅ Creating login and signup forms
- ✅ Using `jacLogin`, `jacSignup`, `jacLogout`, `jacIsLoggedIn`
- ✅ Protected routes with `<Navigate>` components
- ✅ User isolation (each user sees only their data)
- ✅ Logout functionality with `useNavigate()`
- ✅ Conditional UI based on auth state

## Next Step

Congratulations! You've learned all the key concepts. Now let's put everything together into the **complete, final app**!

👉 **[Continue to Step 10: Final Integration](./step-10-final.md)**



