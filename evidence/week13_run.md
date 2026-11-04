# Week 13 Evidence Run — IT Help Desk Ticket Router

- Generated: 2026-11-04T06:19:08.652286Z by `tool/run_evidence.dart`
- API: http://127.0.0.1:8080  |  Mock gateway: http://127.0.0.1:8091
- Dart: 3.13.7  |  OS: windows "Windows 10 Home Single Language" 10.0 (Build 19041)
- Data: fictional seed users only (`.test` domains). Full request/response bodies are in `week13_run.json`.

## 1. Health check

**Expected:** API reports store ok and the notification gateway reachable.

- `GET /health` as `-` → **200** (14 ms, cid `ev13-0002-73148927`) 

**Observed:** status=ok, gateway=ok

## 2. Normal path: submit → rule-based assignment → response → resolve → confirm → close

**Expected:** Ticket is routed by keyword to the network team, assigned to the least-loaded agent, and closes after the requester confirms.

- `POST /api/v1/tickets` as `req-ana` → **201** (52 ms, cid `ev13-0003-73148941`) → TKT-0001 status=assigned assignee=agent-carla

**Observed:** routingReason="keyword match: network (1 hit)", team=network, slaDueAt=2026-11-05T06:19:08.966203Z
- `POST /api/v1/tickets` as `req-ana` → **201** (25 ms, cid `ev13-0004-73148998`) → same id TKT-0001 (double-submit did not create a duplicate)
- `POST /api/v1/tickets/TKT-0001/responses` as `agent-carla` → **200** (24 ms, cid `ev13-0005-73149024`) 
- `POST /api/v1/tickets/TKT-0001/resolve` as `agent-carla` → **200** (23 ms, cid `ev13-0006-73149041`) 
- `POST /api/v1/tickets/TKT-0001/confirm` as `req-ana` → **200** (18 ms, cid `ev13-0007-73149072`) → status=closed

**Observed:** history: assigned → in_progress → resolved → closed

## 3. Transient failure recovered by retry

**Expected:** Gateway returns 503 for the next 4 calls. The new ticket queues 2 notifications, so each fails twice, waits with backoff, and succeeds on attempt 3. No duplicate is delivered.

- `POST /admin/fault` as `-` → **200** (8 ms, cid `ev13-0008-73149623`) (fault injected: next 4 sends fail with 503)
- `POST /api/v1/tickets` as `req-ben` → **201** (16 ms, cid `ev13-0009-73149638`) → TKT-0002 assignee=agent-dan

**Observed:** MSG-00006 ticket.received: status=sent, attempts=3: transient_failure (503) service_unavailable 6ms → transient_failure (503) service_unavailable 4ms → sent (202) 5ms

**Observed:** MSG-00007 ticket.assigned: status=sent, attempts=3: transient_failure (503) service_unavailable 4ms → transient_failure (503) service_unavailable 6ms → sent (202) 5ms

## 4. Timeout treated as transient

**Expected:** Gateway delays 5 s (> 3 s client timeout) once; the attempt is recorded as a timeout and the retry succeeds.

- `POST /admin/fault` as `-` → **200** (4 ms, cid `ev13-0010-73159524`) 
- `POST /api/v1/tickets` as `req-ana` → **201** (12 ms, cid `ev13-0011-73159524`) → TKT-0003

**Observed:** MSG-00008: status=sent: transient_failure timeout 3008ms → sent (202) 5ms

## 5. Permanent failure routed for human action

**Expected:** Gateway rejects the decommissioned mailbox with 422. The message is dead-lettered after one attempt (no retry), appears in the supervisor manual-review queue, and the ticket workflow continues.

- `POST /api/v1/tickets` as `req-gio` → **201** (16 ms, cid `ev13-0012-73164724`) → TKT-0004 status=assigned assignee=agent-faith

**Observed:** MSG-00010: status=dead_letter, reason=permanent_rejection, attempts=1: permanent_failure (422) recipient_rejected 5ms
- `GET /api/v1/automation/notifications?status=dead_letter` as `sup-mara` → **200** (8 ms, cid `ev13-0013-73165275`) → 1 item(s) in manual review
- `POST /api/v1/automation/notifications/MSG-00010/dismiss` as `sup-mara` → **200** (16 ms, cid `ev13-0014-73165290`) → status=dismissed

## 6. Unroutable ticket → supervisor triage

**Expected:** No keyword matches, so the ticket waits in needs_triage and the supervisor is notified; triage assigns it.

- `POST /api/v1/tickets` as `req-ben` → **201** (13 ms, cid `ev13-0015-73165305`) → TKT-0005 status=needs_triage reason="no keyword matched"
- `POST /api/v1/tickets/TKT-0005/triage` as `sup-mara` → **200** (19 ms, cid `ev13-0016-73165321`) → status=assigned assignee=agent-dan

## 7. Adverse requests are refused safely

**Expected:** Invalid, unauthenticated, unauthorized, other-owner and wrong-state requests get 422/401/403/404/409 with no internal detail.

- `POST /api/v1/tickets` as `req-ana` → **422** (9 ms, cid `ev13-0017-73165337`) → {"title":"Title must be 5-120 characters.","description":"Description must be 10-2000 characters.","priority":"Priority must be low, medium, high or critical.","_":"Unexpected fields: role"}
- `POST /api/v1/tickets` as `req-ana` → **400** (8 ms, cid `ev13-0018-73165352`) (malformed JSON)
- `GET /api/v1/tickets` as `-` → **401** (8 ms, cid `ev13-0019-73165352`) (no identity)
- `GET /api/v1/tickets` as `mallory` → **401** (6 ms, cid `ev13-0020-73165368`) (unknown identity)
- `GET /api/v1/automation/notifications` as `agent-carla` → **403** (5 ms, cid `ev13-0021-73165368`) (agent calls supervisor endpoint)
- `GET /api/v1/tickets/TKT-0002` as `req-ana` → **404** (5 ms, cid `ev13-0022-73165381`) (requester reads another user's ticket)
- `POST /api/v1/tickets/TKT-0002/confirm` as `req-ben` → **409** (17 ms, cid `ev13-0023-73165389`) (confirm before resolved)

## 8. Reassignment when an agent becomes unavailable

**Expected:** Supervisor marks an agent unavailable; the next aging scan moves that agent's open tickets to a teammate.

- `POST /api/v1/tickets` as `req-ana` → **201** (13 ms, cid `ev13-0024-73165404`) → TKT-0006 assignee=agent-carla
- `PATCH /api/v1/agents/agent-carla/availability` as `sup-mara` → **200** (17 ms, cid `ev13-0025-73165420`) 
- `POST /api/v1/automation/jobs/aging-scan/run` as `sup-mara` → **200** (41 ms, cid `ev13-0026-73165436`) → stats={"scanned":5,"warnings":0,"breaches":0,"reassigned":1,"sentToTriage":0}
- `GET /api/v1/tickets/TKT-0006` as `sup-mara` → **200** (7 ms, cid `ev13-0027-73165467`) → assignee now agent-noel
- `PATCH /api/v1/agents/agent-carla/availability` as `sup-mara` → **200** (17 ms, cid `ev13-0028-73165482`) (restored)

## 9. SLA aging alerts and escalation

**Expected:** Development clock is advanced. At ≥75% of the SLA window the assignee gets one warning; at ≥100% the ticket is escalated to the supervisor. Re-running the scan does not duplicate alerts.

- `POST /api/v1/tickets` as `req-ben` → **201** (14 ms, cid `ev13-0029-73165498`) → TKT-0007 priority=high (8 h SLA) assignee=agent-eli
- `POST /api/v1/dev/clock/advance` as `sup-mara` → **200** (7 ms, cid `ev13-0030-73165514`) (+6.5 h = 81%)
- `POST /api/v1/automation/jobs/aging-scan/run` as `sup-mara` → **200** (34 ms, cid `ev13-0031-73165529`) → {"scanned":6,"warnings":2,"breaches":0,"reassigned":0,"sentToTriage":0}
- `POST /api/v1/automation/jobs/aging-scan/run` as `sup-mara` → **200** (35 ms, cid `ev13-0032-73165561`) → {"scanned":6,"warnings":0,"breaches":0,"reassigned":0,"sentToTriage":0} (re-run: no duplicates)
- `POST /api/v1/dev/clock/advance` as `sup-mara` → **200** (7 ms, cid `ev13-0033-73165597`) (+2 h = 106%)
- `POST /api/v1/automation/jobs/aging-scan/run` as `sup-mara` → **200** (31 ms, cid `ev13-0034-73165597`) → {"scanned":6,"warnings":0,"breaches":2,"reassigned":0,"sentToTriage":0}

**Observed:** TKT-0007 alerts=[warning, breach], escalated=true; audit: submitted, status_changed, sla_warning, sla_breached

## 10. Support summary

**Expected:** Summary job aggregates ticket counts, open load per agent, breaches and notification health, and notifies the supervisor.

- `POST /api/v1/automation/jobs/daily-summary/run` as `sup-mara` → **200** (43 ms, cid `ev13-0036-73165644`) → {summaryId: SUM-1}
- `GET /api/v1/summaries/latest` as `sup-mara` → **200** (6 ms, cid `ev13-0037-73165689`) 

```json
{
  "totals": {
    "all": 7,
    "open": 6,
    "submittedToday": 7,
    "closedToday": 1,
    "breachedOpen": 2,
    "awaitingTriage": 0
  },
  "byStatus": {
    "closed": 1,
    "assigned": 6
  },
  "openByCategory": {
    "software": 2,
    "hardware": 2,
    "account": 1,
    "network": 1
  },
  "openByAgent": {
    "agent-dan": 2,
    "agent-eli": 2,
    "agent-faith": 1,
    "agent-noel": 1
  },
  "avgResolutionMinutes": 0,
  "notifications": {
    "sent": 20,
    "sentAfterRetry": 3,
    "pendingOrRetrying": 0,
    "deadLetter": 0
  }
}
```

## 11. Gateway received each message once

**Expected:** Idempotency keys mean retries and recovery never deliver the same notification twice.

- `GET /admin/sent` as `-` → **200** (9 ms, cid `ev13-0038-73165689`) → 23 delivered messages
- `GET /api/v1/automation/runs` as `sup-mara` → **200** (8 ms, cid `ev13-0039-73165709`) → 16 job runs recorded

---

Completed in 17 s, 39 requests.
