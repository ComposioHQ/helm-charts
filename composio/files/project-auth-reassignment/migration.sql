\set VERBOSITY default
BEGIN ISOLATION LEVEL SERIALIZABLE;
SELECT
  set_config('project_auth_reassignment.source_admin_email', :'source_admin_email', true) AS source_admin_email_set,
  set_config('project_auth_reassignment.destination_admin_email', :'destination_admin_email', true) AS destination_admin_email_set,
  set_config('project_auth_reassignment.source_created_at_from', :'source_created_at_from', true) AS source_created_at_from_set,
  set_config('project_auth_reassignment.source_created_at_to', :'source_created_at_to', true) AS source_created_at_to_set,
  set_config('project_auth_reassignment.dry_run', :'dry_run', true) AS dry_run_set,
  set_config('project_auth_reassignment.allow_write', :'allow_write', true) AS allow_write_set
\gset

DO $migration$
DECLARE
  source_email text := current_setting('project_auth_reassignment.source_admin_email', true);
  destination_email text := current_setting('project_auth_reassignment.destination_admin_email', true);
  source_created_at_from_text text := current_setting('project_auth_reassignment.source_created_at_from', true);
  source_created_at_to_text text := current_setting('project_auth_reassignment.source_created_at_to', true);
  dry_run_text text := current_setting('project_auth_reassignment.dry_run', true);
  allow_write_text text := current_setting('project_auth_reassignment.allow_write', true);
  source_created_at_from timestamptz;
  source_created_at_to timestamptz;
  source_user_id text;
  destination_user_id text;
  source_org_id text;
  destination_org_id text;
  source_project_id text;
  destination_project_id text;
  source_project_nanoid text;
  destination_project_nanoid text;
  source_project_created_at timestamptz;
  destination_project_created_at timestamptz;
  source_user_count integer;
  destination_user_count integer;
  source_membership_count integer;
  destination_membership_count integer;
  source_project_count integer;
  destination_project_count integer;
  auth_config_count integer;
  invalid_auth_config_count integer;
  updated_auth_config_count integer;
  postcondition_failure_count integer;
  result_status text;
BEGIN
  IF dry_run_text NOT IN ('true', 'false') OR allow_write_text NOT IN ('true', 'false') THEN
    RAISE EXCEPTION USING
      ERRCODE = 'P0001',
      MESSAGE = 'project_auth_reassignment.failed',
      DETAIL = json_build_object('check', 'configuration.boolean', 'message', 'DRY_RUN and ALLOW_WRITE must be exactly true or false')::text;
  END IF;

  BEGIN
    source_created_at_from := source_created_at_from_text::timestamptz;
    source_created_at_to := source_created_at_to_text::timestamptz;
  EXCEPTION WHEN others THEN
    RAISE EXCEPTION USING
      ERRCODE = 'P0001',
      MESSAGE = 'project_auth_reassignment.failed',
      DETAIL = json_build_object('check', 'configuration.timestamp', 'message', 'Source creation timestamps must be valid ISO-8601 values with a timezone')::text;
  END;
  IF source_created_at_from >= source_created_at_to THEN
    RAISE EXCEPTION USING
      ERRCODE = 'P0001',
      MESSAGE = 'project_auth_reassignment.failed',
      DETAIL = json_build_object('check', 'configuration.source_interval', 'message', 'SOURCE_CREATED_AT_FROM must be earlier than SOURCE_CREATED_AT_TO')::text;
  END IF;

  SELECT count(*) INTO source_user_count FROM public.users
    WHERE email = source_email AND "deletedAt" IS NULL;
  SELECT count(*) INTO destination_user_count FROM public.users
    WHERE email = destination_email AND "deletedAt" IS NULL;
  IF source_user_count != 1 OR destination_user_count != 1 THEN
    RAISE EXCEPTION USING
      ERRCODE = 'P0001',
      MESSAGE = 'project_auth_reassignment.failed',
      DETAIL = json_build_object('check', 'selection.users', 'sourceCount', source_user_count, 'destinationCount', destination_user_count)::text;
  END IF;
  SELECT id INTO source_user_id FROM public.users
    WHERE email = source_email AND "deletedAt" IS NULL FOR UPDATE;
  SELECT id INTO destination_user_id FROM public.users
    WHERE email = destination_email AND "deletedAt" IS NULL FOR UPDATE;
  IF source_user_id = destination_user_id THEN
    RAISE EXCEPTION USING
      ERRCODE = 'P0001',
      MESSAGE = 'project_auth_reassignment.failed',
      DETAIL = json_build_object('check', 'invariant.distinct_users', 'message', 'Source and destination users must differ')::text;
  END IF;

  SELECT count(*) INTO source_membership_count
    FROM public.user_org_mapping m JOIN public.orgs o ON o.id = m."orgId" AND o.deleted = false
    WHERE m."userId" = source_user_id AND m."deletedAt" IS NULL;
  SELECT count(*) INTO destination_membership_count
    FROM public.user_org_mapping m JOIN public.orgs o ON o.id = m."orgId" AND o.deleted = false
    WHERE m."userId" = destination_user_id AND m."deletedAt" IS NULL;
  IF source_membership_count != 1 OR destination_membership_count != 1 THEN
    RAISE EXCEPTION USING
      ERRCODE = 'P0001',
      MESSAGE = 'project_auth_reassignment.failed',
      DETAIL = json_build_object('check', 'selection.memberships', 'sourceCount', source_membership_count, 'destinationCount', destination_membership_count)::text;
  END IF;
  SELECT m."orgId" INTO source_org_id FROM public.user_org_mapping m JOIN public.orgs o ON o.id = m."orgId" AND o.deleted = false
    WHERE m."userId" = source_user_id AND m."deletedAt" IS NULL FOR UPDATE OF m, o;
  SELECT m."orgId" INTO destination_org_id FROM public.user_org_mapping m JOIN public.orgs o ON o.id = m."orgId" AND o.deleted = false
    WHERE m."userId" = destination_user_id AND m."deletedAt" IS NULL FOR UPDATE OF m, o;

  SELECT count(*) INTO source_project_count FROM public.projects
    WHERE "orgId" = source_org_id AND deleted = false AND "createdAt" >= source_created_at_from AND "createdAt" < source_created_at_to;
  SELECT count(*) INTO destination_project_count FROM public.projects
    WHERE "orgId" = destination_org_id AND deleted = false;
  IF source_project_count != 1 OR destination_project_count != 1 THEN
    RAISE EXCEPTION USING
      ERRCODE = 'P0001',
      MESSAGE = 'project_auth_reassignment.failed',
      DETAIL = json_build_object('check', 'selection.projects', 'sourceCount', source_project_count, 'destinationCount', destination_project_count)::text;
  END IF;
  SELECT id, "nanoId", "createdAt" INTO source_project_id, source_project_nanoid, source_project_created_at FROM public.projects
    WHERE "orgId" = source_org_id AND deleted = false AND "createdAt" >= source_created_at_from AND "createdAt" < source_created_at_to FOR UPDATE;
  SELECT id, "nanoId", "createdAt" INTO destination_project_id, destination_project_nanoid, destination_project_created_at FROM public.projects
    WHERE "orgId" = destination_org_id AND deleted = false FOR UPDATE;
  IF source_project_id = destination_project_id OR destination_project_created_at >= source_project_created_at THEN
    RAISE EXCEPTION USING
      ERRCODE = 'P0001',
      MESSAGE = 'project_auth_reassignment.failed',
      DETAIL = json_build_object('check', 'invariant.destination_age', 'message', 'Destination project must differ from and predate the source project')::text;
  END IF;

  SELECT count(*), count(*) FILTER (WHERE ("clientId" IS NOT NULL AND "clientId" <> source_project_nanoid) OR "orgMemberId" IS DISTINCT FROM source_user_id OR ("memberId" IS NOT NULL AND "memberId" <> "orgMemberId"))
    INTO auth_config_count, invalid_auth_config_count
    FROM public.auth_configs WHERE "projectId" = source_project_id;
  IF invalid_auth_config_count != 0 THEN
    RAISE EXCEPTION USING
      ERRCODE = 'P0001',
      MESSAGE = 'project_auth_reassignment.failed',
      DETAIL = json_build_object('check', 'invariant.auth_config_identity', 'count', invalid_auth_config_count)::text;
  END IF;

  CREATE TEMP TABLE project_auth_reassignment_locked ON COMMIT DROP AS
    SELECT a.id, a."clientId" AS client_id, a."memberId" AS member_id,
      md5((to_jsonb(a) - ARRAY['projectId', 'orgMemberId', 'clientId', 'memberId']::text[])::text) AS immutable_hash
    FROM public.auth_configs a WHERE a."projectId" = source_project_id FOR UPDATE;

  IF auth_config_count = 0 THEN
    result_status := 'NOTHING_TO_MOVE';
  ELSIF dry_run_text = 'true' OR allow_write_text = 'false' THEN
    result_status := 'WOULD_MOVE';
  ELSE
    UPDATE public.auth_configs a SET
      "projectId" = destination_project_id,
      "orgMemberId" = destination_user_id,
      "clientId" = CASE WHEN a."clientId" IS NULL THEN NULL ELSE destination_project_nanoid END,
      "memberId" = CASE WHEN a."memberId" IS NULL THEN NULL ELSE destination_user_id END
    FROM project_auth_reassignment_locked locked
    WHERE a.id = locked.id AND a."projectId" = source_project_id;
    GET DIAGNOSTICS updated_auth_config_count = ROW_COUNT;
    IF updated_auth_config_count != auth_config_count THEN
      RAISE EXCEPTION USING
        ERRCODE = 'P0001',
        MESSAGE = 'project_auth_reassignment.failed',
        DETAIL = json_build_object('check', 'update.auth_configs', 'expected', auth_config_count, 'actual', updated_auth_config_count)::text;
    END IF;
    SELECT count(*) INTO postcondition_failure_count
      FROM project_auth_reassignment_locked locked JOIN public.auth_configs a ON a.id = locked.id
      WHERE md5((to_jsonb(a) - ARRAY['projectId', 'orgMemberId', 'clientId', 'memberId']::text[])::text) <> locked.immutable_hash
        OR a."projectId" <> destination_project_id
        OR a."orgMemberId" <> destination_user_id
        OR a."clientId" IS DISTINCT FROM CASE WHEN locked.client_id IS NULL THEN NULL ELSE destination_project_nanoid END
        OR a."memberId" IS DISTINCT FROM CASE WHEN locked.member_id IS NULL THEN NULL ELSE destination_user_id END;
    IF postcondition_failure_count != 0 THEN
      RAISE EXCEPTION USING
        ERRCODE = 'P0001',
        MESSAGE = 'project_auth_reassignment.failed',
        DETAIL = json_build_object('check', 'postcondition.auth_configs', 'count', postcondition_failure_count)::text;
    END IF;
    result_status := 'MOVED';
  END IF;
  PERFORM set_config('project_auth_reassignment.summary', json_build_object(
    'event', 'project_auth_reassignment.completed',
    'ok', true,
    'summary', json_build_object(
      'status', result_status,
      'sourceProjectId', source_project_id,
      'destinationProjectId', destination_project_id,
      'authConfigCount', auth_config_count,
      'authConfigClientIdCount', (SELECT count(*) FROM project_auth_reassignment_locked WHERE client_id IS NOT NULL),
      'authConfigMemberIdCount', (SELECT count(*) FROM project_auth_reassignment_locked WHERE member_id IS NOT NULL),
      'connectedAccountCount', 0,
      'connectedAccountMemberIdCount', 0
    )
  )::text, false);
END
$migration$;
COMMIT;
SELECT current_setting('project_auth_reassignment.summary', false);
