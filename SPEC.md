# Company Brain demonstrator

Research precedes implementation. Real reference: GitLab's public handbook-first and asynchronous practices. All employee, customer, financial and operational records are fictional sample data, not GitLab records.

## Capability map and build order
| Module | Responsibility | Depends on |
|---|---|---|
| memory | Source-backed sample objects, permissions, persistence | — |
| ingestion | Structured daily updates, simulated routing, human review | memory |
| retrieval | Keyword search, sourced answers, role demonstration | memory |
| continuity | Responsibility graph, history, evidence, gaps | memory |
| workspace | Overview, map, connections, decisions, audit | memory, ingestion, retrieval, continuity |
| blueprint | Production architecture, SQL, API contract, roadmap | research |
Build: research → memory → ingestion/retrieval/continuity → workspace → validation → private publication.

## Objective and scope
A polished responsive browser demonstrator of a Company Brain, plus practical production implementation artifacts. Browser-only persistent sample data with localStorage, no external tool access, LLM calls or enterprise authentication. Role selector is a simulation, not a security boundary; all sample data is delivered to browser. Never invite confidential data entry. Hosted Site owner-private.

## Acceptance
- Dashboard has functional navigation and selected node inspection.
- Graph filters by department/type and reacts to authorized viewpoint; source details are inspectable.
- Search and source-backed deterministic synthesis operate only over authorized records in demo policy.
- Daily update creates a persisted reported record, runs visible simulated stages, does not auto-mark verified, and can be approved by allowed reviewer other than author.
- All five roles have clear scopes; neither admin nor exec automatically reads restricted HR.
- Continuity handover uses authorized evidence, shows ownership, pending tasks, rationale, dependencies and knowledge gaps; exports text.
- Decisions preserve disputed vs accepted state and historical rationale; sensitive action remains a proposal pending approval.
- Connector page distinguishes simulated connectors, configuration and no real connection.
- Architecture includes diagram, memory tiers, routing, event example, rollout and sources.
- Keyboard-accessible controls and dialogs, responsive at 390px and desktop, reduced-motion support.
- No fabricated external actions; all exports/downloads and local mutations work; no secrets.

## Files and commands
`dist/` static deliverable. `dist/domain.mjs` data/policy/search/ingestion. `dist/app.js` UI. `dist/styles.css` tokens/layout. `tests/domain.test.mjs` meaningful policy/persistence/grounding tests.
Dev: `python3 -m http.server 4173 --directory dist`
Test: `node --test tests/domain.test.mjs`
Syntax: `node --check dist/app.js`
No dependencies or build step. Plain ES modules, escape untrusted strings before HTML insertion. Use native controls and semantic document structure.

## Quality and boundaries
Always: input size limits, source citations, explicit sample/simulated labeling, verify all workflows, test restricted-source retrieval and review boundaries. Ask only for missing enterprise credentials if moving beyond this demonstrator. Never: store credentials, transmit data externally, pretend local policy is server security, assert tacit expertise was recovered, promote self-reports automatically to verified facts.

## Plan and checks
1. Research and contract; 2. policy and meaningful tests; 3. complete UI slices; 4. browser QA, mobile and keyboard; 5. package blueprint and source; 6. publish private.
