#!/usr/bin/env bash
set -euo pipefail

# Test the webhook relay with simulated Azure DevOps payloads.
#
# Usage:
#   ./scripts/test-webhook.sh <webhook-url>
#
# Example:
#   ./scripts/test-webhook.sh https://my-func.azurewebsites.net/api/devops-webhook

WEBHOOK_URL="${1:?Usage: $0 <webhook-url>}"

echo "=== Testing Webhook Relay ==="
echo "URL: $WEBHOOK_URL"
echo ""

# Test 1: Payload WITH trigger tag (should create a Devin session)
echo "Test 1: workitem.updated WITH Devin:Discovery tag"
echo "Expected: session_created"
echo ""

RESPONSE=$(curl -s -w "\nHTTP_STATUS:%{http_code}" \
  -X POST \
  -H "Content-Type: application/json" \
  -d '{
    "eventType": "workitem.updated",
    "resource": {
      "id": 42,
      "rev": 3,
      "revision": {
        "id": 42,
        "fields": {
          "System.WorkItemType": "User Story",
          "System.Title": "Sample work item for testing",
          "System.Description": "This is a test work item to verify the webhook relay.",
          "System.Tags": "Devin:Discovery"
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

# Test 2: Payload WITHOUT trigger tag (should be skipped)
echo "---"
echo "Test 2: workitem.updated WITHOUT Devin:Discovery tag"
echo "Expected: skipped"
echo ""

RESPONSE2=$(curl -s -w "\nHTTP_STATUS:%{http_code}" \
  -X POST \
  -H "Content-Type: application/json" \
  -d '{
    "eventType": "workitem.updated",
    "resource": {
      "id": 99,
      "rev": 1,
      "revision": {
        "id": 99,
        "fields": {
          "System.WorkItemType": "Bug",
          "System.Title": "Some other work item",
          "System.Tags": "Priority; Backend"
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

# Test 3: Non-work-item event (should be ignored)
echo "---"
echo "Test 3: Non-work-item event type"
echo "Expected: ignored"
echo ""

RESPONSE3=$(curl -s -w "\nHTTP_STATUS:%{http_code}" \
  -X POST \
  -H "Content-Type: application/json" \
  -d '{"eventType": "build.complete", "resource": {}}' \
  "$WEBHOOK_URL")

HTTP_STATUS3=$(echo "$RESPONSE3" | tail -1 | sed 's/HTTP_STATUS://')
BODY3=$(echo "$RESPONSE3" | sed '$d')

echo "Response: $BODY3"
echo "HTTP Status: $HTTP_STATUS3"
