#!/usr/bin/env bash
set -euo pipefail

# Test the webhook relay with simulated Azure DevOps payloads.
#
# Usage:
#   ./scripts/test-webhook.sh <webhook-url>
#
# Prerequisites:
#   - WEBHOOK_SECRET environment variable set (same value configured on the
#     Azure Function)
#
# Example:
#   export WEBHOOK_SECRET="your-shared-secret"
#   ./scripts/test-webhook.sh https://my-func.azurewebsites.net/api/devops-webhook

WEBHOOK_URL="${1:?Usage: $0 <webhook-url>}"

if [ -z "${WEBHOOK_SECRET:-}" ]; then
  echo "WARNING: WEBHOOK_SECRET not set. Requests will be sent without authentication."
  AUTH_HEADER=""
else
  AUTH_HEADER="X-Webhook-Secret: $WEBHOOK_SECRET"
fi

echo "=== Testing Webhook Relay ==="
echo "URL: $WEBHOOK_URL"
echo ""

# Test 1: Tag newly added (should create a Devin session)
echo "Test 1: workitem.updated — tag NEWLY ADDED"
echo "Expected: session_created"
echo ""

RESPONSE=$(curl -s -w "\nHTTP_STATUS:%{http_code}" \
  -X POST \
  -H "Content-Type: application/json" \
  ${AUTH_HEADER:+-H "$AUTH_HEADER"} \
  -d '{
    "eventType": "workitem.updated",
    "resource": {
      "id": 42,
      "rev": 3,
      "fields": {
        "System.Tags": {
          "oldValue": "",
          "newValue": "Devin:Implementation"
        }
      },
      "revision": {
        "id": 42,
        "fields": {
          "System.WorkItemType": "User Story",
          "System.Title": "Sample work item for testing",
          "System.Description": "This is a test work item to verify the webhook relay.",
          "System.Tags": "Devin:Implementation"
        }
      },
      "_links": {
        "html": {
          "href": "https://dev.azure.com/example/Project/_workitems/edit/42"
        }
      }
    }
  }' \
  "$WEBHOOK_URL")

HTTP_STATUS=$(echo "$RESPONSE" | tail -1 | sed 's/HTTP_STATUS://')
BODY=$(echo "$RESPONSE" | sed '$d')

echo "Response: $BODY"
echo "HTTP Status: $HTTP_STATUS"
echo ""

# Test 2: Tag already present, unrelated field changed (should be skipped)
echo "---"
echo "Test 2: workitem.updated — tags NOT changed (unrelated field edit)"
echo "Expected: skipped (System.Tags not changed)"
echo ""

RESPONSE2=$(curl -s -w "\nHTTP_STATUS:%{http_code}" \
  -X POST \
  -H "Content-Type: application/json" \
  -d '{
    "eventType": "workitem.updated",
    "resource": {
      "id": 42,
      "rev": 4,
      "fields": {
        "System.State": {
          "oldValue": "New",
          "newValue": "Active"
        }
      },
      "revision": {
        "id": 42,
        "fields": {
          "System.WorkItemType": "User Story",
          "System.Title": "Sample work item for testing",
          "System.Tags": "Devin:Discovery"
        }
      }
    }
  }' \
  "$WEBHOOK_URL")

HTTP_STATUS2=$(echo "$RESPONSE2" | tail -1 | sed 's/HTTP_STATUS://')
BODY2=$(echo "$RESPONSE2" | sed '$d')

echo "Response: $BODY2"
echo "HTTP Status: $HTTP_STATUS2"
echo ""

# Test 3: Tag already existed before this update (should be skipped)
echo "---"
echo "Test 3: workitem.updated — tag already present before update"
echo "Expected: skipped (tag already present)"
echo ""

RESPONSE3=$(curl -s -w "\nHTTP_STATUS:%{http_code}" \
  -X POST \
  -H "Content-Type: application/json" \
  -d '{
    "eventType": "workitem.updated",
    "resource": {
      "id": 42,
      "rev": 5,
      "fields": {
        "System.Tags": {
          "oldValue": "Devin:Discovery",
          "newValue": "Devin:Discovery; Priority"
        }
      },
      "revision": {
        "id": 42,
        "fields": {
          "System.WorkItemType": "User Story",
          "System.Title": "Sample work item for testing",
          "System.Tags": "Devin:Discovery; Priority"
        }
      }
    }
  }' \
  "$WEBHOOK_URL")

HTTP_STATUS3=$(echo "$RESPONSE3" | tail -1 | sed 's/HTTP_STATUS://')
BODY3=$(echo "$RESPONSE3" | sed '$d')

echo "Response: $BODY3"
echo "HTTP Status: $HTTP_STATUS3"
echo ""

# Test 4: Non-work-item event (should be ignored)
echo "---"
echo "Test 4: Non-work-item event type"
echo "Expected: ignored"
echo ""

RESPONSE4=$(curl -s -w "\nHTTP_STATUS:%{http_code}" \
  -X POST \
  -H "Content-Type: application/json" \
  -d '{"eventType": "build.complete", "resource": {}}' \
  "$WEBHOOK_URL")

HTTP_STATUS4=$(echo "$RESPONSE4" | tail -1 | sed 's/HTTP_STATUS://')
BODY4=$(echo "$RESPONSE4" | sed '$d')

echo "Response: $BODY4"
echo "HTTP Status: $HTTP_STATUS4"
