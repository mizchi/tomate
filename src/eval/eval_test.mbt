///|
test "evaluate_rules: matches first tag" {
  let rules : Array[@types.PieceRule] = [
    {
      condition: "approved",
      next: Some("deploy"),
      is_ai_condition: false,
      ai_condition_text: None,
      is_aggregate_condition: false,
      aggregate_type: None,
      aggregate_condition_text: None,
    },
    {
      condition: "rejected",
      next: Some("fix"),
      is_ai_condition: false,
      ai_condition_text: None,
      is_aggregate_condition: false,
      aggregate_type: None,
      aggregate_condition_text: None,
    },
  ]
  let result = @eval.evaluate_rules(rules, "The code is <rule_1> for changes")
  assert_eq(
    result,
    Some({ rule_index: 1, match_method: @types.RuleMatchMethod::TagDetect }),
  )
}

///|
test "evaluate_rules: returns None when no match" {
  let rules : Array[@types.PieceRule] = [
    {
      condition: "done",
      next: None,
      is_ai_condition: false,
      ai_condition_text: None,
      is_aggregate_condition: false,
      aggregate_type: None,
      aggregate_condition_text: None,
    },
  ]
  let result = @eval.evaluate_rules(rules, "No tags here")
  assert_true(result is None)
}

///|
test "evaluate_rules: prefers first matching tag" {
  let rules : Array[@types.PieceRule] = [
    {
      condition: "a",
      next: Some("x"),
      is_ai_condition: false,
      ai_condition_text: None,
      is_aggregate_condition: false,
      aggregate_type: None,
      aggregate_condition_text: None,
    },
    {
      condition: "b",
      next: Some("y"),
      is_ai_condition: false,
      ai_condition_text: None,
      is_aggregate_condition: false,
      aggregate_type: None,
      aggregate_condition_text: None,
    },
  ]
  let result = @eval.evaluate_rules(rules, "<rule_0> and <rule_1>")
  assert_eq(
    result,
    Some({ rule_index: 0, match_method: @types.RuleMatchMethod::TagDetect }),
  )
}

///|
test "evaluate_aggregate: dispatches to all/any" {
  assert_true(@eval.evaluate_aggregate(@types.AggregateType::All, [true, true]))
  assert_false(
    @eval.evaluate_aggregate(@types.AggregateType::All, [true, false]),
  )
  assert_true(
    @eval.evaluate_aggregate(@types.AggregateType::Any, [false, true]),
  )
  assert_false(
    @eval.evaluate_aggregate(@types.AggregateType::Any, [false, false]),
  )
}

///|
test "evaluate_aggregate: edge cases" {
  assert_true(@eval.evaluate_aggregate(@types.AggregateType::All, []))
  assert_false(@eval.evaluate_aggregate(@types.AggregateType::Any, []))
  assert_true(
    @eval.evaluate_aggregate(@types.AggregateType::Any, [false, true, false]),
  )
  assert_false(
    @eval.evaluate_aggregate(@types.AggregateType::All, [true, false, true]),
  )
}

///|
test "evaluate_rules_full: tag detection takes priority" {
  let rules : Array[@types.PieceRule] = [
    {
      condition: "done",
      next: None,
      is_ai_condition: false,
      ai_condition_text: None,
      is_aggregate_condition: true,
      aggregate_type: Some(@types.AggregateType::All),
      aggregate_condition_text: None,
    },
  ]
  let result = @eval.evaluate_rules_full(rules, "<rule_0>", Some([[true]]))
  assert_eq(
    result,
    Some({ rule_index: 0, match_method: @types.RuleMatchMethod::TagDetect }),
  )
}

///|
test "evaluate_rules_full: falls back to aggregate" {
  let rules : Array[@types.PieceRule] = [
    {
      condition: "all done",
      next: None,
      is_ai_condition: false,
      ai_condition_text: None,
      is_aggregate_condition: true,
      aggregate_type: Some(@types.AggregateType::All),
      aggregate_condition_text: None,
    },
  ]
  let result = @eval.evaluate_rules_full(
    rules,
    "no tags",
    Some([[true, true, true]]),
  )
  assert_eq(
    result,
    Some({ rule_index: 0, match_method: @types.RuleMatchMethod::Aggregate }),
  )
}
