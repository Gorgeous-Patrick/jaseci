"""A Number Guessing Game"""

import random;
import from mtllm.llms { OpenAI, Gemini }

# glob llm = OpenAI(model_name="gpt-4o",verbose=False);
 glob llm =
    Gemini(model_name="gemini-1.5-flash", verbose=False);

"""Provide a fun hint if guess is incorrect"""
def give_hint(guess: int, correct_number: int) -> str byllm();

walker GuessGame {
    has guess: int;

    can start with `root entry;
    can process_guess with turn entry;
}

node turn {
    has correct_number: int = random.randint(1, 10);
}

# Will run when in CLI mode (not in cloud)
 with entry:__main__ {
    root spawn GuessGame(3);
    root spawn GuessGame(4);
    root spawn GuessGame(5);
    root spawn GuessGame(6);
}
