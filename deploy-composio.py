#!/usr/bin/env python3

"""
Deploy Composio on Kubernetes with Knative
Generates values.yaml from template and optionally installs/upgrades Helm chart

Usage:
    ./scripts/deploy-composio.py [generate|install|upgrade]

Commands:
    generate-values  - Only generate values.yaml (default)
    install          - Install Knative, generate values.yaml, and run helm install
    upgrade          - Generate values.yaml and run helm upgrade

Required environment variables:
    AWS_ACCOUNT_ID    - Your AWS account ID (e.g., 123456789012)
    IMAGE_TAG         - Docker image tag to use (e.g., 4e5a118)
    POSTGRES_URL      - PostgreSQL connection URL
    ECR_TOKEN_COMMAND - AWS ECR authentication token command (e.g. aws ecr get-login-password --region us-east-1)

Optional environment variables:
    OPENAI_API_KEY    - OpenAI API key for LLM functionality
    RELEASE_NAME      - Helm release name (defaults to "composio")
"""

import os
import sys
import subprocess
import argparse
from pathlib import Path
from string import Template
import time


class ComposioDeployer:
    def __init__(self):
        self.project_root = Path(__file__).parent.absolute()
        self.template_file = self.project_root / "composio" / "values.yaml.template"
        self.output_file = self.project_root / "composio" / "values.yaml"
        self.chart_dir = self.project_root / "composio"
        
        # Default values
        self.release_name = os.getenv("RELEASE_NAME", "composio")
        self.namespace = "composio"
        
        # Knative URLs
        self.knative_urls = [
            "https://github.com/knative/serving/releases/download/knative-v1.15.0/serving-crds.yaml",
            "https://github.com/knative/serving/releases/download/knative-v1.15.0/serving-core.yaml",
            "https://github.com/knative/net-kourier/releases/download/knative-v1.15.0/kourier.yaml"
        ]

    def check_dependencies(self):
        """Check if required tools are available"""
        tools = ["kubectl", "helm"]
        for tool in tools:
            if not self.run_command(f"which {tool}", capture_output=True, check=False).returncode == 0:
                self.error(f"Required tool '{tool}' not found. Please install it first.")

    def check_environment_variables(self, required_vars=None):
        """Validate required environment variables"""
        if required_vars is None:
            required_vars = ["AWS_ACCOUNT_ID", "IMAGE_TAG", "POSTGRES_URL", "ECR_TOKEN_COMMAND"]
        missing_vars = []
        
        for var in required_vars:
            if not os.getenv(var):
                missing_vars.append(var)
        
        if missing_vars:
            self.error(f"Missing required environment variables: {', '.join(missing_vars)}")
        
        # Set optional variables
        self.env_vars = {
            "AWS_ACCOUNT_ID": os.getenv("AWS_ACCOUNT_ID"),
            "IMAGE_TAG": os.getenv("IMAGE_TAG"),
            "POSTGRES_URL": os.getenv("POSTGRES_URL", ""),
            "ECR_TOKEN_COMMAND": os.getenv("ECR_TOKEN_COMMAND", ""),
            "OPENAI_API_KEY": os.getenv("OPENAI_API_KEY", ""),
            "REDIS_URL": os.getenv("REDIS_URL", "")
        }

    def run_command(self, command, capture_output=False, check=True, shell=True):
        """Run a shell command with proper error handling"""
        try:
            if not capture_output:
                print(f"🔧 Running: {command}")
            
            result = subprocess.run(
                command,
                shell=shell,
                capture_output=capture_output,
                text=True,
                check=check
            )
            return result
        except subprocess.CalledProcessError as e:
            if not capture_output:
                self.error(f"Command failed: {command}\nError: {e}")
            raise

    def error(self, message):
        """Print error message and exit"""
        print(f"❌ Error: {message}")
        sys.exit(1)

    def success(self, message):
        """Print success message"""
        print(f"✅ {message}")

    def info(self, message):
        """Print info message"""
        print(f"🔧 {message}")

    def is_knative_installed(self):
        """Check if Knative is already installed"""
        try:
            result = self.run_command(
                "kubectl get namespace knative-serving",
                capture_output=True,
                check=False
            )
            return result.returncode == 0
        except:
            return False

    def install_knative(self):
        """Install Knative serving components"""
        if self.is_knative_installed():
            self.info("Knative already installed, skipping...")
            return

        self.info("Installing Knative components...")
        
        # Install Knative CRDs and core components
        for url in self.knative_urls:
            self.run_command(f"kubectl apply -f {url}")
            time.sleep(2)  # Brief pause between installations
        
        # Configure Kourier as the networking layer
        patch_command = (
            "kubectl patch configmap/config-network "
            "--namespace knative-serving "
            "--type merge "
            "--patch '{\"data\":{\"ingress-class\":\"kourier.ingress.networking.knative.dev\"}}'"
        )
        self.run_command(patch_command)
        
        # Wait for Knative to be ready
        self.info("Waiting for Knative components to be ready...")
        self.run_command(
            "kubectl wait --for=condition=Ready pod -l app=controller "
            "--namespace knative-serving --timeout=300s"
        )
        
        self.success("Knative installed successfully")

    def generate_values_yaml(self):
        """Generate values.yaml from template using environment variables"""
        if not self.template_file.exists():
            self.error(f"Template file not found: {self.template_file}")

        self.info("Generating values.yaml from template...")
        print(f"AWS_ACCOUNT_ID: {self.env_vars['AWS_ACCOUNT_ID']}")
        print(f"IMAGE_TAG: {self.env_vars['IMAGE_TAG']}")
        print(f"POSTGRES_URL: {'****(set)' if self.env_vars['POSTGRES_URL'] != '' else '(not set)'}")
        print(f"ECR_TOKEN_COMMAND: {'****(set)' if self.env_vars['ECR_TOKEN_COMMAND'] != '' else '(not set)'}")
        print(f"OPENAI_API_KEY: {'****(set)' if self.env_vars['OPENAI_API_KEY'] != '' else '(not set)'}")
        print(f"REDIS_URL: {'****(set)' if self.env_vars['REDIS_URL'] != '' else '(not set)'}")
        print()

        # Read template and substitute variables
        with open(self.template_file, 'r') as f:
            template_content = f.read()

        template = Template(template_content)
        output_content = template.safe_substitute(self.env_vars)

        # Write output file
        with open(self.output_file, 'w') as f:
            f.write(output_content)

        self.success(f"Generated: {self.output_file}")

    def helm_release_exists(self):
        """Check if Helm release already exists"""
        try:
            result = self.run_command(
                f"helm list -q -n {self.namespace}",
                capture_output=True,
                check=False
            )
            return self.release_name in result.stdout.strip().split('\n')
        except:
            return False

    def helm_install(self):
        """Install Helm chart"""
        if self.helm_release_exists():
            print(f"⚠️  Warning: Release 'composio' already exists. Use 'upgrade' command instead.")
            return

        self.info("Installing Helm chart...")
        
        # Create namespace if it doesn't exist
        self.run_command(f"kubectl create namespace composio --dry-run=client -o yaml | kubectl apply -f -")
        
        # Install chart - values are already in generated values.yaml
        install_command = "helm install composio ./composio -n composio"
        self.run_command(install_command)
        self.success("Installed release: composio")

    def helm_upgrade(self):
        """Upgrade existing Helm chart"""
        if not self.helm_release_exists():
            self.error(f"Release 'composio' not found. Use 'install' command instead.")

        self.info("Upgrading Helm chart...")
        
        # Simple upgrade - values are already in generated values.yaml
        upgrade_command = "helm upgrade composio ./composio -n composio --debug"
        self.run_command(upgrade_command)
        self.success("Upgraded release: composio")

    def run(self, command):
        """Main execution flow"""
        self.check_dependencies()
        if command == "install":
            self.check_environment_variables(["AWS_ACCOUNT_ID", "IMAGE_TAG", "POSTGRES_URL", "ECR_TOKEN_COMMAND", "REDIS_URL"])
            self.install_knative()
            self.generate_values_yaml()
            self.helm_install()
            print("\n🎉 Composio installed successfully!")
            print(f"\nAccess your services:")
            print(f"  kubectl port-forward -n composio svc/composio-apollo 8080:9900")
            print(f"  kubectl port-forward -n composio svc/composio-mcp 8081:3000")
        elif command == "upgrade":
            self.check_environment_variables(["AWS_ACCOUNT_ID", "IMAGE_TAG"])
            self.generate_values_yaml()
            self.helm_upgrade()
            print("\n🎉 Composio upgraded successfully!")
        elif command == "generate-values":
            self.check_environment_variables(["AWS_ACCOUNT_ID", "IMAGE_TAG"])
            self.generate_values_yaml()
            print("\nNext steps:")
            print(f"  {sys.argv[0]} install   # Install with helm")
            print(f"  {sys.argv[0]} upgrade   # Upgrade existing release")


def main():
    parser = argparse.ArgumentParser(
        description="Deploy Composio on Kubernetes with Knative",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__
    )
    
    parser.add_argument(
        "command",
        choices=["generate-values", "install", "upgrade"],
        help="Command to execute"
    )
    
    args = parser.parse_args()
    
    deployer = ComposioDeployer()
    deployer.run(args.command)


if __name__ == "__main__":
    main() 