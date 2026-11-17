# Managed VPC search with Weaviate

Use the optional `composio/values-managed-vpc-weaviate.yaml` overlay after the base
Managed VPC profile. For Janus, copy the overlay's `weaviate` and `apollo.search`
objects into the environment's registry `applicationValues`, preserving its other
settings. This enables search only for that environment.

Publish a matching release that includes the Weaviate image in its approved image
inventory and declares the optional Weaviate capability. The base Managed VPC
profile keeps search disabled. Merely setting an environment override cannot add
an image missing from an older release's inventory.

The Composio Weaviate image ships `ToolDataOpenai` and `UsecasePlansOpenai` with
`text-embedding-3-large` vectors of dimension 1024. Apollo uses the installation's
existing `OPENAI_API_KEY` to embed queries and run its configured reranker. This
keeps the vector database and indexes inside the customer environment, while query
embedding/reranking still calls the configured OpenAI service. Voyage and
Turbopuffer credentials are not required at runtime for this profile.

The bundled indexes are replaceable release data. Managed VPC Weaviate runs as a
standalone service without volumes or container mounts, and automatic Kubernetes
service-account token mounting is disabled. The runner rejects mounted storage
in the rendered pod, including init and ephemeral containers, regardless of path
spelling. Application credentials and customer data remain in their existing
stores. The service is internal to the cluster; no public ingress or AWS role is
created for it.

Deployment must verify both collections contain objects after Weaviate becomes
ready, then test `COMPOSIO_SEARCH_TOOLS` through the customer API. Readiness of the
database alone does not prove that retrieval, embeddings and reranking work. Review
and approve the deployment plan before enabling this in an existing installation.
