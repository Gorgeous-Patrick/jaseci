# Step 10: Final Integration - Complete Todo App

Congratulations on making it this far! In this final step, we'll bring everything together into a complete, production-ready todo application.

## What You've Built

You've learned:
- ✅ Creating Jac applications
- ✅ Building reusable components
- ✅ Styling with inline CSS
- ✅ Managing state with `useState`
- ✅ Side effects with `useEffect`
- ✅ Client-side routing
- ✅ Backend logic with walkers
- ✅ User authentication
- ✅ Data persistence

Now let's combine it all!

## Complete Application Code

Here's the entire app in one file - a clean implementation:

```jac
# Full Stack Todo App with Auth and Routing
cl import from react {useState, useEffect}
cl import from "@jac-client/utils" {
    Router,
    Routes,
    Route,
    Link,
    Navigate,
    useNavigate,
    jacSpawn,
    jacSignup,
    jacLogin,
    jacLogout,
    jacIsLoggedIn
}

# Backend - Todo Node
node Todo {
    has text: str;
    has done: bool = False;
}

# Backend - Walkers
walker create_todo {
    has text: str;
    can create with `root entry {
        new_todo = here ++> Todo(text=self.text);
        report new_todo;
    }
}

walker read_todos {
    can read with `root entry {
        visit [-->(`?Todo)];
    }
    can report_todos with Todo entry {
        report here;
    }
}

walker toggle_todo {
    can toggle with Todo entry {
        here.done = not here.done;
        report here;
    }
}

walker delete_todo {
    can delete with Todo entry {
        here.destroy();
        report {"success": True};
    }
}

# Frontend Components
cl {
    # Navigation
    def Navigation() -> any {
        let isLoggedIn = jacIsLoggedIn();
        let navigate = useNavigate();

        def handleLogout(e: any) -> None {
            e.preventDefault();
            jacLogout();
            navigate("/login");
        }

        if isLoggedIn {
            return <nav style={{
                "padding": "12px 24px",
                "background": "#3b82f6",
                "color": "#ffffff",
                "display": "flex",
                "justifyContent": "space-between"
            }}>
                <div style={{"fontWeight": "600"}}>Todo App</div>
                <div style={{"display": "flex", "gap": "16px"}}>
                    <Link to="/todos" style={{"color": "#ffffff", "textDecoration": "none"}}>
                        Todos
                    </Link>
                    <button
                        onClick={handleLogout}
                        style={{
                            "background": "none",
                            "color": "#ffffff",
                            "border": "1px solid #ffffff",
                            "padding": "2px 10px",
                            "borderRadius": "4px",
                            "cursor": "pointer"
                        }}
                    >
                        Logout
                    </button>
                </div>
            </nav>;
        }

        return <nav style={{
            "padding": "12px 24px",
            "background": "#3b82f6",
            "color": "#ffffff",
            "display": "flex",
            "justifyContent": "space-between"
        }}>
            <div style={{"fontWeight": "600"}}>Todo App</div>
            <div style={{"display": "flex", "gap": "16px"}}>
                <Link to="/login" style={{"color": "#ffffff", "textDecoration": "none"}}>
                    Login
                </Link>
                <Link to="/signup" style={{"color": "#ffffff", "textDecoration": "none"}}>
                    Sign Up
                </Link>
            </div>
        </nav>;
    }

    # Login Page
    def LoginPage() -> any {
        let [username, setUsername] = useState("");
        let [password, setPassword] = useState("");
        let [error, setError] = useState("");
        let navigate = useNavigate();

        async def handleLogin(e: any) -> None {
            e.preventDefault();
            setError("");
            if not username or not password {
                setError("Please fill in all fields");
                return;
            }
            success = await jacLogin(username, password);
            if success {
                navigate("/todos");
            } else {
                setError("Invalid credentials");
            }
        }

        def handleUsernameChange(e: any) -> None {
            setUsername(e.target.value);
        }

        def handlePasswordChange(e: any) -> None {
            setPassword(e.target.value);
        }

        let errorDisplay = None;
        if error {
            errorDisplay = <div style={{"color": "#dc2626", "fontSize": "14px", "marginBottom": "10px"}}>
                {error}
            </div>;
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
                        onChange={handleUsernameChange}
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
                        onChange={handlePasswordChange}
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
                    {errorDisplay}
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

    # Signup Page
    def SignupPage() -> any {
        let [username, setUsername] = useState("");
        let [password, setPassword] = useState("");
        let [error, setError] = useState("");
        let navigate = useNavigate();

        async def handleSignup(e: any) -> None {
            e.preventDefault();
            setError("");
            if not username or not password {
                setError("Please fill in all fields");
                return;
            }
            result = await jacSignup(username, password);
            if result["success"] {
                navigate("/todos");
            } else {
                setError(result["error"] if result["error"] else "Signup failed");
            }
        }

        def handleUsernameChange(e: any) -> None {
            setUsername(e.target.value);
        }

        def handlePasswordChange(e: any) -> None {
            setPassword(e.target.value);
        }

        let errorDisplay = None;
        if error {
            errorDisplay = <div style={{"color": "#dc2626", "fontSize": "14px", "marginBottom": "10px"}}>
                {error}
            </div>;
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
                <h2 style={{"marginBottom": "20px"}}>Sign Up</h2>
                <form onSubmit={handleSignup}>
                    <input
                        type="text"
                        value={username}
                        onChange={handleUsernameChange}
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
                        onChange={handlePasswordChange}
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
                    {errorDisplay}
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
                    >Sign Up</button>
                </form>
                <p style={{"textAlign": "center", "marginTop": "12px", "fontSize": "14px"}}>
                    Have an account? <Link to="/login">Login</Link>
                </p>
            </div>
        </div>;
    }

    # Todos Page (Protected)
    def TodosPage() -> any {
        # Check if user is logged in, redirect if not
        if not jacIsLoggedIn() {
            return <Navigate to="/login" />;
        }

        let [todos, setTodos] = useState([]);
        let [input, setInput] = useState("");
        let [filter, setFilter] = useState("all");

        # Load todos on mount
        useEffect(lambda -> None {
            async def loadTodos() -> None {
                result = await jacSpawn("read_todos", "", {});
                setTodos(result.reports if result.reports else []);
            }
            loadTodos();
        }, []);

        # Add todo
        async def addTodo() -> None {
            if not input.trim() { return; }
            result = await jacSpawn("create_todo", "", {"text": input.trim()});
            setTodos(todos.concat([result.reports[0][0]]));
            setInput("");
        }

        # Toggle todo
        async def toggleTodo(id: any) -> None {
            await jacSpawn("toggle_todo", id, {});
            setTodos(todos.map(lambda todo: any -> any {
                if todo._jac_id == id {
                    return {
                        "_jac_id": todo._jac_id,
                        "text": todo.text,
                        "done": not todo.done
                    };
                }
                return todo;
            }));
        }

        # Delete todo
        async def deleteTodo(id: any) -> None {
            await jacSpawn("delete_todo", id, {});
            setTodos(todos.filter(lambda todo: any -> bool { return todo._jac_id != id; }));
        }

        # Filter todos
        def getFilteredTodos() -> list {
            if filter == "active" {
                return todos.filter(lambda todo: any -> bool { return not todo.done; });
            } elif filter == "completed" {
                return todos.filter(lambda todo: any -> bool { return todo.done; });
            }
            return todos;
        }

        filteredTodos = getFilteredTodos();
        activeCount = todos.filter(lambda todo: any -> bool { return not todo.done; }).length;

        return <div style={{
            "maxWidth": "600px",
            "margin": "20px auto",
            "padding": "20px",
            "background": "#ffffff",
            "borderRadius": "8px",
            "boxShadow": "0 2px 4px rgba(0,0,0,0.1)"
        }}>
            <h1 style={{"marginBottom": "20px"}}>My Todos</h1>

            # Add todo input
            <div style={{"display": "flex", "gap": "8px", "marginBottom": "16px"}}>
                <input
                    type="text"
                    value={input}
                    onChange={lambda e: any -> None { setInput(e.target.value); }}
                    onKeyPress={lambda e: any -> None {
                        if e.key == "Enter" { addTodo(); }
                    }}
                    placeholder="What needs to be done?"
                    style={{
                        "flex": "1",
                        "padding": "8px",
                        "border": "1px solid #ddd",
                        "borderRadius": "4px"
                    }}
                />
                <button
                    onClick={addTodo}
                    style={{
                        "padding": "8px 16px",
                        "background": "#3b82f6",
                        "color": "#ffffff",
                        "border": "none",
                        "borderRadius": "4px",
                        "cursor": "pointer",
                        "fontWeight": "600"
                    }}
                >Add</button>
            </div>

            # Filter buttons
            <div style={{"display": "flex", "gap": "8px", "marginBottom": "16px"}}>
                <button
                    onClick={lambda -> None { setFilter("all"); }}
                    style={{
                        "padding": "6px 12px",
                        "background": ("#3b82f6" if filter == "all" else "#e5e7eb"),
                        "color": ("#ffffff" if filter == "all" else "#000000"),
                        "border": "none",
                        "borderRadius": "4px",
                        "cursor": "pointer",
                        "fontSize": "14px"
                    }}
                >All</button>
                <button
                    onClick={lambda -> None { setFilter("active"); }}
                    style={{
                        "padding": "6px 12px",
                        "background": ("#3b82f6" if filter == "active" else "#e5e7eb"),
                        "color": ("#ffffff" if filter == "active" else "#000000"),
                        "border": "none",
                        "borderRadius": "4px",
                        "cursor": "pointer",
                        "fontSize": "14px"
                    }}
                >Active</button>
                <button
                    onClick={lambda -> None { setFilter("completed"); }}
                    style={{
                        "padding": "6px 12px",
                        "background": ("#3b82f6" if filter == "completed" else "#e5e7eb"),
                        "color": ("#ffffff" if filter == "completed" else "#000000"),
                        "border": "none",
                        "borderRadius": "4px",
                        "cursor": "pointer",
                        "fontSize": "14px"
                    }}
                >Completed</button>
            </div>

            # Todo list
            <div>
                {(<div style={{"padding": "20px", "textAlign": "center", "color": "#999"}}>
                    No todos yet. Add one above!
                </div>) if filteredTodos.length == 0 else (
                    filteredTodos.map(lambda todo: any -> any {
                        return <div
                            key={todo._jac_id}
                            style={{
                                "display": "flex",
                                "alignItems": "center",
                                "gap": "10px",
                                "padding": "10px",
                                "borderBottom": "1px solid #e5e7eb"
                            }}
                        >
                            <input
                                type="checkbox"
                                checked={todo.done}
                                onChange={lambda -> None { toggleTodo(todo._jac_id); }}
                                style={{"cursor": "pointer"}}
                            />
                            <span style={{
                                "flex": "1",
                                "textDecoration": ("line-through" if todo.done else "none"),
                                "color": ("#999" if todo.done else "#000")
                            }}>
                                {todo.text}
                            </span>
                            <button
                                onClick={lambda -> None { deleteTodo(todo._jac_id); }}
                                style={{
                                    "padding": "4px 8px",
                                    "background": "#ef4444",
                                    "color": "#ffffff",
                                    "border": "none",
                                    "borderRadius": "4px",
                                    "cursor": "pointer",
                                    "fontSize": "12px"
                                }}
                            >Delete</button>
                        </div>;
                    })
                )}
            </div>

            # Stats
            {(<div style={{
                    "marginTop": "16px",
                    "padding": "10px",
                    "background": "#f9fafb",
                    "borderRadius": "4px",
                    "fontSize": "14px",
                    "color": "#666"
                }}>
                    {activeCount} {"item" if activeCount == 1 else "items"} left
                </div>) if todos.length > 0 else None}
        </div>;
    }

    # Home/Landing Page - auto-redirect
    def HomePage() -> any {
        if jacIsLoggedIn() {
            return <Navigate to="/todos" />;
        }
        return <Navigate to="/login" />;
    }

    # Main App with React Router
    def app() -> any {
        return <Router>
            <div style={{"fontFamily": "system-ui, sans-serif"}}>
                <Navigation />
                <Routes>
                    <Route path="/" element={<HomePage />} />
                    <Route path="/login" element={<LoginPage />} />
                    <Route path="/signup" element={<SignupPage />} />
                    <Route path="/todos" element={<TodosPage />} />
                </Routes>
            </div>
        </Router>;
    }
}
```

## Running the Complete App

1. **Save the code** to `app.jac`

2. **Start the server:**
   ```bash
   jac serve app.jac
   ```

3. **Open in browser:**
   - Go to `http://localhost:8000`
   - You'll be redirected to the login page

4. **Test it out:**
   - Create an account at `/signup`
   - Login at `/login`
   - You'll be redirected to `/todos` (the todos page)
   - Create, complete, and delete todos
   - Try filtering (All/Active/Completed)
   - Logout from the navigation bar
   - Login again - your todos persist!

## Features You've Built

✅ **Authentication:**
- User signup with password confirmation
- Secure login
- Session persistence
- Protected routes

✅ **Todo Management:**
- Create todos
- Mark as complete/incomplete
- Delete todos
- Filter by status (all/active/completed)
- Clear completed todos
- Item counter

✅ **UI/UX:**
- Responsive design
- Beautiful styling
- Loading states
- Error handling
- Empty states

✅ **Backend:**
- Data persistence
- User isolation
- Graph-based data structure
- Automatic API endpoints

## What's Next?

Now that you have a complete app, you can:

### 1. Add More Features
- Edit todo text
- Due dates and priorities
- Categories/tags
- Search functionality
- Sort options

### 2. Improve UI
- Dark mode
- Animations
- Mobile responsiveness
- Drag-and-drop reordering

### 3. Deploy Your App
- Use Jac Cloud for hosting
- Deploy to Vercel/Netlify
- Set up custom domain

### 4. Learn More
- Explore advanced walker patterns
- Learn about Jac's AI features
- Build more complex data graphs
- Integrate external APIs

## Deployment Guide

### Quick Deploy with Jac Cloud

```bash
# Install jac-cloud
pip install jac-cloud

# Deploy your app
jac cloud deploy app.jac

# Your app is now live!
```

### Environment Setup

For production, you might want to configure:

```bash
# Set environment variables
export JAC_DATABASE_URL="postgresql://..."
export JAC_SECRET_KEY="your-secret-key"

# Run in production mode
jac serve app.jac --prod
```

## Troubleshooting

### Issue: Todos not persisting
**Solution**: Make sure walkers have `auth: bool = True`

### Issue: Can't login after signup
**Solution**: Check console for errors. Verify signup returns success.

### Issue: UI looks broken
**Solution**: Clear browser cache, check for JavaScript errors.

### Issue: Performance is slow
**Solution**: Add indexes to frequently queried data, use pagination for large lists.

## Congratulations! 🎉

You've built a complete, production-ready todo application with:
- Modern frontend (React via Jac)
- Secure backend (Walkers)
- User authentication
- Data persistence
- Beautiful UI

You've learned the fundamentals of full-stack development with Jac!

## Learn More

### Explore React Concepts
Want to dive deeper into the React patterns Jac uses?
- [React Official Documentation](https://react.dev/learn)
- [React Hooks Reference](https://react.dev/reference/react)

### Jac Resources
- [Jac Official Documentation](https://www.jac-lang.org)
- [Jac Examples Repository](https://github.com/Jaseci-Labs/jaclang)
- [Jac Community Forum](https://community.jac-lang.org)

## Share Your Creation!

Built something cool? Share it with the community:
- Tag `#JacLang` on social media
- Contribute examples to Jac repository
- Write about your experience

## Thank You!

Thank you for completing this walkthrough. You now have the skills to build full-stack applications with Jac. Keep building, keep learning, and most importantly - have fun coding! 🚀

---

**Happy coding with Jac!**



