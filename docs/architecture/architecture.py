from diagrams import Cluster, Diagram, Edge
from diagrams.k8s.compute import Pod
from diagrams.k8s.network import Ingress
from diagrams.k8s.storage import PV
from diagrams.onprem.database import Postgresql
from diagrams.onprem.inmemory import Redis
from diagrams.onprem.monitoring import Prometheus
from diagrams.generic.compute import Rack
from diagrams.generic.network import Firewall

# Custom graph attributes for better styling
graph_attr = {
    "fontsize": "16",
    "bgcolor": "white",
    "pad": "0.5",
    "splines": "spline",
    "nodesep": "0.8",
    "ranksep": "1.2"
}

cluster_attr = {
    "fontsize": "14",
    "style": "rounded",
    "margin": "20"
}

with Diagram(
    "Composio Kubernetes Architecture",
    show=False,
    filename="composio_architecture",
    direction="LR",
    graph_attr=graph_attr,
    outformat="png"
):

    # External components
    with Cluster("External", graph_attr={"bgcolor": "#e8f4f8", "style": "rounded"}):
        internet = Firewall("Internet")
        tools_apis = Firewall("Tools / LLM APIs")
        postgres = Postgresql("PostgreSQL\n(External)")
        object_storage = Rack("Object Storage\n(Optional)")
        registry = Rack("Registry / Pull Secrets")

    with Cluster("Kubernetes Cluster", graph_attr={"bgcolor": "#f0f0f0", "style": "rounded,bold"}):

        with Cluster("Composio Namespace", graph_attr={"bgcolor": "#e3f2fd"}):
            frontend_ingress = Ingress("Frontend Ingress\n(Optional)")
            apollo_ingress = Ingress("Apollo Ingress\n(Optional)")
            frontend = Pod("Frontend\n(Optional)")

            apollo = Pod("Apollo\n(API)")
            thermos = Pod("Thermos\n(Orchestration)")
            mercury = Pod("Mercury\n(Deployment default)")
            weaviate = Pod("Weaviate\n(Search)")
            redis = Redis("Redis\n(Bundled default)")
            temporal = Pod("Temporal\n(Optional)")
            monitoring = Prometheus("OTEL Collector\n(Optional)")
            secrets = PV("K8s Secrets")
            knative = Pod("Knative for Mercury\n(Optional)")

    # Entry points
    internet >> Edge(label="HTTPS", color="#2196f3", style="dashed") >> frontend_ingress >> frontend
    internet >> Edge(label="HTTPS", color="#2196f3", style="dashed") >> apollo_ingress >> apollo
    frontend >> Edge(color="#2196f3") >> apollo

    # Core service interconnections
    apollo >> Edge(color="#4caf50", style="bold", label="orchestrate") >> thermos
    thermos >> Edge(color="#4caf50", style="bold", label="execute") >> mercury
    mercury >> Edge(color="#4caf50", label="callback / control") >> apollo

    # Data and external dependencies
    apollo >> Edge(color="#ff9800", label="cache") >> redis
    apollo >> Edge(color="#9c27b0", label="persist") >> postgres
    apollo >> Edge(color="#8e24aa", label="search") >> weaviate
    apollo >> Edge(color="#6d4c41", style="dashed", label="optional storage") >> object_storage
    thermos >> Edge(color="#e91e63", style="dashed", label="optional workflows") >> temporal
    mercury >> Edge(color="#f44336", style="bold", label="outbound APIs") >> tools_apis

    # Optional observability
    apollo >> Edge(color="#607d8b", style="dashed") >> monitoring
    thermos >> Edge(color="#607d8b", style="dashed") >> monitoring
    mercury >> Edge(color="#607d8b", style="dashed") >> monitoring
    frontend >> Edge(color="#607d8b", style="dashed") >> monitoring

    # Support services
    secrets >> Edge(color="#9e9e9e", style="dotted") >> apollo
    secrets >> Edge(color="#9e9e9e", style="dotted") >> thermos
    secrets >> Edge(color="#9e9e9e", style="dotted") >> mercury
    secrets >> Edge(color="#9e9e9e", style="dotted") >> frontend
    registry >> Edge(color="#9e9e9e", style="dotted") >> apollo
    registry >> Edge(color="#9e9e9e", style="dotted") >> thermos
    registry >> Edge(color="#9e9e9e", style="dotted") >> mercury
    registry >> Edge(color="#9e9e9e", style="dotted") >> weaviate
    registry >> Edge(color="#9e9e9e", style="dotted") >> frontend
    knative >> Edge(color="#ef6c00", style="dashed", label="optional runtime") >> mercury

print("✓ Diagram generated successfully: composio_architecture.png")
