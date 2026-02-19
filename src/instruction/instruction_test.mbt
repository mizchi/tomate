///|
test "expand_template: simple variable" {
  let vars : Map[String, String] = Map::new()
  vars["name"] = "world"
  assert_eq(@instruction.expand_template("Hello {name}!", vars), "Hello world!")
}

///|
test "expand_template: multiple variables" {
  let vars : Map[String, String] = Map::new()
  vars["a"] = "X"
  vars["b"] = "Y"
  assert_eq(@instruction.expand_template("{a} and {b}", vars), "X and Y")
}

///|
test "expand_template: unknown variable preserved" {
  let vars : Map[String, String] = Map::new()
  assert_eq(
    @instruction.expand_template("Hello {unknown}", vars),
    "Hello {unknown}",
  )
}

///|
test "expand_template: no variables" {
  let vars : Map[String, String] = Map::new()
  assert_eq(
    @instruction.expand_template("No placeholders here", vars),
    "No placeholders here",
  )
}

///|
test "expand_template: empty template" {
  let vars : Map[String, String] = Map::new()
  assert_eq(@instruction.expand_template("", vars), "")
}

///|
test "expand_template: unclosed brace" {
  let vars : Map[String, String] = Map::new()
  vars["x"] = "val"
  assert_eq(@instruction.expand_template("test {x", vars), "test {x")
}

///|
test "expand_template: adjacent placeholders" {
  let vars : Map[String, String] = Map::new()
  vars["a"] = "1"
  vars["b"] = "2"
  assert_eq(@instruction.expand_template("{a}{b}", vars), "12")
}

///|
test "build_judge_instruction: formats rules" {
  let rules : Array[@types.PieceRule] = [
    {
      condition: "code is approved",
      next: Some("deploy"),

      is_ai_condition: false,
      ai_condition_text: None,
      is_aggregate_condition: false,
      aggregate_type: None,
      aggregate_condition_text: None,
    },
    {
      condition: "needs improvement",
      next: Some("fix"),

      is_ai_condition: false,
      ai_condition_text: None,
      is_aggregate_condition: false,
      aggregate_type: None,
      aggregate_condition_text: None,
    },
  ]
  let result = @instruction.build_judge_instruction(
    rules, "The code looks good",
  )
  assert_true(result.contains("Rule 0: code is approved"))
  assert_true(result.contains("Rule 1: needs improvement"))
  assert_true(result.contains("<rule_N>"))
  assert_true(result.contains("The code looks good"))
}
