# Company Brain — implementation roadmap

29 October 2026. This is a production delivery plan, not a claim that the accompanying browser demonstrator implements enterprise identity, connectors, model inference, or server persistence. All estimates assume 2 backend engineers, 1 frontend engineer, a part-time platform/security engineer, an accountable product owner, and source-system owners. Phases overlap only after dependency gates pass; validate estimates after discovery.

## Phase 0 — agree scope and evidence (weeks 1–2)

Owner: product lead + security + one department manager.

- Inventory source systems, canonical owners, source ACL APIs/events, quotas, data residency, consent, retention and deletion obligations. Start with approved shared Slack channels and handbook/project records; exclude private HR and unapproved DMs.
- Define OIDC tenant mapping, SCIM lifecycle, identity aliases and group ownership. Choose tenant isolation model and a single approved model region/provider path.
- Threat-model source prompt injection, stale ACLs, private source summaries, connector token compromise, export leakage, and cross-tenant references.
- Assemble 100–200 approved evaluation questions/updates, including unanswerable questions, conflicting dates, departed-owner responsibilities, and permission-denied cases.
- Agree review status semantics, handover coverage denominator, latency/cost budgets and named incident/on-call owners.

Exit: written source permission maps and retention policy; evaluation set; approved capability map; read-only pilot scope; no confidential source before these decisions.

## Phase 1 — identity and reliable evidence (weeks 3–5)

Owner: backend/platform. Dependencies: phase 0.

- Implement FastAPI identity middleware, transaction-local tenant/subject DB context, nonowner `NOBYPASSRLS` API role, source grant projection, and OpenFGA policy checks. SQL is the foundation, not a complete policy implementation.
- Implement Slack signed webhook inbox, prompt acknowledgement, deduplication, rate-limited backfill, source versions, ACL freshness/tombstones, and reconciliation. Add handbook/project source adapter using approved credentials.
- Encrypt evidence in object storage; write transactional outbox; establish retention and secret filtering; deploy the audit sink.
- Build operational dashboards for connector lag, failures, retries, DLQ, policy freshness and purge status. Verify backup/restore.

Exit: duplicate/replay/forgery tests; no cross-tenant reads or references; ACL removal denies immediately within agreed freshness budget; worker restart loses no durable envelope; source revision and content hash traceable. Read-only search can launch to a small pilot after security sign-off.

## Phase 2 — daily updates and grounded retrieval (weeks 6–8)

Owner: backend/model + frontend. Dependencies: reliable evidence.

- Implement structured daily updates through dashboard and Slack, source-span extraction, entity resolution, schema validation and explicit reported/proposed/accepted states.
- Add lexical + vector retrieval, authorized candidate filtering, authoritative checks before reranking/model context, claim-level citations and final access recheck.
- Implement owner review queue, conflict cases, bitemporal revisions, source freshness and abstention. Version model/prompt/schema adapters and add evaluation regression runs.
- Begin department-specific retrieval scopes and terminology without duplicating all data.

Exit: zero known unauthorized disclosures across the role/source-ACL adversarial suite; accepted claims have evidence; date conflicts remain visible; unsupported questions abstain; cite exact source revision/span; meet agreed extraction quality and latency/cost budgets on the golden set. Numeric thresholds are selected in phase 0 rather than invented after tests fail.

## Phase 3 — continuity and proactive intelligence (weeks 9–11)

Owner: product + department manager + backend. Dependencies: accepted memory.

- Connect tasks, ownership, decisions/rationale, procedures, customers and hard dependencies in the typed graph. Add deterministic blocked/overdue/missing-owner rules and evidence-backed alerts.
- Implement verified offboarding signal → session/token/delegation revocation workflow; test identity deactivation separately from handover generation.
- Generate permission-scoped continuity drafts with as-of time, freshness, active responsibility denominator, evidence gaps, suggested successor and explicit acceptance.
- Add documented expertise search with evidence/recency and opt-in tags. Add decision rationale gap prompts.

Exit: staged unexpected-departure exercise; manager/successor can recover known responsibilities; missing tacit knowledge remains labeled; no inherited private correspondence access; packet export rechecks permissions; revocation works during active generation; source deletion invalidates all dependent retrieval surfaces.

## Phase 4 — assisted workflows (weeks 12–14)

Owner: platform/security + source owners. Dependencies: proven read-only reliability.

- Introduce exact action proposals with parameter schema, plan hash, expected target version, reason, TTL and required approver. Separate requester from approver for sensitive actions.
- Start with one reversible low-impact project-tool write. Execute through a capability-limited gateway with current authorization, policy/version checks, idempotency and recorded source receipt.
- Test timeout after source success, retries, approval expiry, modified plans, self-approval, stale objects, partial failure and compensating actions. Do not call the compensating action an atomic rollback when the external tool lacks transactions.
- Keep HR/financial/destructive writes disabled until separately authorized and proven.

Exit: demonstrated no duplicate external effect under retry; changed/expired plans cannot execute; source/version and approver state rechecked; action and result audited; operator can stop workflows and recover.

## Phase 5 — expand and optimize (week 15 onward)

Owner: product/platform + each source owner.

- Add email/calendar, approved transcripts, CRM/support, GitHub/GitLab events, and limited HR directory metadata one connector at a time. Each needs its own ACL, deletion, rate-limit and reconciliation proof.
- Mine recurring event sequences into owner-reviewed workflow drafts. Add bounded dependency impact scenarios and compare predictions against outcomes before using them operationally.
- Use measured bottlenecks to decide whether Kafka, a dedicated graph store, isolated queues, tenant partitioning, or private model hosting is justified.
- Re-run policy, provenance, model, restore and continuity evaluations on every relevant change. Review source freshness/coverage monthly and ownership after reorganizations.

## Release and operating gates

| Concern | Required evidence | Owner |
|---|---|---|
| Identity and ACL | Employee/manager/head/exec/admin tests; source permissions override role; revocation during generation | Security |
| Derived knowledge | Public + private evidence stays private; hidden nodes/counts/suggestions do not leak | Backend/security |
| Delivery | Duplicate, out-of-order, missed delivery, backfill, provider throttling and reconciliation drills | Platform |
| Truth and history | Contradiction, supersession, rationale gap, valid-time and known-time queries | Product/data |
| Models | Structured extraction, faithful citations, abstention, injection resistance and bounded cost | Model engineer |
| Continuity | Unexpected-departure scenario with real responsibility denominator and unknowns | Department manager |
| Deletion | Per-store purge/tombstone propagation and backup expiration drill | Platform/privacy owner |
| Sensitive actions | Distinct approver, plan hash, expiry, version, current authorization and idempotency | Source owner/security |
| Resilience | Database restore, object store recovery, worker restart, connector outage and DLQ replay | Platform |

Deploy with read-only feature flags, a small approved cohort, and a kill switch for ingestion, generation and external actions independently. Roll back model/prompt/projection versions without deleting source evidence. Quarantine invalid extraction output and replay from the durable inbox after correction. Maintain a runbook for connector compromise and mass policy revocation.

## First practical production slice

One department; one approved Slack channel; one handbook/project source; employee update → reviewed candidate → accepted claim → authorized cited answer → manager continuity draft. Ship this complete slice before broad connectors, autonomous writes, or digital-twin prediction. The architectural boundary remains stable as departments expand.
