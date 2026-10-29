-- Company Brain production FOUNDATION, PostgreSQL 17+ with pgvector.
-- Not a complete backend or a substitute for source-system authorization.
-- Apply with a migration owner: psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f schema.sql
-- Do not run as the API principal. Provision nonowner NOBYPASSRLS roles separately.
-- No PUBLIC privileges or application write policies are granted by this migration.
-- Authorized writers, audit sink, retention jobs and OpenFGA integration must be implemented.
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE EXTENSION IF NOT EXISTS vector;
CREATE SCHEMA brain;
REVOKE ALL ON SCHEMA brain FROM PUBLIC;

CREATE FUNCTION brain.current_tenant() RETURNS uuid
LANGUAGE sql STABLE AS $$
  SELECT nullif(current_setting('brain.tenant_id', true), '')::uuid
$$;
CREATE FUNCTION brain.current_subject() RETURNS uuid
LANGUAGE sql STABLE AS $$
  SELECT nullif(current_setting('brain.subject_id', true), '')::uuid
$$;
-- Server sets these using SET LOCAL in each transaction after verified OIDC auth.
-- They are NOT credentials; clients must never receive a DB connection or SQL access.

CREATE TABLE brain.tenants (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  authz_epoch bigint NOT NULL DEFAULT 1 CHECK (authz_epoch > 0),
  active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE brain.principals (
  tenant_id uuid NOT NULL REFERENCES brain.tenants(id),
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  external_identity_id text NOT NULL,
  display_name text NOT NULL,
  active boolean NOT NULL DEFAULT true,
  auth_epoch bigint NOT NULL DEFAULT 1,
  PRIMARY KEY (tenant_id, id),
  UNIQUE (tenant_id, external_identity_id)
);
CREATE TABLE brain.role_bindings (
  tenant_id uuid NOT NULL,
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  principal_id uuid NOT NULL,
  role_name text NOT NULL CHECK (role_name IN ('employee','manager','department_head','executive','administrator')),
  scope_type text NOT NULL CHECK (scope_type IN ('self','team','department','organization','system')),
  scope_id text NOT NULL,
  valid_from timestamptz NOT NULL DEFAULT now(),
  valid_until timestamptz,
  PRIMARY KEY (tenant_id,id),
  FOREIGN KEY (tenant_id,principal_id) REFERENCES brain.principals(tenant_id,id),
  CHECK (valid_until IS NULL OR valid_until > valid_from)
);
CREATE TABLE brain.connectors (
  tenant_id uuid NOT NULL REFERENCES brain.tenants(id),
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  provider text NOT NULL,
  installation_id text NOT NULL,
  secret_reference text NOT NULL, -- Secrets-manager reference only; never a token.
  status text NOT NULL DEFAULT 'disabled' CHECK (status IN ('disabled','active','degraded','revoked')),
  allowed_scopes jsonb NOT NULL DEFAULT '[]',
  reconciliation_cursor text,
  last_acl_sync_at timestamptz,
  PRIMARY KEY (tenant_id,id),
  UNIQUE (tenant_id,provider,installation_id)
);
CREATE TABLE brain.inbox_events (
  tenant_id uuid NOT NULL,
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  connector_id uuid NOT NULL,
  external_delivery_id text NOT NULL,
  envelope_hash text NOT NULL CHECK (length(envelope_hash)=64),
  envelope_object_key text NOT NULL,
  event_time timestamptz,
  received_at timestamptz NOT NULL DEFAULT now(),
  state text NOT NULL DEFAULT 'received' CHECK (state IN ('received','processing','complete','quarantined','failed')),
  attempts integer NOT NULL DEFAULT 0 CHECK (attempts >= 0),
  PRIMARY KEY (tenant_id,id),
  UNIQUE (tenant_id,connector_id,external_delivery_id),
  FOREIGN KEY (tenant_id,connector_id) REFERENCES brain.connectors(tenant_id,id)
);

-- Every content-bearing entity/claim/edge/procedure has a policy resource.
CREATE TABLE brain.resources (
  tenant_id uuid NOT NULL REFERENCES brain.tenants(id),
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  kind text NOT NULL CHECK (kind IN ('employee','project','task','customer','process','document','message','meeting','code_change','update','claim','edge','decision','procedure','handover','action')),
  canonical_key text NOT NULL,
  title text NOT NULL,
  attributes jsonb NOT NULL DEFAULT '{}',
  classification text NOT NULL CHECK (classification IN ('public','internal','confidential','restricted')),
  acl_state text NOT NULL DEFAULT 'stale' CHECK (acl_state IN ('stale','ready','revoked')),
  acl_epoch bigint NOT NULL DEFAULT 1 CHECK (acl_epoch > 0),
  acl_synced_at timestamptz,
  acl_valid_until timestamptz,
  deleted_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (tenant_id,id),
  UNIQUE (tenant_id,kind,canonical_key)
);
CREATE TABLE brain.resource_dependencies (
  tenant_id uuid NOT NULL,
  derived_resource_id uuid NOT NULL,
  upstream_resource_id uuid NOT NULL,
  upstream_acl_epoch bigint NOT NULL,
  PRIMARY KEY (tenant_id,derived_resource_id,upstream_resource_id),
  FOREIGN KEY (tenant_id,derived_resource_id) REFERENCES brain.resources(tenant_id,id),
  FOREIGN KEY (tenant_id,upstream_resource_id) REFERENCES brain.resources(tenant_id,id),
  CHECK (derived_resource_id <> upstream_resource_id)
);
-- A trusted authorization writer computes source-ACL intersection, not union.
-- It must prevent dependency cycles and invalidate transitive derived resources.
CREATE TABLE brain.resource_read_grants (
  tenant_id uuid NOT NULL,
  resource_id uuid NOT NULL,
  principal_id uuid NOT NULL,
  resource_acl_epoch bigint NOT NULL,
  tenant_authz_epoch bigint NOT NULL,
  principal_auth_epoch bigint NOT NULL,
  lineage_fingerprint text NOT NULL,
  valid_until timestamptz NOT NULL,
  PRIMARY KEY (tenant_id,resource_id,principal_id),
  FOREIGN KEY (tenant_id,resource_id) REFERENCES brain.resources(tenant_id,id),
  FOREIGN KEY (tenant_id,principal_id) REFERENCES brain.principals(tenant_id,id)
);
CREATE TABLE brain.source_versions (
  tenant_id uuid NOT NULL,
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  resource_id uuid NOT NULL,
  connector_id uuid NOT NULL,
  external_id text NOT NULL,
  revision text NOT NULL,
  source_url text NOT NULL,
  content_hash text NOT NULL CHECK (length(content_hash)=64),
  extracted_text_hash text NOT NULL CHECK (length(extracted_text_hash)=64),
  extracted_text_bytes integer NOT NULL CHECK (extracted_text_bytes >= 0),
  evidence_object_key text NOT NULL,
  author_id uuid,
  event_time timestamptz NOT NULL,
  observed_at timestamptz NOT NULL DEFAULT now(),
  retention_until timestamptz NOT NULL,
  deleted_at timestamptz,
  PRIMARY KEY (tenant_id,id),
  UNIQUE (tenant_id,resource_id,revision),
  UNIQUE (tenant_id,id,resource_id),
  FOREIGN KEY (tenant_id,resource_id) REFERENCES brain.resources(tenant_id,id),
  FOREIGN KEY (tenant_id,connector_id) REFERENCES brain.connectors(tenant_id,id),
  FOREIGN KEY (tenant_id,author_id) REFERENCES brain.principals(tenant_id,id)
);
CREATE TABLE brain.chunks (
  tenant_id uuid NOT NULL,
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  source_version_id uuid NOT NULL,
  resource_id uuid NOT NULL,
  span_start integer NOT NULL CHECK (span_start >= 0),
  span_end integer NOT NULL CHECK (span_end > span_start),
  text_content text NOT NULL,
  search_vector tsvector GENERATED ALWAYS AS (to_tsvector('english',text_content)) STORED,
  embedding_model_version text NOT NULL,
  embedding vector(768), -- Deliberate contract: select a 768-dim adapter; migrate/version on change.
  PRIMARY KEY (tenant_id,id),
  FOREIGN KEY (tenant_id,source_version_id,resource_id) REFERENCES brain.source_versions(tenant_id,id,resource_id)
);
CREATE INDEX chunks_fts ON brain.chunks USING gin(search_vector);
CREATE INDEX chunks_embedding ON brain.chunks USING hnsw(embedding vector_cosine_ops);
CREATE INDEX chunks_scope ON brain.chunks(tenant_id,resource_id);

CREATE TABLE brain.claims (
  tenant_id uuid NOT NULL,
  id uuid NOT NULL, -- Same identifier as policy resource of kind claim.
  subject_id uuid NOT NULL,
  predicate text NOT NULL,
  value_json jsonb NOT NULL,
  status text NOT NULL DEFAULT 'proposed' CHECK (status IN ('observed','proposed','accepted','disputed','superseded','withdrawn')),
  owner_id uuid,
  evidence_quality jsonb NOT NULL DEFAULT '{}', -- Evidence dimensions, not LLM confidence-as-truth.
  valid_from timestamptz NOT NULL,
  valid_to timestamptz,
  recorded_from timestamptz NOT NULL DEFAULT now(),
  recorded_to timestamptz,
  supersedes_id uuid,
  PRIMARY KEY (tenant_id,id),
  FOREIGN KEY (tenant_id,id) REFERENCES brain.resources(tenant_id,id),
  FOREIGN KEY (tenant_id,subject_id) REFERENCES brain.resources(tenant_id,id),
  FOREIGN KEY (tenant_id,owner_id) REFERENCES brain.principals(tenant_id,id),
  FOREIGN KEY (tenant_id,supersedes_id) REFERENCES brain.claims(tenant_id,id),
  CHECK (valid_to IS NULL OR valid_to > valid_from),
  CHECK (recorded_to IS NULL OR recorded_to > recorded_from),
  CHECK (supersedes_id IS NULL OR supersedes_id <> id)
);
CREATE TABLE brain.claim_evidence (
  tenant_id uuid NOT NULL,
  claim_id uuid NOT NULL,
  source_version_id uuid NOT NULL,
  span_start integer NOT NULL CHECK (span_start >= 0),
  span_end integer NOT NULL CHECK (span_end > span_start),
  extraction_version text NOT NULL,
  model_version text NOT NULL,
  prompt_version text NOT NULL,
  PRIMARY KEY (tenant_id,claim_id,source_version_id,span_start),
  FOREIGN KEY (tenant_id,claim_id) REFERENCES brain.claims(tenant_id,id),
  FOREIGN KEY (tenant_id,source_version_id) REFERENCES brain.source_versions(tenant_id,id)
);
-- Spans use UTF-8 byte offsets into the versioned extracted text.
-- Ingestion validates end <= extracted_text_bytes and accepted claims have evidence.
-- Authoritative writer transactions enforce claim/resource kinds and provenance completeness.
CREATE TABLE brain.edges (
  tenant_id uuid NOT NULL,
  id uuid NOT NULL,
  from_id uuid NOT NULL,
  relation text NOT NULL CHECK (relation IN ('owns','part_of','blocks','depends_on','decided','supports','expert_in','customer_of','supersedes')),
  to_id uuid NOT NULL,
  supporting_claim_id uuid NOT NULL,
  PRIMARY KEY (tenant_id,id),
  FOREIGN KEY (tenant_id,id) REFERENCES brain.resources(tenant_id,id),
  FOREIGN KEY (tenant_id,from_id) REFERENCES brain.resources(tenant_id,id),
  FOREIGN KEY (tenant_id,to_id) REFERENCES brain.resources(tenant_id,id),
  FOREIGN KEY (tenant_id,supporting_claim_id) REFERENCES brain.claims(tenant_id,id)
);
CREATE INDEX edge_traversal ON brain.edges(tenant_id,from_id,relation);
CREATE TABLE brain.claim_conflicts (
  tenant_id uuid NOT NULL,
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  left_claim_id uuid NOT NULL,
  right_claim_id uuid NOT NULL,
  reviewer_id uuid,
  state text NOT NULL DEFAULT 'open' CHECK (state IN ('open','resolved','dismissed')),
  resolution_claim_id uuid,
  PRIMARY KEY (tenant_id,id),
  FOREIGN KEY (tenant_id,left_claim_id) REFERENCES brain.claims(tenant_id,id),
  FOREIGN KEY (tenant_id,right_claim_id) REFERENCES brain.claims(tenant_id,id),
  FOREIGN KEY (tenant_id,resolution_claim_id) REFERENCES brain.claims(tenant_id,id),
  FOREIGN KEY (tenant_id,reviewer_id) REFERENCES brain.principals(tenant_id,id),
  CHECK (left_claim_id <> right_claim_id)
);
CREATE TABLE brain.decisions (
  tenant_id uuid NOT NULL,
  id uuid NOT NULL,
  project_id uuid,
  rationale_claim_id uuid NOT NULL,
  alternatives_json jsonb NOT NULL DEFAULT '[]',
  approver_id uuid NOT NULL,
  effective_at timestamptz NOT NULL,
  supersedes_id uuid,
  PRIMARY KEY (tenant_id,id),
  FOREIGN KEY (tenant_id,id) REFERENCES brain.resources(tenant_id,id),
  FOREIGN KEY (tenant_id,project_id) REFERENCES brain.resources(tenant_id,id),
  FOREIGN KEY (tenant_id,rationale_claim_id) REFERENCES brain.claims(tenant_id,id),
  FOREIGN KEY (tenant_id,approver_id) REFERENCES brain.principals(tenant_id,id),
  FOREIGN KEY (tenant_id,supersedes_id) REFERENCES brain.decisions(tenant_id,id)
);
CREATE TABLE brain.procedures (
  tenant_id uuid NOT NULL,
  id uuid NOT NULL,
  version integer NOT NULL CHECK (version > 0),
  owner_id uuid NOT NULL,
  source_version_id uuid NOT NULL,
  state text NOT NULL DEFAULT 'draft' CHECK (state IN ('draft','approved','retired')),
  validated_at timestamptz,
  PRIMARY KEY (tenant_id,id,version),
  FOREIGN KEY (tenant_id,id) REFERENCES brain.resources(tenant_id,id),
  FOREIGN KEY (tenant_id,owner_id) REFERENCES brain.principals(tenant_id,id),
  FOREIGN KEY (tenant_id,source_version_id) REFERENCES brain.source_versions(tenant_id,id)
);
CREATE TABLE brain.daily_updates (
  tenant_id uuid NOT NULL,
  id uuid NOT NULL,
  author_id uuid NOT NULL,
  source_version_id uuid NOT NULL,
  work_date date NOT NULL,
  completed jsonb NOT NULL,
  current_tasks jsonb NOT NULL,
  upcoming jsonb NOT NULL,
  blockers jsonb NOT NULL,
  dependencies jsonb NOT NULL,
  submitted_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (tenant_id,id),
  FOREIGN KEY (tenant_id,id) REFERENCES brain.resources(tenant_id,id),
  FOREIGN KEY (tenant_id,author_id) REFERENCES brain.principals(tenant_id,id),
  FOREIGN KEY (tenant_id,source_version_id) REFERENCES brain.source_versions(tenant_id,id),
  CHECK (jsonb_typeof(completed)='array' AND jsonb_typeof(current_tasks)='array' AND jsonb_typeof(upcoming)='array' AND jsonb_typeof(blockers)='array' AND jsonb_typeof(dependencies)='array')
);
CREATE TABLE brain.processing_jobs (
  tenant_id uuid NOT NULL,
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  requester_id uuid NOT NULL,
  resource_id uuid,
  workflow_id text NOT NULL,
  stage text NOT NULL,
  state text NOT NULL CHECK (state IN ('queued','running','awaiting_review','completed','failed')),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (tenant_id,id),
  FOREIGN KEY (tenant_id,requester_id) REFERENCES brain.principals(tenant_id,id),
  FOREIGN KEY (tenant_id,resource_id) REFERENCES brain.resources(tenant_id,id)
);
CREATE TABLE brain.continuity_snapshots (
  tenant_id uuid NOT NULL,
  id uuid NOT NULL,
  employee_id uuid NOT NULL,
  requester_id uuid NOT NULL,
  purpose text NOT NULL,
  as_of timestamptz NOT NULL,
  state text NOT NULL DEFAULT 'draft' CHECK (state IN ('draft','reviewed','accepted','invalidated')),
  reviewed_current_responsibilities integer NOT NULL CHECK (reviewed_current_responsibilities >= 0),
  discovered_active_responsibilities integer NOT NULL CHECK (discovered_active_responsibilities >= 0),
  sections_json jsonb NOT NULL DEFAULT '[]',
  gaps_json jsonb NOT NULL DEFAULT '[]',
  PRIMARY KEY (tenant_id,id),
  FOREIGN KEY (tenant_id,id) REFERENCES brain.resources(tenant_id,id),
  FOREIGN KEY (tenant_id,employee_id) REFERENCES brain.principals(tenant_id,id),
  FOREIGN KEY (tenant_id,requester_id) REFERENCES brain.principals(tenant_id,id),
  CHECK (reviewed_current_responsibilities <= discovered_active_responsibilities)
);
-- Snapshot source-resource lineage lives in resource_dependencies; viewing/exporting
-- always reauthorizes it. JSON sections cannot widen the snapshot's source audience.
CREATE TABLE brain.action_proposals (
  tenant_id uuid NOT NULL,
  id uuid NOT NULL,
  action_type text NOT NULL,
  parameters_json jsonb NOT NULL,
  plan_hash text NOT NULL CHECK (length(plan_hash)=64),
  target_version text NOT NULL,
  requester_id uuid NOT NULL,
  required_approver_id uuid NOT NULL,
  policy_version text NOT NULL,
  state text NOT NULL DEFAULT 'pending' CHECK (state IN ('pending','approved','rejected','expired','executing','executed','failed','cancelled')),
  expires_at timestamptz NOT NULL,
  idempotency_key text NOT NULL,
  PRIMARY KEY (tenant_id,id),
  UNIQUE (tenant_id,requester_id,idempotency_key),
  UNIQUE (tenant_id,id,required_approver_id,plan_hash),
  FOREIGN KEY (tenant_id,id) REFERENCES brain.resources(tenant_id,id),
  FOREIGN KEY (tenant_id,requester_id) REFERENCES brain.principals(tenant_id,id),
  FOREIGN KEY (tenant_id,required_approver_id) REFERENCES brain.principals(tenant_id,id),
  CHECK (requester_id <> required_approver_id)
);
CREATE TABLE brain.approval_decisions (
  tenant_id uuid NOT NULL,
  proposal_id uuid NOT NULL,
  approver_id uuid NOT NULL,
  expected_plan_hash text NOT NULL,
  decision text NOT NULL CHECK (decision IN ('approve','reject')),
  reason text NOT NULL,
  decided_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (tenant_id,proposal_id),
  FOREIGN KEY (tenant_id,proposal_id,approver_id,expected_plan_hash)
    REFERENCES brain.action_proposals(tenant_id,id,required_approver_id,plan_hash)
);
-- Gateway still rechecks permission, expiry, unchanged plan/version and idempotency.
CREATE TABLE brain.audit_events (
  tenant_id uuid NOT NULL REFERENCES brain.tenants(id),
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  actor_id uuid,
  on_behalf_of_id uuid,
  action text NOT NULL,
  resource_ref uuid,
  outcome text NOT NULL,
  policy_version text NOT NULL,
  request_id uuid NOT NULL,
  occurred_at timestamptz NOT NULL DEFAULT now(),
  metadata jsonb NOT NULL DEFAULT '{}', -- No private snippets, tokens, or full prompts.
  PRIMARY KEY (tenant_id,id),
  FOREIGN KEY (tenant_id,actor_id) REFERENCES brain.principals(tenant_id,id),
  FOREIGN KEY (tenant_id,on_behalf_of_id) REFERENCES brain.principals(tenant_id,id)
);
CREATE TABLE brain.outbox_events (
  tenant_id uuid NOT NULL,
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  resource_id uuid NOT NULL,
  event_type text NOT NULL,
  payload jsonb NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  delivered_at timestamptz,
  PRIMARY KEY (tenant_id,id),
  FOREIGN KEY (tenant_id,resource_id) REFERENCES brain.resources(tenant_id,id)
);
CREATE TABLE brain.purge_jobs (
  tenant_id uuid NOT NULL,
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  resource_id uuid NOT NULL,
  requested_at timestamptz NOT NULL DEFAULT now(),
  store_status_json jsonb NOT NULL DEFAULT '{}',
  completed_at timestamptz,
  PRIMARY KEY (tenant_id,id),
  FOREIGN KEY (tenant_id,resource_id) REFERENCES brain.resources(tenant_id,id)
);

-- Fail-closed RLS on every table; no write policies supplied.
DO $$ DECLARE tab record;
BEGIN
  FOR tab IN SELECT tablename FROM pg_tables WHERE schemaname='brain' LOOP
    EXECUTE format('ALTER TABLE brain.%I ENABLE ROW LEVEL SECURITY',tab.tablename);
    EXECUTE format('ALTER TABLE brain.%I FORCE ROW LEVEL SECURITY',tab.tablename);
  END LOOP;
END $$;
CREATE POLICY tenant_self ON brain.tenants FOR SELECT
  USING (id=brain.current_tenant() AND active);
CREATE POLICY principal_self ON brain.principals FOR SELECT
  USING (tenant_id=brain.current_tenant() AND id=brain.current_subject() AND active);
CREATE POLICY own_role ON brain.role_bindings FOR SELECT
  USING (tenant_id=brain.current_tenant() AND principal_id=brain.current_subject());
CREATE POLICY own_grants ON brain.resource_read_grants FOR SELECT
  USING (tenant_id=brain.current_tenant() AND principal_id=brain.current_subject() AND valid_until>now());
CREATE POLICY authorized_resource ON brain.resources FOR SELECT USING (
  tenant_id=brain.current_tenant() AND deleted_at IS NULL AND acl_state='ready'
  AND acl_valid_until>now()
  AND EXISTS (
    SELECT 1 FROM brain.resource_read_grants g
    JOIN brain.tenants t ON t.id=g.tenant_id
    JOIN brain.principals p ON p.tenant_id=g.tenant_id AND p.id=g.principal_id
    WHERE g.tenant_id=resources.tenant_id AND g.resource_id=resources.id
      AND g.principal_id=brain.current_subject() AND g.valid_until>now()
      AND g.resource_acl_epoch=resources.acl_epoch
      AND g.tenant_authz_epoch=t.authz_epoch AND g.principal_auth_epoch=p.auth_epoch
      AND t.active AND p.active
  )
);
CREATE FUNCTION brain.can_read_resource(p_tenant uuid,p_resource uuid) RETURNS boolean
LANGUAGE sql STABLE SECURITY INVOKER AS $$
  SELECT p_tenant=brain.current_tenant() AND EXISTS (
    SELECT 1 FROM brain.resources r WHERE r.tenant_id=p_tenant AND r.id=p_resource
  )
$$;
CREATE POLICY readable_source ON brain.source_versions FOR SELECT USING (
  deleted_at IS NULL AND retention_until>now() AND brain.can_read_resource(tenant_id,resource_id)
);
CREATE POLICY readable_chunk ON brain.chunks FOR SELECT USING (
  brain.can_read_resource(tenant_id,resource_id)
  AND EXISTS (SELECT 1 FROM brain.source_versions v WHERE v.tenant_id=chunks.tenant_id AND v.id=chunks.source_version_id)
);
CREATE POLICY readable_claim ON brain.claims FOR SELECT USING (brain.can_read_resource(tenant_id,id));
CREATE POLICY readable_evidence ON brain.claim_evidence FOR SELECT USING (
  brain.can_read_resource(tenant_id,claim_id)
  AND EXISTS (SELECT 1 FROM brain.source_versions v WHERE v.tenant_id=claim_evidence.tenant_id AND v.id=claim_evidence.source_version_id)
);
CREATE POLICY readable_edge ON brain.edges FOR SELECT USING (
  brain.can_read_resource(tenant_id,id) AND brain.can_read_resource(tenant_id,from_id)
  AND brain.can_read_resource(tenant_id,to_id) AND brain.can_read_resource(tenant_id,supporting_claim_id)
);
CREATE POLICY readable_conflict ON brain.claim_conflicts FOR SELECT USING (
  brain.can_read_resource(tenant_id,left_claim_id) AND brain.can_read_resource(tenant_id,right_claim_id)
);
CREATE POLICY readable_decision ON brain.decisions FOR SELECT USING (
  brain.can_read_resource(tenant_id,id) AND brain.can_read_resource(tenant_id,rationale_claim_id)
);
CREATE POLICY readable_procedure ON brain.procedures FOR SELECT USING (brain.can_read_resource(tenant_id,id));
CREATE POLICY readable_update ON brain.daily_updates FOR SELECT USING (brain.can_read_resource(tenant_id,id));
CREATE POLICY readable_continuity ON brain.continuity_snapshots FOR SELECT USING (brain.can_read_resource(tenant_id,id));
CREATE POLICY own_job ON brain.processing_jobs FOR SELECT USING (
  tenant_id=brain.current_tenant() AND requester_id=brain.current_subject()
  AND (resource_id IS NULL OR brain.can_read_resource(tenant_id,resource_id))
);
CREATE POLICY readable_proposal ON brain.action_proposals FOR SELECT USING (brain.can_read_resource(tenant_id,id));
CREATE POLICY readable_approval ON brain.approval_decisions FOR SELECT USING (brain.can_read_resource(tenant_id,proposal_id));
-- inbox, connector configuration, dependency index, outbox, audit and purge jobs
-- have no API policies: administrative APIs expose purpose-limited metadata only.
REVOKE ALL ON ALL TABLES IN SCHEMA brain FROM PUBLIC;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA brain FROM PUBLIC;
ALTER DEFAULT PRIVILEGES IN SCHEMA brain REVOKE ALL ON TABLES FROM PUBLIC;
ALTER DEFAULT PRIVILEGES IN SCHEMA brain REVOKE ALL ON FUNCTIONS FROM PUBLIC;
COMMIT;

-- REQUIRED DEPLOYMENT WORK (not silently granted here):
-- 1. Provision separate migration, API-read, ingestion-write, authz-write and audit roles.
-- 2. Give API only selected SELECT + helper EXECUTE; no table ownership/BYPASSRLS.
-- 3. Trusted API sets tenant/subject context; direct browser/database access is forbidden.
-- 4. Authz writer projects all-source intersections; invalidate on any upstream change.
--    MVP safe fallback: bump tenant.authz_epoch, denying all old grants until rebuilt.
-- 5. Authoritative OpenFGA checks before context and response; epoch checks alone
--    cannot detect a source ACL change that the connector has not yet observed.
-- 6. Add reviewed writer policies, transitions, provenance-completeness constraints,
--    retention/purge workers, tenant-aware indexes/partitioning and production tests.
