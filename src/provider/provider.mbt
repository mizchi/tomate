// Provider: trait for LLM provider abstraction

///|
pub(open) trait Provider {
  call(Self, system_prompt : String, user_message : String) -> @types.AgentResponse
}

// Helper: String to null-terminated UTF-8 Bytes for C FFI

///|
fn string_to_bytes(s : String) -> Bytes {
  let arr = s.to_array()
  // Allocate for worst case UTF-8 + null terminator
  let buf = Array::new(capacity=arr.length() * 4 + 1)
  for c in arr {
    let code = c.to_int()
    if code < 0x80 {
      buf.push(code.to_byte())
    } else if code < 0x800 {
      buf.push((0xC0 | (code >> 6)).to_byte())
      buf.push((0x80 | (code & 0x3F)).to_byte())
    } else if code < 0x10000 {
      buf.push((0xE0 | (code >> 12)).to_byte())
      buf.push((0x80 | ((code >> 6) & 0x3F)).to_byte())
      buf.push((0x80 | (code & 0x3F)).to_byte())
    } else {
      buf.push((0xF0 | (code >> 18)).to_byte())
      buf.push((0x80 | ((code >> 12) & 0x3F)).to_byte())
      buf.push((0x80 | ((code >> 6) & 0x3F)).to_byte())
      buf.push((0x80 | (code & 0x3F)).to_byte())
    }
  }
  buf.push(b'\x00') // null terminator
  Bytes::from_array(buf)
}

// Helper: UTF-8 Bytes to String

///|
fn bytes_to_string(b : Bytes) -> String {
  let len = b.length()
  if len == 0 {
    return ""
  }
  let buf = StringBuilder::new()
  for i = 0; i < len; {
    let byte0 = b[i].to_int()
    if byte0 < 0x80 {
      if byte0 == 0 {
        break // null terminator
      }
      buf.write_char(byte0.unsafe_to_char())
      continue i + 1
    } else if byte0 < 0xE0 && i + 1 < len {
      let code = ((byte0 & 0x1F) << 6) | (b[i + 1].to_int() & 0x3F)
      buf.write_char(code.unsafe_to_char())
      continue i + 2
    } else if byte0 < 0xF0 && i + 2 < len {
      let code = ((byte0 & 0x0F) << 12) |
        ((b[i + 1].to_int() & 0x3F) << 6) |
        (b[i + 2].to_int() & 0x3F)
      buf.write_char(code.unsafe_to_char())
      continue i + 3
    } else if i + 3 < len {
      let code = ((byte0 & 0x07) << 18) |
        ((b[i + 1].to_int() & 0x3F) << 12) |
        ((b[i + 2].to_int() & 0x3F) << 6) |
        (b[i + 3].to_int() & 0x3F)
      buf.write_char(code.unsafe_to_char())
      continue i + 4
    } else {
      buf.write_char('\u{FFFD}') // replacement char
      continue i + 1
    }
  }
  buf.to_string()
}

// FFI for native subprocess execution

///|
#borrow(cmd)
extern "C" fn exec_command_ffi(cmd : Bytes) -> Bytes = "mizchi_tomate_provider_exec_command"

///|
pub fn exec_command(cmd : String) -> String {
  let result_bytes = exec_command_ffi(string_to_bytes(cmd))
  bytes_to_string(result_bytes)
}

// MockProvider: deterministic responses for testing

///|
pub(all) struct MockProvider {
  responses : Map[String, String]
  mut default_response : String
}

///|
pub fn MockProvider::new() -> MockProvider {
  { responses: Map::new(), default_response: "Mock response: task completed." }
}

///|
pub fn MockProvider::with_response(
  self : MockProvider,
  key : String,
  content : String,
) -> MockProvider {
  self.responses[key] = content
  self
}

///|
pub fn MockProvider::set_default(self : MockProvider, content : String) -> Unit {
  self.default_response = content
}

///|
pub impl Provider for MockProvider with call(
  self,
  _system_prompt : String,
  user_message : String,
) -> @types.AgentResponse {
  let content = {
    let mut found : String? = None
    self.responses.each(fn(key, val) {
      if user_message.contains(key) && found is None {
        found = Some(val)
      }
    })
    found.unwrap_or(self.default_response)
  }
  {
    persona: "mock",
    status: @types.Status::Complete,
    content,
    error: None,
    matched_rule_index: None,
    matched_rule_method: None,
  }
}

// ClaudeProvider: calls claude CLI as subprocess

///|
pub(all) struct ClaudeProvider {
  model : String?
  project_cwd : String
}

///|
pub fn ClaudeProvider::new(
  project_cwd : String,
  model : String?,
) -> ClaudeProvider {
  { model, project_cwd }
}

///|
fn escape_shell_arg(s : String) -> String {
  let buf = StringBuilder::new()
  buf.write_char('\'')
  let chars = s.to_array()
  for c in chars {
    if c == '\'' {
      buf.write_string("'\\''")
    } else {
      buf.write_char(c)
    }
  }
  buf.write_char('\'')
  buf.to_string()
}

///|
pub impl Provider for ClaudeProvider with call(
  self,
  system_prompt : String,
  user_message : String,
) -> @types.AgentResponse {
  let mut cmd = "unset CLAUDECODE; cd \{escape_shell_arg(self.project_cwd)} && claude -p"
  match self.model {
    Some(m) => cmd = cmd + " --model " + escape_shell_arg(m)
    None => ()
  }
  if system_prompt.length() > 0 {
    cmd = cmd + " --system-prompt " + escape_shell_arg(system_prompt)
  }
  cmd = cmd + " " + escape_shell_arg(user_message)
  let output = exec_command(cmd)
  if output.length() == 0 {
    {
      persona: "claude",
      status: @types.Status::Error,
      content: "",
      error: Some("claude command returned empty output"),
      matched_rule_index: None,
      matched_rule_method: None,
    }
  } else {
    {
      persona: "claude",
      status: @types.Status::Complete,
      content: output,
      error: None,
      matched_rule_index: None,
      matched_rule_method: None,
    }
  }
}

// Factory function

///|
pub fn create_mock_provider() -> &Provider {
  MockProvider::new()
}

///|
pub fn create_claude_provider(
  project_cwd : String,
  model : String?,
) -> &Provider {
  ClaudeProvider::new(project_cwd, model)
}

///|
pub fn create_provider(
  provider_type : @types.ProviderType,
  project_cwd : String,
  model : String?,
) -> &Provider {
  match provider_type {
    @types.ProviderType::Claude => create_claude_provider(project_cwd, model)
    @types.ProviderType::Mock => create_mock_provider()
  }
}
