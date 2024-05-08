#!/bin/bash

# Step 1: Generate private key and CSR
echo "Generating private key and CSR..."
cat <<EOF | cfssl genkey - | cfssljson -bare server
{
  "hosts": [
    "my-svc.my-namespace.svc.cluster.local",
    "my-pod.my-namespace.pod.cluster.local",
    "192.0.2.24",
    "10.0.34.2"
  ],
  "CN": "my-pod.my-namespace.pod.cluster.local",
  "key": {
    "algo": "ecdsa",
    "size": 256
  }
}
EOF

# Step 2: Create and apply CertificateSigningRequest in Kubernetes
echo "Creating Kubernetes CSR object..."
cat <<EOF | kubectl apply -f -
apiVersion: certificates.k8s.io/v1
kind: CertificateSigningRequest
metadata:
  name: my-svc.my-namespace
spec:
  request: \$(cat server.csr | base64 | tr -d '\n')
  signerName: example.com/serving
  usages:
  - digital signature
  - key encipherment
  - server auth
EOF

# Step 3: Approve the CSR
echo "Approving CSR..."
kubectl certificate approve my-svc.my-namespace

# Step 4: Sign the certificate
echo "Signing the certificate..."
kubectl get csr my-svc.my-namespace -o jsonpath='{.spec.request}' | \
  base64 --decode | \
  cfssl sign -ca ca.pem -ca-key ca-key.pem -config server-signing-config.json - | \
  cfssljson -bare ca-signed-server

# Step 5: Upload the signed certificate
echo "Uploading the signed certificate..."
kubectl get csr my-svc.my-namespace -o json | \
  jq '.status.certificate = "'\$(base64 ca-signed-server.pem | tr -d '\n')'"' | \
  kubectl replace --raw /apis/certificates.k8s.io/v1/certificatesigningrequests/my-svc.my-namespace/status -f -

# Step 6: Download and use the certificate
echo "Creating Kubernetes secret with the signed certificate..."
kubectl get csr my-svc.my-namespace -o jsonpath='{.status.certificate}' | \
  base64 --decode > server.crt
kubectl create secret tls server --cert server.crt --key server-key.pem

echo "Process complete!"

