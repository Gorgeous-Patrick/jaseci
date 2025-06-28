# Chapter 12: Walkers as API Endpoints

In this chapter, we'll explore how Jac automatically transforms walkers into RESTful API endpoints without any manual configuration. We'll build a simple shared notebook system that demonstrates automatic API generation, request handling, and parameter validation through a practical example.

!!! info "What You'll Learn"
    - How walkers automatically become API endpoints
    - Request/response handling in Jac
    - Parameter validation and type safety
    - REST patterns using walker semantics
    - Building multi-user applications with shared data

---

## Automatic API Generation

Traditional web development requires explicit route definitions, request parsing, and response formatting. Jac eliminates this complexity by automatically converting any walker into a REST API endpoint when deployed with `jac serve`.

!!! success "API Generation Benefits"
    - **Zero Configuration**: No route definitions or HTTP handlers needed
    - **Type Safety**: Parameters automatically validated from walker attributes
    - **Instant REST**: Every walker becomes an endpoint immediately
    - **Request Parsing**: JSON request bodies mapped to walker attributes
    - **Response Formatting**: Walker reports become JSON responses

### Traditional vs Jac API Development

!!! example "API Development Comparison"
    === "Jac Automatic APIs"
        ```jac
        # notebook.jac - No manual API setup needed
        node Note {
            has title: str;
            has content: str;
            has author: str;
            has created_at: str = "2024-01-15";
        }

        walker create_note {
            has title: str;
            has content: str;
            has author: str;

            can create_new_note with `root entry {
                new_note = Note(
                    title=self.title,
                    content=self.content,
                    author=self.author
                );
                here ++> new_note;
                report {"message": "Note created", "id": new_note.id};
            }
        }

        walker get_notes {
            can fetch_all_notes with `root entry {
                all_notes = [-->(`?Note)];
                notes_data = [
                    {"id": n.id, "title": n.title, "author": n.author}
                    for n in all_notes
                ];
                report {"notes": notes_data, "total": len(notes_data)};
            }
        }
        ```
    === "Traditional Approach"
        ```python
        # app.py - Manual API setup required
        from flask import Flask, request, jsonify
        from typing import Dict, List

        app = Flask(__name__)

        # Global storage (in production, use a database)
        notebooks = {}

        @app.route('/create_note', methods=['POST'])
        def create_note():
            try:
                data = request.get_json()
                title = data.get('title')
                content = data.get('content')
                author = data.get('author')

                # Manual validation
                if not title or not content or not author:
                    return jsonify({"error": "Missing required fields"}), 400

                note_id = len(notebooks) + 1
                notebooks[note_id] = {
                    "id": note_id,
                    "title": title,
                    "content": content,
                    "author": author
                }

                return jsonify({"message": "Note created", "id": note_id})
            except Exception as e:
                return jsonify({"error": str(e)}), 500

        @app.route('/get_notes', methods=['GET'])
        def get_notes():
            return jsonify(list(notebooks.values()))

        if __name__ == '__main__':
            app.run(debug=True)
        ```

---

## Request/Response Handling

Jac automatically handles request parsing and response formatting. When a walker is called via HTTP, request JSON is mapped to walker attributes, and walker reports become JSON responses.

### Basic Notebook System

Let's start with a simple notebook where users can create and view notes:

!!! example "Simple Note Creation"
    === "Jac"

        ```jac
        # simple_notebook.jac
        node Note {
            has title: str;
            has content: str;
            has author: str;
        }

        walker create_note {
            has title: str;
            has content: str;
            has author: str;

            can process_creation with `root entry {
                # Create and connect note to root
                new_note = Note(
                    title=self.title,
                    content=self.content,
                    author=self.author
                );
                here ++> new_note;

                # Report success with note details
                report {
                    "status": "created",
                    "note": {
                        "title": new_note.title,
                        "author": new_note.author
                    }
                };
            }
        }
        ```

    === "Python Equivalent"
        ```python
        # simple_notebook.py - Requires manual setup
        from flask import Flask, request, jsonify
        from dataclasses import dataclass
        from typing import List

        app = Flask(__name__)

        @dataclass
        class Note:
            title: str
            content: str
            author: str

        # In-memory storage
        notes: List[Note] = []

        @app.route('/create_note', methods=['POST'])
        def create_note():
            data = request.get_json()

            # Manual validation and error handling
            if not all(k in data for k in ['title', 'content', 'author']):
                return jsonify({"error": "Missing fields"}), 400

            note = Note(
                title=data['title'],
                content=data['content'],
                author=data['author']
            )
            notes.append(note)

            return jsonify({
                "status": "created",
                "note": {"title": note.title, "author": note.author}
            })

        if __name__ == '__main__':
            app.run()
        ```

### Deployment and Testing

Deploy your notebook API:

```bash
jac serve simple_notebook.jac
```

Test the API endpoint (all walker endpoints are POST):

```bash
curl -X POST http://localhost:8000/walker/create_note \
  -H "Content-Type: application/json" \
  -d '{
    "title": "My First Note",
    "content": "This is a test note",
    "author": "Alice"
  }'
```

!!! success "API Response"
    ```json
    {
        "returns": [
            {
                "status": "created",
                "note": {
                    "title": "My First Note",
                    "author": "Alice"
                }
            }
        ]
    }
    ```

---

## Parameter Validation

Jac automatically validates request parameters based on walker attribute types. This eliminates manual validation code and ensures type safety.

### Enhanced Notebook with Validation

!!! example "Notebook with Type Validation"

    ```jac
    # validated_notebook.jac
    node Note {
        has title: str;
        has content: str;
        has author: str;
        has priority: int = 1;  # 1-5 priority level
        has tags: list[str] = [];
    }

    walker create_note {
        has title: str;
        has content: str;
        has author: str;
        has priority: int = 1;
        has tags: list[str] = [];

        can validate_and_create with `root entry {
            # Jac automatically validates types before this runs

            # Additional business logic validation
            if len(self.title) < 3 {
                report {"error": "Title must be at least 3 characters"};
                return;
            }

            if self.priority < 1 or self.priority > 5 {
                report {"error": "Priority must be between 1 and 5"};
                return;
            }

            # Create note with validated data
            new_note = Note(
                title=self.title,
                content=self.content,
                author=self.author,
                priority=self.priority,
                tags=self.tags
            );
            here ++> new_note;

            report {
                "message": "Note created successfully",
                "note_title": new_note.title,
                "priority": new_note.priority
            };
        }
    }
    ```

### Testing Validation

```bash
# Valid request
curl -X POST http://localhost:8000/walker/create_note \
  -H "Content-Type: application/json" \
  -d '{
    "title": "Important Meeting",
    "content": "Discuss project timeline",
    "author": "Bob",
    "priority": 3,
    "tags": ["work", "meeting"]
  }'

# Invalid request - priority out of range
curl -X POST http://localhost:8000/walker/create_note \
  -H "Content-Type: application/json" \
  -d '{
    "title": "Test",
    "content": "Test content",
    "author": "Bob",
    "priority": 10
  }'
```

!!! tip "Automatic Type Validation"
    Jac validates types before your walker code runs. Invalid types return HTTP 400 automatically.

---

## REST Patterns with Walkers

Walkers naturally map to REST operations, creating intuitive API patterns for common CRUD operations.

### Complete Notebook API

!!! example "Full CRUD Notebook System"

    ```jac
    import from uuid { uuid4 }

    # complete_notebook.jac
    node Note {
        has title: str;
        has content: str;
        has author: str;
        has priority: int = 1;
        has created_at: str = "2024-01-15";
        has id: str;
    }

    # CREATE - Add new note
    walker create_note {
        has title: str;
        has content: str;
        has author: str;
        has priority: int = 1;

        can add_note with `root entry {
            new_note = Note(
                title=self.title, content=self.content,
                author=self.author, priority=self.priority,
                id="note_" + str(uuid4())
            );
            here ++> new_note;
            report {"message": "Note created", "id": new_note.id};
        }
    }

    # READ - Get all notes
    walker list_notes {
        can get_all_notes with `root entry {
            all_notes = [-->(`?Note)];
            report {
                "notes": [
                    {
                        "id": n.id,
                        "title": n.title,
                        "author": n.author,
                        "priority": n.priority
                    }
                    for n in all_notes
                ],
                "total": len(all_notes)
            };
        }
    }

    # READ - Get specific note
    walker get_note {
        has note_id: str;

        can fetch_note with `root entry {
            target_note = [-->(`?Note)](?id == self.note_id);

            if target_note {
                note = target_note[0];
                report {
                    "note": {
                        "id": note.id,
                        "title": note.title,
                        "content": note.content,
                        "author": note.author,
                        "priority": note.priority
                    }
                };
            } else {
                report {"error": "Note not found"};
            }
        }
    }

    # UPDATE - Modify note
    walker update_note {
        has note_id: str;
        has title: str = "";
        has content: str = "";
        has priority: int = 0;

        can modify_note with `root entry {
            target_note = [-->(`?Note)](?id == self.note_id);

            if target_note {
                note = target_note[0];

                # Update only provided fields
                if self.title {
                    note.title = self.title;
                }
                if self.content {
                    note.content = self.content;
                }
                if self.priority > 0 {
                    note.priority = self.priority;
                }

                report {"message": "Note updated", "id": note.id};
            } else {
                report {"error": "Note not found"};
            }
        }
    }

    # DELETE - Remove note
    walker delete_note {
        has note_id: str;

        can remove_note with `root entry {
            target_note = [-->(`?Note)](?id == self.note_id);

            if target_note {
                note = target_note[0];
                # Delete the node and its connections
                del note;
                report {"message": "Note deleted", "id": self.note_id};
            } else {
                report {"error": "Note not found"};
            }
        }
    }
    ```

### API Usage Examples

```bash
# Create a note
curl -X POST http://localhost:8000/walker/create_note \
  -H "Content-Type: application/json" \
  -d '{"title": "Shopping List", "content": "Milk, Bread, Eggs", "author": "Alice"}'

# List all notes
curl -X POST http://localhost:8000/walker/list_notes \
  -H "Content-Type: application/json" \
  -d '{}'

# Get specific note (replace with actual ID)
curl -X POST http://localhost:8000/walker/get_note \
  -H "Content-Type: application/json" \
  -d '{"note_id": "note_123"}'

# Update a note
curl -X POST http://localhost:8000/walker/update_note \
  -H "Content-Type: application/json" \
  -d '{"note_id": "note_123", "priority": 5}'

# Delete a note
curl -X POST http://localhost:8000/walker/delete_note \
  -H "Content-Type: application/json" \
  -d '{"note_id": "note_123"}'
```

---

## Shared Notebook with Permissions

Let's add basic permission checking to demonstrate multi-user patterns:

!!! example "Notebook with User Permissions"
    ```jac  linenums="1"
    import from uuid { uuid4 }

    # shared_notebook.jac
    node Note {
        has title: str;
        has content: str;
        has author: str;
        has shared_with: list[str] = [];
        has is_public: bool = false;
        has id: str;
    }

    walker create_shared_note {
        has title: str;
        has content: str;
        has author: str;
        has shared_with: list[str] = [];
        has is_public: bool = false;

        can create_note with `root entry {
            new_note = Note(
                title=self.title,
                content=self.content,
                author=self.author,
                shared_with=self.shared_with,
                is_public=self.is_public,
                id="note_" + str(uuid4())
            );
            here ++> new_note;

            report {
                "message": "Shared note created",
                "id": new_note.id,
                "shared_with": len(self.shared_with),
                "is_public": self.is_public
            };
        }
    }

    walker get_user_notes {
        has user: str;

        can fetch_accessible_notes with `root entry {
            all_notes = [-->(`?Note)];
            accessible_notes = [];

            for note in all_notes {
                # User can access if they're the author, note is public,
                # or they're in the shared_with list
                if (note.author == self.user or
                    note.is_public or
                    self.user in note.shared_with) {
                    accessible_notes.append({
                        "id": note.id,
                        "title": note.title,
                        "author": note.author,
                        "is_mine": note.author == self.user
                    });
                }
            }

            report {
                "user": self.user,
                "notes": accessible_notes,
                "count": len(accessible_notes)
            };
        }
    }

    walker share_note {
        has note_id: str;
        has user: str;
        has share_with: str;

        can add_share_permission with `root entry {
            target_note = [-->(`?Note)](?id == self.note_id);

            if target_note {
                note = target_note[0];

                # Only author can share
                if note.author == self.user {
                    if self.share_with not in note.shared_with {
                        note.shared_with.append(self.share_with);
                    }

                    report {
                        "message": f"Note shared with {self.share_with}",
                        "shared_with": note.shared_with
                    };
                } else {
                    report {"error": "Only author can share notes"};
                }
            } else {
                report {"error": "Note not found"};
            }
        }
    }
    ```

### Testing Shared Notebook

```bash
# Create a shared note
curl -X POST http://localhost:8000/walker/create_shared_note \
  -H "Content-Type: application/json" \
  -d '{
    "title": "Team Meeting Notes",
    "content": "Discussed project milestones",
    "author": "Alice",
    "shared_with": ["Bob", "Charlie"],
    "is_public": false
  }'

# Get notes for a user
curl -X POST http://localhost:8000/walker/get_user_notes \
  -H "Content-Type: application/json" \
  -d '{"user": "Bob"}'

# Share note with another user
curl -X POST http://localhost:8000/walker/share_note \
  -H "Content-Type: application/json" \
  -d '{
    "note_id": "note_123",
    "user": "Alice",
    "share_with": "David"
  }'
```

---

## Key Takeaways

!!! summary "What We've Learned"
    - **Automatic API Generation**: Walkers become REST endpoints without configuration
    - **Type-Safe Parameters**: Request validation handled automatically by type system
    - **Natural REST Patterns**: CRUD operations map intuitively to walker semantics
    - **Shared Data Models**: Persistent nodes enable multi-user applications
    - **Business Logic Focus**: No HTTP handling code needed, focus on application logic

### Next Steps

In the upcoming chapters, we'll explore:

- **Chapter 13**: Automatic persistence for stateful applications
- **Chapter 14**: Deploying to Jac Cloud for infinite scale
- **Chapter 15**: Advanced user management and authentication

!!! tip "Try It Yourself"
    Experiment with the notebook system by adding:

    - Note categories or folders
    - Full-text search across notes
    - Note revision history
    - Collaborative editing features

    Remember: Every walker you create automatically becomes an API endpoint when deployed!

---

*Ready to learn about persistent data? Continue to [Chapter 13: Persistence and the Root Node](chapter_13.md)!*
