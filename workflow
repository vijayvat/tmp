# .github/workflows/jfrog-token-refresh.yml
name: JFrog Token Refresh via Vault

on:
  schedule:
    - cron: '0 2 * * 1'  # Every Monday at 2 AM UTC
  workflow_dispatch:  # Manual trigger

jobs:
  refresh-jfrog-token:
    runs-on: ubuntu-latest
    
    steps:
    - name: Authenticate with Vault
      uses: hashicorp/vault-action@v3
      with:
        url: ${{ secrets.VAULT_URL }}
        method: approle
        roleId: ${{ secrets.VAULT_ROLE_ID }}
        secretId: ${{ secrets.VAULT_SECRET_ID }}
        secrets: |
          ${{ secrets.VAULT_SECRET_PATH }} access_token | CURRENT_ACCESS_TOKEN;
          ${{ secrets.VAULT_SECRET_PATH }} refresh_token | REFRESH_TOKEN;
          ${{ secrets.VAULT_SECRET_PATH }} token_id | TOKEN_ID

    - name: Check token expiration and refresh
      env:
        JFROG_URL: ${{ secrets.JFROG_URL }}
        VAULT_SECRET_PATH: ${{ secrets.VAULT_SECRET_PATH }}
      run: |
        echo "Checking token expiration using token ID: $TOKEN_ID"
        
        # Check specific token expiration using token ID
        token_info=$(curl -s -w "%{http_code}" \
          -H "Authorization: Bearer $CURRENT_ACCESS_TOKEN" \
          "$JFROG_URL/access/api/v1/tokens/$TOKEN_ID")
        
        http_code="${token_info: -3}"
        response_body="${token_info%???}"
        
        if [ "$http_code" != "200" ]; then
          echo "Token is already invalid (HTTP $http_code), cannot refresh"
          echo "Manual intervention required - contact admin team for new refreshable token"
          echo "MANUAL_ACTION_REQUIRED=true" >> $GITHUB_ENV
          exit 1
        else
          expiry=$(echo "$response_body" | jq -r '.expiry')
          current_time=$(date +%s)
          
          echo "Token expiry: $expiry"
          echo "Current time: $current_time"
          
          # Calculate time difference (assuming expiry is Unix timestamp)
          time_until_expiry=$((expiry - current_time))
          
          echo "Time until expiry: $time_until_expiry seconds"
          
          # Refresh if expires within 7 days (604800 seconds)
          if [ "$time_until_expiry" -lt 604800 ]; then
            echo "Token expires within 7 days, refresh needed"
            NEEDS_REFRESH=true
          else
            echo "Token is valid for more than 7 days"
            NEEDS_REFRESH=false
          fi
        fi
        
        if [ "$NEEDS_REFRESH" = "true" ]; then
          echo "Refreshing token using refresh token..."
          
          # Refresh the token
          refresh_response=$(curl -s \
            -X POST \
            -H "Authorization: Bearer $REFRESH_TOKEN" \
            "$JFROG_URL/access/api/v1/tokens/refresh")
          
          new_access_token=$(echo "$refresh_response" | jq -r '.access_token')
          new_refresh_token=$(echo "$refresh_response" | jq -r '.refresh_token')
          new_token_id=$(echo "$refresh_response" | jq -r '.token_id')
          
          if [ -z "$new_access_token" ]; then
            echo "Failed to refresh token"
            echo "Response: $refresh_response"
            echo "REFRESH_FAILED=true" >> $GITHUB_ENV
            exit 1
          fi
          
          echo "Token refreshed successfully"
          echo "NEW_ACCESS_TOKEN=$new_access_token" >> $GITHUB_ENV
          echo "NEW_REFRESH_TOKEN=$new_refresh_token" >> $GITHUB_ENV
          echo "NEW_TOKEN_ID=$new_token_id" >> $GITHUB_ENV
          echo "TOKEN_REFRESHED=true" >> $GITHUB_ENV
        else
          echo "No refresh needed"
          echo "TOKEN_REFRESHED=false" >> $GITHUB_ENV
        fi

    - name: Update token in Vault
      if: env.TOKEN_REFRESHED == 'true'
      uses: hashicorp/vault-action@v3
      with:
        url: ${{ secrets.VAULT_URL }}
        method: approle
        roleId: ${{ secrets.VAULT_ROLE_ID }}
        secretId: ${{ secrets.VAULT_SECRET_ID }}
        secrets: |
          ${{ secrets.VAULT_SECRET_PATH }} | VAULT_PATH
      env:
        VAULT_SECRET_PATH: ${{ secrets.VAULT_SECRET_PATH }}
      run: |
        echo "Updating tokens in Vault at path: $VAULT_SECRET_PATH"
        
        # Write new tokens to Vault
        vault kv put $VAULT_SECRET_PATH \
          access_token="$NEW_ACCESS_TOKEN" \
          refresh_token="$NEW_REFRESH_TOKEN" \
          token_id="$NEW_TOKEN_ID" \
          last_updated="$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
          updated_by="github-actions"
        
        if [ $? -eq 0 ]; then
          echo "Tokens successfully updated in Vault"
        else
          echo "Failed to update tokens in Vault"
          exit 1
        fi

    - name: Verify new token
      if: env.TOKEN_REFRESHED == 'true'
      env:
        JFROG_URL: ${{ secrets.JFROG_URL }}
      run: |
        echo "Testing new access token..."
        
        test_response=$(curl -s -w "%{http_code}" \
          -H "Authorization: Bearer $NEW_ACCESS_TOKEN" \
          "$JFROG_URL/artifactory/api/system/ping")
        
        test_http_code="${test_response: -3}"
        
        if [ "$test_http_code" = "200" ]; then
          echo "New token is working correctly"
        else
          echo "New token verification failed (HTTP $test_http_code)"
          exit 1
        fi

    - name: Create GitHub issue for token refresh notification
      if: env.TOKEN_REFRESHED == 'true'
      uses: actions/github-script@v7
      with:
        script: |
          const issue = await github.rest.issues.create({
            owner: context.repo.owner,
            repo: context.repo.repo,
            title: `JFrog Token Refreshed - ${new Date().toISOString().split('T')[0]}`,
            body: `## JFrog Access Token Refreshed
            
            **Date:** ${new Date().toISOString()}
            **Vault Path:** \`${{ secrets.VAULT_SECRET_PATH }}\`
            **Action:** Token has been refreshed and updated in HashiCorp Vault
            
            ### Next Steps
            Please retrieve the updated token from Vault and update your dependencies:
            
            1. Access Vault at the path above
            2. Retrieve the new \`access_token\` value
            3. Update your applications/services that use this token
            4. Test your integrations with the new token
            
            ### Token Details
            - **Vault Path:** \`${{ secrets.VAULT_SECRET_PATH }}\`
            - **Updated By:** GitHub Actions workflow
            - **Workflow Run:** [View run](${{ github.server_url }}/${{ github.repository }}/actions/runs/${{ github.run_id }})
            
            The old token will remain valid for a short period but should be replaced promptly.
            
            ---
            *This issue was automatically created by the JFrog token refresh workflow.*`,
            labels: ['jfrog', 'token-refresh', 'vault', 'automation'],
            assignees: ${{ secrets.GITHUB_ISSUE_ASSIGNEES }}
          });
          
          console.log(`Created issue #${issue.data.number}`);

    - name: Handle manual action required
      if: env.MANUAL_ACTION_REQUIRED == 'true'
      uses: actions/github-script@v7
      with:
        script: |
          const issue = await github.rest.issues.create({
            owner: context.repo.owner,
            repo: context.repo.repo,
            title: `JFrog Token EXPIRED - Manual Action Required - ${new Date().toISOString().split('T')[0]}`,
            body: `## JFrog Token Has Expired
            
            **Date:** ${new Date().toISOString()}
            **Vault Path:** \`${{ secrets.VAULT_SECRET_PATH }}\`
            **Status:** TOKEN EXPIRED - MANUAL ACTION REQUIRED
            
            ### Issue
            The JFrog access token has already expired and cannot be refreshed automatically.
            
            ### Action Required
            1. **Contact admin team** to generate a new refreshable token pair
            2. **Ensure new token is created with:** \`"refreshable": true\`
            3. **Update Vault** at path: \`${{ secrets.VAULT_SECRET_PATH }}\` with:
               - \`access_token\`: new access token
               - \`refresh_token\`: new refresh token
               - \`token_id\`: new token ID
            4. **Verify** the automation will work for future refreshes
            
            ### Vault Structure Required
            \`\`\`json
            {
              "access_token": "new_access_token_here",
              "refresh_token": "new_refresh_token_here",
              "token_id": "new_token_id_here",
              "last_updated": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
              "updated_by": "admin_name"
            }
            \`\`\`
            
            ### Workflow Details
            - **Workflow Run:** [View run](${{ github.server_url }}/${{ github.repository }}/actions/runs/${{ github.run_id }})
            - **Error:** Access token returned HTTP non-200, indicating expiry
            
            ---
            *This issue was automatically created by the JFrog token refresh workflow.*`,
            labels: ['jfrog', 'token-expired', 'vault', 'urgent', 'manual-action-required', 'admin-team'],
            assignees: ${{ secrets.GITHUB_ISSUE_ASSIGNEES }}
          });
          
          console.log(`Created manual action issue #${issue.data.number}`);

    - name: Handle refresh failure
      if: env.REFRESH_FAILED == 'true'
      uses: actions/github-script@v7
      with:
        script: |
          const issue = await github.rest.issues.create({
            owner: context.repo.owner,
            repo: context.repo.repo,
            title: `JFrog Token Refresh FAILED - ${new Date().toISOString().split('T')[0]}`,
            body: `## JFrog Token Refresh Failed
            
            **Date:** ${new Date().toISOString()}
            **Vault Path:** \`${{ secrets.VAULT_SECRET_PATH }}\`
            **Status:** FAILED
            
            ### Action Required
            The automated token refresh has failed. This likely means:
            
            1. The refresh token has expired
            2. The refresh token is invalid
            3. JFrog API is experiencing issues
            
            ### Manual Steps Required
            1. Contact the admin team to generate a new refreshable token
            2. Update the token in Vault at path: \`${{ secrets.VAULT_SECRET_PATH }}\`
            3. Ensure the new token is created with \`refreshable: true\`
            
            ### Workflow Details
            - **Workflow Run:** [View run](${{ github.server_url }}/${{ github.repository }}/actions/runs/${{ github.run_id }})
            - **Error:** Token refresh API call failed
            
            ---
            *This issue was automatically created by the JFrog token refresh workflow.*`,
            labels: ['jfrog', 'token-refresh', 'vault', 'automation', 'urgent', 'manual-action-required'],
            assignees: ${{ secrets.GITHUB_ISSUE_ASSIGNEES }}
          });
          
          console.log(`Created failure issue #${issue.data.number}`);
