#!/usr/bin/env bash
set -euo pipefail

COMPARTMENT_ID="$OCI_COMPARTMENT_ID"
SUBNET_NAME="subnet-public-alfred"
SHAPE="VM.Standard.A1.Flex"
OCPUS=4
MEMORY_IN_GBS=24
INSTANCE_DISPLAY_NAME="servidor-automatizaciones"
SSH_PUBLIC_KEY_FILE="$HOME/.ssh/oracle_cloud_ssh_key.pub"

echo "Comprobando si la instancia ya existe..."
EXISTING=$(oci compute instance list \
  --compartment-id "$COMPARTMENT_ID" \
  --display-name "$INSTANCE_DISPLAY_NAME" \
  --lifecycle-state RUNNING \
  --query "data[0]" --raw-output 2>/dev/null || true)

if [ -n "$EXISTING" ] && [ "$EXISTING" != "null" ]; then
  echo "La instancia ya existe y está en marcha."
  INSTANCE_ID=$(echo "$EXISTING" | jq -r '.id')
  IP=$(oci compute instance list-vnics --instance-id "$INSTANCE_ID" --compartment-id "$COMPARTMENT_ID" --query 'data[0]."public-ip"' --raw-output)
  cat > SUCCESS.md <<EOF
# Instancia Oracle Cloud creada

- Nombre: $INSTANCE_DISPLAY_NAME
- OCID: $INSTANCE_ID
- IP pública: $IP
- Usuario SSH: opc
EOF
  exit 0
fi

AD=$(oci iam availability-domain list --compartment-id "$COMPARTMENT_ID" --query 'data[0].name' --raw-output)
SUBNET_ID=$(oci network subnet list --compartment-id "$COMPARTMENT_ID" --display-name "$SUBNET_NAME" --query 'data[0].id' --raw-output)
IMAGE_ID=$(oci compute image list --compartment-id "$COMPARTMENT_ID" --operating-system "Oracle Linux" --operating-system-version "9" --shape "$SHAPE" --sort-by TIMECREATED --sort-order DESC --query 'data[0].id' --raw-output)

echo "Intentando crear instancia ($SHAPE, $OCPUS OCPU / $MEMORY_IN_GBS GB) en AD $AD..."

set +e
RESULT=$(oci compute instance launch \
  --compartment-id "$COMPARTMENT_ID" \
  --availability-domain "$AD" \
  --shape "$SHAPE" \
  --shape-config "{\"ocpus\": $OCPUS, \"memoryInGBs\": $MEMORY_IN_GBS}" \
  --subnet-id "$SUBNET_ID" \
  --image-id "$IMAGE_ID" \
  --ssh-authorized-keys-file "$SSH_PUBLIC_KEY_FILE" \
  --display-name "$INSTANCE_DISPLAY_NAME" \
  --assign-public-ip true \
  --wait-for-state RUNNING \
  --max-wait-seconds 300 2>&1)
STATUS=$?
set -e

echo "$RESULT"

if [ $STATUS -eq 0 ]; then
  INSTANCE_ID=$(echo "$RESULT" | jq -r '.data.id')
  IP=$(oci compute instance list-vnics --instance-id "$INSTANCE_ID" --compartment-id "$COMPARTMENT_ID" --query 'data[0]."public-ip"' --raw-output)
  cat > SUCCESS.md <<EOF
# Instancia Oracle Cloud creada

- Nombre: $INSTANCE_DISPLAY_NAME
- OCID: $INSTANCE_ID
- IP pública: $IP
- Usuario SSH: opc
EOF
  echo "¡Éxito! Instancia creada."
else
  echo "Fallo esperado (probablemente falta de capacidad). Se reintentará en la siguiente ejecución programada."
fi
