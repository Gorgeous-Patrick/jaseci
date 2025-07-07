import from mtllm { Model, Video }
import os;


glob llm = Model(
    model_name="mockllm",
    outputs=["Something"],
);

def is_aligned(video: Video, text: str) -> bool by llm(
    method="Chain-of-Thoughts",
    context="Mugen is the moving character"
);

with entry {
    video = Video(
        os.path.join(os.path.dirname(__file__), "mugen.mp4"),
        1
    );
    text = "Mugen jumps off and collects few coins.";
    print(is_aligned(video, text));
}
