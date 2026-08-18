%dw 2.0
output application/json
var isClassic = (payload.method default "") == "message/send" or (payload.method default "") == "message/stream"
var msg = payload.params.message default {}
var cleanMsg = {
  (messageId: msg.messageId) if (msg.messageId?),
  (contextId: msg.contextId) if (msg.contextId?),
  (taskId: msg.taskId) if (msg.taskId?),
  role: ((msg.role default "user") match {
    case "user" -> "ROLE_USER"
    case "agent" -> "ROLE_AGENT"
    else -> "ROLE_USER"
  }),
  parts: (msg.parts default []) map ((prt) ->
    if (prt.text?) {text: prt.text}
    else if (prt.data?) {data: prt.data}
    else if (prt.file?) {file: prt.file}
    else (prt - "kind")),
  (metadata: msg.metadata) if (msg.metadata?),
  (referenceTaskIds: msg.referenceTaskIds) if (msg.referenceTaskIds?)
}
---
if (isClassic)
  (payload - "method" - "params" - "id") ++ {
    id: (if (payload.id is Number) "jrn:" else "jrs:") ++ ((payload.id default "") as String),
    method: "SendMessage",
    params: {message: cleanMsg}
  }
else payload
