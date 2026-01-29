# kubectl Installation Guide

kubectl is the Kubernetes command-line tool required for blueprints that deploy or interact with Kubernetes clusters (EKS, AKS, GKE).

## Version Requirements

- **Version compatibility**: kubectl should be within one minor version of your cluster
- **Recommended**: Latest stable version

## Installation

### macOS

#### Using Homebrew (Recommended)

```bash
# Install kubectl
brew install kubectl

# Verify installation
kubectl version --client
```

#### Using Official Binary

```bash
# Download latest release (Apple Silicon)
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/darwin/arm64/kubectl"

# For Intel Macs:
# curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/darwin/amd64/kubectl"

# Make executable
chmod +x ./kubectl

# Move to PATH
sudo mv ./kubectl /usr/local/bin/kubectl

# Verify
kubectl version --client
```

### Windows

#### Using Chocolatey (Recommended)

```powershell
# Install kubectl
choco install kubernetes-cli

# Verify installation
kubectl version --client
```

#### Using winget

```powershell
# Install kubectl
winget install Kubernetes.kubectl

# Verify installation
kubectl version --client
```

#### Using Official Binary

```powershell
# Download (PowerShell)
curl.exe -LO "https://dl.k8s.io/release/v1.29.0/bin/windows/amd64/kubectl.exe"

# Move to a directory in your PATH, e.g.:
Move-Item kubectl.exe C:\Windows\System32\kubectl.exe

# Verify
kubectl version --client
```

### Linux

#### Using Package Manager

**Ubuntu/Debian:**
```bash
# Add Kubernetes apt repository
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.29/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.29/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list

# Install
sudo apt-get update
sudo apt-get install kubectl

# Verify
kubectl version --client
```

**RHEL/CentOS/Fedora:**
```bash
# Add Kubernetes yum repository
cat <<EOF | sudo tee /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://pkgs.k8s.io/core:/stable:/v1.29/rpm/
enabled=1
gpgcheck=1
gpgkey=https://pkgs.k8s.io/core:/stable:/v1.29/rpm/repodata/repomd.xml.key
EOF

# Install
sudo yum install kubectl

# Verify
kubectl version --client
```

#### Using Official Binary

```bash
# Download latest release
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"

# Make executable
chmod +x kubectl

# Move to PATH
sudo mv kubectl /usr/local/bin/

# Verify
kubectl version --client
```

## Cloud Provider Integration

### AWS EKS

Install the AWS CLI and configure EKS authentication:

```bash
# Update kubeconfig for EKS cluster
aws eks update-kubeconfig --region <region> --name <cluster-name>

# Verify connection
kubectl get nodes
```

### Azure AKS

Install the Azure CLI and configure AKS authentication:

```bash
# Get AKS credentials
az aks get-credentials --resource-group <resource-group> --name <cluster-name>

# Verify connection
kubectl get nodes
```

### Google GKE

Install gcloud CLI and configure GKE authentication:

```bash
# Install gke-gcloud-auth-plugin (required for GKE)
gcloud components install gke-gcloud-auth-plugin

# Get GKE credentials
gcloud container clusters get-credentials <cluster-name> --region <region>

# Verify connection
kubectl get nodes
```

## Configuration

### kubeconfig

kubectl uses a configuration file (kubeconfig) to connect to clusters:

- **Default location**: `~/.kube/config`
- **Override with**: `KUBECONFIG` environment variable

### Multiple Clusters

Manage multiple clusters using contexts:

```bash
# View all contexts
kubectl config get-contexts

# Switch context
kubectl config use-context <context-name>

# View current context
kubectl config current-context
```

### Namespace Default

Set a default namespace:

```bash
kubectl config set-context --current --namespace=<namespace>
```

## Verification

```bash
# Check client version
kubectl version --client

# Check connection to cluster (requires configured kubeconfig)
kubectl cluster-info

# List nodes
kubectl get nodes

# List all pods in all namespaces
kubectl get pods -A
```

## Shell Completion

Enable tab completion for kubectl:

### Bash

```bash
# Add to ~/.bashrc
echo 'source <(kubectl completion bash)' >> ~/.bashrc

# Add alias (optional)
echo 'alias k=kubectl' >> ~/.bashrc
echo 'complete -o default -F __start_kubectl k' >> ~/.bashrc

# Reload
source ~/.bashrc
```

### Zsh

```bash
# Add to ~/.zshrc
echo 'source <(kubectl completion zsh)' >> ~/.zshrc

# Reload
source ~/.zshrc
```

### PowerShell

```powershell
# Add to PowerShell profile
kubectl completion powershell | Out-String | Invoke-Expression
```

## Common Commands

| Command | Description |
|---------|-------------|
| `kubectl get pods` | List pods |
| `kubectl get svc` | List services |
| `kubectl get nodes` | List nodes |
| `kubectl describe pod <name>` | Pod details |
| `kubectl logs <pod>` | View pod logs |
| `kubectl exec -it <pod> -- /bin/sh` | Shell into pod |
| `kubectl apply -f file.yaml` | Apply configuration |
| `kubectl delete -f file.yaml` | Delete resources |
| `kubectl port-forward svc/<name> 8080:80` | Port forward |

## Troubleshooting

### Connection refused

```
The connection to the server localhost:8080 was refused
```

kubeconfig is not configured:
```bash
# Check kubeconfig
echo $KUBECONFIG
cat ~/.kube/config

# For EKS
aws eks update-kubeconfig --region <region> --name <cluster-name>
```

### Certificate errors

```
Unable to connect to the server: x509: certificate
```

Solutions:
1. Refresh kubeconfig from cloud provider
2. Check cluster certificates haven't expired
3. Verify time synchronization on your machine

### Unauthorized

```
error: You must be logged in to the server (Unauthorized)
```

Solutions:
1. Re-authenticate with cloud provider
2. Check IAM/RBAC permissions
3. Refresh credentials:
```bash
# AWS
aws sts get-caller-identity
aws eks update-kubeconfig --region <region> --name <cluster-name>

# Azure
az aks get-credentials --resource-group <rg> --name <cluster> --overwrite-existing

# GCP
gcloud container clusters get-credentials <cluster> --region <region>
```

### Context not found

```bash
# List available contexts
kubectl config get-contexts

# Check kubeconfig file
cat ~/.kube/config
```

## Useful Plugins

Consider installing these kubectl plugins via [krew](https://krew.sigs.k8s.io/):

```bash
# Install krew
(
  set -x; cd "$(mktemp -d)" &&
  OS="$(uname | tr '[:upper:]' '[:lower:]')" &&
  ARCH="$(uname -m | sed -e 's/x86_64/amd64/' -e 's/arm64/arm64/')" &&
  KREW="krew-${OS}_${ARCH}" &&
  curl -fsSLO "https://github.com/kubernetes-sigs/krew/releases/latest/download/${KREW}.tar.gz" &&
  tar zxvf "${KREW}.tar.gz" &&
  ./"${KREW}" install krew
)

# Install useful plugins
kubectl krew install ctx    # Quick context switching
kubectl krew install ns     # Quick namespace switching
kubectl krew install neat   # Clean up YAML output
```

## Resources

- [kubectl Documentation](https://kubernetes.io/docs/reference/kubectl/)
- [kubectl Cheat Sheet](https://kubernetes.io/docs/reference/kubectl/cheatsheet/)
- [EKS User Guide](https://docs.aws.amazon.com/eks/latest/userguide/)
- [AKS Documentation](https://docs.microsoft.com/en-us/azure/aks/)
- [GKE Documentation](https://cloud.google.com/kubernetes-engine/docs)
