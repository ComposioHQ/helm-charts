from diagrams import Cluster, Diagram, Edge
from diagrams.k8s.compute import Pod, Deployment
from diagrams.k8s.network import Ingress, Service
from diagrams.k8s.storage import PV
from diagrams.onprem.database import Postgresql
from diagrams.onprem.inmemory import Redis
from diagrams.onprem.monitoring import Prometheus
from diagrams.onprem.queue import Rabbitmq
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
        tools_apis = Firewall("Tools/LLM APIs")
    
    with Cluster("Kubernetes Cluster", graph_attr={"bgcolor": "#f0f0f0", "style": "rounded,bold"}):
        
        # Ingress layer
        ingress = Ingress("Public Ingress")
        
        with Cluster("Core Services", graph_attr={"bgcolor": "#e3f2fd"}):
            apollo = Pod("Apollo\n(OAuth/Business Logic)")
            thermos = Pod("Thermos\n(Tools Manager)")
            mercury = Pod("Mercury\n(Knative)")
        
        with Cluster("Data Layer", graph_attr={"bgcolor": "#fff3e0"}):
            with Cluster("Cache & State"):
                redis = Redis("Redis")
            
            with Cluster("Primary DB"):
                postgres = Postgresql("PostgreSQL")
            
            with Cluster("Workflows"):
                temporal = Rabbitmq("Temporal.io")
        
        with Cluster("Support Services", graph_attr={"bgcolor": "#f1f8e9"}):
            secrets = PV("Secrets")
            registry = Rack("ECR\n(Images)")
        
        with Cluster("Observability", graph_attr={"bgcolor": "#fce4ec"}):
            monitoring = Prometheus("Metrics & Traces")
    
    # Traffic flow - Internet to K8s
    internet >> Edge(label="HTTPS", color="#2196f3", style="bold") >> ingress
    ingress >> Edge(color="#2196f3") >> apollo
    
    # Core service interconnections
    apollo >> Edge(color="#4caf50", style="bold") >> thermos
    thermos >> Edge(color="#4caf50", style="bold") >> mercury
    
    # Apollo connections
    apollo >> Edge(color="#ff9800", label="cache") >> redis
    apollo >> Edge(color="#9c27b0", label="persist") >> postgres
    
    # Thermos connections
    thermos >> Edge(color="#ff9800") >> redis
    thermos >> Edge(color="#e91e63", label="orchestrate") >> temporal
    
    # Mercury connections
    mercury >> Edge(color="#f44336", style="bold", label="API calls") >> tools_apis
    
    # Temporal connections
    temporal >> Edge(color="#ff9800") >> redis
    temporal >> Edge(color="#9c27b0") >> postgres
    
    # Monitoring connections
    apollo >> Edge(color="#607d8b", style="dashed") >> monitoring
    thermos >> Edge(color="#607d8b", style="dashed") >> monitoring
    mercury >> Edge(color="#607d8b", style="dashed") >> monitoring
    
    # Support services (implicit connections, visual only)
    secrets >> Edge(color="#9e9e9e", style="dotted") >> apollo
    registry >> Edge(color="#9e9e9e", style="dotted") >> apollo
    
    # Egress
    tools_apis >> Edge(label="egress", color="#2196f3", style="dashed") >> internet

print("✓ Diagram generated successfully: composio_architecture.png")
