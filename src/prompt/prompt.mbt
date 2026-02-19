// Faceted Prompting: compose system prompt and user message from facets

///|
pub fn compose(facets : @types.FacetSet) -> @types.ComposedPrompt {
  let system_parts : Array[String] = []
  // Persona → system prompt
  match facets.persona {
    Some(p) => system_parts.push(p)
    None => ()
  }
  let user_parts : Array[String] = []
  // Policies → user message
  for policy in facets.policies {
    user_parts.push("<policy>\n\{policy}\n</policy>")
  }
  // Knowledge → user message
  for knowledge in facets.knowledge {
    user_parts.push("<knowledge>\n\{knowledge}\n</knowledge>")
  }
  // Instructions → user message
  for instruction in facets.instructions {
    user_parts.push(instruction)
  }
  {
    system_prompt: join_lines(system_parts),
    user_message: join_lines(user_parts),
  }
}

///|
fn join_lines(parts : Array[String]) -> String {
  let buf = StringBuilder::new()
  for i, part in parts {
    if i > 0 {
      buf.write_string("\n\n")
    }
    buf.write_string(part)
  }
  buf.to_string()
}

///|
pub fn compose_with_task(
  facets : @types.FacetSet,
  task : String,
) -> @types.ComposedPrompt {
  let result = compose(facets)
  let user_msg = if result.user_message.length() > 0 {
    result.user_message + "\n\n<task>\n" + task + "\n</task>"
  } else {
    "<task>\n" + task + "\n</task>"
  }
  { system_prompt: result.system_prompt, user_message: user_msg }
}

///|
pub fn compose_with_previous_response(
  facets : @types.FacetSet,
  task : String,
  previous : String,
) -> @types.ComposedPrompt {
  let result = compose_with_task(facets, task)
  let user_msg = "<previous_response>\n" +
    previous +
    "\n</previous_response>\n\n" +
    result.user_message
  { system_prompt: result.system_prompt, user_message: user_msg }
}
