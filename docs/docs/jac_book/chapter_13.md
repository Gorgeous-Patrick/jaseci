# Chapter 13: Persistence and the Root Node

In this chapter, we'll explore Jac's automatic persistence system and the fundamental concept of the root node. We'll build a simple counter application that demonstrates how Jac automatically maintains state when running as a service with a database backend.

!!! info "What You'll Learn"
    - Understanding Jac's automatic persistence mechanism with jac serve
    - The root node as the entry point for all persistent data
    - State consistency across API requests and service restarts
    - Building stateful applications with jac-cloud

---

## What is Automatic Persistence?

Traditional programming requires explicit database setup, connection management, and data serialization. Jac eliminates this complexity by making persistence a core language feature when running as a service. When you use `jac serve` with a database backend, nodes and their connections automatically persist across requests and service restarts.

!!! warning "Persistence Requirements"
    - **Database Backend**: Persistence requires `jac serve` with a configured database
    - **Service Mode**: `jac run` executions are stateless and don't persist data
    - **Root Connection**: Nodes must be connected to root to persist
    - **API Context**: Persistence works within the context of API endpoints

!!! success "Persistence Benefits"
    - **Zero Configuration**: No manual database schema or ORM setup
    - **Automatic State**: Data persists without explicit save/load operations
    - **Graph Integrity**: Relationships between nodes are maintained
    - **Type Safety**: Persistent data maintains type information
    - **Instant Recovery**: Services resume exactly where they left off

### Traditional vs Jac Persistence

!!! example "Persistence Comparison"
    === "Traditional Approach"
        ```python
        # counter_api.py - Manual database setup required
        from flask import Flask, jsonify, request
        import sqlite3
        import os

        app = Flask(__name__)

        class Counter:
            def __init__(self):
                self.db_path = "counter.db"
                self.init_db()

            def init_db(self):
                conn = sqlite3.connect(self.db_path)
                cursor = conn.cursor()
                cursor.execute('''
                    CREATE TABLE IF NOT EXISTS counter (
                        id INTEGER PRIMARY KEY,
                        value INTEGER
                    )
                ''')
                cursor.execute('SELECT value FROM counter WHERE id = 1')
                if not cursor.fetchone():
                    cursor.execute('INSERT INTO counter (id, value) VALUES (1, 0)')
                conn.commit()
                conn.close()

            def get_value(self):
                conn = sqlite3.connect(self.db_path)
                cursor = conn.cursor()
                cursor.execute('SELECT value FROM counter WHERE id = 1')
                value = cursor.fetchone()[0]
                conn.close()
                return value

            def increment(self):
                conn = sqlite3.connect(self.db_path)
                cursor = conn.cursor()
                cursor.execute('UPDATE counter SET value = value + 1 WHERE id = 1')
                conn.commit()
                conn.close()
                return self.get_value()

        counter = Counter()

        @app.route('/counter')
        def get_counter():
            return jsonify({"value": counter.get_value()})

        @app.route('/counter/increment', methods=['POST'])
        def increment_counter():
            new_value = counter.increment()
            return jsonify({"value": new_value})

        if __name__ == "__main__":
            app.run(debug=True)
        ```

    === "Jac Automatic Persistence"
        ```jac
        # main.jac - No database setup needed
        node Counter {
            has value: int = 0;

            can increment() -> int {
                self.value += 1;
                return self.value;
            }

            can get_value() -> int {
                return self.value;
            }
        }

        walker get_counter {
            can get_counter_endpoint with `root entry {
                counter_nodes = [root --> Counter];
                if not counter_nodes {
                    counter = Counter();
                    root ++> counter;
                } else {
                    counter = counter_nodes[0];
                }
                report {"value": counter.get_value()};
            }
        }

        walker increment_counter {
            can increment_counter_endpoint with `root entry {
                counter_nodes = [root --> Counter];
                if not counter_nodes {
                    counter = Counter();
                    root ++> counter;
                } else {
                    counter = counter_nodes[0];
                }
                new_value = counter.increment();
                report {"value": new_value};
            }
        }
        ```

---

## Setting Up a Jac Cloud Project

To demonstrate persistence, we need to create a proper jac-cloud project structure:

!!! example "Project Structure"
    ```
    counter-app/
    ├── .env                 # Environment configuration
    ├── main.jac            # Main application logic
    ├── server.py           # Optional custom server setup
    └── requirements.txt    # Python dependencies
    ```

Let's create our counter application:

!!! example "Complete Counter Project"
    === ".env"
        ```bash
        # .env - Database configuration
        DATABASE_URL=sqlite:///./app.db
        SECRET_KEY=your-secret-key-here
        ```

    === "main.jac"
        ```jac
        # main.jac
        node Counter {
            has value: int = 0;
            has created_at: str;

            can increment() -> int {
                self.value += 1;
                return self.value;
            }

            can reset() -> int {
                self.value = 0;
                return self.value;
            }
        }

        walker get_counter {
            can get_counter_endpoint with `root entry {
                counter_nodes = [root --> Counter];
                if not counter_nodes {
                    counter = Counter(created_at="2024-01-15");
                    root ++> counter;
                    report {"value": 0, "status": "created"};
                } else {
                    counter = counter_nodes[0];
                    report {"value": counter.value, "status": "existing"};
                }
            }
        }

        walker increment_counter {
            can increment_counter_endpoint with `root entry {
                counter_nodes = [root --> Counter];
                if not counter_nodes {
                    counter = Counter(created_at="2024-01-15");
                    root ++> counter;
                } else {
                    counter = counter_nodes[0];
                }
                new_value = counter.increment();
                report {"value": new_value, "previous": new_value - 1};
            }
        }

        walker reset_counter {
            can reset_counter_endpoint with `root entry {
                counter_nodes = [root --> Counter];
                if counter_nodes {
                    counter = counter_nodes[0];
                    counter.reset();
                    report {"value": 0, "status": "reset"};
                } else {
                    report {"value": 0, "status": "no_counter_found"};
                }
            }
        }
        ```

    === "requirements.txt"
        ```
        jaclang
        fastapi
        uvicorn
        python-dotenv
        ```

---

## The Root Node Concept

The root node is Jac's fundamental concept for persistent data organization. When running with `jac serve`, every request has access to a special `root` node that serves as the entry point for all persistent graph structures.

### Understanding Root Node

!!! info "Root Node Properties"
    - **Request Context**: Available in every API request when using jac serve
    - **Persistence Gateway**: Starting point for all persistent data
    - **Graph Anchor**: All persistent nodes must be reachable from root
    - **Automatic Creation**: Exists automatically with database backend
    - **Transaction Boundary**: Changes persist at the end of each request

### Running the Service

```bash
# Navigate to project directory
cd counter-app

# Install dependencies
pip install -r requirements.txt

# Start the service with database persistence
jac serve main.jac

# Service starts on http://localhost:8000
# API documentation available at http://localhost:8000/docs
```

### Testing Persistence

```bash
# First request - Create counter
curl -X POST http://localhost:8000/walker/get_counter \
  -H "Content-Type: application/json" \
  -d '{}'
# Response: {"returns": [{"value": 0, "status": "created"}]}

# Increment the counter
curl -X POST http://localhost:8000/walker/increment_counter \
  -H "Content-Type: application/json" \
  -d '{}'
# Response: {"returns": [{"value": 1, "previous": 0}]}

# Increment again
curl -X POST http://localhost:8000/walker/increment_counter \
  -H "Content-Type: application/json" \
  -d '{}'
# Response: {"returns": [{"value": 2, "previous": 1}]}

# Check counter value
curl -X POST http://localhost:8000/walker/get_counter \
  -H "Content-Type: application/json" \
  -d '{}'
# Response: {"returns": [{"value": 2, "status": "existing"}]}

# Restart the service (Ctrl+C, then jac serve main.jac again)

# Counter value persists after restart
curl -X POST http://localhost:8000/walker/get_counter \
  -H "Content-Type: application/json" \
  -d '{}'
# Response: {"returns": [{"value": 2, "status": "existing"}]}
```

!!! tip "Persistence in Action"
    Notice how the counter value persists between requests and even service restarts when using `jac serve` with a database!

---

## State Consistency

Jac maintains state consistency through its graph-based persistence model when running as a service. All connected nodes and their relationships are automatically maintained across requests and service restarts.

### Enhanced Counter with History

Let's enhance our counter to track increment history:

!!! example "Counter with History Tracking"
    ```jac
    # main.jac - Enhanced with history
    import from datetime { datetime };

    node Counter {
        has value: int = 0;
        has created_at: str;

        can increment() -> int {
            old_value = self.value;
            self.value += 1;

            # Create history entry
            history = HistoryEntry(
                timestamp=str(datetime.now()),
                old_value=old_value,
                new_value=self.value
            );
            self ++> history;
            return self.value;
        }

        can get_history() -> list[dict] {
            history_nodes = [self --> HistoryEntry];
            return [
                {
                    "timestamp": h.timestamp,
                    "old_value": h.old_value,
                    "new_value": h.new_value
                }
                for h in history_nodes
            ];
        }
    }

    node HistoryEntry {
        has timestamp: str;
        has old_value: int;
        has new_value: int;
    }

    walker get_counter_with_history {
        can get_counter_with_history_endpoint with `root entry {
            counter_nodes = [root --> Counter];
            if not counter_nodes {
                counter = Counter(created_at=str(datetime.now()));
                root ++> counter;
                report {
                    "value": 0,
                    "status": "created",
                    "history": []
                };
            } else {
                counter = counter_nodes[0];
                report {
                    "value": counter.value,
                    "status": "existing",
                    "history": counter.get_history()
                };
            }
        }
    }

    walker increment_with_history {
        can increment_with_history_endpoint with `root entry {
            counter_nodes = [root --> Counter];
            if not counter_nodes {
                counter = Counter(created_at=str(datetime.now()));
                root ++> counter;
            } else {
                counter = counter_nodes[0];
            }

            new_value = counter.increment();
            report {
                "value": new_value,
                "history": counter.get_history()
            };
        }
    }
    ```

### Testing History Persistence

```bash
# Start fresh service
jac serve main.jac

# Multiple increments to build history
curl -X POST http://localhost:8000/walker/increment_with_history \
  -H "Content-Type: application/json" \
  -d '{}'

curl -X POST http://localhost:8000/walker/increment_with_history \
  -H "Content-Type: application/json" \
  -d '{}'

curl -X POST http://localhost:8000/walker/increment_with_history \
  -H "Content-Type: application/json" \
  -d '{}'

# Check counter with complete history
curl -X POST http://localhost:8000/walker/get_counter_with_history \
  -H "Content-Type: application/json" \
  -d '{}'
# Response includes value and complete history array

# Restart service - history persists
# jac serve main.jac (after restart)
curl -X POST http://localhost:8000/walker/get_counter_with_history \
  -H "Content-Type: application/json" \
  -d '{}'
# All history entries remain intact
```

---

## Building Stateful Applications

The automatic persistence enables building sophisticated stateful applications. Let's create a multi-counter management system:

!!! example "Multi-Counter Management System"
    ```jac
    # main.jac - Multi-counter system
    import from datetime { datetime }

    node CounterManager {
        has created_at: str;

        can create_counter(name: str) -> dict {
            # Check if counter already exists
            existing = [self --> Counter](?name == name);
            if existing {
                return {"status": "exists", "counter": existing[0].name};
            }

            new_counter = Counter(name=name, value=0);
            self ++> new_counter;
            return {"status": "created", "counter": name};
        }

        can list_counters() -> list[dict] {
            counters = [self --> Counter];
            return [
                {"name": c.name, "value": c.value}
                for c in counters
            ];
        }

        can get_total() -> int {
            counters = [self --> Counter];
            return sum([c.value for c in counters]);
        }
    }

    node Counter {
        has name: str;
        has value: int = 0;

        can increment(amount: int = 1) -> int {
            self.value += amount;
            return self.value;
        }
    }

    walker create_counter {
        has name: str;

        can create_counter_endpoint with `root entry {
            manager_nodes = [root --> CounterManager];
            if not manager_nodes {
                manager = CounterManager(created_at=str(datetime.now()));
                root ++> manager;
            } else {
                manager = manager_nodes[0];
            }

            result = manager.create_counter(self.name);
            report result;
        }
    }

    walker increment_named_counter {
        has name: str;
        has amount: int = 1;

        can increment_named_counter_endpoint with `root entry {
            manager_nodes = [root --> CounterManager];
            if not manager_nodes {
                report {"error": "No counter manager found"};
                return;
            }

            manager = manager_nodes[0];
            counters = [manager --> Counter](?name == self.name);

            if not counters {
                report {"error": f"Counter {self.name} not found"};
                return;
            }

            counter = counters[0];
            new_value = counter.increment(self.amount);
            report {"name": self.name, "value": new_value};
        }
    }

    walker get_all_counters {
        can get_all_counters_endpoint with `root entry {
            manager_nodes = [root --> CounterManager];
            if not manager_nodes {
                report {"counters": [], "total": 0};
                return;
            }

            manager = manager_nodes[0];
            report {
                "counters": manager.list_counters(),
                "total": manager.get_total()
            };
        }
    }
    ```

### API Usage Examples

```bash
# Create multiple counters
curl -X POST "http://localhost:8000/walker/create_counter" \
     -H "Content-Type: application/json" \
     -d '{"name": "page_views"}'

curl -X POST "http://localhost:8000/walker/create_counter" \
     -H "Content-Type: application/json" \
     -d '{"name": "user_signups"}'

# Increment specific counters
curl -X POST "http://localhost:8000/walker/increment_named_counter" \
     -H "Content-Type: application/json" \
     -d '{"name": "page_views", "amount": 5}'

curl -X POST "http://localhost:8000/walker/increment_named_counter" \
     -H "Content-Type: application/json" \
     -d '{"name": "user_signups", "amount": 2}'

# View all counters
curl -X POST http://localhost:8000/walker/get_all_counters \
  -H "Content-Type: application/json" \
  -d '{}'
# Response: {"returns": [{"counters": [{"name": "page_views", "value": 5}, {"name": "user_signups", "value": 2}], "total": 7}]}
```

---

## Persistence Best Practices

!!! tip "Effective Persistence Patterns"
    - **Service Mode**: Always use `jac serve` for persistent applications
    - **Database Backend**: Configure appropriate database in .env file
    - **Root Connection**: Connect all persistent nodes to root or root-connected nodes
    - **Initialization Checks**: Use filtering to check for existing data
    - **Transaction Awareness**: Changes persist automatically at request completion

### Production Deployment

!!! example "Production Configuration"
    === ".env"
        ```bash
        # Production .env
        DATABASE_URL=postgresql://user:password@host:5432/dbname
        SECRET_KEY=your-production-secret-key
        DEBUG=false
        ```

    === "Docker Setup"
        ```dockerfile
        # Dockerfile
        FROM python:3.11

        WORKDIR /app
        COPY requirements.txt .
        RUN pip install -r requirements.txt

        COPY . .
        EXPOSE 8000

        CMD ["jac", "serve", "main.jac", "--host", "0.0.0.0"]
        ```

---

## Key Takeaways

!!! summary "What We've Learned"
    - **Service Requirement**: Persistence only works with `jac serve`, not `jac run`
    - **Database Backend**: Requires proper database configuration
    - **Root Node**: Central entry point for all persistent graph structures
    - **Request Lifecycle**: State persists automatically between API requests
    - **Service Restarts**: Data survives service restarts with proper database setup
    - **Graph Integrity**: Relationships between nodes persist automatically

### Next Steps

In the upcoming chapters, we'll explore:

- **Chapter 14**: Advanced Jac Cloud features and deployment
- **Chapter 15**: Multi-user systems with shared persistent state
- **Chapter 16**: Scaling persistent applications in production

!!! tip "Try It Yourself"
    Create your own persistent application by:
    - Building a todo list API that persists tasks
    - Adding user authentication with persistent user data
    - Creating a simple blog with persistent posts and comments

    Remember: Only nodes connected to root (directly or indirectly) will persist when using `jac serve` with a database!

---

*Ready to explore advanced cloud features? Continue to [Chapter 14: Advanced Jac Cloud](chapter_14.md)!*
