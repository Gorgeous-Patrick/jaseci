Mapping patterns enable matching against dictionary structures while extracting specific keys and capturing remaining key-value pairs.

**Basic Mapping Pattern Structure**

Line 6 demonstrates a mapping pattern: `case {"key1" : 1, "key2" : 2, **rest}:`. This pattern matches dictionary objects that contain the specified keys with their corresponding values, while capturing any additional key-value pairs.

**Key-Value Matching**

The pattern `{"key1" : 1, "key2" : 2, **rest}` requires that the matched dictionary contains:
- A key `"key1"` with value `1`
- A key `"key2"` with value `2`

The dictionary being matched (line 4) is `{"key1": 1, "key2": 2, "232": 3453}`, which satisfies both requirements, so the pattern matches successfully.

**Rest Pattern with Double Asterisk**

The `**rest` syntax captures all remaining key-value pairs that weren't explicitly matched in the pattern. In this example, after matching `"key1": 1` and `"key2": 2`, the remaining pair `"232": 3453` is captured in the variable `rest` as a new dictionary `{"232": 3453}`. This variable can then be used in the case body, as shown on line 8 where it's printed in the f-string.

**Partial Matching**

Mapping patterns perform partial matching - the dictionary being matched can contain more keys than specified in the pattern. The pattern matches as long as all specified keys exist with their required values. If you omit the `**rest` pattern, extra keys are simply ignored. If you include `**rest`, those extra keys are captured for use in the case body.

**Pattern Failure**

The pattern would fail to match if:
- The matched value is not a dictionary
- Any specified key is missing from the dictionary
- Any specified key has a different value than required in the pattern
