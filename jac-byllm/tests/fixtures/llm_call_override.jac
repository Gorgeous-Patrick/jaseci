import from mtllm { Model }

glob llm = Model(
    model_name="mockllm",
    outputs=[
      'Hello there, Alex!',
      'Strongly Positive',
       'Bonjour le monde!',
      '\n42\nfoo\n3.14\n[1]',
      '1;2;3;4;5',
      '{"foo": "42"}',
    ]
);


"Greet the user with the given name."
def greet(name: str) -> str {
  return "Howdy " + name;
}

"Analyze the sentiment of the given text."
def analyze_sentiment(text: str) -> str {
  return "Neutral";
}

"Translate text to another language."
def translate_text(text: str, target_lang: str) -> str {
  return "Translation not available";
}


# -----------------------------------------------------------------------------
# Parameter count
# -----------------------------------------------------------------------------

# Optional multiple arguments.
"""Just prints all the arguments passed to this function."""
def fn_with_more_args(*args: int) -> str {
  return "Function with defaults called with args: " + str(args);
}

# One positional required and multiple optional arguments.
"""Join the given numbers with a specified delimiter."""
def delimeter_join(delimeter: str, *numbers: int) -> str {
  return "???";
}

# Different order type resolved check.
"""Returns the key value pair as a string like ex: {"key": "value"}"""
def str_key_value_pair(value: str, key: str) -> str {
  return "???";
}


with entry {
  print("Normal function call:", greet("Alex"));
  print("LLM override call:", greet("Alex") by llm());

  print("Normal sentiment:", analyze_sentiment("I love this product!"));
  print("LLM sentiment:", analyze_sentiment("I love this product!") by llm());

  print("Normal translation:", translate_text("Hello world", "French"));
  print("LLM translation:", translate_text("Hello world", "French") by llm());

  print(fn_with_more_args(42, 'foo', 3.14, [1]) by llm());
  print(delimeter_join(';', 1,2,3,4,5) by llm());
  print(str_key_value_pair(key='foo', value='42') by llm());

}
