import from mtllm { Model, Image }
import os;

glob llm = Model(
    model_name="mockllm",
    outputs=["Something"],
);


def solve_math_question(question_img: Image) -> str
    by llm(method="Chain-of-Thoughts");

with entry {
    question_img = Image(
        os.path.join(
            os.path.dirname(__file__),
            'math_question.jpg'
        )
    );
    print(solve_math_question(question_img));
}
