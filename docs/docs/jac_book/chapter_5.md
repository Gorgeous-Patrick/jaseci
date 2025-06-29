# Chapter 5: Advanced AI Operations

In this chapter, we'll explore Jac's advanced AI capabilities through MTLLM (Meaning Typed LLM). We'll build a simple image captioning tool that demonstrates model configuration, semantic strings, and multimodal AI integration in Jac applications.

!!! info "What You'll Learn"
    - MTLLM variations and model selection
    - Model declaration and configuration patterns
    - Semantic strings for enhanced AI context
    - Multimodality support for vision and audio
    - Building AI-powered applications with type safety

---

## MTLLM Overview

MTLLM (Meaning Typed LLM) is Jac's AI integration framework that makes working with Large Language Models as simple as calling a function. Unlike traditional AI programming that requires complex prompt engineering and API management, MTLLM enables natural AI integration through Jac's type system.

!!! success "MTLLM Benefits"
    - **Zero Prompt Engineering**: Define function signatures, let AI handle implementation
    - **Type Safety**: AI functions integrate with Jac's type system
    - **Model Flexibility**: Switch between different AI models easily
    - **Multimodal Support**: Handle text, images, and audio seamlessly
    - **Built-in Optimization**: Automatic prompt optimization and caching

### Traditional vs MTLLM AI Programming

!!! example "AI Integration Comparison"
    === "Traditional Approach"
        ```python
        # image_caption.py - Complex API management required
        import openai
        import base64
        from PIL import Image

        class ImageCaptioner:
            def __init__(self, api_key):
                self.client = openai.OpenAI(api_key=api_key)

            def encode_image(self, image_path):
                with open(image_path, "rb") as image_file:
                    return base64.b64encode(image_file.read()).decode('utf-8')

            def caption_image(self, image_path):
                base64_image = self.encode_image(image_path)

                response = self.client.chat.completions.create(
                    model="gpt-4-vision-preview",
                    messages=[
                        {
                            "role": "user",
                            "content": [
                                {
                                    "type": "text",
                                    "text": "Describe this image in detail."
                                },
                                {
                                    "type": "image_url",
                                    "image_url": {
                                        "url": f"data:image/jpeg;base64,{base64_image}"
                                    }
                                }
                            ]
                        }
                    ],
                    max_tokens=300
                )

                return response.choices[0].message.content

        # Usage
        captioner = ImageCaptioner("your-api-key")
        caption = captioner.caption_image("photo.jpg")
        print(caption)
        ```

    === "Jac MTLLM"
        <div class="code-block">
        ```jac
        # image_caption.jac - Simple AI integration
        import from mtllm.llms { OpenAI }

        glob llm = OpenAI(model_name="gpt-4-vision-preview");

        """Generate a detailed caption for the given image."""
        def caption_image(image_path: str) -> str by llm();

        with entry {
            caption = caption_image("photo.jpg");
            print(caption);
        }
        ```
        </div>

---

## Model Declaration and Configuration

MTLLM supports various AI models through a unified interface. Let's start with basic model configuration and gradually build our image captioning tool.

### Basic Model Setup

!!! example "Model Configuration"
    === "Jac"
        <div class="code-block">
        ```jac
        # basic_setup.jac
        import from mtllm.llms { OpenAI, Gemini }

        # Configure different models
        glob text_model = OpenAI(model_name="gpt-4o");
        glob vision_model = OpenAI(model_name="gpt-4-vision-preview");
        glob gemini_model = Gemini(model_name="gemini-2.0-flash");

        """Analyze text sentiment."""
        def analyze_sentiment(text: str) -> str by text_model();

        """Generate image description."""
        def describe_image(image_path: str) -> str by vision_model();

        with entry {
            # Test text analysis
            sentiment = analyze_sentiment("I love learning Jac programming!");
            print(f"Sentiment: {sentiment}");

            # Test image description
            description = describe_image("sample.jpg");
            print(f"Image: {description}");
        }
        ```
        </div>

    === "Python Equivalent"
        ```python
        # basic_setup.py - Manual model management
        import openai
        from google import generativeai as genai

        class ModelManager:
            def __init__(self):
                self.openai_client = openai.OpenAI(api_key="your-key")
                genai.configure(api_key="your-gemini-key")
                self.gemini_model = genai.GenerativeModel('gemini-2.0-flash')

            def analyze_sentiment(self, text):
                response = self.openai_client.chat.completions.create(
                    model="gpt-4o",
                    messages=[
                        {"role": "system", "content": "Analyze the sentiment of the text."},
                        {"role": "user", "content": text}
                    ]
                )
                return response.choices[0].message.content

            def describe_image(self, image_path):
                # Complex image encoding and API calls required
                pass

        # Usage requires manual instantiation and management
        manager = ModelManager()
        sentiment = manager.analyze_sentiment("I love learning!")
        ```

### Model Configuration Options

!!! example "Advanced Model Configuration"
    <div class="code-block">
    ```jac
    # model_config.jac
    import from mtllm.llms { OpenAI }

    # Configure model with custom parameters
    glob creative_model = OpenAI(
        model_name="gpt-4o",
        temperature=0.9,  # More creative
        max_tokens=500,
        verbose=True      # Show prompts for debugging
    );

    glob precise_model = OpenAI(
        model_name="gpt-4o",
        temperature=0.1,  # More deterministic
        max_tokens=200
    );

    """Generate creative story from image."""
    def create_story(image_path: str) -> str by creative_model();

    """Extract factual information from image."""
    def extract_facts(image_path: str) -> str by precise_model();
    ```
    </div>

---

## Building the Image Captioning Tool

Let's progressively build an image captioning tool that demonstrates MTLLM's capabilities.

### Simple Image Caption Generator

!!! example "Basic Image Captioning"
    === "Jac"
        <div class="code-block">
        ```jac
        # image_captioner.jac
        import from mtllm.llms { OpenAI }

        glob vision_llm = OpenAI(model_name="gpt-4-vision-preview");

        obj ImageCaptioner {
            has name: str;

            """Generate a brief, descriptive caption for the image."""
            def generate_caption(image_path: str) -> str by vision_llm();

            """Extract specific objects visible in the image."""
            def identify_objects(image_path: str) -> list[str] by vision_llm();

            """Determine the mood or atmosphere of the image."""
            def analyze_mood(image_path: str) -> str by vision_llm();
        }

        with entry {
            captioner = ImageCaptioner(name="AI Photo Assistant");

            # Generate basic caption
            caption = captioner.generate_caption("nature_photo.jpg");
            print(f"Caption: {caption}");

            # Identify objects
            objects = captioner.identify_objects("nature_photo.jpg");
            print(f"Objects found: {objects}");

            # Analyze mood
            mood = captioner.analyze_mood("nature_photo.jpg");
            print(f"Mood: {mood}");
        }
        ```
        </div>

    === "Python Equivalent"
        ```python
        # image_captioner.py - Complex implementation required
        import openai
        import base64

        class ImageCaptioner:
            def __init__(self, name, api_key):
                self.name = name
                self.client = openai.OpenAI(api_key=api_key)

            def _encode_image(self, image_path):
                with open(image_path, "rb") as image_file:
                    return base64.b64encode(image_file.read()).decode('utf-8')

            def generate_caption(self, image_path):
                base64_image = self._encode_image(image_path)
                response = self.client.chat.completions.create(
                    model="gpt-4-vision-preview",
                    messages=[{
                        "role": "user",
                        "content": [
                            {"type": "text", "text": "Generate a brief, descriptive caption for the image."},
                            {"type": "image_url", "image_url": {"url": f"data:image/jpeg;base64,{base64_image}"}}
                        ]
                    }]
                )
                return response.choices[0].message.content

            def identify_objects(self, image_path):
                # Similar complex implementation
                pass

            def analyze_mood(self, image_path):
                # Similar complex implementation
                pass

        # Usage
        captioner = ImageCaptioner("AI Assistant", "your-api-key")
        caption = captioner.generate_caption("photo.jpg")
        ```

---

## Semantic Strings and Context Enhancement

Semantic strings (`sem`) provide additional context to AI functions without cluttering your code. They're particularly useful for domain-specific applications.

### Enhanced Captioning with Context

!!! example "Context-Enhanced Captioning"
    <div class="code-block">
    ```jac
    # enhanced_captioner.jac
    import from mtllm.llms { OpenAI }

    glob vision_llm = OpenAI(model_name="gpt-4-vision-preview");

    obj PhotoAnalyzer {
        has photographer_name: str;
        has style_preference: str;
    }

    # Add semantic context for better AI understanding
    sem PhotoAnalyzer = "Professional photo analysis tool for photographers";
    sem PhotoAnalyzer.photographer_name = "Name of the photographer for personalized analysis";
    sem PhotoAnalyzer.style_preference = "Preferred photography style (artistic, documentary, commercial)";

    obj PhotoAnalyzer {
        """Generate caption considering photographer's style preference."""
        def generate_styled_caption(image_path: str) -> str by vision_llm(incl_info=(self.style_preference));

        """Provide technical photography feedback."""
        def analyze_composition(image_path: str) -> dict by vision_llm();

        """Suggest improvements for the photo."""
        def suggest_improvements(image_path: str) -> list[str] by vision_llm(incl_info=(self.photographer_name, self.style_preference));
    }

    with entry {
        analyzer = PhotoAnalyzer(
            photographer_name="Alice",
            style_preference="artistic"
        );

        # Generate styled caption
        caption = analyzer.generate_styled_caption("portrait.jpg");
        print(f"Styled caption: {caption}");

        # Analyze composition
        composition = analyzer.analyze_composition("portrait.jpg");
        print(f"Composition analysis: {composition}");

        # Get improvement suggestions
        suggestions = analyzer.suggest_improvements("portrait.jpg");
        print(f"Suggestions: {suggestions}");
    }
    ```
    </div>

---

## Multimodal AI Integration

MTLLM excels at handling multiple types of media. Let's extend our tool to handle both images and audio.

### Multi-Modal Caption Tool

!!! example "Image and Audio Processing"
    <div class="code-block">
    ```jac
    # multimodal_tool.jac
    import from mtllm.llms { OpenAI }

    glob multimodal_llm = OpenAI(model_name="gpt-4o");

    obj MediaAnalyzer {
        has analysis_mode: str = "detailed";

        """Generate caption for image with contextual understanding."""
        def caption_image(image_path: str, context: str = "") -> str by multimodal_llm();

        """Transcribe and summarize audio content."""
        def process_audio(audio_path: str) -> dict by multimodal_llm();

        """Generate alt text for accessibility."""
        def generate_alt_text(image_path: str) -> str by multimodal_llm();

        """Create social media description."""
        def create_social_post(image_path: str, platform: str) -> str by multimodal_llm(incl_info=(self.analysis_mode));
    }

    with entry {
        analyzer = MediaAnalyzer(analysis_mode="social_media");

        # Process different media types
        image_caption = analyzer.caption_image(
            "vacation_photo.jpg",
            "Family vacation at the beach"
        );
        print(f"Image caption: {image_caption}");

        # Generate accessible alt text
        alt_text = analyzer.generate_alt_text("vacation_photo.jpg");
        print(f"Alt text: {alt_text}");

        # Create platform-specific content
        instagram_post = analyzer.create_social_post("vacation_photo.jpg", "Instagram");
        print(f"Instagram post: {instagram_post}");

        # Process audio if available
        try {
            audio_summary = analyzer.process_audio("interview.mp3");
            print(f"Audio summary: {audio_summary}");
        } except Exception as e {
            print(f"Audio processing not available: {e}");
        }
    }
    ```
    </div>

### Advanced Multimodal Features

!!! example "Content Generation Pipeline"
    <div class="code-block">
    ```jac
    # content_pipeline.jac
    import from mtllm.llms { OpenAI }

    glob content_llm = OpenAI(model_name="gpt-4o", temperature=0.7);

    obj ContentCreator {
        has brand_voice: str;
        has target_audience: str;

        """Analyze image and generate marketing copy."""
        def create_marketing_copy(image_path: str, product_name: str) -> dict by content_llm(
            incl_info=(self.brand_voice, self.target_audience)
        );

        """Generate multiple caption variations."""
        def generate_variations(image_path: str, count: int = 3) -> list[str] by content_llm();

        """Create SEO-optimized description."""
        def optimize_for_seo(image_path: str, keywords: list[str]) -> str by content_llm();
    }

    with entry {
        creator = ContentCreator(
            brand_voice="friendly and professional",
            target_audience="young professionals"
        );

        # Generate marketing content
        marketing_content = creator.create_marketing_copy(
            "product_photo.jpg",
            "EcoWater Bottle"
        );
        print(f"Marketing copy: {marketing_content}");

        # Generate multiple variations
        variations = creator.generate_variations("product_photo.jpg", count=5);
        for (i, variation) in enumerate(variations) {
            print(f"Variation {i+1}: {variation}");
        }

        # SEO optimization
        seo_description = creator.optimize_for_seo(
            "product_photo.jpg",
            ["eco-friendly", "water bottle", "sustainable"]
        );
        print(f"SEO description: {seo_description}");
    }
    ```
    </div>

---

## Testing and Error Handling

AI applications require robust error handling and testing strategies.

### Robust AI Integration

!!! example "Error-Resilient AI Functions"
    <div class="code-block">
    ```jac
    # robust_ai.jac
    import from mtllm.llms { OpenAI }

    glob reliable_llm = OpenAI(model_name="gpt-4o", max_tries=3);

    obj RobustCaptioner {
        has fallback_enabled: bool = True;

        """Generate caption with error handling."""
        def safe_caption(image_path: str) -> dict {
            try {
                caption = self.generate_caption_ai(image_path);
                return {
                    "success": True,
                    "caption": caption,
                    "source": "ai"
                };
            } except Exception as e {
                if self.fallback_enabled {
                    fallback_caption = f"Image analysis unavailable for {image_path}";
                    return {
                        "success": False,
                        "caption": fallback_caption,
                        "source": "fallback",
                        "error": str(e)
                    };
                } else {
                    raise e;
                }
            }
        }

        """AI-powered caption generation."""
        def generate_caption_ai(image_path: str) -> str by reliable_llm();

        """Validate generated content."""
        def validate_caption(caption: str) -> bool {
            # Basic validation rules
            if len(caption) < 10 {
                return False;
            }
            if "error" in caption.lower() {
                return False;
            }
            return True;
        }
    }

    with entry {
        captioner = RobustCaptioner(fallback_enabled=True);

        # Test with different scenarios
        test_images = ["valid_photo.jpg", "corrupted.jpg", "missing.jpg"];

        for image in test_images {
            result = captioner.safe_caption(image);

            if result["success"] {
                is_valid = captioner.validate_caption(result["caption"]);
                print(f"{image}: {result['caption']} (Valid: {is_valid})");
            } else {
                print(f"{image}: Failed - {result['error']}");
            }
        }
    }
    ```
    </div>

---

## Best Practices

!!! tip "AI Development Guidelines"
    - **Start Simple**: Begin with basic AI functions, add complexity gradually
    - **Use Semantic Strings**: Provide context without cluttering function signatures
    - **Handle Failures**: Always implement fallback strategies for AI functions
    - **Test Thoroughly**: AI outputs can be unpredictable, test with various inputs
    - **Optimize Models**: Choose appropriate models and parameters for your use case

## Key Takeaways

!!! summary "What We've Learned"
    **MTLLM Integration:**

    - **Simple AI Functions**: Define AI capabilities with `by llm()` syntax
    - **Model Configuration**: Flexible model selection and parameter tuning
    - **Type Safety**: AI functions integrate seamlessly with Jac's type system
    - **Zero Prompt Engineering**: Function signatures become prompts automatically

    **Advanced Features:**

    - **Semantic Context**: Enhanced AI understanding through semantic strings
    - **Multimodal Support**: Seamless handling of images, text, and audio
    - **Error Handling**: Robust patterns for production AI applications
    - **Model Selection**: Easy switching between different AI providers and models

    **Practical Applications:**

    - **Content Generation**: Automated text and media analysis
    - **Data Processing**: Intelligent data transformation and extraction
    - **API Integration**: Direct AI integration without complex setup
    - **Scalable Architecture**: AI functions work in both local and cloud deployments

!!! tip "Try It Yourself"
    Enhance the image captioning tool by adding:
    - Batch processing for multiple images
    - Integration with cloud storage services
    - Custom model fine-tuning capabilities
    - Real-time image analysis from camera feeds

    Remember: AI functions in Jac are as easy to use as regular functions, but with the power of Large Language Models!

---

*Ready to learn about imports and modular programming? Continue to [Chapter 6: Imports System and File Operations](chapter_6.md)!*
