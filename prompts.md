# All User Prompts — Daily Rewards Project

These are all user prompts from this conversation, in chronological order:

---

**Prompt 1:** Read test task PDF, plan implementation
> read @Тестовое_задание_Full_Stack_Developer_Node_1.pdf, plan implementation, perform web search if needed and available.

---

**Prompt 2:** Client engine choice — "простой клиент" (simple client)
> we need it to be implemented too. chose the best engine for this puprose, explain your choice.

Context: The test task specifies a simple Lua client with LÖVE or Defold that shows claim button, status text ("можем получить / не можем / почему"), and result popup on click (coins awarded or error from server).

---

**Prompt 3:** Add TypeScript + finalize LÖVE2D client (with image showing UI design)
> do these two things:
> 1. add typescript to backend. choose the simpliest approach: compilation or run ts natively, explain your choice.
> 2. test task contains this: "... и простой клиент на LUA движок Defold или LÖVE (Love2D). "

Also specified client requirements from test task:
- Each launch gets new user_id from server
- UI shows: claim button (always available), status ("can claim / can't / why")
- On click: show result (coins awarded) or error reason from server

Image provided showed a mockup with: 7-day progress indicators, day labels, coins for each day, total coins display, current day indicator, claim button, and status text area.

---

**Prompt 4:** "continue" — after TypeScript migration in progress

---

**Prompt 5:** Docker Compose + dev/prod configs
> pack the entire stack in docker compose, ensure it applies migrations if needed and works properly. add separated configs for dev and prod. add description in readme (explain how to run project at the top).

---

**Prompt 6:** Local startup script instead of Docker-only
> forget about docker, create a script that checks required dependencies and then runs everything (including docker and client), or fails gracefully.

---

**Prompt 7:** cjson dependency + README update
> it does not ensures cjson is installed, fix it.
> also, add start.sh to top

---

**Prompt 8:** Pure Lua JSON parser
> just download library and include it in project, or use different approach to read json. we need app to work, not to be complex.

---

**Prompt 9-16:** Runtime errors (each with LÖVE2D error trace)
- `Failed to connect to server` + `Failed to parse JSON response: attempt to call global 'decodeObject' (a nil value)` — json.lua mutual recursion bug
- `attempt to index local 'result' (a nil value)` — api.lua pcall handling bug
- Image showed UI with day indicators, reward status, claim button working
- `attempt to call field 'getNewFont' (a nil value)` — LÖVE API: newFont vs getNewFont
- `Failed to connect to server` + JSON parse error after cjson removal
- `attempt to call global 'checkCooldown' (a nil value)` — function ordering bug

---

**Final Prompt:** Create prompts.md
> take all user prompts from our conversation, write them to prompts.md file. in readme, at the top, mention that project was created with local Qwen 3.6 assistance, and link file.
