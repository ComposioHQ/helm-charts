# Auth-config project reassignment

`projectAuthReassignment` renders a one-shot Kubernetes Job that moves auth
configs from exactly one newer source project to exactly one older destination
project. It does not move connected accounts. The migration SQL is kept as a
literal chart file and mounted from a ConfigMap; the Job itself is a small,
ordinary Kubernetes Job manifest.

Connected accounts that still reference a moved auth config remain associated
with the source project. Review or migrate those separately before relying on
the destination project for connected-account operations.

The Job selects users by their stored admin emails, requires the source
project's creation timestamp to be within the supplied half-open UTC interval,
and requires the destination project to predate the source. It runs a
serializable transaction and verifies that only these auth-config fields change:
`projectId`, `orgMemberId`, and non-null legacy `clientId` / `memberId`.

The Job imports the release's usual core Secret with `envFrom`; it therefore
uses the existing `POSTGRES_URL` and needs no separate database-secret setting.
This deliberately makes every core-Secret key available to the short-lived Job,
not just `POSTGRES_URL`. If that Secret or its `POSTGRES_URL` key is missing,
the Job exits with a precise error instead of waiting for a Pod startup failure.

It is disabled by default. The chart renders it only when all four selection
values are supplied. It remains a dry run unless both controls below are set.

```yaml
projectAuthReassignment:
  enabled: true
  sourceAdminEmail: admin@glean.com_workspace
  destinationAdminEmail: admin@localhost
  sourceCreatedAtFrom: "2026-07-10T00:00:00Z"
  sourceCreatedAtTo: "2026-07-13T00:00:00Z"
  dryRun: false
  allowWrite: true
```

Run it with `helm upgrade --reuse-values`, then wait for the Job:

```bash
helm upgrade <release> composio/ --namespace <namespace> --reuse-values -f reassignment-values.yaml
kubectl wait --namespace <namespace> --for=condition=complete job/<release>-project-auth-reassignment --timeout=15m
kubectl logs --namespace <namespace> job/<release>-project-auth-reassignment
```

The Job prints one structured completion JSON object. On a selection,
invariant, update, or postcondition failure it exits non-zero and PostgreSQL
prints `project_auth_reassignment.failed` with a JSON `DETAIL` naming the
failed check and relevant counts. Its `backoffLimit` is zero, so it never
retries after a failure. A terminal Job is intentionally retained: this
prevents an ordinary later `helm upgrade --reuse-values` from silently running
the migration again.

For a rerun, first delete the completed or failed Job; Kubernetes Job pod
templates are immutable:

```bash
kubectl delete --namespace <namespace> job/<release>-project-auth-reassignment
```
