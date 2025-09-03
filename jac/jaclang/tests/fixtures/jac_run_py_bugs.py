import pygame

pygame.init()

class SimpleClass:
    def __init__(self, name: str, age: int) -> None:
        self.name = name
        self.age = age

    def greet(self):
        return f"Hello, my name is {self.name} and I am {self.age} years old."


# Create an object of the class
person = SimpleClass("Alice", 30)

# Run the greet method
print(person.greet())