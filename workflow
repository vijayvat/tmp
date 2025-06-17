# JFrog Artifactory Token Management - Actual Requirements & APIs

## Token Types in JFrog
Based on actual documentation:

1. **Access Tokens** - Primary authentication method with expiration
2. **Refresh Tokens** - **YES, they exist** but are optional and not commonly used
3. **Reference Tokens** - 64-character alias to Access Tokens (shorter format)
4. **Identity Tokens** - Different type, not for API access

## Available APIs (Confirmed)

### Check Token Info
- **Primary**: `GET {JFROG_URL}/access/api/v1/tokens` 
- **Legacy**: `GET {JFROG_URL}/artifactory/api/security/token`
- **Response includes**: `expires_in` (seconds until expiration)

### Create New Token
- **Primary**: `POST {JFROG_URL}/access/api/v1/tokens`
- **Legacy**: `POST {JFROG_URL}/artifactory/api/security/token`
- **Authentication**: Username + Password (not existing token)
- **Body**: `{"expires_in": seconds, "scope": "applied-permissions/user"}`

### Refresh Token (Optional)
- **Endpoint**: `POST {JFROG_URL}/access/api/v1/tokens/refresh`
- **Requirement**: Token must be created with `"refreshable": true`
- **Note**: Most implementations don't use this approach

## Implementation Steps

### Step 1: Read Secrets from GitHub
Required secrets:
- `JFROG_URL` - Your JFrog instance URL
- `JFROG_USERNAME` - Username for authentication  
- `JFROG_PASSWORD` - Password or API key
- `JFROG_TOKEN` - Current access token to check/rotate

### Step 2: Check Token Expiration
```bash
# Call token info API
curl -H "Authorization: Bearer $CURRENT_TOKEN" \
  "$JFROG_URL/access/api/v1/tokens"

# Extract expires_in from response
# If expires_in < 604800 (7 days), proceed to rotation
```

### Step 3: Create New Token (if needed)
```bash
# Create new token using username/password
curl -X POST \
  -u "$JFROG_USERNAME:$JFROG_PASSWORD" \
  -H "Content-Type: application/json" \
  "$JFROG_URL/access/api/v1/tokens" \
  -d '{"expires_in": 2592000, "scope": "applied-permissions/user"}'

# Extract access_token from response
```

### Step 4: Update GitHub Secret
- Use GitHub Actions to update `JFROG_TOKEN` secret with new token
- Use marketplace action like `gliech/create-github-secret-action`

### Step 5: Optional Cleanup
- Revoke old token: `DELETE {JFROG_URL}/access/api/v1/tokens/{token_id}`

## Scheduling
- **Frequency**: Weekly (`0 2 * * 1` - Monday 2 AM UTC)
- **Logic**: Only rotate if token expires within 7 days
- **Manual trigger**: Available for testing

## Key Findings
- **Refresh tokens exist** but are rarely used in practice
- **Two API versions** available (Access API is newer, Artifactory API is legacy)
- **Username/password needed** for creating new tokens (not existing token)
- **Token expiration info** is available via API
- **JFrog CLI auto-refreshes** tokens every hour when using username/password

## Requirements Summary
1. JFrog instance with Access API enabled
2. Username/password with token creation permissions
3. GitHub repository secrets configured
4. Weekly scheduled GitHub Action
5. 7-day expiration buffer for safety
