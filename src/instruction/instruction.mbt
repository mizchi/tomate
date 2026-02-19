// Template expansion: {variable} placeholder replacement

///|
pub fn expand_template(
  template : String,
  variables : Map[String, String],
) -> String {
  let buf = StringBuilder::new()
  let len = template.length()
  let chars = template.to_array()
  for i = 0; i < len; {
    if chars[i] == '{' {
      // Find closing brace
      let start = i + 1
      let mut end = -1
      for j = start; j < len; j = j + 1 {
        if chars[j] == '}' {
          end = j
          break
        }
      }
      if end >= 0 {
        let key = template.view(start_offset=start, end_offset=end).to_string()
        match variables.get(key) {
          Some(val) => buf.write_string(val)
          None => {
            buf.write_char('{')
            buf.write_string(key)
            buf.write_char('}')
          }
        }
        continue end + 1
      } else {
        buf.write_char('{')
        continue start
      }
    } else {
      buf.write_char(chars[i])
      continue i + 1
    }
  }
  buf.to_string()
}

// Build instruction from movement context

///|
pub fn build_movement_instruction(
  movement : @types.PieceMovement,
  task : String,
  variables : Map[String, String],
) -> @types.ComposedPrompt {
  variables["task"] = task
  let expanded = expand_template(movement.instruction_template, variables)
  let instructions : Array[String] = [expanded]
  // Append rule instructions so the LLM knows to emit <rule_N> tags
  if movement.rules.length() > 0 {
    let rule_buf = StringBuilder::new()
    rule_buf.write_string(
      "After completing your response, you MUST include exactly one of the following tags to indicate which condition is met:\n",
    )
    for i, rule in movement.rules {
      rule_buf.write_string("  <rule_\{i}> - \{rule.condition}")
      match rule.next {
        Some(next) => rule_buf.write_string(" (next: \{next})")
        None => ()
      }
      rule_buf.write_char('\n')
    }
    rule_buf.write_string(
      "\nYou MUST include the matching <rule_N> tag at the end of your response.",
    )
    instructions.push(rule_buf.to_string())
  }
  let facets : @types.FacetSet = {
    persona: movement.persona,
    policies: movement.policy_contents.unwrap_or([]),
    knowledge: movement.knowledge_contents.unwrap_or([]),
    instructions,
  }
  @prompt.compose_with_task(facets, task)
}

// Build judge instruction for rule evaluation

///|
pub fn build_judge_instruction(
  rules : Array[@types.PieceRule],
  content : String,
) -> String {
  let buf = StringBuilder::new()
  buf.write_string(
    "Evaluate the following content and determine which rule condition is met.\n\n",
  )
  buf.write_string("Content to evaluate:\n")
  buf.write_string(content)
  buf.write_string("\n\nRules:\n")
  for i, rule in rules {
    buf.write_string("Rule \{i}: \{rule.condition}")
    match rule.next {
      Some(next) => buf.write_string(" -> next: \{next}")
      None => ()
    }
    buf.write_char('\n')
  }
  buf.write_string(
    "\nRespond with ONLY the tag <rule_N> where N is the matching rule index.",
  )
  buf.to_string()
}
