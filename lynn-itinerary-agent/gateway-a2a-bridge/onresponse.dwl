%dw 2.0
output application/json
var idStr = (payload.id default "") as String
var isClassic = (idStr startsWith "jrn:") or (idStr startsWith "jrs:")
var origId = if (idStr startsWith "jrn:") (idStr[4 to -1] as Number) else if (idStr startsWith "jrs:") (idStr[4 to -1]) else payload.id
fun st(s) = s match {
  case "TASK_STATE_SUBMITTED" -> "submitted"
  case "TASK_STATE_WORKING" -> "working"
  case "TASK_STATE_INPUT_REQUIRED" -> "input-required"
  case "TASK_STATE_COMPLETED" -> "completed"
  case "TASK_STATE_CANCELED" -> "canceled"
  case "TASK_STATE_FAILED" -> "failed"
  case "TASK_STATE_REJECTED" -> "rejected"
  case "TASK_STATE_AUTH_REQUIRED" -> "auth-required"
  else -> (if (s == null) null else lower(s))
}
fun rl(r) = r match {
  case "ROLE_AGENT" -> "agent"
  case "ROLE_USER" -> "user"
  else -> (if (r == null) null else lower(r))
}
fun pt(p) = (p - "kind") ++ {kind: (if (p.text?) "text" else if (p.data?) "data" else if (p.file?) "file" else "text")}
fun mg(m) = if (m == null) null else (m - "role" - "parts" - "kind") ++ {(role: rl(m.role)) if (m.role?), (parts: m.parts map pt($)) if (m.parts?), kind: "message"}
fun tk(t) = (t - "status" - "artifacts" - "history" - "kind") ++ {(status: (t.status - "state" - "message") ++ {(state: st(t.status.state)) if (t.status.state?), (message: mg(t.status.message)) if (t.status.message?)}) if (t.status?), (artifacts: t.artifacts map ((a) -> (a - "parts") ++ {(parts: a.parts map pt($)) if (a.parts?)})) if (t.artifacts?), (history: t.history map mg($)) if (t.history?), kind: "task"}
---
if (isClassic and payload.result.task?) (payload - "result" - "jsonrpc" - "id") ++ {jsonrpc: (payload.jsonrpc default "2.0"), id: origId, result: tk(payload.result.task)}
else if (isClassic and payload.result.message?) (payload - "result" - "jsonrpc" - "id") ++ {jsonrpc: (payload.jsonrpc default "2.0"), id: origId, result: mg(payload.result.message)}
else if (isClassic) ((payload - "id") ++ {id: origId})
else payload
