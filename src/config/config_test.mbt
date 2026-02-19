///|
test "parse_piece_config: minimal config" {
  let json =
    #|{
    #|  "name": "simple",
    #|  "movements": [
    #|    {
    #|      "name": "plan",
    #|      "instructionTemplate": "Plan: {task}"
    #|    }
    #|  ]
    #|}
  let config = @config.parse_piece_config(json)
  assert_eq(config.name, "simple")
  assert_eq(config.movements.length(), 1)
  assert_eq(config.movements[0].name, "plan")
  assert_eq(config.initial_movement, "plan")
  assert_eq(config.max_movements, 20)
}

///|
test "parse_piece_config: with rules" {
  let json =
    #|{
    #|  "name": "review",
    #|  "movements": [
    #|    {
    #|      "name": "review",
    #|      "instructionTemplate": "Review code",
    #|      "rules": [
    #|        {"condition": "approved", "next": "COMPLETE"},
    #|        {"condition": "rejected", "next": "fix"}
    #|      ]
    #|    },
    #|    {
    #|      "name": "fix",
    #|      "instructionTemplate": "Fix issues"
    #|    }
    #|  ],
    #|  "initialMovement": "review"
    #|}
  let config = @config.parse_piece_config(json)
  assert_eq(config.initial_movement, "review")
  assert_eq(config.movements[0].rules.length(), 2)
  assert_eq(config.movements[0].rules[0].condition, "approved")
  assert_eq(config.movements[0].rules[0].next, Some("COMPLETE"))
}

///|
test "parse_piece_config: with loop detection" {
  let json =
    #|{
    #|  "name": "loopy",
    #|  "movements": [{"name": "step", "instructionTemplate": "Do step"}],
    #|  "loopDetection": {
    #|    "maxConsecutiveSameStep": 5,
    #|    "action": "abort"
    #|  }
    #|}
  let config = @config.parse_piece_config(json)
  assert_true(config.loop_detection is Some(_))
  match config.loop_detection {
    Some(ld) => {
      assert_eq(ld.max_consecutive_same_step, 5)
      assert_eq(ld.action, @types.LoopAction::Abort)
    }
    None => fail("Expected loop detection")
  }
}

///|
test "parse_piece_config: with maxMovements" {
  let json =
    #|{
    #|  "name": "limited",
    #|  "movements": [{"name": "step", "instructionTemplate": "Do"}],
    #|  "maxMovements": 50
    #|}
  let config = @config.parse_piece_config(json)
  assert_eq(config.max_movements, 50)
}

///|
test "parse_piece_config: movement with all fields" {
  let json =
    #|{
    #|  "name": "full",
    #|  "movements": [{
    #|    "name": "review",
    #|    "description": "Code review step",
    #|    "persona": "You are a code reviewer",
    #|    "personaDisplayName": "Reviewer",
    #|    "edit": true,
    #|    "passPreviousResponse": true,
    #|    "instructionTemplate": "Review: {task}",
    #|    "provider": "claude"
    #|  }]
    #|}
  let config = @config.parse_piece_config(json)
  let m = config.movements[0]
  assert_eq(m.description, Some("Code review step"))
  assert_eq(m.persona, Some("You are a code reviewer"))
  assert_eq(m.persona_display_name, "Reviewer")
  assert_true(m.edit)
  assert_true(m.pass_previous_response)
  assert_eq(m.provider, Some(@types.ProviderType::Claude))
}

///|
test "parse_piece_config: invalid JSON" {
  let result = try? @config.parse_piece_config("not json")
  assert_true(result is Err(_))
}

///|
test "parse_piece_config: missing name" {
  let json =
    #|{"movements": [{"name": "x"}]}
  let result = try? @config.parse_piece_config(json)
  assert_true(result is Err(_))
}

///|
test "parse_piece_config: missing movements" {
  let json =
    #|{"name": "test"}
  let result = try? @config.parse_piece_config(json)
  assert_true(result is Err(_))
}

// Builder DSL tests

///|
test "rule: simple rule" {
  let r = @config.rule("done", next=Some("COMPLETE"))
  assert_eq(r.condition, "done")
  assert_eq(r.next, Some("COMPLETE"))
  assert_false(r.is_ai_condition)
}

///|
test "rule: AI condition" {
  let r = @config.rule("code is correct", ai=true)
  assert_true(r.is_ai_condition)
  assert_eq(r.ai_condition_text, Some("code is correct"))
}

///|
test "movement: with defaults" {
  let m = @config.movement("plan", instruction="Plan the task")
  assert_eq(m.name, "plan")
  assert_eq(m.instruction_template, "Plan the task")
  assert_false(m.edit)
  assert_false(m.pass_previous_response)
}

///|
test "piece: builds config" {
  let config = @config.piece(
    "test",
    [
      @config.movement("plan", instruction="Plan"),
      @config.movement("implement", instruction="Implement"),
    ],
    max_movements=10,
  )
  assert_eq(config.name, "test")
  assert_eq(config.movements.length(), 2)
  assert_eq(config.initial_movement, "plan")
  assert_eq(config.max_movements, 10)
}

///|
test "piece: custom initial movement" {
  let config = @config.piece(
    "test",
    [
      @config.movement("a", instruction="A"),
      @config.movement("b", instruction="B"),
    ],
    initial=Some("b"),
  )
  assert_eq(config.initial_movement, "b")
}
