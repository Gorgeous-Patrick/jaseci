# Chapter 14: Jac Cloud Introduction

In this chapter, we'll explore Jac Cloud, the revolutionary cloud platform that transforms your Jac programs into scalable web services without code changes. We'll build a simple weather API that demonstrates how the same code runs locally and scales infinitely in the cloud.

!!! info "What You'll Learn"
    - Understanding Jac Cloud's scale-agnostic architecture
    - Converting walkers into API endpoints automatically
    - Deploying applications with zero configuration
    - Managing persistence and state in the cloud

---

## What is Jac Cloud?

Jac Cloud is a cloud-native execution environment designed specifically for Jac programs. It enables developers to write code once and run it anywhere - from local development to production-scale deployments - without any modifications.

!!! success "Key Benefits"
    - **Zero Code Changes**: Same code runs locally and in the cloud
    - **Automatic APIs**: Walkers become REST endpoints automatically
    - **Built-in Persistence**: Data storage handled transparently
    - **Instant Scaling**: Scale by increasing service replicas
    - **Developer Focus**: No infrastructure management needed

### Traditional vs Jac Cloud Development

!!! example "Development Comparison"
    === "Traditional Approach"
        ```python
        # app.py - Manual API setup required
        from flask import Flask, jsonify, request
        import requests

        app = Flask(__name__)

        @app.route('/weather/<city>', methods=['GET'])
        def get_weather(city):
            # Manual API endpoint definition
            api_key = "your_api_key"
            url = f"http://api.openweathermap.org/data/2.5/weather?q={city}&appid={api_key}"
            response = requests.get(url)
            return jsonify(response.json())

        if __name__ == '__main__':
            app.run(debug=True)
        ```

    === "Jac Cloud"
        ```jac
        # weather.jac - No manual API setup needed
        walker get_weather {
            has city: str;

            can get_weather_data with `root entry {
                # Your weather logic here
                weather_info = f"Weather in {self.city}: Sunny, 25°C";
                report {"city": self.city, "weather": weather_info};
            }
        }
        ```

---

## Quick Setup and Deployment

Let's start with a minimal weather API example and gradually enhance it throughout this chapter.

### Your First Cloud Application

!!! example "Basic Weather Service"
    === "Jac"
        ```jac
        # weather_service.jac
        walker get_weather {
            has city: str;

            can fetch_weather with `root entry {
                # Simple weather simulation
                weather_data = {
                    "city": self.city,
                    "temperature": "25°C",
                    "condition": "Sunny",
                    "humidity": "60%"
                };
                report weather_data;
            }
        }
        ```

    === "Python Equivalent"
        ```python
        # weather_service.py - Would need Flask/FastAPI setup
        from flask import Flask, jsonify, request

        app = Flask(__name__)

        @app.route('/get_weather', methods=['POST'])
        def get_weather():
            data = request.get_json()
            city = data.get('city')

            weather_data = {
                "city": city,
                "temperature": "25°C",
                "condition": "Sunny",
                "humidity": "60%"
            }
            return jsonify(weather_data)

        if __name__ == '__main__':
            app.run()
        ```

### Running Locally

Test your weather service locally:

```bash
jac run weather_service.jac
```

!!! tip "Local Testing"
    Your walker runs as a simple function locally, perfect for development and testing.

### Deploying to Cloud

Deploy the same code to the cloud with one command:

```bash
jac serve weather_service.jac
```

!!! success "Instant Deployment"
    ```
    INFO:     Started server process [26286]
    INFO:     Waiting for application startup.
    INFO:     Application startup complete.
    INFO:     Uvicorn running on http://0.0.0.0:8000 (Press CTRL+C to quit)
    ```

Your walker is now automatically available as a REST API endpoint!

---

## Walker Endpoints as APIs

Jac Cloud automatically transforms your walkers into RESTful API endpoints. Let's enhance our weather service to demonstrate this.

### Enhanced Weather Service

!!! example "Weather API with Persistence"
    === "Jac"
        ```jac
        # enhanced_weather.jac
        node WeatherCache {
            has city: str;
            has last_updated: str;
            has temperature: int;
            has condition: str;
        }

        walker get_weather {
            has city: str;

            can fetch_weather with `root entry {
                # Check if weather data exists
                cached_weather = [-->(`?WeatherCache)](?city == self.city);

                if cached_weather {
                    weather_data = {
                        "city": cached_weather[0].city,
                        "temperature": f"{cached_weather[0].temperature}°C",
                        "condition": cached_weather[0].condition,
                        "cached": True
                    };
                } else {
                    # Create new weather data
                    new_weather = WeatherCache(
                        city=self.city,
                        last_updated="2024-01-15",
                        temperature=25,
                        condition="Sunny"
                    );
                    here ++> new_weather;

                    weather_data = {
                        "city": self.city,
                        "temperature": "25°C",
                        "condition": "Sunny",
                        "cached": False
                    };
                }

                report weather_data;
            }
        }
        ```

    === "Python Equivalent"
        ```python
        # enhanced_weather.py - Requires database setup
        from flask import Flask, jsonify, request
        from sqlalchemy import create_engine, Column, String, Integer
        from sqlalchemy.ext.declarative import declarative_base
        from sqlalchemy.orm import sessionmaker

        app = Flask(__name__)
        Base = declarative_base()

        class WeatherCache(Base):
            __tablename__ = 'weather_cache'
            id = Column(Integer, primary_key=True)
            city = Column(String)
            temperature = Column(Integer)
            condition = Column(String)
            last_updated = Column(String)

        # Database setup required
        engine = create_engine('sqlite:///weather.db')
        Base.metadata.create_all(engine)
        Session = sessionmaker(bind=engine)

        @app.route('/get_weather', methods=['POST'])
        def get_weather():
            session = Session()
            data = request.get_json()
            city = data.get('city')

            # Manual database queries
            cached = session.query(WeatherCache).filter_by(city=city).first()

            if cached:
                weather_data = {
                    "city": cached.city,
                    "temperature": f"{cached.temperature}°C",
                    "condition": cached.condition,
                    "cached": True
                }
            else:
                new_weather = WeatherCache(
                    city=city, temperature=25,
                    condition="Sunny", last_updated="2024-01-15"
                )
                session.add(new_weather)
                session.commit()

                weather_data = {
                    "city": city,
                    "temperature": "25°C",
                    "condition": "Sunny",
                    "cached": False
                }

            session.close()
            return jsonify(weather_data)
        ```

### Testing Your API

Once deployed with `jac serve enhanced_weather.jac`, test your API (all walker endpoints are POST):

```bash
curl -X POST http://localhost:8000/walker/get_weather \
  -H "Content-Type: application/json" \
  -d '{"city": "New York"}'
```

!!! success "API Response"
    ```json
    {
        "returns": [
            {
                "city": "New York",
                "temperature": "25°C",
                "condition": "Sunny",
                "cached": false
            }
        ]
    }
    ```

---

## Local to Cloud: The Same Code Everywhere

The power of Jac Cloud lies in its scale-agnostic nature. Let's see how the same weather service works in different environments.

### Development Environment

!!! example "Local Development"
    ```bash
    # Run locally for testing
    jac run enhanced_weather.jac
    ```

    Your walker executes as a simple function, perfect for debugging and development.

### Production Deployment

!!! example "Cloud Deployment"
    ```bash
    # Deploy to production
    jac serve enhanced_weather.jac --port 8000
    ```

    The exact same code now serves thousands of users with automatic:

    - Load balancing
    - Persistence management
    - API endpoint generation
    - Request validation

### Adding Multiple Weather Operations

Let's add more functionality to demonstrate API scalability:

!!! example "Multi-Operation Weather Service"
    ```jac
    # complete_weather.jac
    node WeatherCache {
        has city: str;
        has temperature: int;
        has condition: str;
        has humidity: int;
        has last_updated: str;
    }

    walker get_weather {
        has city: str;

        can fetch_weather with `root entry {
            cached = [-->(`?WeatherCache)](?city == self.city);

            if cached {
                report {
                    "city": cached[0].city,
                    "temperature": f"{cached[0].temperature}°C",
                    "condition": cached[0].condition,
                    "humidity": f"{cached[0].humidity}%"
                };
            } else {
                new_weather = WeatherCache(
                    city=self.city, temperature=25, condition="Sunny",
                    humidity=60, last_updated="2024-01-15"
                );
                here ++> new_weather;

                report {
                    "city": self.city,
                    "temperature": "25°C",
                    "condition": "Sunny",
                    "humidity": "60%"
                };
            }
        }
    }

    walker add_city {
        has city: str;
        has temperature: int;
        has condition: str;

        can add_weather_data with `root entry {
            new_weather = WeatherCache(
                city=self.city,
                temperature=self.temperature,
                condition=self.condition,
                humidity=50,
                last_updated="2024-01-15"
            );
            here ++> new_weather;

            report {"message": f"Weather data added for {self.city}"};
        }
    }

    walker list_cities {
        can get_all_cities with `root entry {
            all_weather = [-->(`?WeatherCache)];
            cities = [w.city for w in all_weather];
            report {"cities": cities, "total": len(cities)};
        }
    }
    ```

### API Endpoints Generated

When you deploy with `jac serve complete_weather.jac`, you automatically get:

!!! info "Generated API Endpoints"
    - `POST /walker/get_weather` - Fetch weather for a city
    - `POST /walker/add_city` - Add weather data for a city
    - `POST /walker/list_cities` - List all available cities

### Testing Multiple Endpoints

```bash
# Add a city
curl -X POST http://localhost:8000/walker/add_city \
  -H "Content-Type: application/json" \
  -d '{"city": "London", "temperature": 18, "condition": "Rainy"}'

# List all cities
curl -X POST http://localhost:8000/walker/list_cities \
  -H "Content-Type: application/json" \
  -d '{}'

# Get weather for London
curl -X POST http://localhost:8000/walker/get_weather \
  -H "Content-Type: application/json" \
  -d '{"city": "London"}'
```

---

## Best Practices

!!! summary "Cloud Development Guidelines"
    - **Design for scale**: Write code that works equally well locally and in production
    - **Use environment variables**: Configure applications without code changes
    - **Test locally first**: Use `jac run` for development, `jac serve` for deployment
    - **Monitor endpoints**: Check the automatic API documentation at `/docs`
    - **Validate inputs**: Always validate walker parameters for robust APIs
    - **Handle errors gracefully**: Provide meaningful error messages to API consumers

## Key Takeaways

!!! summary "What We've Learned"
    **Scale-Agnostic Development:**

    - **Same code everywhere**: Write once, run locally or in the cloud without changes
    - **Automatic APIs**: Walkers become REST endpoints instantly
    - **Built-in persistence**: Graph data persists automatically across requests
    - **Zero infrastructure**: No server setup, database configuration, or API framework needed

    **Deployment Benefits:**

    - **Instant deployment**: From development to production with one command
    - **Automatic scaling**: Add more service instances to handle increased load
    - **Built-in documentation**: API docs generated automatically from walker signatures
    - **Type safety**: Request validation handled by the type system

    **Development Workflow:**

    - **Local testing**: Use `jac run` for development and debugging
    - **Service deployment**: Use `jac serve` to create REST APIs
    - **Cloud deployment**: Same code scales infinitely in Jac Cloud
    - **Configuration management**: Environment variables for flexible deployment

    **API Features:**

    - **RESTful endpoints**: All walkers become POST endpoints automatically
    - **JSON request/response**: Structured data exchange with type validation
    - **Error handling**: Automatic HTTP status codes and error responses
    - **Documentation**: Interactive API docs available at `/docs` endpoint

!!! tip "Try It Yourself"
    Experiment with cloud deployment by building:
    - A weather service with external API integration
    - A simple e-commerce catalog with products and categories
    - A content management system with posts and tags
    - A social media backend with users and posts

    Remember: Any walker you create automatically becomes a scalable API endpoint!

---

*Ready to learn about multi-user systems? Continue to [Chapter 15: Multi-User Architecture and Permissions](chapter_15.md)!*
