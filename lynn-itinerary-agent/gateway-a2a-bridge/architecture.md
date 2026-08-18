# Lynn Itinerary Agent — Architecture (A2A transport bridge)

```mermaid
flowchart TB
    %% ---------- Clients ----------
    UI["Railway agent-broker-ui<br/>A2A v0.3 JSON-RPC<br/>message/send · role:user · parts kind:text<br/>no A2A-Version header"]
    GRPC["Native A2A v1.0 client<br/>gRPC-transcoded<br/>SendMessage · ROLE_USER · parts:text<br/>A2A-Version: 1.0"]

    %% ---------- Flex Gateway ----------
    subgraph GW["Flex Gateway — lynn-demo-gw (CloudHub 2.0 · usa-e2)<br/>API instance: lynn_itinerary_agent (21105670)"]
        direction TB
        P1["1 · a-two-a-v1-agent-card (system)"]
        P2["2 · tracing (system)"]
        P3["3 · header-injection<br/>inject A2A-Version: 1.0"]
        P4["4 · user-context-propagation (system)"]
        P5["5 · DW onRequest<br/>v0.3 to v1.0<br/>message/send to SendMessage · whitelist proto fields · TAG id (jrs/jrn)"]
        P6["6 · DW onResponse<br/>v1.0 to v0.3<br/>unwrap result.task · map TASK_STATE_* / ROLE_* · STRIP tag"]
        P1 --> P2 --> P3 --> P4 --> P5 --> P6
    end

    %% ---------- Broker ----------
    subgraph BR["Broker — lynn-itinerary-network (AgentScript · mulesoft-agent-graph-module)"]
        direction LR
        RG["resolveGuest"] --> GC["guestContext"] --> IB["itineraryBuilder"] --> CI["createItinerary"]
    end

    %% ---------- Backends ----------
    LLM["OpenAI gpt-4o"]
    subgraph MCP["MCP servers (CloudHub 2.0 · usa-e1)"]
        MA["lynn-resort-systems · 7 tools"]
        MB["lynn-interests · 4 tools"]
        MC["lynn-casino-gaming · 6 tools"]
    end
    DB[("Aiven MySQL<br/>casino_demo")]

    %% ---------- Edges ----------
    UI -->|"POST /lynn_itinerary_agent/"| P1
    GRPC -->|"POST /lynn_itinerary_agent/ (untagged → passes through)"| P1
    P6 -->|"A2A 1.0 gRPC-transcoded"| BR
    BR -->|"LLM via gw :8082 egress proxy"| LLM
    BR -->|"MCP Streamable HTTP via gw :8082"| MCP
    MA --> DB
    MB --> DB
    MC --> DB

    %% ---------- Highlight the bridge policies ----------
    classDef bridge fill:#fde68a,stroke:#b45309,color:#000,font-weight:bold;
    classDef system fill:#e5e7eb,stroke:#6b7280,color:#374151;
    class P3,P5,P6 bridge;
    class P1,P2,P4 system;
```

**Legend** — amber = the three A2A-bridge policies we added/modified (header-injection + the two
DataWeave body transforms); grey = pre-existing system policies created by the broker registration.
Policies 5 & 6 form the bidirectional translator; native gRPC traffic (untagged `id`) passes through
both untouched, so one URL serves both A2A generations.
