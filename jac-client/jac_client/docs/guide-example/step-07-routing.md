# Step 7: Adding Routes (Multiple Pages)

In this step, you'll learn how to create a multi-page application with routing - all without page reloads!

## What is Client-Side Routing?

Traditional websites:
- Click link → Browser requests new page from server → Page reloads
- Every page load = full refresh

Modern single-page apps (SPAs):
- Click link → JavaScript changes URL and content → No reload!
- Feels instant and smooth

**Python analogy:**

```python
# Traditional routing (like Flask)
@app.route("/")
def home():
    return render_template("home.html")

@app.route("/about")
def about():
    return render_template("about.html")

# Client-side routing (Jac)
# All pages are components, routing happens in browser
```

## Import Router Components

First, import routing utilities from Jac:

```jac
cl import from react {useState, useEffect}
cl import from "@jac-client/utils" {
    Router,
    Routes,
    Route,
    Link,
    Navigate,
    useNavigate
}
```

### What Each Does:

- `Router` - Container for all routing logic
- `Routes` - Groups your route definitions
- `Route` - Defines a single page/route
- `Link` - Navigation link (like `<a>` but without reload)
- `Navigate` - Component for redirecting
- `useNavigate` - Hook for programmatic navigation

## Basic Routing Setup

Let's create a simple multi-page app:

```jac
cl import from react {useState}
cl import from "@jac-client/utils" {Router, Routes, Route, Link}

cl {
    # Home Page Component
    def HomePage() -> any {
        return <div style={{"padding": "20px"}}>
            <h1>🏠 Home Page</h1>
            <p>Welcome to our app!</p>
        </div>;
    }

    # About Page Component
    def AboutPage() -> any {
        return <div style={{"padding": "20px"}}>
            <h1>ℹ️ About Page</h1>
            <p>This is a todo app built with Jac!</p>
        </div>;
    }

    # Main App with Routing
    def app() -> any {
        return <Router>
            <div>
                {/* Navigation Bar */}
                <nav style={{
                    "backgroundColor": "#3b82f6",
                    "padding": "16px",
                    "marginBottom": "20px"
                }}>
                    <Link to="/" style={{
                        "color": "white",
                        "marginRight": "20px",
                        "textDecoration": "none"
                    }}>
                        Home
                    </Link>
                    <Link to="/about" style={{
                        "color": "white",
                        "textDecoration": "none"
                    }}>
                        About
                    </Link>
                </nav>

                {/* Routes */}
                <Routes>
                    <Route path="/" element={<HomePage />} />
                    <Route path="/about" element={<AboutPage />} />
                </Routes>
            </div>
        </Router>;
    }
}
```

**Try it!** Click the links - notice the URL changes but the page doesn't reload! ✨

### Breaking It Down:

1. **`<Router>`** - Wraps your entire app and manages routing state

2. **`<Link to="/">`** - Creates clickable navigation
   - Like `<a href="">` but prevents page reload

3. **`<Routes>`** - Container for route definitions

4. **`<Route>`** - Defines what component to show for each URL
   - `path="/"` - URL pattern
   - `element={<HomePage />}` - Component to render (must use JSX)

## Creating Our Todo App Pages

Let's create three pages:
1. **Home** - Landing page
2. **Login** - User authentication
3. **Dashboard** - Todo list (requires login)

```jac
cl import from react {useState}
cl import from "@jac-client/utils" {Router, Routes, Route, Link, useNavigate}

cl {
    # Home Page
    def HomePage() -> any {
        return <div style={{
            "textAlign": "center",
            "padding": "50px"
        }}>
            <h1 style={{"fontSize": "3rem", "marginBottom": "20px"}}>
                📝 Todo App
            </h1>
            <p style={{"fontSize": "1.2rem", "color": "#666", "marginBottom": "30px"}}>
                Stay organized and productive
            </p>
            <Link to="/login" style={{
                "display": "inline-block",
                "padding": "12px 30px",
                "backgroundColor": "#3b82f6",
                "color": "white",
                "textDecoration": "none",
                "borderRadius": "8px",
                "fontSize": "1.1rem"
            }}>
                Get Started
            </Link>
        </div>;
    }

    # Login Page
    def LoginPage() -> any {
        let [username, setUsername] = useState("");
        let [password, setPassword] = useState("");
        let navigate = useNavigate();

        def handleLogin(event: any) -> None {
            event.preventDefault();
            console.log("Login:", username, password);
            # We'll implement real auth later!
            navigate("/dashboard");
        }

        return <div style={{
            "maxWidth": "400px",
            "margin": "50px auto",
            "padding": "30px",
            "backgroundColor": "#ffffff",
            "borderRadius": "12px",
            "boxShadow": "0 4px 6px rgba(0,0,0,0.1)"
        }}>
            <h2 style={{"marginBottom": "20px"}}>Sign In</h2>
            <form onSubmit={handleLogin}>
                <div style={{"marginBottom": "16px"}}>
                    <label style={{"display": "block", "marginBottom": "8px"}}>
                        Username
                    </label>
                    <input
                        type="text"
                        value={username}
                        onChange={lambda e: any -> None {
                            setUsername(e.target.value);
                        }}
                        style={{
                            "width": "100%",
                            "padding": "10px",
                            "borderRadius": "6px",
                            "border": "1px solid #ddd"
                        }}
                        required={True}
                    />
                </div>
                <div style={{"marginBottom": "16px"}}>
                    <label style={{"display": "block", "marginBottom": "8px"}}>
                        Password
                    </label>
                    <input
                        type="password"
                        value={password}
                        onChange={lambda e: any -> None {
                            setPassword(e.target.value);
                        }}
                        style={{
                            "width": "100%",
                            "padding": "10px",
                            "borderRadius": "6px",
                            "border": "1px solid #ddd"
                        }}
                        required={True}
                    />
                </div>
                <button type="submit" style={{
                    "width": "100%",
                    "padding": "12px",
                    "backgroundColor": "#3b82f6",
                    "color": "white",
                    "border": "none",
                    "borderRadius": "6px",
                    "cursor": "pointer",
                    "fontSize": "16px"
                }}>
                    Sign In
                </button>
            </form>
            <p style={{"marginTop": "16px", "textAlign": "center"}}>
                Don't have an account?{" "}
                <Link to="/signup" style={{"color": "#3b82f6"}}>
                    Sign up
                </Link>
            </p>
        </div>;
    }

    # Dashboard (Todo List)
    def DashboardPage() -> any {
        let [todos, setTodos] = useState([
            {"id": 1, "text": "Welcome to your dashboard!", "done": False}
        ]);

        return <div style={{"maxWidth": "720px", "margin": "20px auto", "padding": "20px"}}>
            <div style={{
                "display": "flex",
                "justifyContent": "space-between",
                "alignItems": "center",
                "marginBottom": "24px"
            }}>
                <h1>My Todos</h1>
                <Link to="/" style={{"color": "#ef4444"}}>
                    Logout
                </Link>
            </div>

            <div>
                {todos.map(lambda todo: any -> any {
                    return <div key={todo["id"]} style={{
                        "padding": "16px",
                        "backgroundColor": "#ffffff",
                        "borderRadius": "8px",
                        "marginBottom": "8px",
                        "boxShadow": "0 1px 3px rgba(0,0,0,0.1)"
                    }}>
                        {todo["text"]}
                    </div>;
                })}
            </div>
        </div>;
    }

    # Main App
    def app() -> any {
        return <Router>
            <div style={{"fontFamily": "system-ui, sans-serif"}}>
                <Navigation />
                <Routes>
                    <Route path="/login" element={<LoginPage />} />
                    <Route path="/signup" element={<SignupPage />} />
                    <Route path="/todos" element={<TodosPage />} />
                </Routes>
            </div>
        </Router>;
    }
}
```

**Key changes from examples:**
- Added `<Navigation />` component at the top
- Routes are: `/login`, `/signup`, and `/todos` (not `/dashboard`)
- Protected routes check auth inside the component (see below)
```

## Programmatic Navigation

Sometimes you need to navigate from code (not a link click):

```jac
def LoginPage() -> any {
    let navigate = useNavigate();  # Get navigation function

    def handleLogin() -> None {
        # Do login logic...

        # Navigate to dashboard
        navigate("/dashboard");
    }

    return <button onClick={lambda -> None { handleLogin(); }}>
        Login
    </button>;
}
```

**Use cases:**
- After form submission
- After successful API call
- On timeout/error
- Conditional redirects

## Route Parameters

Pass data through the URL:

```jac
cl import from "@jac-client/utils" {useParams}

# Define route with parameter
<Route path="/todo/:id" element={<TodoDetailPage />} />

# Component accesses parameters via useParams hook
def TodoDetailPage() -> any {
    let params = useParams();
    let todoId = params.id;  # Access the :id parameter

    return <div>
        <h1>Todo Details</h1>
        <p>Viewing todo with ID: {todoId}</p>
    </div>;
}

# Navigate with parameter
<Link to="/todo/123">View Todo 123</Link>
```

## Protected Routes

Prevent access to pages that require authentication:

```jac
cl import from "@jac-client/utils" {Router, Routes, Route, Navigate, jacIsLoggedIn}

cl {
    # Protected Dashboard - requires login
    def DashboardPage() -> any {
        # Check authentication at the start
        if not jacIsLoggedIn() {
            return <Navigate to="/login" />;
        }

        return <div>
            <h1>🎉 Private Dashboard</h1>
            <p>You are logged in!</p>
        </div>;
    }

    def app() -> any {
        return <Router>
            <Routes>
                <Route path="/" element={<HomePage />} />
                <Route path="/login" element={<LoginPage />} />

                {/* Protected route - checks auth inside component */}
                <Route path="/dashboard" element={<DashboardPage />} />
            </Routes>
        </Router>;
    }
}
```

**What happens:**
- If user is logged in → Shows dashboard
- If not logged in → Redirects to login

## Creating a Navigation Header Component

Let's make a reusable header with navigation:

```jac
cl {
    def Header() -> any {
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
                <div style={{
                    "fontSize": "1.5rem",
                    "fontWeight": "700",
                    "color": "#3b82f6"
                }}>
                    Todo App
                </div>
                <nav style={{"display": "flex", "gap": "24px"}}>
                    <Link to="/" style={{
                        "textDecoration": "none",
                        "color": "#374151"
                    }}>
                        Home
                    </Link>
                    <Link to="/login" style={{
                        "textDecoration": "none",
                        "color": "#374151"
                    }}>
                        Login
                    </Link>
                    <Link to="/dashboard" style={{
                        "textDecoration": "none",
                        "color": "#374151"
                    }}>
                        Dashboard
                    </Link>
                </nav>
            </div>
        </header>;
    }

    def app() -> any {
        return <Router>
            <div>
                <Header />  {/* Shows on all pages */}

                <main style={{"minHeight": "calc(100vh - 64px)"}}>
                    <Routes>
                        <Route path="/" element={<HomePage />} />
                        <Route path="/login" element={<LoginPage />} />
                        <Route path="/dashboard" element={<DashboardPage />} />
                    </Routes>
                </main>
            </div>
        </Router>;
    }
}
```

## Active Link Styling

Highlight the current page link:

```jac
cl import from "@jac-client/utils" {useLocation}

def NavLink(to: str, text: str) -> any {
    let location = useLocation();  # Get current URL
    let isActive = location.pathname == to;

    return <Link to={to} style={{
        "padding": "8px 16px",
        "textDecoration": "none",
        "color": (("#ffffff" if isActive else "#cbd5e1")),
        "backgroundColor": (("#3b82f6" if isActive else "transparent")),
        "borderRadius": "6px",
        "fontWeight": (("600" if isActive else "normal"))
    }}>
        {text}
    </Link>;
}

# Usage
<nav>
    <NavLink to="/" text="Home" />
    <NavLink to="/about" text="About" />
    <NavLink to="/dashboard" text="Dashboard" />
</nav>
```

## 404 Page (Not Found)

Handle unknown routes:

```jac
def NotFoundPage() -> any {
    return <div style={{
        "textAlign": "center",
        "padding": "100px 20px"
    }}>
        <h1 style={{"fontSize": "4rem", "marginBottom": "20px"}}>
            404
        </h1>
        <p style={{"fontSize": "1.5rem", "color": "#666", "marginBottom": "30px"}}>
            Page not found
        </p>
        <Link to="/" style={{
            "padding": "12px 24px",
            "backgroundColor": "#3b82f6",
            "color": "white",
            "textDecoration": "none",
            "borderRadius": "8px"
        }}>
            Go Home
        </Link>
    </div>;
}

# Add as last route (catches everything)
<Routes>
    <Route path="/" element={<HomePage />} />
    <Route path="/login" element={<LoginPage />} />
    <Route path="/dashboard" element={<DashboardPage />} />
    <Route path="*" element={<NotFoundPage />} />  {/* Catch-all */}
</Routes>
```

## Common Routing Patterns

### Pattern 1: Nested Layouts

```jac
def MainLayout() -> any {
    return <div>
        <Header />
        <Routes>
            <Route path="/" element={<HomePage />} />
            <Route path="/about" element={<AboutPage />} />
        </Routes>
        <Footer />
    </div>;
}
```

### Pattern 2: Conditional Navigation

```jac
def Header() -> any {
    let isLoggedIn = jacIsLoggedIn();

    return <nav>
        <Link to="/">Home</Link>
        {(
            <Link to="/dashboard">Dashboard</Link>
        ) if isLoggedIn else (
            <Link to="/login">Login</Link>
        )}
    </nav>;
}
```

### Pattern 3: Redirect Component

```jac
def OldPage() -> any {
    return <Navigate to="/new-page" />;  # Auto-redirect
}
```

## Common Issues

### Issue: Link doesn't work
**Check**: Is it inside a `<Router>` component?

### Issue: Page reloads on link click
**Check**: Are you using `<Link>` or regular `<a>` tag?
- ✅ Use `<Link to="/">`
- ❌ Don't use `<a href="/">`

### Issue: useNavigate() not working
**Check**: Is the component rendered inside `<Routes>`?

### Issue: Route not matching
**Check**: Is the `path` prop spelled correctly? Is it inside `<Routes>`?

## What You Learned

- ✅ What client-side routing is
- ✅ How to set up routing with `Router`, `Routes`, `Route`
- ✅ Creating navigation links with `Link`
- ✅ Programmatic navigation with `useNavigate`
- ✅ Route parameters for dynamic URLs
- ✅ Protected routes with guards
- ✅ Creating navigation components
- ✅ Handling 404 errors

## Next Step

Now you have multiple pages, but they don't save data to a backend yet. Let's create **walkers** - Jac's way of handling backend logic!

👉 **[Continue to Step 8: Backend with Walkers](./step-08-walkers.md)**



