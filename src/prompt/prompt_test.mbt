///|
test "compose: persona becomes system prompt" {
  let result = @prompt.compose({
    persona: Some("You are a code reviewer."),
    policies: [],
    knowledge: [],
    instructions: [],
  })
  assert_eq(result.system_prompt, "You are a code reviewer.")
  assert_eq(result.user_message, "")
}

///|
test "compose: policies wrapped in tags" {
  let result = @prompt.compose({
    persona: None,
    policies: ["Be concise", "Use formal tone"],
    knowledge: [],
    instructions: [],
  })
  assert_true(result.user_message.contains("<policy>"))
  assert_true(result.user_message.contains("Be concise"))
  assert_true(result.user_message.contains("Use formal tone"))
}

///|
test "compose: knowledge wrapped in tags" {
  let result = @prompt.compose({
    persona: None,
    policies: [],
    knowledge: ["MoonBit uses snake_case"],
    instructions: [],
  })
  assert_true(result.user_message.contains("<knowledge>"))
  assert_true(result.user_message.contains("MoonBit uses snake_case"))
}

///|
test "compose: full facets combined" {
  let result = @prompt.compose({
    persona: Some("Expert developer"),
    policies: ["Policy A"],
    knowledge: ["Knowledge B"],
    instructions: ["Do X then Y"],
  })
  assert_eq(result.system_prompt, "Expert developer")
  assert_true(result.user_message.contains("<policy>"))
  assert_true(result.user_message.contains("<knowledge>"))
  assert_true(result.user_message.contains("Do X then Y"))
}

///|
test "compose_with_task: appends task tag" {
  let result = @prompt.compose_with_task(
    {
      persona: Some("Coder"),
      policies: [],
      knowledge: [],
      instructions: ["Implement fib"],
    },
    "Add fibonacci function",
  )
  assert_true(result.user_message.contains("<task>"))
  assert_true(result.user_message.contains("Add fibonacci function"))
}

///|
test "compose_with_previous_response: includes previous output" {
  let result = @prompt.compose_with_previous_response(
    { persona: None, policies: [], knowledge: [], instructions: [] },
    "Review the code",
    "fn fib(n: Int) -> Int { ... }",
  )
  assert_true(result.user_message.contains("<previous_response>"))
  assert_true(result.user_message.contains("fn fib"))
  assert_true(result.user_message.contains("<task>"))
}

///|
test "compose: empty facets produce empty strings" {
  let result = @prompt.compose({
    persona: None,
    policies: [],
    knowledge: [],
    instructions: [],
  })
  assert_eq(result.system_prompt, "")
  assert_eq(result.user_message, "")
}
