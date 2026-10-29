# Company Brain — research notes

Research date: 29 October 2026. These notes combine the two independent architecture and security research passes used before the prototype was built. Primary-source links appear next to the claims they support. Recommendations, capacity assumptions, and proposed architecture are our design judgments, not vendor guarantees.

GitLab is the public real-company reference only. Operational people, projects, metrics, decisions, customer examples and employment scenarios are fictional sample data. The website is a browser demonstrator; these notes do not imply live enterprise integrations or production security. Final architecture and implementation boundaries are specified in `COMPANY_BRAIN_ARCHITECTURE.md`.

---

# Company Brain: primary-source research and architecture recommendations

Researched 29 October 2026. Architecture recommendations below are our design judgments. GitLab is the public reference organization, not a customer or an organization whose private data is available. All prototype people, initiatives, updates, risks, metrics and employment scenarios must be fictional and labeled as sample data.

## Findings that change the design

1. GitLab's public handbook describes a handbook-first approach in an asynchronous, all-remote organization. Keep canonical ownership in source tools; let the brain connect evidence, provenance and approved knowledge rather than becoming a competing document authority. [GitLab Handbook Usage](https://handbook.gitlab.com/handbook/about/handbook-usage/)
2. Slack Events are tied to granted OAuth scopes and the conversations the app can access. Its HTTP receiver must acknowledge within three seconds; failures are retried up to three times. Persist the signed raw envelope and enqueue before doing LLM work. Deduplicate by workspace + event ID, reconcile missed changes, and monitor connector lag. These mechanics prevent duplicated tasks and silent knowledge loss. [Slack Events API](https://docs.slack.dev/apis/events-api/)
3. Slack signs a base string built from the timestamp and original raw request body using HMAC-SHA256. Its verification example rejects timestamps more than five minutes from local time and compares signatures using a timing-safe comparison. Never parse/reformat the body before verifying. [Slack request verification](https://docs.slack.dev/authentication/verifying-requests-from-slack/)
4. Slack API limits vary by method and application category. Do not promise unlimited historical ingestion or hardcode one generic quota; implement per-workspace/per-method budgets, honor retry responses, and inspect the installed app's category. Use event-first incremental ingestion and a rate-limited backfill. [Slack rate limits](https://docs.slack.dev/apis/web-api/rate-limits/)
5. GitHub.com recommends HTTPS, minimal event subscriptions, a webhook secret, a response within ten seconds and use of X-GitHub-Delivery for deduplication; redelivery preserves that ID. A durable inbox with a unique delivery key must acknowledge duplicate deliveries without reprocessing side effects. [GitHub webhook best practices](https://docs.github.com/en/webhooks/using-webhooks/best-practices-for-using-webhooks)
6. GitHub does not automatically redeliver failed webhook deliveries. Add a reconciliation job that inspects delivery status and requests redelivery, plus a periodic source-state scan to close gaps. Do not assume webhook subscription implies complete history. [Handling failed GitHub deliveries](https://docs.github.com/en/webhooks/using-webhooks/handling-failed-webhook-deliveries)
7. Verify GitHub's X-Hub-Signature-256 against the original payload with the installation's high-entropy secret. Signature validation establishes origin/integrity, not the reader's entitlement to the resulting content. [GitHub webhook validation](https://docs.github.com/en/webhooks/using-webhooks/validating-webhook-deliveries)
8. PostgreSQL RLS is default-deny when enabled and no applicable policy exists. Superusers and BYPASSRLS roles bypass policies; owners normally bypass them unless FORCE ROW LEVEL SECURITY is set. Use an application role that is neither owner nor superuser and has NOBYPASSRLS; set tenant and user context only from a verified identity server-side. Read and write policies need separate tests. [PostgreSQL row security](https://www.postgresql.org/docs/current/ddl-rowsecurity.html)
9. pgvector supports exact and approximate nearest-neighbor search. With approximate indexes, filtering occurs after index scanning and can reduce returned results. Iterative scans (from 0.8.0) scan further under configured limits. Test ACL-selective queries against exact-search baselines; use exact fallback for small authorized corpora, and tenant partitions when justified. Never remove ACL filtering to improve recall. [pgvector official repository](https://github.com/pgvector/pgvector)
10. Temporal keeps workflow execution state durable across failures. Use deterministic workflow code for orchestration and external activities for network, DB and model calls. [Temporal workflow execution](https://docs.temporal.io/workflow-execution)
11. Activities are independently executed work and should be idempotent because retries can repeat side effects. An LLM call belongs in an activity; cache its versioned result and require an idempotency key for any external mutation. Durable execution is not permission to assume exactly-once delivery at an external tool. [Temporal activities](https://docs.temporal.io/activities)

## Practical stack and boundaries

Start with a modular application, not a swarm of independent services. Suggested stack: TypeScript/React dashboard, FastAPI Python API and model workers, PostgreSQL with full-text search + pgvector + relational edge tables, S3-compatible object storage with encryption, Redis only for short-lived caches, Temporal for workflows/approvals, OIDC SSO + SCIM lifecycle synchronization, and an authorization policy module. Use the existing cloud's managed queue and secrets manager. Add OpenTelemetry traces and operational dashboards. Neo4j is an optional later graph projection, not a prerequisite; Postgres edges and recursive queries make an inspectable MVP and avoid a second consistency problem. At higher volume introduce a durable event log (Kafka/Redpanda or cloud equivalent), dedicated graph serving, and isolated departmental worker queues based on measured constraints.

The Main Brain is a permission-aware set of versioned entities, claims, edges, procedures and decision records plus a retrieval coordinator. It is not an all-knowing model and not a model trained on the company's raw records. The CPU is a deterministic policy-enforcing orchestrator. Department sub-brains are bounded retrieval scopes, taxonomies and worker policies over the same provenance model; they do not silently duplicate all corporate data.

Specialists are configurable tasks with structured output schemas: daily-update extraction, meeting outcomes/action items, conversation decision candidates, document classification/chunking, code-change impact, contradiction detection and evidence-grounded synthesis. Several tasks can share a small model. A more capable reasoning model is reserved for multi-hop synthesis or ambiguity. No LLM decides its own access scope or executes arbitrary tools.

Use model capability classes in the design rather than unverified model names or prices: deterministic parsing/rules first, small extraction model next, stronger reasoning model only on evaluation-driven escalation. Version prompts, schemas and model IDs. Evaluate proposed claims, citation coverage, extraction quality, permission leaks and handover completeness separately. Self-reported confidence is not evidence of truth.

## Data plane

Ingest only sources and scopes explicitly approved by the organization. Connector credentials remain server-side. Track object identity, revision, source URL, actor mapping, event time, ingestion time, source ACL version and deletion state. Preserve raw evidence subject to retention policy and exclude secrets, private HR cases and unapproved DMs by default.

Pipeline: signature verification → durable inbox/ack → identity resolution and ACL snapshot → malware/secret/PII classification → normalized event → specialist extraction → schema validation → entity and source-reference validation → claim staging → owner approval for consequential/ambiguous facts → append versioned organizational memory → update search and graph projections through transactional outbox.

Keep source observations, extracted candidates, inferred hypotheses and approved decisions distinct. A signed message can be faithfully captured while its business claim remains unconfirmed. Extracted facts require source spans, dates, author and verification state. Contradictions create a review case and retain both alternatives. Supersession closes validity intervals; it does not erase history. Store valid_from/valid_to (when true in the company) and recorded_at/superseded_at (when the system learned it) for temporal questions.

An ACL change/deletion is a first-class event. Recompute grants for chunks, summaries, edges, alerts and handover packets. Immediately deny retrieval when authorization is unknown or stale, invalidate permission-versioned caches, and process deletion/tombstones in every projection. A summary derived from A and B is readable only to readers entitled to every supporting restricted item, unless an explicitly reviewed declassified summary exists. Counting hidden nodes or naming hidden sources can itself leak information.

## Illustrative daily-update journey

Fictional Senior Backend Engineer Alex Morgan reports: “Completed the composite-index benchmark on staging. Working on CI Insights query optimization. Next: run the 100k-pipeline benchmark with Noah. Blocked on anonymized load-test data.” The Slack connector records an authorized source revision and acknowledges. The update specialist emits completed/current/next/blocker/dependency arrays with exact source spans. Entity resolution maps Alex, Noah Williams, CI Insights and issue #2841; unresolved references remain unresolved.

The CPU validates evidence and links the update to the existing performance gate: p95 420 ms versus a 250 ms target. ADR-042 already accepts a 10% rollout on November 3, superseding the full October 30 launch proposal. Benchmark completion and a pending index merge request do not prove the regression is fixed. Maya Chen, Engineering Manager, reviews candidate claims; Sarah Park owns the downstream launch checklist.

The graph links Alex → OWNS → query optimization → PART_OF → CI Insights; platform dataset delivery → BLOCKS → load-test sign-off → BLOCKS → launch readiness. Separately, the API gateway service catalog names Alex as primary owner while Noah's draft handover names Noah. The Brain preserves the ownership conflict for Maya's review rather than choosing the newest statement.

An employee query retrieves only allowed project records; a project manager sees authorized team updates; department head Elena sees permitted portfolio dependencies. Executives and administrators gain no automatic private source access. Cited answers retain source revisions, dates, verification states and outstanding uncertainties.

## Continuity, discovery and digital twin

On verified offboarding, revoke the person's tokens and sessions first, then generate a source-authorized continuity packet for an approved successor/manager. Traverse owned responsibilities, open tasks, recent decisions with rationale, runbooks, contacts, deadlines and external dependencies. Mark freshness, unconfirmed assignments and gaps. Suggest a backup expert from documented contributions and approved expertise tags, with evidence and recency; do not infer private expertise or employee performance. The successor accepts responsibility through an explicit workflow.

The packet cannot recover tacit knowledge never captured. Display coverage against known responsibilities, the newest source revision and missing documentation. Reassignment is not automatic evidence that access to old private correspondence is lawful or appropriate. Re-check access every time a packet is viewed/exported, and record the recipient, purpose and evidence set.

Workflow discovery groups repeated authorized event sequences and proposes a draft procedure to its owner. The organizational digital twin is a versioned dependency graph, not a psychological replica. Change-impact simulations traverse hard dependencies and show assumptions and confidence bands; workload and deadlines can support risk scenarios, not certain causal predictions. Keep inferred effects visually separate from recorded dependencies and decisions.

## Initial capacity and acceptance assumptions

For planning only: 1,000 employees × 50 authorized events/day = 50,000 events/day, with 20× burst capacity. Source quotas and document sizes can dominate throughput. Target webhook persistence/ack p95 below one second, authorized search p95 below two seconds and typical cited synthesis below eight seconds; these are proposed SLOs to measure, not achieved metrics. Coalesce chat threads before extraction, avoid re-embedding unchanged content hashes, batch embeddings, cache by tenant + principal + ACL version + corpus revision, and place hard per-workflow token/cost/time budgets.

Read-only launch gates: permission-leak adversarial tests across roles, source ACL revocation and deletion propagation, no duplicated tasks under retries, successful recovery from worker failure, citation/source-span integrity, explicit abstention on unsupported answers, handover gap visibility, and restore drills. Sensitive writes stay disabled until approval, separation-of-duty, idempotency and rollback checks pass.

## Incremental roadmap

1. Two-week discovery: source inventory, canonical owners, classifications, retention, tenancy, SSO, threat model, a small golden evaluation set, and agreed scope/quality gates.
2. Read-only pilot: one department, approved Slack channels plus handbook/project records, durable inbox, source revisions, RLS, searchable evidence, extraction staging and audit.
3. Knowledge and continuity: accepted decisions/rationale, temporal graph, daily updates, contradiction queue, department scopes and measured handover coverage. Prove authorization revocation, backfill and restore.
4. Assisted workflows: durable approvals, limited reversible tool writes, explicit action diffs, source version checks, idempotency and rollback. Expand connectors only after permission mapping is validated.
5. Cross-team intelligence: CRM/meeting/calendar/HR metadata integrations with purpose-specific access, curated expertise mapping, workflow drafts and explainable change-impact scenarios. Add separate graph/event infrastructure only where query/volume evidence warrants it.



---

# Company Brain: security, memory, and continuity research

Research date: 29 October 2026. Design proposals below are recommendations, not descriptions of GitLab's internal implementation. Prototype data must remain synthetic.

## Primary-source findings

- OpenFGA's [RAG Authorization](https://openfga.dev/docs/modeling/agents/rag-authorization) explicitly covers third-party content and permissions synchronization. It supports either candidate retrieval followed by authorization checks **before model context**, or authorized-object filtering before retrieval. Therefore “ask the LLM to hide restricted content” is not an authorization mechanism.
- OpenFGA's [Search With Permissions](https://openfga.dev/docs/interacting/search-with-permissions) describes a local access index followed by final checks as an approach for large corpora; list-all-accessible-IDs first can become slow at scale. Use tenant and department narrowing in the data query, a permission index for recall, and authoritative batch checks before retrieval content is sent to an LLM.
- OpenFGA's [Query Consistency](https://openfga.dev/docs/interacting/consistency) says its latency-minimizing mode can serve cached permissions and miss a recent change when caching is enabled. Its higher-consistency mode reads the database. Design explicit ACL epochs and revocation tombstones; bypass cached authorization for sensitive actions and recently changed grants.
- PostgreSQL [Row Security Policies](https://www.postgresql.org/docs/current/ddl-rowsecurity.html) gives default deny after enabling RLS without a matching policy. Table owners, superusers, and `BYPASSRLS` roles can bypass normal RLS; `FORCE ROW LEVEL SECURITY` subjects the owner. Therefore the app must use a restricted non-owner role, not the migration/maintenance principal. RLS alone does not govern `TRUNCATE`.
- OWASP [LLM Prompt Injection Prevention](https://cheatsheetseries.owasp.org/cheatsheets/LLM_Prompt_Injection_Prevention_Cheat_Sheet.html) emphasizes that prompt formatting and string screening are not security boundaries. Apply least privilege and validate tool calls at the actual execution boundary. Treat Slack posts, PDFs, code comments, retrieved documents, and model output as untrusted.
- NIST's [Generative AI Profile](https://nvlpubs.nist.gov/nistpubs/ai/NIST.AI.600-1.pdf) supports tracking origin and history to manage GAI risk. Our implementation should attach evidence spans, source versions, model/prompt versions, and review history to every extracted claim.
- IETF [SCIM core schema RFC 7643](https://www.rfc-editor.org/info/rfc7643/) defines the user `active` administrative status, commonly used to represent whether the account is suspended. The precise lifecycle behavior belongs to the service implementation. Therefore SCIM deactivation must trigger an explicit Company Brain session/token revocation workflow; setting one directory field alone must not be assumed to revoke all existing sessions.

## Access decision and strict hierarchy

A useful rule is:

`allow = active_identity AND same_tenant AND role_allows_action AND source_resource_access AND classification_allowed AND purpose_condition AND NOT revoked`

The employee/manager/department-head/executive/admin hierarchy governs scope and permitted actions. It must not become a universal reading hierarchy. An executive may see approved company-wide aggregates but still lack access to individual payroll, medical, privileged legal, or security incident records. An administrator manages connectors and policies; administrative privileges do not automatically grant content access. Emergency access is a separate, expiring, audited approval.

| Role | Default operational scope | Example permitted action | Additional gate |
|---|---|---|---|
| Employee | Own work; explicitly shared projects | Submit update; query shared runbook | Existing source ACL |
| Manager | Direct reports and shared team projects | Review team update; propose assignment | Relevant project/record access |
| Department head | Department's approved portfolio | Review capacity and cross-team risk | Field/classification scope |
| Executive | Approved organization summaries | Ask for strategic dependencies | Sensitive-source access is separate |
| Administrator | System configuration | Configure connector; inspect metadata | No default right to read content |

LLM agents are service principals acting on behalf of a requester, with intersected capabilities: `requester permissions ∩ agent task scope ∩ connector scope`. Never let an ingestion principal's broad read privileges transfer into interactive query privileges.

## Retrieval, graph, and derived knowledge

1. Validate session and tenant. Resolve current group membership server-side; reject client-supplied role claims.
2. Apply tenant/classification/access-index filters during lexical/vector candidate search.
3. Batch-check document access against authoritative policy before returning text to reranker or model. Do not log restricted snippets in shared traces.
4. For graph traversal, authorize every node, relationship, and contributing evidence. Hidden relationships must not leak via node labels, counts, suggestions, degree, or timing-dependent error wording.
5. Build context only from approved sources. Enforce token budgets and redaction before a model call.
6. Produce claim-level references with source ID, version, excerpt offsets, and observed timestamp. Recheck access and ACL epoch just before response delivery; regenerate/omit affected statements if permission changed.
7. Cache answers per tenant, requester authorization fingerprint, source version set, model/prompt version, and TTL. Shared semantic caches must not cross authorization boundaries.

A derived statement has provenance links to all material source claims. By default its usable ACL is the intersection of those sources. For example, a statement inferred from a private HR note and a public project issue stays private even if it is “about” a public project. Wider circulation requires a separate declassification/review workflow producing a sanitized statement with its own policy and lineage. Never union all source audiences.

Avoid storing a single unrestricted precomputed summary for the entire company and filtering its sentences later. Build scoped summaries or regenerate from currently authorized evidence.

## Memory and temporal correctness

- **Working memory:** Redis/session cache with TTL; no durable truth. Separate namespaces per tenant and authorization fingerprint.
- **Episodic memory:** Immutable event envelopes and versioned source snapshots with retention controls. Keep “what was known at time X” separately from event effective time.
- **Semantic memory:** Reviewed claims with subject/predicate/object or text, confidence, status, owner, validity interval, recorded interval, and source evidence. Confidence is evidence-quality metadata; it is not proof of truth.
- **Procedural memory:** Versioned runbooks/workflow definitions, explicit owner, last-validated date, and approval state. A model-suggested workflow begins as a draft.
- **Historical memory:** Append-only claim revisions and decision events, including rationale, alternatives, approver, reversal, and effective date. Correct by superseding, not silently overwriting.

Conflicts use `claim_conflict` records linking contradictory claims. Maintain both, label `disputed`, surface dates/authority/evidence, and assign an owner. Do not “resolve” by last-write-wins or by letting a model pick a truth. A changed task deadline may simply supersede the old deadline; contradictory statements for the same validity period need review. Source deletion/revocation can make formerly supported claims unverifiable, so they must be withdrawn from retrieval until new evidence exists.

## Revocation, deletion, and retention

On source ACL change: increment resource ACL epoch, write a deny tombstone first, invalidate answer/snippet caches, update FGA/access index, and asynchronously rebuild affected materialized summaries. Tombstones block use while downstream indexes converge. Recheck source access for high-sensitivity content at request time if the connector supports it. A stale connector exceeding its ACL freshness budget fails closed for that scope.

On content deletion: tombstone source versions immediately, mark derived claims invalid, remove chunks/vectors/graph evidence, invalidate summaries and caches, record purge completion by store, and expire backups per documented retention. An audit record can preserve non-content metadata and hashes without retaining deleted personal text. Legal holds and retention exceptions need separate configured policy; “never lost” should mean retained authorized institutional knowledge, not indefinite retention of every personal conversation.

## Reliable employee continuity

Unexpected departure should trigger two distinct workflows:

1. **Access revocation:** disable identity, revoke sessions and delegated tokens, remove group grants, rotate owned connector credentials, stop scheduled actions, and reassign automation ownership. Preserve author attribution using a stable person ID.
2. **Authorized continuity snapshot:** list responsibilities from task/project ownership, open decisions and rationale, pending approvals, customer commitments, dependencies, reviewed procedures, documented expertise, and evidence gaps. Snapshot includes an as-of timestamp, source freshness, coverage denominators, missing-source warnings, and the reviewer's scope.

The handover does not broaden the successor's access or recover undocumented tacit knowledge. A successor sees only authorized facts. Sensitive sections require explicit new grants at the source. Reassignment is a proposal until the receiving owner and manager approve. A useful coverage score is “reviewed active responsibilities with at least one current source / discovered active responsibilities,” rather than a vague claim of 100% knowledge capture.

## Action approval boundary

The model can propose, never self-approve, high-impact changes. Sensitive examples: employee offboarding, outbound customer messages, CRM changes above a threshold, permission changes, production deployments, deletion, or changes to financial/HR records.

Approval object: action type, exact validated parameters, target versions, plan hash, requester, authorized approver, expiry, reason, policy version, and immutable decision record. The requester cannot approve their own sensitive action. Execution rechecks requester/approver permissions, unchanged plan hash, current target version, expiry, and idempotency key. Changed plans return to approval. Approval does not grant arbitrary future tool use.

## Proposed storage records

All tables and graph labels carry `tenant_id`. Compound foreign keys include tenant ID to prevent cross-tenant edges.

- `principal(id, tenant_id, external_identity_id, active, department_id, auth_epoch)`
- `role_binding(principal_id, role, scope_type, scope_id, valid_from, valid_until)`
- `source_resource(id, tenant_id, connector_id, external_id, classification, acl_epoch, acl_synced_at, deleted_at)`
- `source_version(id, resource_id, version, content_hash, object_key, event_time, observed_at, retention_until)`
- `acl_binding(resource_id, subject_type, subject_id, relation, valid_until)`
- `chunk(id, source_version_id, span_start, span_end, embedding_version, embedding)`
- `entity(id, tenant_id, type, canonical_key)`
- `claim(id, tenant_id, subject_id, predicate, value_json, status, valid_from, valid_to, recorded_from, recorded_to, confidence, owner_id)`
- `claim_evidence(claim_id, source_version_id, span_start, span_end, extraction_run_id)`
- `edge(id, tenant_id, from_entity_id, relation, to_entity_id, claim_id)`
- `claim_conflict(id, left_claim_id, right_claim_id, state, reviewer_id, resolution_claim_id)`
- `decision(id, project_id, rationale_claim_id, alternatives_json, approver_id, effective_at, supersedes_id)`
- `approval(id, tenant_id, action_type, plan_hash, parameters_json, requester_id, approver_id, state, expires_at, target_version)`
- `audit_event(id, tenant_id, actor_id, on_behalf_of_id, action, resource_ref, decision, policy_version, request_id, occurred_at)`
- `purge_job(id, tenant_id, resource_id, requested_at, store_status_json, completed_at)`

## API contract notes

- `POST /v1/updates`: authenticated author; schema-validated completed/current/next/blockers/dependencies; returns 202 and processing ID. Author and tenant resolved from session, never body.
- `GET /v1/processing/{id}`: authorized job status and stage metadata; no internal prompts or hidden content.
- `POST /v1/query`: `{question, scope, as_of?}`; server derives principal. Returns `{answer, claims, citations, as_of, freshness, limitations}` or a bounded insufficient-evidence answer.
- `GET /v1/graph?entity=...`: permission-filtered nodes/edges and evidence. Avoid restricted object count disclosure.
- `POST /v1/handover-snapshots`: person reference and scope; authorization checked for each source. Returns immutable draft with coverage/gaps.
- `POST /v1/actions/proposals`: creates a validated exact action plan and approval requirement.
- `POST /v1/approvals/{id}/decisions`: authorized distinct approver, expected plan hash, approve/reject and reason.
- `POST /v1/actions/{id}/execute`: execution service only; current authorization, plan/version/expiry checks and idempotency.
- `POST /v1/connectors/{id}/events`: authenticates signature/replay window, deduplicates delivery ID, durable queue before acknowledgement.

Use server-generated request IDs; audit authorization and mutations. Return indistinguishable not-found responses for invisible resources. Do not leak titles through URLs, search autocomplete, error messages, global notifications, or handover export names.

## Model routing and cost controls

Use deterministic code for identity, ACLs, deadlines, deduplication, schema validation, checksums, approvals, and source version tracking. A small extraction model handles normal updates and entity candidates. A stronger reasoning model handles ambiguity, conflict explanations, complex cross-team synthesis, and only already-authorized evidence. Route sensitive content to an approved region/provider or isolated deployment according to classification. Every route records model version, token/cost budget, purpose, and result quality signal. Cap loops, context, concurrency, and per-tenant spend. Batch asynchronous extraction; cache embeddings by content hash; embed changed chunks only.

## Focused acceptance tests

- Employee cannot retrieve manager-only HR text via search, graph, summaries, suggestions, errors, or handover export.
- Executive and admin still fail source ACL check without a grant.
- A claim derived from public + private sources remains private.
- ACL revocation during generation causes response withdrawal/regeneration.
- Source deletion removes vectors, evidence, cached answers, and derived unsupported claims.
- A forged webhook, repeated delivery, cross-tenant ID, and client-supplied role are rejected.
- Prompt injection in a document cannot trigger a tool action or widen retrieval.
- A modified, expired, self-approved, or replayed action plan cannot execute.
- A handover marks missing undocumented expertise rather than fabricating it.
- Concurrent task deadline edits preserve both observed history and the accepted effective deadline.
