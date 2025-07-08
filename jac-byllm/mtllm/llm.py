"""LLM abstraction module.

This module provides a LLM class that abstracts LiteLLM and offers
enhanced functionality and interface for language model operations.
"""

# flake8: noqa: E402

import inspect
import json
import logging
import os
from types import MethodType
from typing import Callable, get_type_hints

# This will prevent LiteLLM from fetching pricing information from
# the bellow URL every time we import the litellm and use a cached
# local json file. Maybe we we should conditionally enable this.
# https://raw.githubusercontent.com/BerriAI/litellm/main/model_prices_and_context_window.json
os.environ["LITELLM_LOCAL_MODEL_COST_MAP"] = "True"

import litellm
from litellm._logging import _disable_debugging

from .types import (
    CompletionRequest,
    CompletionResult,
    Image,
    LiteLLMMessage,
    Media,
    Message,
    MessageRole,
    MessageType,
    MockToolCall,
    Text,
    Tool,
    ToolCall,
)

SYSTEM_PERSONA = """\
This is a task you must complete by returning only the output.
Do not include explanations, code, or extra text—only the result.
"""  # noqa E501

INSTRUCTION_TOOL = """
Use the tools provided to reach the goal. Call one tool at a time with \
proper args—no explanations, no narration. Think step by step, invoking tools \
as needed. When done, always call finish_tool(output) to return the final \
output. Only use tools.
"""  # noqa E501


class Model:
    """A wrapper class that abstracts LiteLLM functionality.

    This class provides a simplified and enhanced interface for interacting
    with various language models through LiteLLM.
    """

    def __init__(self, model_name: str, **kwargs: object) -> None:
        """Initialize the JacLLM instance.

        Args:
            model: The model name to use (e.g., "gpt-3.5-turbo", "claude-3-sonnet-20240229")
            api_key: API key for the model provider
            **kwargs: Additional configuration options
        """
        # Every litellm call will be logged to the tty and that pollutes the output.
        # When there is a by llm() call in the jaclang.
        logging.getLogger("httpx").setLevel(logging.WARNING)
        _disable_debugging()

        self.model_name = model_name
        self.config = kwargs

        # The parameters for the llm call like temprature, top_k, max_token, etc.
        # This is only applicable for the next call passed from `by llm(**kwargs)`.
        self.call_params: dict[str, object] = {}

    def __call__(self, **kwargs: object) -> "Model":
        """Construct the call parameters and return self (factory pattern).

        Example:
            ```jaclang
            llm = JacLLM(model="gpt-3.5-turbo", api_key="your_api_key")

            # The bellow call will construct the parameter and return self.
            def answer_user_query(query: str) -> str by
                llm(
                    temperature=0.7,
                    max_tokens=100,
                );
            ```
        """
        self.call_params = kwargs
        return self

    def invoke(self, caller: Callable, args: dict[str | int, object]) -> object:
        """Invoke the LLM with the given caller and arguments."""
        # Prepare the tools for the LLM call.
        tools = [
            Tool(func) for func in self.call_params.get("tools", [])  # type: ignore
        ]

        # Construct the input information from the arguments.
        param_names = list(inspect.signature(caller).parameters.keys())
        inputs_detail: list[str] = []
        media_inputs: list[Media] = []

        for key, value in args.items():
            if isinstance(value, Media):
                media_inputs.append(value)
                continue

            if isinstance(key, str):
                inputs_detail.append(f"{key} = {value}")
            else:
                # TODO: Handle *args, **kwargs properly.
                if key < len(param_names):
                    inputs_detail.append(f"{param_names[key]} = {value}")
                else:
                    inputs_detail.append(f"arg = {value}")

        if incl_info := self.call_params.get("incl_info"):
            if isinstance(incl_info, dict):
                for key, value in incl_info.items():
                    if isinstance(value, Media):
                        media_inputs.append(value)
                    else:
                        inputs_detail.append(f"{key} = {value}")

        if isinstance(caller, MethodType):
            inputs_detail.insert(0, f"self = {caller.__self__}")

        # Prepare the messages for the LLM call.
        messages: list[MessageType] = [
            Message(
                role=MessageRole.SYSTEM,
                content=SYSTEM_PERSONA + (INSTRUCTION_TOOL if tools else ""),
            ),
            Message(
                role=MessageRole.USER,
                content=[
                    Text(
                        Tool.get_func_description(caller)
                        + "\n\n"
                        + "\n".join(inputs_detail)
                    ),
                    *media_inputs,
                ],
            ),
        ]

        # Prepare return type.
        return_type = get_type_hints(caller).get("return")

        # Prepare the llm call request.
        req = CompletionRequest(
            messages=messages,
            tools=tools,
            resp_type=return_type,
            params={},
        )

        # Invoke the LLM and handle tool calls.
        while True:
            resp = self.completion(req)
            if resp.tool_calls:
                for tool_call in resp.tool_calls:
                    if tool_call.is_finish_call():
                        return tool_call.get_output()
                    else:
                        req.add_message(tool_call())
            else:
                break

        return resp.output

    def completion(self, req: CompletionRequest) -> CompletionResult:
        """Perform a completion request with the LLM."""
        if self.model_name.lower().strip() == "mockllm":
            return self._dispatch_mock_llm_call(req)
        return self._dispatch_llm_call(req)

    def _dispatch_llm_call(self, req: CompletionRequest) -> CompletionResult:
        """Dispatch the LLM call with the given request."""
        # Prepare the parameters for the LLM call
        params = {
            "model": self.model_name,
            "api_base": self.config.get("host") or self.config.get("api_base"),
            "messages": req.get_msg_list(),
            "tools": req.get_tool_list() or None,
            "response_format": req.get_output_schema(),
            "temperature": self.call_params.get("temperature", 0.7),
            # "max_tokens": self.call_params.get("max_tokens", 100),
            # "top_k": self.call_params.get("top_k", 50),
            # "top_p": self.call_params.get("top_p", 0.9),
        }

        # Call the LiteLLM API
        self._log_info(f"Calling LLM: {self.model_name} with params:\n{params}")
        output = litellm.completion(**params)

        # Output format:
        # https://docs.litellm.ai/docs/#response-format-openai-format
        #
        # TODO: Handle stream output (type ignoring stream response)
        message: LiteLLMMessage = output.choices[0].message  # type: ignore
        req.add_message(message)

        output_content: str = message.content  # type: ignore
        self._log_info(f"LLM call completed with response:\n{output_content}")
        output_value = req.parse_response(output_content)

        tool_calls: list[ToolCall] = []
        for tool_call in message.tool_calls or []:  # type: ignore
            if tool := req.get_tool(tool_call["function"]["name"]):
                args_json = json.loads(tool_call["function"]["arguments"])
                args = tool.parse_arguments(args_json)
                tool_calls.append(
                    ToolCall(call_id=tool_call["id"], tool=tool, args=args)
                )
            else:
                raise RuntimeError(
                    f"Attempted to call tool: '{tool_call['function']['name']}' which was not present."
                )

        return CompletionResult(
            output=output_value,
            tool_calls=tool_calls,
        )

    def _dispatch_mock_llm_call(self, req: CompletionRequest) -> CompletionResult:
        """Dispatch the mock LLM call with the given request."""
        output = self.config["outputs"].pop(0)  # type: ignore

        if isinstance(output, MockToolCall):
            self._log_info(
                f"Mock LLM call completed with tool call:\n{output.to_tool_call()}"
            )
            return CompletionResult(
                output=None,
                tool_calls=[output.to_tool_call()],
            )

        self._log_info(f"Mock LLM call completed with response:\n{output}")
        return CompletionResult(
            output=output,
            tool_calls=[],
        )

    def _log_info(self, message: str) -> None:
        """Log a message to the console."""
        # FIXME: The logger.info will not always log so for now I'm printing to stdout
        # remove and log properly.
        if bool(self.config.get("verbose", False)):
            print(message)
