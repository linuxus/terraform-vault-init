#!/bin/sh
set -e

NAMESPACE="vault"
KEYS_FILE="vault-keys.txt"

# Function to check if a pod exists
pod_exists() {
  local pod_name=$1
  kubectl get pod -n $NAMESPACE $pod_name >/dev/null 2>&1
  return $?
}

# Function to wait for a pod to be ready
wait_for_pod() {
  local pod_name=$1
  echo "Waiting for $pod_name to be ready..."
  
  # Wait for pod to exist
  while ! pod_exists $pod_name; do
    echo "Pod $pod_name does not exist yet, waiting..."
    sleep 5
  done
  
  # Wait for pod to be running
  while [ "$(kubectl get pod -n $NAMESPACE $pod_name -o jsonpath='{.status.phase}')" != "Running" ]; do
    echo "Pod $pod_name is not running yet, waiting..."
    sleep 5
  done
  
  # Wait for container to be ready
  while [ "$(kubectl get pod -n $NAMESPACE $pod_name -o jsonpath='{.status.containerStatuses[0].ready}')" != "true" ]; do
    echo "Container in $pod_name is not ready yet, waiting..."
    sleep 5
  done
  
  echo "$pod_name is ready"
  sleep 5  # Give a little extra time
}

# Initialize vault if needed and save keys to file
initialize_vault() {
  echo "Initializing Vault..."
  kubectl exec -n $NAMESPACE vault-0 -- vault operator init -key-shares=5 -key-threshold=3 > $KEYS_FILE
  echo "Keys saved to $KEYS_FILE"
  cat $KEYS_FILE
}

# Unseal a pod using keys from file
unseal_vault() {
  local pod_name=$1
  echo "Unsealing $pod_name..."
  
  # Extract keys from file
  KEY1=$(grep "Unseal Key 1:" $KEYS_FILE | cut -d: -f2 | tr -d ' ')
  KEY2=$(grep "Unseal Key 2:" $KEYS_FILE | cut -d: -f2 | tr -d ' ')
  KEY3=$(grep "Unseal Key 3:" $KEYS_FILE | cut -d: -f2 | tr -d ' ')
  
  echo "Using keys:"
  echo "Key 1: $KEY1"
  echo "Key 2: $KEY2"
  echo "Key 3: $KEY3"
  
  # Reset any previous unseal
  kubectl exec -n $NAMESPACE $pod_name -- vault operator unseal -reset >/dev/null 2>&1 || true
  
  # Apply the keys
  echo "Applying Key 1..."
  kubectl exec -n $NAMESPACE $pod_name -- vault operator unseal $KEY1
  sleep 2
  
  echo "Applying Key 2..."
  kubectl exec -n $NAMESPACE $pod_name -- vault operator unseal $KEY2
  sleep 2
  
  echo "Applying Key 3..."
  kubectl exec -n $NAMESPACE $pod_name -- vault operator unseal $KEY3
  sleep 2
  
  # Check status
  echo "Checking unsealing status..."
  kubectl exec -n $NAMESPACE $pod_name -- vault status
}

# Get the root token from the keys file
get_root_token() {
  grep "Initial Root Token:" $KEYS_FILE | cut -d: -f2 | tr -d ' '
}

# Check if the Vault StatefulSet exists
if ! kubectl get statefulset vault -n $NAMESPACE >/dev/null 2>&1; then
  echo "Error: Vault statefulset not found in namespace $NAMESPACE"
  echo "Please deploy the Terraform configuration first."
  exit 1
fi

# Get current replicas
CURRENT_REPLICAS=$(kubectl get statefulset vault -n $NAMESPACE -o jsonpath='{.spec.replicas}')
echo "Current replicas: $CURRENT_REPLICAS"

# Scale down to 0 if needed
if [ "$CURRENT_REPLICAS" != "0" ]; then
  echo "Scaling down to 0 replicas..."
  kubectl scale statefulset vault -n $NAMESPACE --replicas=0
  
  # Wait for pods to terminate
  while pod_exists vault-0 || pod_exists vault-1 || pod_exists vault-2; do
    echo "Waiting for pods to terminate..."
    sleep 5
  done
fi

# Scale up to 1 replica
echo "Scaling up to 1 replica..."
kubectl scale statefulset vault -n $NAMESPACE --replicas=1
wait_for_pod "vault-0"

# Check logs
echo "Checking vault-0 logs:"
kubectl logs vault-0 -n $NAMESPACE

# Check if keys file exists, initialize if not
if [ ! -f "$KEYS_FILE" ]; then
  echo "No keys file found, initializing Vault..."
  initialize_vault
else
  echo "Using existing keys from $KEYS_FILE"
  cat $KEYS_FILE
  
  # Check if vault-0 is already initialized
  INIT_STATUS=$(kubectl exec -n $NAMESPACE vault-0 -- vault status 2>/dev/null || echo "Vault not initialized")
  if echo "$INIT_STATUS" | grep -q "Sealed: true"; then
    echo "Vault is already initialized but sealed. Will unseal..."
  elif echo "$INIT_STATUS" | grep -q "Sealed: false"; then
    echo "Vault is already initialized and unsealed."
  else
    echo "Cannot determine Vault status, reinitializing..."
    initialize_vault
  fi
fi

# Unseal vault-0
unseal_vault "vault-0"

# Wait for it to stabilize
echo "Waiting for vault-0 to stabilize..."
sleep 10

# Scale up to 2 replicas
echo "Scaling up to 2 replicas..."
kubectl scale statefulset vault -n $NAMESPACE --replicas=2
wait_for_pod "vault-1"

# Join vault-1 to the Raft cluster
echo "Joining vault-1 to the Raft cluster..."
VAULT0_POD_IP=$(kubectl get pod vault-0 -n $NAMESPACE -o jsonpath='{.status.podIP}')
echo "vault-0 IP: $VAULT0_POD_IP"

kubectl exec -n $NAMESPACE vault-1 -- vault operator raft join http://vault-0.vault-internal.$NAMESPACE.svc.cluster.local:8200 || \
kubectl exec -n $NAMESPACE vault-1 -- vault operator raft join http://$VAULT0_POD_IP:8200

# Unseal vault-1
unseal_vault "vault-1"

# Scale up to 3 replicas
echo "Scaling up to 3 replicas..."
kubectl scale statefulset vault -n $NAMESPACE --replicas=3
wait_for_pod "vault-2"

# Join vault-2 to the Raft cluster
echo "Joining vault-2 to the Raft cluster..."
kubectl exec -n $NAMESPACE vault-2 -- vault operator raft join http://vault-0.vault-internal.$NAMESPACE.svc.cluster.local:8200 || \
kubectl exec -n $NAMESPACE vault-2 -- vault operator raft join http://$VAULT0_POD_IP:8200

# Unseal vault-2
unseal_vault "vault-2"

# Login and check raft peers
ROOT_TOKEN=$(get_root_token)
echo "Logging in with Root Token: $ROOT_TOKEN"
kubectl exec -n $NAMESPACE vault-0 -- vault login $ROOT_TOKEN
echo "Checking Raft peers..."
kubectl exec -n $NAMESPACE vault-0 -- vault operator raft list-peers

echo "Vault deployment complete!"
echo "To access Vault UI, run: kubectl port-forward svc/vault -n $NAMESPACE 8200:8200"
echo "Then open your browser to: http://localhost:8200"
echo "Log in with Root Token: $ROOT_TOKEN"