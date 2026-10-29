# Company Brain validation

Validated 29 October 2026.

## Passed

- 13 Node domain tests: role/source filtering, restricted HR and admin access, sourced answers and abstention, conflict preservation, input validation, separate reviewers, tombstones, person-specific continuity, department-scoped successor plans, per-persona audit, IST dates and question relevance.
- JavaScript syntax checks for app.js and domain.mjs.
- Browser journey: employee submits an update; simulated pipeline retains a self-report; different manager attests; status persists across reload.
- Manager retrieval preserves the gateway ownership conflict; Administrator query abstains without private Engineering sources.
- Successor requester cannot approve; Department head can approve the evidence snapshot. No external execution occurs.
- Continuity exposes missing rollback evidence and disputed ownership, with source-backed text export implemented.
- Hypothetical impact scenario updates its illustrative date from an explicit delay assumption and links supporting sources.
- All main screens render at 390px without horizontal document overflow; desktop inspected at 1440px.
- Dialog focus lands on the first update field. Focus trap and Escape behavior implemented. Dashboard text contrast measured and corrected. This is targeted QA, not formal WCAG certification.
- Architecture file downloaded through the browser. No JavaScript errors or warnings observed during tested flows.
- SQL: 60 PostgreSQL statements parsed. No live PostgreSQL/pgvector migration or policy integration run.
- OpenAPI 3.1 contract validator passed for 11 paths. No backend HTTP implementation deployed.

## Explicit limits

All operating data is fictional. Model tasks are simulated with deterministic local rules. Connector cards describe contracts and do not access accounts. localStorage is not enterprise persistence. Demo roles are not authentication, and every sample record is delivered to the browser. Architecture, SQL and API files define subsequent engineering work and security gates.
